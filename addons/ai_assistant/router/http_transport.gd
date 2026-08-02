@tool
class_name AIHTTPTransport
extends Node

## HTTPTransport — gerçek HTTP taşıma katmanı (Layer 7).
##
## DeepSeek V4 Pro 384K çıktı profili uzun sürebilir ve büyük bir JSON
## gövdesi döndürebilir. Taşıyıcı bu nedenle kısa sohbet varsayımlarına
## değil, uzun üretim profiline göre yapılandırılır. Anahtar hiçbir zaman
## burada saklanmaz; her çağrıda yalnız header olarak alınır.

const LONG_REQUEST_TIMEOUT_SECONDS: float = 1800.0
const MAX_RESPONSE_BODY_BYTES: int = 64 * 1024 * 1024
const DOWNLOAD_CHUNK_BYTES: int = 256 * 1024

var live_mode: bool = false
var timeout_seconds: float = LONG_REQUEST_TIMEOUT_SECONDS

var _http: HTTPRequest = null
var _busy: bool = false
var _pending_callback: Callable
var _request_start_ms: int = 0
var last_dry_run: Dictionary = {}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = timeout_seconds
	_http.body_size_limit = MAX_RESPONSE_BODY_BYTES
	_http.download_chunk_size = DOWNLOAD_CHUNK_BYTES
	_http.accept_gzip = true
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func send_post(
	url: String, headers: PackedStringArray, body: Dictionary, callback: Callable
) -> bool:
	if _busy:
		push_warning("HTTPTransport: önceki istek hâlâ sürüyor")
		return false
	if url.strip_edges().is_empty():
		push_warning("HTTPTransport: URL boş")
		return false
	if not url.begins_with("https://"):
		push_warning("HTTPTransport: üretim isteği HTTPS olmalı")
		return false

	var body_json: String = JSON.stringify(body)

	if not live_mode:
		last_dry_run = {
			"url": url,
			"headers": _redacted_headers(headers),
			"body": body,
			"body_json": body_json,
		}
		if callback.is_valid():
			callback.call({
				"ok": false,
				"status": 0,
				"json": {},
				"error": "DRY-RUN: istek hazırlandı ama gönderilmedi "
					+ "(live_mode=false)",
				"latency_ms": 0,
				"dry_run": true,
			})
		return true

	if _http == null:
		push_error("HTTPTransport: HTTPRequest hazır değil (node ağaçta mı?)")
		return false

	_busy = true
	_pending_callback = callback
	_request_start_ms = Time.get_ticks_msec()

	var err: int = _http.request(
		url, headers, HTTPClient.METHOD_POST, body_json
	)
	if err != OK:
		_busy = false
		if callback.is_valid():
			callback.call({
				"ok": false,
				"status": 0,
				"json": {},
				"error": "HTTP isteği başlatılamadı (kod %d)" % err,
				"latency_ms": 0,
				"dry_run": false,
			})
		return false
	return true


func _on_request_completed(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray
) -> void:
	_busy = false
	var latency: int = Time.get_ticks_msec() - _request_start_ms

	if result != HTTPRequest.RESULT_SUCCESS:
		if _pending_callback.is_valid():
			_pending_callback.call({
				"ok": false,
				"status": 0,
				"json": {},
				"error": _result_error_text(result),
				"latency_ms": latency,
				"dry_run": false,
			})
		return

	var text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var json_data: Dictionary = {}
	if parsed is Dictionary:
		json_data = parsed
	elif parsed == null:
		if _pending_callback.is_valid():
			_pending_callback.call({
				"ok": false,
				"status": response_code,
				"json": {},
				"error": "Yanıt JSON olarak ayrıştırılamadı",
				"latency_ms": latency,
				"dry_run": false,
			})
		return

	var is_ok: bool = response_code >= 200 and response_code < 300
	if _pending_callback.is_valid():
		_pending_callback.call({
			"ok": is_ok,
			"status": response_code,
			"json": json_data,
			"error": "" if is_ok else "HTTP %d" % response_code,
			"latency_ms": latency,
			"dry_run": false,
		})


## Dry-run tanısı API anahtarını bellekteki sonuç sözlüğüne bile yazmaz.
func _redacted_headers(headers: PackedStringArray) -> PackedStringArray:
	var safe := PackedStringArray()
	for header in headers:
		var text: String = str(header)
		if text.to_lower().begins_with("authorization:"):
			safe.append("Authorization: [REDACTED]")
		else:
			safe.append(text)
	return safe


func _result_error_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "İstek zaman aşımına uğradı"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Sunucuya bağlanılamadı"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "DNS çözümlenemedi — internet bağlantısı yok olabilir"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Bağlantı hatası"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/SSL el sıkışma hatası"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Yanıt güvenli gövde boyutu limitini aştı"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Sunucudan yanıt alınamadı"
		_:
			return "Ağ hatası (result kodu %d)" % result


func is_busy() -> bool:
	return _busy


func transport_profile() -> Dictionary:
	return {
		"timeout_seconds": timeout_seconds,
		"max_response_body_bytes": MAX_RESPONSE_BODY_BYTES,
		"download_chunk_bytes": DOWNLOAD_CHUNK_BYTES,
		"gzip": true,
		"threaded": true,
		"https_only": true,
	}
