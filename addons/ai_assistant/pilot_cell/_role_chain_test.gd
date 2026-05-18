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
	return results


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
