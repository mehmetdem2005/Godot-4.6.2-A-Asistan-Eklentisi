@tool
class_name AIAgentLiveBridgeTest
extends RefCounted

## Pilot Cell — Canlı Köprü Self-Test (Aşama 4a/6).
##
## AIAgentLiveBridge'in senkron ve saf yüzeyini doğrular: ön koşul
## kapıları, istek kurulumu, ham HTTP sonucunun ajan-sonucuna eşlenmesi
## ve güvenli sağlayıcı gözlemlenebilirliği.
##
## Gerçek ağ çağrısı asenkrondur. Burada finalize_raw'a sentetik raw
## beslenir; gerçek DeepSeek V4 kanıtı tools/deepseek_v4_live_runner.gd
## ile alınır. Mock policy: başarısız raw sahte başarı üretmez.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("LiveBridge: Durum", _test_status_initial()))
	results.append(_b("LiveBridge: Kapı", _test_no_router_fails()))
	results.append(_b("LiveBridge: İstek", _test_build_request()))
	results.append(_b("LiveBridge: İstek", _test_build_request_undefined()))
	results.append(_b("LiveBridge: Eşleme", _test_finalize_success()))
	results.append(_b("LiveBridge: Eşleme", _test_finalize_401()))
	results.append(_b("LiveBridge: Eşleme", _test_finalize_429()))
	results.append(_b("LiveBridge: Eşleme", _test_finalize_no_router()))
	results.append(_b("LiveBridge: Mock", _test_finalize_mock_policy()))
	results.append(_b("LiveBridge: Sohbet", _test_chat_no_router_fails()))
	results.append(_b("LiveBridge: Sohbet", _test_chat_extra_params_safe()))
	results.append(_b("LiveBridge: Bölünme", _test_finish_reason_propagated()))
	results.append(_b("LiveBridge: Metadata", _test_provider_metadata()))
	results.append(_b("LiveBridge: Metadata", _test_cache_metadata()))
	results.append(_b("LiveBridge: Güvenlik", _test_error_redacts_secret()))
	return results


static func _test_provider_metadata() -> Dictionary:
	var name := "V4 başarı sonucu tam sağlayıcı metadata'sı taşır"
	var bridge := AIAgentLiveBridge.new()
	bridge.attach_router(AIProviderRouter.new())
	var req: AIProviderRequest = bridge.build_request_for(
		AICellRoles.Role.CODE_ENGINEER,
		"küçük bir fonksiyon yaz",
		{},
		AIDeepSeekModelPolicy.MODEL_PRO
	)
	var raw: Dictionary = {
		"ok": true,
		"status": 200,
		"json": {
			"model": AIDeepSeekModelPolicy.MODEL_PRO,
			"choices": [{
				"message": {"content": "func test():\n\tpass"},
				"finish_reason": "stop",
			}],
			"usage": {"prompt_tokens": 11, "completion_tokens": 7},
		},
		"latency_ms": 123,
	}
	var mapped: Dictionary = bridge.finalize_raw(
		raw, req, AICellRoles.Role.CODE_ENGINEER
	)
	bridge.free()
	if not bool(mapped["ok"]):
		return _fail(name, "başarı beklenir: " + str(mapped["status_note"]))
	if int(mapped["provider"]) != AIProviderRequest.Provider.DEEPSEEK:
		return _fail(name, "provider DeepSeek olmalı")
	if str(mapped["provider_name"]) != "deepseek":
		return _fail(name, "provider_name yanlış")
	if str(mapped["model"]) != AIDeepSeekModelPolicy.MODEL_PRO:
		return _fail(name, "model kimliği korunmadı")
	if int(mapped["input_tokens"]) != 11:
		return _fail(name, "input token korunmadı")
	if int(mapped["output_tokens"]) != 7:
		return _fail(name, "output token korunmadı")
	if int(mapped["total_tokens"]) != 18:
		return _fail(name, "toplam token yanlış")
	if str(mapped["finish_reason"]) != "stop":
		return _fail(name, "finish reason korunmadı")
	if int(mapped["http_status"]) != 200:
		return _fail(name, "HTTP durum korunmadı")
	if int(mapped["latency_ms"]) != 123:
		return _fail(name, "latency korunmadı")
	if bool(mapped["from_cache"]):
		return _fail(name, "canlı yanıt cache sayılmamalı")
	if str(mapped["request_ref"]) != req.id:
		return _fail(name, "request_ref korunmadı")
	return _ok(name)


static func _test_cache_metadata() -> Dictionary:
	var name := "Cache yanıtı from_cache ve model kimliğini taşır"
	var bridge := AIAgentLiveBridge.new()
	var response := AIProviderResponse.create_from_cache(
		"önbellek cevabı",
		AIProviderRequest.Provider.DEEPSEEK,
		AIDeepSeekModelPolicy.MODEL_FLASH
	)
	response.finish_reason = "stop"
	response.request_ref = "req_cache_1"
	var mapped: Dictionary = bridge._result_from_response(
		AICellRoles.Role.PRODUCT_MANAGER, response
	)
	bridge.free()
	if not bool(mapped["ok"]):
		return _fail(name, "cache yanıtı kullanılabilir olmalı")
	if not bool(mapped["from_cache"]):
		return _fail(name, "from_cache=true taşınmalı")
	if str(mapped["model"]) != AIDeepSeekModelPolicy.MODEL_FLASH:
		return _fail(name, "cache model kimliği kayboldu")
	if str(mapped["request_ref"]) != "req_cache_1":
		return _fail(name, "cache request_ref kayboldu")
	return _ok(name)


static func _test_error_redacts_secret() -> Dictionary:
	var name := "401 hata sonucu gizli anahtarı ve ham header'ı taşımaz"
	var bridge := AIAgentLiveBridge.new()
	bridge.attach_router(AIProviderRouter.new())
	var req: AIProviderRequest = bridge.build_request_for(
		AICellRoles.Role.ARCHITECT,
		"planla",
		{},
		AIDeepSeekModelPolicy.LEGACY_REASONER
	)
	var secret := "sk_SUPER_SECRET_SHOULD_NOT_APPEAR"
	var mapped: Dictionary = bridge.finalize_raw(
		{
			"ok": false,
			"status": 401,
			"error": "Authorization: Bearer " + secret,
			"latency_ms": 9,
		},
		req,
		AICellRoles.Role.ARCHITECT
	)
	bridge.free()
	if bool(mapped["ok"]):
		return _fail(name, "401 başarısız olmalı")
	if int(mapped["http_status"]) != 401:
		return _fail(name, "HTTP 401 metadata'da olmalı")
	if str(mapped["status_note"]).contains(secret):
		return _fail(name, "gizli anahtar status_note'a sızdı")
	if str(mapped).contains(secret) or str(mapped).contains("Authorization"):
		return _fail(name, "ham header sonuç sözlüğüne sızdı")
	if str(mapped["model"]) != AIDeepSeekModelPolicy.MODEL_PRO:
		return _fail(name, "legacy model güvenli V4 Pro kimliğine dönmeli")
	if not str(mapped["content"]).is_empty():
		return _fail(name, "hata sonucu sahte içerik taşımamalı")
	return _ok(name)


static func _test_finish_reason_propagated() -> Dictionary:
	var name := "finish_reason='length' sonuca taşınır (bölünmüş üretim)"
	var bridge := AIAgentLiveBridge.new()
	bridge.attach_router(AIProviderRouter.new())
	var req: AIProviderRequest = bridge.build_request_for(
		AICellRoles.Role.CODE_ENGINEER, "uzun kod"
	)
	var raw: Dictionary = {
		"ok": true,
		"status": 200,
		"json": {"choices": [{
			"message": {"content": "func a():\n\tpass"},
			"finish_reason": "length",
		}]},
		"latency_ms": 10,
	}
	var mapped: Dictionary = bridge.finalize_raw(
		raw, req, AICellRoles.Role.CODE_ENGINEER
	)
	bridge.free()
	if not bool(mapped["ok"]):
		return _fail(name, "ok olmalı: " + str(mapped["status_note"]))
	if str(mapped.get("finish_reason", "")) != "length":
		return _fail(name, "finish_reason taşınmadı: "
			+ str(mapped.get("finish_reason", "")))
	return _ok(name)


static func _test_chat_extra_params_safe() -> Dictionary:
	var name := "think_chat history+project_context additive (regresyon yok)"
	var bridge := AIAgentLiveBridge.new()
	var captured: Array = []
	bridge.thought_completed.connect(func(r: Dictionary) -> void:
		captured.append(r)
	)
	var started: bool = bridge.think_chat(
		"merhaba",
		"",
		[{"role": "user", "content": "önceki"},
			{"role": "assistant", "content": "yanıt"}],
		"PROJE DOSYALARI:\n  res://player.gd"
	)
	bridge.free()
	if started:
		return _fail(name, "router yokken başlatılmamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "ek parametrelerle de dürüst hata dönmeli")
	return _ok(name)


static func _test_chat_no_router_fails() -> Dictionary:
	var name := "think_chat router yokken açık başarısızlık (sahte yok)"
	var bridge := AIAgentLiveBridge.new()
	var captured: Array = []
	bridge.thought_completed.connect(func(r: Dictionary) -> void:
		captured.append(r)
	)
	var started: bool = bridge.think_chat("merhaba")
	if started:
		bridge.free()
		return _fail(name, "router yokken başlatılmamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		bridge.free()
		return _fail(name, "router yokken dürüst hata dönmeli")
	bridge.free()
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# DURUM + ÖN KOŞUL KAPILARI
# ============================================================

static func _test_status_initial() -> Dictionary:
	var name := "Köprü başlangıç durumu"
	var bridge := AIAgentLiveBridge.new()
	var st: Dictionary = bridge.bridge_status()
	if bool(st["router_attached"]):
		bridge.free()
		return _fail(name, "başlangıçta router bağlı olmamalı")
	if bool(st["busy"]):
		bridge.free()
		return _fail(name, "başlangıçta meşgul olmamalı")
	bridge.free()
	return _ok(name)


static func _test_no_router_fails() -> Dictionary:
	var name := "Router yokken açık başarısızlık (sahte yok)"
	var bridge := AIAgentLiveBridge.new()
	var captured: Array = []
	bridge.thought_completed.connect(func(r: Dictionary) -> void:
		captured.append(r)
	)
	var started: bool = bridge.think_live(
		AICellRoles.Role.PRODUCT_MANAGER, "ana menü"
	)
	if started:
		bridge.free()
		return _fail(name, "router yokken başlatılmamalı")
	if captured.is_empty():
		bridge.free()
		return _fail(name, "başarısızlık sinyali yayılmalı")
	var r: Dictionary = captured[0]
	if bool(r["ok"]):
		bridge.free()
		return _fail(name, "router yokken ok=true olmamalı (sahte cevap)")
	if bool(r["llm_called"]):
		bridge.free()
		return _fail(name, "çağrı yapılmadan llm_called true olmamalı")
	bridge.free()
	return _ok(name)


# ============================================================
# İSTEK KURULUMU
# ============================================================

static func _test_build_request() -> Dictionary:
	var name := "İstek kurulumu Brain'i yeniden kullanır"
	var bridge := AIAgentLiveBridge.new()
	var req: AIProviderRequest = bridge.build_request_for(
		AICellRoles.Role.CODE_ENGINEER, "oyuncu hareketi yaz"
	)
	if req == null:
		bridge.free()
		return _fail(name, "geçerli rol için istek kurulmalı")
	if req.messages.size() < 2:
		bridge.free()
		return _fail(name, "istek system + user mesajı içermeli")
	bridge.free()
	return _ok(name)


static func _test_build_request_undefined() -> Dictionary:
	var name := "Promptsuz rol istek kurmaz (mock yok)"
	var bridge := AIAgentLiveBridge.new()
	var req: AIProviderRequest = bridge.build_request_for(999, "görev")
	if req != null:
		bridge.free()
		return _fail(name, "promptsuz rol null istek dönmeli")
	bridge.free()
	return _ok(name)


# ============================================================
# HAM SONUÇ EŞLEME
# ============================================================

static func _test_finalize_success() -> Dictionary:
	var name := "Başarılı raw → ajan cevabı çözülür"
	var bridge := AIAgentLiveBridge.new()
	var router := AIProviderRouter.new()
	bridge.attach_router(router)
	var req: AIProviderRequest = bridge.build_request_for(
		AICellRoles.Role.PRODUCT_MANAGER, "test"
	)
	var raw: Dictionary = {
		"ok": true,
		"status": 200,
		"json": {"choices": [{"message": {"content": "BAGLANTI_TAMAM"}}]},
		"latency_ms": 42,
	}
	var mapped: Dictionary = bridge.finalize_raw(
		raw, req, AICellRoles.Role.PRODUCT_MANAGER
	)
	if not bool(mapped["ok"]):
		bridge.free()
		return _fail(name, "geçerli yanıt ok=true olmalı: " +
			str(mapped["status_note"]))
	if str(mapped["content"]) != "BAGLANTI_TAMAM":
		bridge.free()
		return _fail(name, "içerik yanlış çözüldü: " + str(mapped["content"]))
	if int(mapped["latency_ms"]) != 42:
		bridge.free()
		return _fail(name, "gecikme korunmalı")
	bridge.free()
	return _ok(name)


static func _test_finalize_401() -> Dictionary:
	var name := "401 → açık anahtar reddi"
	var bridge := AIAgentLiveBridge.new()
	bridge.attach_router(AIProviderRouter.new())
	var mapped: Dictionary = bridge.finalize_raw(
		{"ok": false, "status": 401, "error": "unauth"}, null,
		AICellRoles.Role.ARCHITECT
	)
	if bool(mapped["ok"]):
		bridge.free()
		return _fail(name, "401'de ok=true olmamalı")
	if not str(mapped["status_note"]).contains("401"):
		bridge.free()
		return _fail(name, "not 401 sebebini içermeli")
	bridge.free()
	return _ok(name)


static func _test_finalize_429() -> Dictionary:
	var name := "429 → açık limit mesajı"
	var bridge := AIAgentLiveBridge.new()
	bridge.attach_router(AIProviderRouter.new())
	var mapped: Dictionary = bridge.finalize_raw(
		{"ok": false, "status": 429, "error": "rate"}, null,
		AICellRoles.Role.QA_ENGINEER
	)
	if bool(mapped["ok"]):
		bridge.free()
		return _fail(name, "429'da ok=true olmamalı")
	if not str(mapped["status_note"]).contains("429"):
		bridge.free()
		return _fail(name, "not 429 sebebini içermeli")
	bridge.free()
	return _ok(name)


static func _test_finalize_no_router() -> Dictionary:
	var name := "Router yokken yanıt çözülemez (açık)"
	var bridge := AIAgentLiveBridge.new()
	var mapped: Dictionary = bridge.finalize_raw(
		{"ok": true, "status": 200, "json": {}}, null,
		AICellRoles.Role.ARCHITECT
	)
	if bool(mapped["ok"]):
		bridge.free()
		return _fail(name, "router yokken ok=true olmamalı")
	if not str(mapped["status_note"]).contains("Router"):
		bridge.free()
		return _fail(name, "router eksikliği raporlanmalı")
	bridge.free()
	return _ok(name)


static func _test_finalize_mock_policy() -> Dictionary:
	var name := "Geçersiz JSON → sahte başarı YOK"
	var bridge := AIAgentLiveBridge.new()
	bridge.attach_router(AIProviderRouter.new())
	var req: AIProviderRequest = bridge.build_request_for(
		AICellRoles.Role.PRODUCT_MANAGER, "test"
	)
	var mapped: Dictionary = bridge.finalize_raw(
		{"ok": true, "status": 200, "json": {"unexpected": true}},
		req, AICellRoles.Role.PRODUCT_MANAGER
	)
	if bool(mapped["ok"]):
		bridge.free()
		return _fail(name, "boş yanıtta ok=true olmamalı (mock yasak)")
	bridge.free()
	return _ok(name)
