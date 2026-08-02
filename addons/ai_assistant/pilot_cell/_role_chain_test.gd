@tool
class_name AIRoleChainRunnerTest
extends RefCounted

## RoleChainRunner Self-Test (Plan C).
##
## SAF/SENKRON yüzeyi doğrular: zincir sırası (Architect→CodeEngineer
## →Reviewer), Reviewer FAIL heuristiği, köprüsüz/router'sız DÜRÜST
## başarısızlık (sahte ara çıktı uydurulmaz — mock policy).
##
## Çoklu rol bağlam aktarımı + tek düzeltme turu ASENKRON ve gerçek
## LLM gerektirir — tools/build_plan_runner.gd'de canlı kanıtlanır
## (sahte LLM içeriği gerçekmiş gibi beslenmez).


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Chain: Sıra", _test_base_chain_order()))
	results.append(_b("Chain: Heuristik", _test_is_fail_true()))
	results.append(_b("Chain: Heuristik", _test_is_fail_pass()))
	results.append(_b("Chain: Heuristik", _test_is_fail_mixed()))
	results.append(_b("Chain: Köprü", _test_no_bridge_honest()))
	results.append(_b("Chain: Köprü", _test_no_router_honest()))
	results.append(_b("Chain: Model", _test_code_model_is_chat()))
	results.append(_b("Chain: V4", _test_router_uses_v4_adapter()))
	results.append(_b("Chain: V4", _test_legacy_chat_maps_non_thinking()))
	results.append(_b("Chain: V4", _test_legacy_reasoner_maps_thinking()))
	results.append(_b("Chain: V4", _test_flash_code_stays_flash()))
	results.append(_b("Chain: V4", _test_v4_output_cap()))
	results.append(_b("Chain: V4", _test_v4_response_model()))
	results.append(_b("Chain: V4", _test_v4_cache_separation()))
	results.append(_b("Chain: Bölünme", _test_join_clean_strips_fences()))
	results.append(_b("Chain: Bölünme", _test_tail_keeps_end()))
	results.append(_b("Chain: Bölünme", _test_chunk_bound()))
	results.append(_b("Chain: Onarım", _test_repair_mode_two_steps()))
	results.append(_b("Chain: Onarım", _test_full_mode_three_steps()))
	return results


static func _test_repair_mode_two_steps() -> Dictionary:
	var name := "Onarım modu Architect'siz (CodeEngineer→Reviewer)"
	var r := _new()
	var bridge := AIAgentLiveBridge.new()
	r.attach_bridge(bridge)
	# Router yok → think_live SENKRON çöker; ama _steps run()'da
	# mode'a göre kurulur (çöküşten önce).
	r.run("hatalı kodu onar", "", "repair")
	var steps: Array = r._steps
	bridge.free()
	r.free()
	if steps.size() != 2:
		return _fail(name, "onarım 2 adım olmalı: %d" % steps.size())
	if int(steps[0]) != AICellRoles.Role.CODE_ENGINEER:
		return _fail(name, "ilk adım CodeEngineer olmalı")
	if int(steps[1]) != AICellRoles.Role.REVIEWER:
		return _fail(name, "ikinci adım Reviewer olmalı")
	return _ok(name)


static func _test_full_mode_three_steps() -> Dictionary:
	var name := "Tam mod Architect→CodeEngineer→Reviewer (geriye uyumlu)"
	var r := _new()
	var bridge := AIAgentLiveBridge.new()
	r.attach_bridge(bridge)
	r.run("üret", "")  # mode varsayılan "full"
	var steps: Array = r._steps
	bridge.free()
	r.free()
	if steps.size() != 3 or int(steps[0]) != AICellRoles.Role.ARCHITECT:
		return _fail(name, "tam mod 3 adım/Architect başlamalı")
	return _ok(name)


static func _test_join_clean_strips_fences() -> Dictionary:
	var name := "Parça birleştirme ``` çitlerini söker (kesintisiz kod)"
	var r := _new()
	var raw := "```gdscript\nextends Node\n```\n```\nfunc f():\n\tpass\n```"
	var joined: String = r._join_clean(raw)
	r.free()
	if joined.contains("```"):
		return _fail(name, "çit kalmamalı: " + joined)
	if joined != "extends Node\nfunc f():\n\tpass":
		return _fail(name, "kod yanlış birleşti: " + joined)
	return _ok(name)


static func _test_tail_keeps_end() -> Dictionary:
	var name := "_tail uzun metnin sonunu, kısa metni aynen verir"
	var r := _new()
	var short_keep: String = r._tail("kisa")
	var long_text: String = "A".repeat(5000)
	var tail: String = r._tail(long_text)
	r.free()
	if short_keep != "kisa":
		return _fail(name, "kısa metin korunmalı")
	if tail.length() != AIRoleChainRunner.CONT_TAIL_CHARS:
		return _fail(name, "kuyruk uzunluğu yanlış: %d" % tail.length())
	return _ok(name)


static func _test_chunk_bound() -> Dictionary:
	var name := "Bölünmüş üretim sınırlı (sonsuz döngü yok)"
	if AIRoleChainRunner.MAX_CODE_CHUNKS < 1:
		return _fail(name, "en az 1 parça")
	if AIRoleChainRunner.MAX_CODE_CHUNKS > 12:
		return _fail(name, "üst sınır makul kalmalı (≤12)")
	return _ok(name)


static func _test_code_model_is_chat() -> Dictionary:
	var name := "Legacy kod seçimi deepseek-chat (V4 adapter normalize eder)"
	if AIRoleChainRunner.CODE_MODEL != "deepseek-chat":
		return _fail(name, "geriye uyumlu CODE_MODEL deepseek-chat olmalı")
	# Sözleşme: zincirdeki kod-üreten rol gerçekten kod-üreten say.
	if not AICellRoles.is_code_generating(AICellRoles.Role.CODE_ENGINEER):
		return _fail(name, "CodeEngineer kod-üreten olmalı")
	if AICellRoles.is_code_generating(AICellRoles.Role.ARCHITECT):
		return _fail(name, "Architect kod-üreten sayılmamalı (model korunur)")
	return _ok(name)


# ============================================================
# DEEPSEEK V4 BACKEND POLİTİKASI — Faz 5
# ============================================================

static func _v4_request(purpose: int, model_id: String) -> AIProviderRequest:
	var req := AIProviderRequest.create(purpose, "Phase5Test")
	req.model = model_id
	req.system_prompt = "V4 test"
	req.add_message("user", "Godot kodu üret")
	req.max_tokens = 100000
	return req


static func _test_router_uses_v4_adapter() -> Dictionary:
	var name := "Canlı router DeepSeek için V4 adapter kullanır"
	var router := AIProviderRouter.new()
	var adapter: AIProviderAdapterBase = router.get_adapter(
		AIProviderRequest.Provider.DEEPSEEK
	)
	if not adapter is AIDeepSeekV4Adapter:
		return _fail(name, "DeepSeek adapter V4 değil")
	return _ok(name)


static func _test_legacy_chat_maps_non_thinking() -> Dictionary:
	var name := "Legacy chat → V4 Pro + düşünme kapalı"
	var adapter := AIDeepSeekV4Adapter.new()
	var body: Dictionary = adapter.build_request_body(_v4_request(
		AIProviderRequest.Purpose.CODE,
		AIDeepSeekModelPolicy.LEGACY_CHAT
	))
	if str(body["model"]) != AIDeepSeekModelPolicy.MODEL_PRO:
		return _fail(name, "legacy chat V4 Pro'ya dönmeli")
	if str(body["thinking"]["type"]) != "disabled":
		return _fail(name, "kod üretiminde düşünme kapalı olmalı")
	if not body.has("temperature"):
		return _fail(name, "düşünmesiz üretimde temperature korunmalı")
	if str(body).contains(AIDeepSeekModelPolicy.LEGACY_CHAT):
		return _fail(name, "legacy model ağ gövdesine sızdı")
	return _ok(name)


static func _test_legacy_reasoner_maps_thinking() -> Dictionary:
	var name := "Legacy reasoner → V4 Pro + düşünme max"
	var adapter := AIDeepSeekV4Adapter.new()
	var body: Dictionary = adapter.build_request_body(_v4_request(
		AIProviderRequest.Purpose.VALIDATION,
		AIDeepSeekModelPolicy.LEGACY_REASONER
	))
	if str(body["model"]) != AIDeepSeekModelPolicy.MODEL_PRO:
		return _fail(name, "legacy reasoner V4 Pro'ya dönmeli")
	if str(body["thinking"]["type"]) != "enabled":
		return _fail(name, "validation düşünmeli olmalı")
	if str(body.get("reasoning_effort", "")) != "max":
		return _fail(name, "validation reasoning_effort=max olmalı")
	if body.has("temperature"):
		return _fail(name, "düşünme modunda temperature gönderilmemeli")
	if str(body).contains(AIDeepSeekModelPolicy.LEGACY_REASONER):
		return _fail(name, "legacy reasoner ağ gövdesine sızdı")
	return _ok(name)


static func _test_flash_code_stays_flash() -> Dictionary:
	var name := "V4 Flash kod isteği Flash + düşünmesiz kalır"
	var adapter := AIDeepSeekV4Adapter.new()
	var body: Dictionary = adapter.build_request_body(_v4_request(
		AIProviderRequest.Purpose.CODE,
		AIDeepSeekModelPolicy.MODEL_FLASH
	))
	if str(body["model"]) != AIDeepSeekModelPolicy.MODEL_FLASH:
		return _fail(name, "Flash seçimi korunmadı")
	if str(body["thinking"]["type"]) != "disabled":
		return _fail(name, "CODE amacı düşünmesiz olmalı")
	return _ok(name)


static func _test_v4_output_cap() -> Dictionary:
	var name := "V4 çıktı tavanı 384K, altı değer korunur"
	var adapter := AIDeepSeekV4Adapter.new()
	var req: AIProviderRequest = _v4_request(
		AIProviderRequest.Purpose.CODE,
		AIDeepSeekModelPolicy.MODEL_PRO
	)
	if int(adapter.build_request_body(req)["max_tokens"]) != 100000:
		return _fail(name, "100K yapay olarak kırpılmamalı")
	req.max_tokens = 999999
	if int(adapter.build_request_body(req)["max_tokens"]) != 384000:
		return _fail(name, "384K sağlayıcı tavanına kırpılmalı")
	return _ok(name)


static func _test_v4_response_model() -> Dictionary:
	var name := "V4 yanıtındaki gerçek model kimliği korunur"
	var adapter := AIDeepSeekV4Adapter.new()
	var raw: Dictionary = {
		"model": AIDeepSeekModelPolicy.MODEL_FLASH,
		"choices": [{"message": {"content": "tamam"}, "finish_reason": "stop"}],
		"usage": {"prompt_tokens": 3, "completion_tokens": 2},
	}
	var response: AIProviderResponse = adapter.parse_response(raw, 200)
	if not response.ok:
		return _fail(name, "geçerli V4 yanıtı başarısız")
	if response.model != AIDeepSeekModelPolicy.MODEL_FLASH:
		return _fail(name, "gerçek model korunmadı: " + response.model)
	return _ok(name)


static func _test_v4_cache_separation() -> Dictionary:
	var name := "V4 cache amacı/düşünme moduna göre ayrılır"
	var code_req: AIProviderRequest = _v4_request(
		AIProviderRequest.Purpose.CODE,
		AIDeepSeekModelPolicy.MODEL_PRO
	)
	var reason_req: AIProviderRequest = _v4_request(
		AIProviderRequest.Purpose.REASONING,
		AIDeepSeekModelPolicy.MODEL_PRO
	)
	if code_req.compute_cache_key() == reason_req.compute_cache_key():
		return _fail(name, "düşünmeli ve düşünmesiz istek cache çakıştı")
	var legacy_chat: AIProviderRequest = _v4_request(
		AIProviderRequest.Purpose.REASONING,
		AIDeepSeekModelPolicy.LEGACY_CHAT
	)
	var legacy_reasoner: AIProviderRequest = _v4_request(
		AIProviderRequest.Purpose.REASONING,
		AIDeepSeekModelPolicy.LEGACY_REASONER
	)
	if legacy_chat.compute_cache_key() == legacy_reasoner.compute_cache_key():
		return _fail(name, "legacy chat/reasoner cache çakıştı")
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _new() -> AIRoleChainRunner:
	return AIRoleChainRunner.new()


static func _test_base_chain_order() -> Dictionary:
	var name := "Zincir Architect→CodeEngineer→Reviewer sırasında"
	if AIRoleChainRunner.BASE_CHAIN.size() != 3:
		return _fail(name, "3 rol olmalı")
	if int(AIRoleChainRunner.BASE_CHAIN[0]) != AICellRoles.Role.ARCHITECT:
		return _fail(name, "ilk rol Architect olmalı")
	if int(AIRoleChainRunner.BASE_CHAIN[1]) != AICellRoles.Role.CODE_ENGINEER:
		return _fail(name, "ikinci rol CodeEngineer olmalı")
	if int(AIRoleChainRunner.BASE_CHAIN[2]) != AICellRoles.Role.REVIEWER:
		return _fail(name, "üçüncü rol Reviewer olmalı")
	return _ok(name)


static func _test_is_fail_true() -> Dictionary:
	var name := "Reviewer 'FAIL' → düzeltme tetikler"
	var r := _new()
	var got: bool = r._is_fail("FAIL: eksik tip bildirimi var")
	r.free()
	if not got:
		return _fail(name, "FAIL algılanmadı")
	return _ok(name)


static func _test_is_fail_pass() -> Dictionary:
	var name := "Reviewer 'PASS' → düzeltme yok"
	var r := _new()
	var got: bool = r._is_fail("PASS — kod temiz")
	r.free()
	if got:
		return _fail(name, "PASS yanlışlıkla FAIL sayıldı")
	return _ok(name)


static func _test_is_fail_mixed() -> Dictionary:
	var name := "PASS+FAIL birlikte → güvenli (PASS kazanır)"
	var r := _new()
	var got: bool = r._is_fail("Genel PASS; küçük not: FAIL olmamalı")
	r.free()
	if got:
		return _fail(name, "PASS varken FAIL sayılmamalı")
	return _ok(name)


static func _test_no_bridge_honest() -> Dictionary:
	var name := "Köprüsüz run → dürüst başarısızlık"
	var r := _new()
	var captured: Array = []
	r.chain_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	var started: bool = r.run("bir görev")
	r.free()
	if started:
		return _fail(name, "köprüsüz başlamamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "dürüst ok=false dönmeli")
	return _ok(name)


static func _test_no_router_honest() -> Dictionary:
	var name := "Router'sız köprü → zincir dürüstçe çöker (sahte yok)"
	var r := _new()
	var bridge := AIAgentLiveBridge.new()
	r.attach_bridge(bridge)
	var captured: Array = []
	r.chain_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	# Router yok → think_live SENKRON _emit_fail → _on_thought → _finish.
	r.run("bir görev")
	bridge.free()
	r.free()
	if captured.is_empty():
		return _fail(name, "chain_completed yayılmalı")
	if bool(captured[0]["ok"]):
		return _fail(name, "router yokken ok=false olmalı")
	if str(captured[0]["content"]) != "":
		return _fail(name, "sahte içerik üretilmemeli")
	return _ok(name)
