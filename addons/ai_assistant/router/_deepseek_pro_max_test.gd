@tool
class_name AIDeepSeekProMaxTest
extends RefCounted

## DeepSeek V4 Pro maksimum üretim profili sözleşmeleri.
## Gerçek ağ kullanmadan, canlı router'ın göndereceği güvenli gövdeyi
## ve uzun-yanıt taşıma profilini doğrular.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("ProMax: Model", _test_default_forces_v4_pro()))
	results.append(_b("ProMax: Model", _test_legacy_and_flash_cannot_downgrade()))
	results.append(_b("ProMax: Thinking", _test_thinking_enabled()))
	results.append(_b("ProMax: Thinking", _test_reasoning_effort_max()))
	results.append(_b("ProMax: Output", _test_max_output_384k()))
	results.append(_b("ProMax: Context", _test_context_budget_reduces_output()))
	results.append(_b("ProMax: Context", _test_exhausted_context_rejected()))
	results.append(_b("ProMax: Params", _test_thinking_omits_temperature()))
	results.append(_b("ProMax: Transport", _test_long_transport_profile()))
	results.append(_b("ProMax: Security", _test_https_and_header_redaction()))
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray(["=== DeepSeek Pro Max Test Sonuçları ==="])
	var current: String = ""
	for result in results:
		if str(result["batch"]) != current:
			current = str(result["batch"])
			lines.append("--- %s ---" % current)
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append("--- %d geçti, %d başarısız (toplam %d) ---" % [
		passed, failed, results.size()
	])
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _prepared(
	model_id: String = "",
	estimated_input_tokens: int = 0,
	purpose: int = AIProviderRequest.Purpose.CODE
) -> Dictionary:
	var router := AIProviderRouter.new()
	router.set_api_key(AIProviderRequest.Provider.DEEPSEEK, "unit-test-key")
	var request := AIProviderRequest.create(purpose, "ProMaxTest")
	request.model = model_id
	request.estimated_input_tokens = estimated_input_tokens
	request.add_message("system", "Godot 4.6.3 üretim ajanı")
	request.add_message("user", "Üretim sözleşmesini doğrula")
	var routed: Dictionary = router.route(request)
	return {"router": router, "request": request, "routed": routed}


static func _body(prepared: Dictionary) -> Dictionary:
	var routed: Dictionary = prepared["routed"]
	if bool(routed.get("resolved", false)):
		return {}
	return (routed.get("prepared", {}) as Dictionary).get("body", {})


static func _test_default_forces_v4_pro() -> Dictionary:
	var name := "Boş model seçimi canlıda DeepSeek V4 Pro olur"
	var body: Dictionary = _body(_prepared())
	if str(body.get("model", "")) != AIDeepSeekModelPolicy.MODEL_PRO:
		return _fail(name, "model V4 Pro değil: " + str(body.get("model", "")))
	return _ok(name)


static func _test_legacy_and_flash_cannot_downgrade() -> Dictionary:
	var name := "Legacy ve Flash canlı üretim profilini düşüremez"
	for model_id in [
		AIDeepSeekModelPolicy.LEGACY_CHAT,
		AIDeepSeekModelPolicy.LEGACY_REASONER,
		AIDeepSeekModelPolicy.MODEL_FLASH,
	]:
		var body: Dictionary = _body(_prepared(model_id))
		if str(body.get("model", "")) != AIDeepSeekModelPolicy.MODEL_PRO:
			return _fail(name, "%s V4 Pro'ya zorlanmadı" % model_id)
	return _ok(name)


static func _test_thinking_enabled() -> Dictionary:
	var name := "V4 Pro bütün üretim amaçlarında thinking=enabled"
	for purpose in [
		AIProviderRequest.Purpose.REASONING,
		AIProviderRequest.Purpose.CODE,
		AIProviderRequest.Purpose.VALIDATION,
		AIProviderRequest.Purpose.SUMMARY,
	]:
		var body: Dictionary = _body(_prepared("", 0, purpose))
		var thinking: Dictionary = body.get("thinking", {})
		if str(thinking.get("type", "")) != "enabled":
			return _fail(name, "amaç %d düşünmesiz kaldı" % purpose)
	return _ok(name)


static func _test_reasoning_effort_max() -> Dictionary:
	var name := "V4 Pro reasoning_effort=max kullanır"
	var body: Dictionary = _body(_prepared())
	if str(body.get("reasoning_effort", "")) != "max":
		return _fail(name, "reasoning_effort max değil")
	return _ok(name)


static func _test_max_output_384k() -> Dictionary:
	var name := "Normal girdide max_tokens=384000"
	var prepared: Dictionary = _prepared()
	var body: Dictionary = _body(prepared)
	if int(body.get("max_tokens", 0)) != AIDeepSeekModelPolicy.MAX_OUTPUT_TOKENS:
		return _fail(name, "çıktı tavanı yanlış: %s" % body.get("max_tokens", 0))
	var request: AIProviderRequest = prepared["request"]
	if request.max_tokens != AIDeepSeekModelPolicy.MAX_OUTPUT_TOKENS:
		return _fail(name, "request sözleşmesi 384K'ya normalize edilmedi")
	return _ok(name)


static func _test_context_budget_reduces_output() -> Dictionary:
	var name := "1M bağlam yaklaşınca çıktı güvenli kalan alana iner"
	var input_tokens: int = 950000
	var expected: int = (
		AIDeepSeekModelPolicy.MAX_CONTEXT_TOKENS
		- AIDeepSeekModelPolicy.CONTEXT_SAFETY_TOKENS
		- input_tokens
	)
	var body: Dictionary = _body(_prepared("", input_tokens))
	if int(body.get("max_tokens", -1)) != expected:
		return _fail(name, "beklenen %d, gelen %s" % [
			expected, body.get("max_tokens", -1)
		])
	return _ok(name)


static func _test_exhausted_context_rejected() -> Dictionary:
	var name := "Tükenmiş 1M bağlam sıfır token isteği göndermez"
	var prepared: Dictionary = _prepared("", 999999)
	var routed: Dictionary = prepared["routed"]
	if not bool(routed.get("resolved", false)):
		return _fail(name, "tükenmiş bağlam ağ isteğine dönüştü")
	var response: AIProviderResponse = routed.get("response", null)
	if response == null or response.ok:
		return _fail(name, "açık başarısızlık dönmeli")
	if not response.error_message.to_lower().contains("bağlam"):
		return _fail(name, "hata bağlam bütçesini açıklamıyor")
	return _ok(name)


static func _test_thinking_omits_temperature() -> Dictionary:
	var name := "Thinking isteğinde etkisiz temperature gönderilmez"
	var body: Dictionary = _body(_prepared())
	if body.has("temperature"):
		return _fail(name, "temperature düşünme gövdesine sızdı")
	return _ok(name)


static func _test_long_transport_profile() -> Dictionary:
	var name := "Taşıyıcı 384K uzun üretim kapasitesine sahip"
	var transport := AIHTTPTransport.new()
	var profile: Dictionary = transport.transport_profile()
	transport.free()
	if float(profile.get("timeout_seconds", 0.0)) < 1800.0:
		return _fail(name, "timeout 30 dakikadan kısa")
	if int(profile.get("max_response_body_bytes", 0)) < 64 * 1024 * 1024:
		return _fail(name, "yanıt gövde limiti 64 MiB altında")
	if not bool(profile.get("gzip", false)) or not bool(profile.get("threaded", false)):
		return _fail(name, "gzip/threaded taşıma açık değil")
	return _ok(name)


static func _test_https_and_header_redaction() -> Dictionary:
	var name := "Taşıyıcı HTTPS zorlar ve dry-run anahtarını redakte eder"
	var transport := AIHTTPTransport.new()
	var cb := func(_response: Dictionary) -> void:
		pass
	if transport.send_post("http://api.example.com", PackedStringArray(), {}, cb):
		transport.free()
		return _fail(name, "HTTP üretim isteği kabul edildi")
	transport.send_post(
		"https://api.example.com",
		PackedStringArray(["Authorization: Bearer secret-value"]),
		{"model": "test"}, cb
	)
	var headers: String = str(transport.last_dry_run.get("headers", []))
	transport.free()
	if headers.contains("secret-value"):
		return _fail(name, "Authorization değeri dry-run kaydına sızdı")
	if not headers.contains("[REDACTED]"):
		return _fail(name, "redaksiyon işareti yok")
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


static func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
