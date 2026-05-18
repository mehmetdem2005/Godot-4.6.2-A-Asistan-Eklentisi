@tool
class_name AIAgentLiveBridgeTest
extends RefCounted

## Pilot Cell — Canlı Köprü Self-Test (Aşama 4a).
##
## AIAgentLiveBridge'in SENKRON ve saf yüzeyini doğrular: ön koşul
## kapıları, istek kurulumu (Brain'i değiştirmeden yeniden kullanım),
## ham HTTP sonucunun ajan-sonucuna eşlenmesi.
##
## ÖNEMLİ: Gerçek ağ çağrısı ASENKRON — senkron panele girmez
## (devir §5.4). Burada finalize_raw'a SAHTE raw beslenir; gerçek
## DeepSeek kanıtı ayrı headless koşturucudadır (tools/agent_live_runner.gd).
## Mock policy: sahte raw "başarısız" da test edilir — uydurma cevap yok.


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
	return results


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
	# Geçmiş + proje bağlamı verilse de router yokken sözleşme aynı:
	# dürüst başarısızlık, sahte içerik yok (geriye uyumlu).
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
# İSTEK KURULUMU — Brain'i değiştirmeden yeniden kullanım
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
# HAM SONUÇ EŞLEME — sahte raw, gerçek mantık
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
	# 200 ama choices yok — sağlayıcı yanıtı kullanılamaz
	var mapped: Dictionary = bridge.finalize_raw(
		{"ok": true, "status": 200, "json": {"unexpected": true}},
		req, AICellRoles.Role.PRODUCT_MANAGER
	)
	if bool(mapped["ok"]):
		bridge.free()
		return _fail(name, "boş yanıtta ok=true olmamalı (mock yasak)")
	bridge.free()
	return _ok(name)
