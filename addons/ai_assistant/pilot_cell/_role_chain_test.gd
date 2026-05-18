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
	results.append(_b("Chain: Bölünme", _test_join_clean_strips_fences()))
	results.append(_b("Chain: Bölünme", _test_tail_keeps_end()))
	results.append(_b("Chain: Bölünme", _test_chunk_bound()))
	return results


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
	var name := "Kod rolleri deepseek-chat'e zorlanır (reasoner değil)"
	if AIRoleChainRunner.CODE_MODEL != "deepseek-chat":
		return _fail(name, "CODE_MODEL deepseek-chat olmalı")
	# Sözleşme: zincirdeki kod-üreten rol gerçekten kod-üreten say.
	if not AICellRoles.is_code_generating(AICellRoles.Role.CODE_ENGINEER):
		return _fail(name, "CodeEngineer kod-üreten olmalı")
	if AICellRoles.is_code_generating(AICellRoles.Role.ARCHITECT):
		return _fail(name, "Architect kod-üreten sayılmamalı (model korunur)")
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
