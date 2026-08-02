@tool
class_name AIDeepSeekReasoningStreamTest
extends RefCounted

## Faz 14 — DeepSeek'in sağlayıcı tarafından döndürülen
## reasoning_content ve content SSE akış sözleşmeleri.


static func run_all() -> Array:
	var results: Array = []
	results.append_array(_decoder_tests())
	results.append_array(_adapter_tests())
	results.append_array(_transport_and_event_tests())
	return results


static func _decoder_tests() -> Array:
	var decoder := AIDeepSeekSSEDecoder.new()
	var reasoning_json: String = JSON.stringify({
		"model": "deepseek-v4-pro",
		"choices": [{
			"delta": {"reasoning_content": "Önce "},
			"finish_reason": null,
		}],
		"usage": null,
	})
	var content_json: String = JSON.stringify({
		"model": "deepseek-v4-pro",
		"choices": [{
			"delta": {"content": "sonuç"},
			"finish_reason": "stop",
		}],
		"usage": null,
	})
	var stream: String = (
		"data: " + reasoning_json + "\n\n"
		+ "data: " + content_json + "\n\n"
		+ "data: [DONE]\n\n"
	)
	var bytes: PackedByteArray = stream.to_utf8_buffer()
	var midpoint: int = bytes.size() / 2
	var events: Array = []
	events.append_array(decoder.feed_bytes(bytes.slice(0, midpoint)))
	events.append_array(decoder.feed_bytes(bytes.slice(midpoint)))

	var first_json: Dictionary = events[0].get("json", {})
	var first_choices: Array = first_json.get("choices", [])
	var first_choice: Dictionary = first_choices[0]
	var first_delta: Dictionary = first_choice.get("delta", {})
	var second_json: Dictionary = events[1].get("json", {})
	var second_choices: Array = second_json.get("choices", [])
	var second_choice: Dictionary = second_choices[0]
	var second_delta: Dictionary = second_choice.get("delta", {})

	var utf_decoder := AIDeepSeekSSEDecoder.new()
	var utf_line: String = (
		"data: "
		+ JSON.stringify({
			"choices": [{
				"delta": {"reasoning_content": "ejderha düşünüyorum"},
			}],
		})
		+ "\n\n"
	)
	var utf_bytes: PackedByteArray = utf_line.to_utf8_buffer()
	var utf_events: Array = []
	for index in utf_bytes.size():
		var one_byte: PackedByteArray = utf_bytes.slice(index, index + 1)
		utf_events.append_array(utf_decoder.feed_bytes(one_byte))
	var utf_json: Dictionary = utf_events[0].get("json", {})
	var utf_choices: Array = utf_json.get("choices", [])
	var utf_choice: Dictionary = utf_choices[0]
	var utf_delta: Dictionary = utf_choice.get("delta", {})

	var multi := AIDeepSeekSSEDecoder.new()
	var multi_events: Array = []
	multi_events.append_array(multi.feed_bytes(
		"data: {\"a\":\n".to_utf8_buffer()
	))
	multi_events.append_array(multi.feed_bytes(
		"data: 1}\n\n".to_utf8_buffer()
	))
	var multi_json: Dictionary = multi_events[0].get("json", {})

	return [
		_b("SSE", _check(
			"Parçalı ağ chunk'ları üç olayı korur",
			events.size() == 3
		)),
		_b("SSE", _check(
			"reasoning_content ayrı okunur",
			str(first_delta.get("reasoning_content", "")) == "Önce "
		)),
		_b("SSE", _check(
			"content ayrı okunur",
			str(second_delta.get("content", "")) == "sonuç"
		)),
		_b("SSE", _check(
			"DONE akışı kapatır",
			bool(events[2].get("done", false)) and decoder.is_done()
		)),
		_b("SSE", _check(
			"UTF-8 byte byte bölünse de bozulmaz",
			str(utf_delta.get("reasoning_content", ""))
				== "ejderha düşünüyorum"
		)),
		_b("SSE", _check(
			"Çok satırlı data JSON birleştirilir",
			multi_events.size() == 1 and int(multi_json.get("a", 0)) == 1
		)),
	]


static func _adapter_tests() -> Array:
	var adapter := AIDeepSeekV4Adapter.new()
	var request := AIProviderRequest.create(
		AIProviderRequest.Purpose.REASONING, "stream-test"
	)
	request.model = AIDeepSeekModelPolicy.MODEL_PRO
	request.max_tokens = 384000
	request.add_message("user", "Bir ejderha tasarla")
	var body: Dictionary = adapter.build_request_body(request)
	var stream_options: Dictionary = body.get("stream_options", {})
	var thinking: Dictionary = body.get("thinking", {})
	return [
		_b("İstek", _check(
			"V4 Pro isteği stream=true",
			bool(body.get("stream", false))
		)),
		_b("İstek", _check(
			"Streaming usage chunk istenir",
			bool(stream_options.get("include_usage", false))
		)),
		_b("İstek", _check(
			"Thinking enabled kalır",
			str(thinking.get("type", "")) == "enabled"
		)),
		_b("İstek", _check(
			"Reasoning effort max kalır",
			str(body.get("reasoning_effort", "")) == "max"
		)),
	]


static func _transport_and_event_tests() -> Array:
	var transport := AIStreamingHTTPTransport.new()
	var parsed: Dictionary = transport._parse_https_url(
		"https://api.deepseek.com/chat/completions"
	)
	var profile: Dictionary = transport.transport_profile()
	var reasoning_event: Dictionary = AILiveAgentEvent.create(
		AILiveAgentEvent.TYPE_REASONING_CHUNK,
		"node-1", 3, "Architect", "Mimari", "ham parça ", 0.0, 1
	)
	var content_event: Dictionary = AILiveAgentEvent.create(
		AILiveAgentEvent.TYPE_CONTENT_CHUNK,
		"node-1", 3, "Architect", "Mimari", "cevap parçası", 0.0, 1
	)
	var reasoning_valid: Dictionary = AILiveAgentEvent.validate(reasoning_event)
	var content_valid: Dictionary = AILiveAgentEvent.validate(content_event)
	transport.free()
	return [
		_b("Taşıyıcı", _check(
			"HTTPS URL host/path doğru ayrılır",
			bool(parsed.get("ok", false))
				and str(parsed.get("host", "")) == "api.deepseek.com"
				and str(parsed.get("path", "")) == "/chat/completions"
		)),
		_b("Taşıyıcı", _check(
			"Profil SSE reasoning desteğini bildirir",
			bool(profile.get("sse_streaming", false))
				and bool(profile.get("reasoning_content", false))
		)),
		_b("Olay", _check(
			"Reasoning chunk olayı geçerli",
			bool(reasoning_valid.get("ok", false))
		)),
		_b("Olay", _check(
			"Content chunk olayı geçerli",
			bool(content_valid.get("ok", false))
		)),
	]


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray([
		"=== DeepSeek Reasoning Stream Test Sonuçları ===",
	])
	var batch: String = ""
	for result_value in results:
		var result: Dictionary = result_value
		if str(result.get("batch", "")) != batch:
			batch = str(result.get("batch", ""))
			lines.append("--- %s ---" % batch)
		if bool(result.get("ok", false)):
			passed += 1
			lines.append("  ✓ " + str(result.get("name", "Test")))
		else:
			failed += 1
			lines.append(
				"  ✗ %s — %s" % [
					str(result.get("name", "Test")),
					str(result.get("reason", "Başarısız")),
				]
			)
	lines.append("--- %d geçti, %d başarısız (toplam %d) ---" % [
		passed, failed, results.size(),
	])
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _check(name: String, ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "name": name, "reason": reason if not ok else ""}
