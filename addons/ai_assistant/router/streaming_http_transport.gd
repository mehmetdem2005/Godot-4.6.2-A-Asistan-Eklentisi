@tool
class_name AIStreamingHTTPTransport
extends AIHTTPTransport

## DeepSeek V4 SSE taşıyıcısı. HTTPRequest bütün gövdeyi beklediği için
## gerçek token akışında düşük seviyeli HTTPClient kullanılır.

signal stream_delta(kind: String, text: String, metadata: Dictionary)

const STREAM_READ_CHUNK_BYTES: int = 32 * 1024
const STREAM_IDLE_TIMEOUT_MS: int = 1800 * 1000

var _client: HTTPClient = null
var _decoder: AIDeepSeekSSEDecoder = null
var _stream_busy: bool = false
var _stream_callback: Callable
var _stream_headers := PackedStringArray()
var _stream_body_json: String = ""
var _host: String = ""
var _path: String = "/"
var _port: int = 443
var _request_sent: bool = false
var _response_started: bool = false
var _response_code: int = 0
var _is_event_stream: bool = false
var _stream_start_ms: int = 0
var _last_activity_ms: int = 0
var _reasoning_content: String = ""
var _answer_content: String = ""
var _finish_reason: String = ""
var _model: String = ""
var _usage: Dictionary = {}
var _raw_body := PackedByteArray()


func _ready() -> void:
	super._ready()
	set_process(false)


func send_post(
	url: String, headers: PackedStringArray, body: Dictionary, callback: Callable
) -> bool:
	if not bool(body.get("stream", false)):
		return super.send_post(url, headers, body, callback)
	if not live_mode:
		return super.send_post(url, headers, body, callback)
	if _stream_busy or super.is_busy():
		push_warning("StreamingHTTPTransport: önceki istek hâlâ sürüyor")
		return false
	var parsed: Dictionary = _parse_https_url(url)
	if not bool(parsed.get("ok", false)):
		push_warning("StreamingHTTPTransport: " + str(parsed.get("error", "URL hatası")))
		return false

	_reset_stream_state()
	_host = str(parsed["host"])
	_path = str(parsed["path"])
	_port = int(parsed["port"])
	_stream_headers = headers.duplicate()
	if not _has_header(_stream_headers, "accept"):
		_stream_headers.append("Accept: text/event-stream")
	_stream_headers.append("Cache-Control: no-cache")
	_stream_body_json = JSON.stringify(body)
	_stream_callback = callback
	_stream_start_ms = Time.get_ticks_msec()
	_last_activity_ms = _stream_start_ms
	_decoder = AIDeepSeekSSEDecoder.new()
	_client = HTTPClient.new()
	_client.read_chunk_size = STREAM_READ_CHUNK_BYTES
	var connect_error: int = _client.connect_to_host(
		_host, _port, TLSOptions.client()
	)
	if connect_error != OK:
		_client = null
		return false
	_stream_busy = true
	set_process(true)
	return true


func _process(_delta: float) -> void:
	if not _stream_busy or _client == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_activity_ms > STREAM_IDLE_TIMEOUT_MS:
		_finish_stream(false, "Akış zaman aşımına uğradı")
		return
	var poll_error: int = _client.poll()
	if poll_error != OK:
		_finish_stream(false, "HTTPClient poll hatası: %d" % poll_error)
		return

	match _client.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, \
		HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if not _request_sent:
				var request_error: int = _client.request(
					HTTPClient.METHOD_POST,
					_path,
					_stream_headers,
					_stream_body_json
				)
				if request_error != OK:
					_finish_stream(false, "HTTP isteği başlatılamadı: %d" % request_error)
					return
				_request_sent = true
				_last_activity_ms = now
			elif _client.has_response():
				_begin_response()
				_finish_from_connection_end()
		HTTPClient.STATUS_BODY:
			_begin_response()
			var chunk: PackedByteArray = _client.read_response_body_chunk()
			if not chunk.is_empty():
				_last_activity_ms = now
				if _raw_size() + chunk.size() > MAX_RESPONSE_BODY_BYTES:
					_finish_stream(false, "Yanıt güvenli gövde boyutu limitini aştı")
					return
				if _is_event_stream:
					_process_sse_events(_decoder.feed_bytes(chunk))
				else:
					_raw_body.append_array(chunk)
		HTTPClient.STATUS_CANT_RESOLVE:
			_finish_stream(false, "DNS çözümlenemedi")
		HTTPClient.STATUS_CANT_CONNECT:
			_finish_stream(false, "Sunucuya bağlanılamadı")
		HTTPClient.STATUS_CONNECTION_ERROR:
			_finish_stream(false, "Bağlantı hatası")
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_finish_stream(false, "TLS/SSL el sıkışma hatası")
		HTTPClient.STATUS_DISCONNECTED:
			if _response_started:
				_finish_from_connection_end()
			else:
				_finish_stream(false, "Bağlantı yanıt alınmadan kapandı")


func _begin_response() -> void:
	if _response_started or _client == null or not _client.has_response():
		return
	_response_started = true
	_response_code = _client.get_response_code()
	var headers: Dictionary = _client.get_response_headers_as_dictionary()
	var content_type: String = ""
	for key_value in headers.keys():
		if str(key_value).to_lower() == "content-type":
			content_type = str(headers[key_value]).to_lower()
			break
	_is_event_stream = content_type.contains("text/event-stream")


func _process_sse_events(events: Array) -> void:
	for event_value in events:
		var event: Dictionary = event_value
		if bool(event.get("done", false)):
			_finish_stream(_response_code >= 200 and _response_code < 300, "")
			return
		if not str(event.get("error", "")).is_empty():
			continue
		var chunk_json: Dictionary = event.get("json", {})
		_process_stream_json(chunk_json)


func _process_stream_json(chunk_json: Dictionary) -> void:
	if chunk_json.has("model"):
		_model = str(chunk_json.get("model", _model))
	var usage_value: Variant = chunk_json.get("usage", null)
	if usage_value is Dictionary:
		_usage = (usage_value as Dictionary).duplicate(true)
	var choices: Array = chunk_json.get("choices", []) as Array
	if choices.is_empty():
		return
	var choice: Dictionary = choices[0] as Dictionary
	var delta: Dictionary = choice.get("delta", {}) as Dictionary
	var reasoning: String = str(delta.get("reasoning_content", ""))
	var content: String = str(delta.get("content", ""))
	if not reasoning.is_empty():
		_reasoning_content += reasoning
		stream_delta.emit("reasoning", reasoning, {
			"model": _model,
			"reasoning_chars": _reasoning_content.length(),
		})
	if not content.is_empty():
		_answer_content += content
		stream_delta.emit("content", content, {
			"model": _model,
			"content_chars": _answer_content.length(),
		})
	var finish_value: Variant = choice.get("finish_reason", null)
	if finish_value != null and not str(finish_value).is_empty():
		_finish_reason = str(finish_value)


func _finish_from_connection_end() -> void:
	if not _stream_busy:
		return
	if _is_event_stream:
		_process_sse_events(_decoder.finish())
		if _stream_busy:
			_finish_stream(_response_code >= 200 and _response_code < 300, "")
		return
	var parsed_json: Dictionary = {}
	if not _raw_body.is_empty():
		var parsed: Variant = JSON.parse_string(_raw_body.get_string_from_utf8())
		if parsed is Dictionary:
			parsed_json = parsed
	var ok: bool = _response_code >= 200 and _response_code < 300
	_complete_callback({
		"ok": ok,
		"status": _response_code,
		"json": parsed_json,
		"error": "" if ok else "HTTP %d" % _response_code,
		"latency_ms": Time.get_ticks_msec() - _stream_start_ms,
		"dry_run": false,
		"streamed": false,
	})


func _finish_stream(ok: bool, error_text: String) -> void:
	if not _stream_busy:
		return
	var message: Dictionary = {
		"content": _answer_content,
		"reasoning_content": _reasoning_content,
	}
	var response_json: Dictionary = {
		"model": _model,
		"choices": [{
			"index": 0,
			"message": message,
			"finish_reason": _finish_reason,
		}],
		"usage": _usage,
	}
	_complete_callback({
		"ok": ok,
		"status": _response_code,
		"json": response_json,
		"error": error_text if not ok else "",
		"latency_ms": Time.get_ticks_msec() - _stream_start_ms,
		"dry_run": false,
		"streamed": true,
		"reasoning_content": _reasoning_content,
		"content": _answer_content,
	})


func _complete_callback(result: Dictionary) -> void:
	var callback: Callable = _stream_callback
	_stream_busy = false
	set_process(false)
	if _client != null:
		_client.close()
	_client = null
	_stream_callback = Callable()
	if callback.is_valid():
		callback.call(result)


func is_busy() -> bool:
	return _stream_busy or super.is_busy()


func transport_profile() -> Dictionary:
	var profile: Dictionary = super.transport_profile()
	profile["sse_streaming"] = true
	profile["stream_read_chunk_bytes"] = STREAM_READ_CHUNK_BYTES
	profile["reasoning_content"] = true
	return profile


func _reset_stream_state() -> void:
	_reasoning_content = ""
	_answer_content = ""
	_finish_reason = ""
	_model = ""
	_usage = {}
	_raw_body.clear()
	_request_sent = false
	_response_started = false
	_response_code = 0
	_is_event_stream = false


func _raw_size() -> int:
	return _raw_body.size() + _reasoning_content.to_utf8_buffer().size() \
		+ _answer_content.to_utf8_buffer().size()


func _has_header(headers: PackedStringArray, name: String) -> bool:
	var prefix: String = name.to_lower() + ":"
	for header in headers:
		if str(header).to_lower().begins_with(prefix):
			return true
	return false


func _parse_https_url(url: String) -> Dictionary:
	if not url.begins_with("https://"):
		return {"ok": false, "error": "yalnız HTTPS desteklenir"}
	var remainder: String = url.trim_prefix("https://")
	var slash: int = remainder.find("/")
	var authority: String = remainder if slash < 0 else remainder.left(slash)
	var path_value: String = "/" if slash < 0 else remainder.substr(slash)
	if authority.is_empty():
		return {"ok": false, "error": "host boş"}
	var host_value: String = authority
	var port_value: int = 443
	var colon: int = authority.rfind(":")
	if colon > 0:
		var port_text: String = authority.substr(colon + 1)
		if port_text.is_valid_int():
			port_value = int(port_text)
			host_value = authority.left(colon)
	return {
		"ok": not host_value.is_empty(),
		"host": host_value,
		"port": port_value,
		"path": path_value,
		"error": "",
	}
