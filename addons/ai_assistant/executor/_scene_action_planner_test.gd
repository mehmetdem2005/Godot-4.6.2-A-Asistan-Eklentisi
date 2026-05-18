@tool
class_name AISceneActionPlannerTest
extends RefCounted

## SceneActionPlanner + editör-action kablolaması self-test.
##
## Doğrular: editör mutasyon planlarının saf doğrulaması (geçerli node
## tipi / ad / yol / değer) VE executor'ın dürüstlüğü — editör yokken
## SAHTE "yapıldı" demez (SKIP), geçersiz plan FAIL eder (mock policy).
##
## Gerçek editör uygulaması (sahneye node ekleme vb.) Godot editöründe
## kullanıcı tarafından göz ile doğrulanır (devir §5.4) — burada DEĞİL.

static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Plan: Node", _test_node_add_valid()))
	results.append(_b("Plan: Node", _test_node_add_bad_type()))
	results.append(_b("Plan: Node", _test_node_add_non_node()))
	results.append(_b("Plan: Node", _test_node_add_bad_name()))
	results.append(_b("Plan: Node", _test_node_remove_rules()))
	results.append(_b("Plan: Prop", _test_property_set_rules()))
	results.append(_b("Plan: Script", _test_script_attach_rules()))
	results.append(_b("Plan: Ayar", _test_project_setting_rules()))
	results.append(_b("Plan: Yön", _test_plan_for_unknown()))
	results.append(_b("Exec: Dürüst", _test_executor_skips_no_editor()))
	results.append(_b("Exec: Dürüst", _test_executor_fails_bad_plan()))
	return results


static func _p() -> AISceneActionPlanner:
	return AISceneActionPlanner.new()


static func _test_node_add_valid() -> Dictionary:
	var name := "NODE_ADD: geçerli tip+ad kabul"
	var r: Dictionary = _p().plan_node_add({
		"node_type": "Node2D", "node_name": "Player", "parent": ".",
	})
	if not bool(r["ok"]):
		return _fail(name, "geçerli plan reddedildi: " + str(r["reason"]))
	if str(r["node_type"]) != "Node2D" or str(r["node_name"]) != "Player":
		return _fail(name, "plan alanları yanlış")
	return _ok(name)


static func _test_node_add_bad_type() -> Dictionary:
	var name := "NODE_ADD: uydurma tip RET (sahte yok)"
	var r: Dictionary = _p().plan_node_add({
		"node_type": "Notreal__Xyz", "node_name": "A",
	})
	if bool(r["ok"]):
		return _fail(name, "geçersiz tip kabul edildi")
	return _ok(name)


static func _test_node_add_non_node() -> Dictionary:
	var name := "NODE_ADD: Node olmayan sınıf (Resource) RET"
	var r: Dictionary = _p().plan_node_add({
		"node_type": "Resource", "node_name": "A",
	})
	if bool(r["ok"]):
		return _fail(name, "Node olmayan tip kabul edildi")
	return _ok(name)


static func _test_node_add_bad_name() -> Dictionary:
	var name := "NODE_ADD: yasak karakterli/boş ad RET"
	var bad: Dictionary = _p().plan_node_add({
		"node_type": "Node", "node_name": "a/b",
	})
	var empty: Dictionary = _p().plan_node_add({
		"node_type": "Node", "node_name": "",
	})
	if bool(bad["ok"]) or bool(empty["ok"]):
		return _fail(name, "geçersiz ad kabul edildi")
	return _ok(name)


static func _test_node_remove_rules() -> Dictionary:
	var name := "NODE_REMOVE: yol gerekir, kök silinemez"
	var ok_r: Dictionary = _p().plan_node_remove({
		"node_path": "Root/Enemy",
	})
	var empty: Dictionary = _p().plan_node_remove({"node_path": ""})
	var root: Dictionary = _p().plan_node_remove({"node_path": "."})
	if not bool(ok_r["ok"]):
		return _fail(name, "geçerli yol reddedildi")
	if bool(empty["ok"]) or bool(root["ok"]):
		return _fail(name, "boş yol / kök kabul edildi")
	return _ok(name)


static func _test_property_set_rules() -> Dictionary:
	var name := "PROPERTY_SET: node+property+value anahtarı zorunlu"
	var ok_r: Dictionary = _p().plan_property_set({
		"node_path": "Root", "property": "position", "value": Vector2(1, 2),
	})
	var no_val: Dictionary = _p().plan_property_set({
		"node_path": "Root", "property": "position",
	})
	var no_prop: Dictionary = _p().plan_property_set({
		"node_path": "Root", "property": "", "value": 1,
	})
	if not bool(ok_r["ok"]):
		return _fail(name, "geçerli property planı reddedildi")
	if bool(no_val["ok"]):
		return _fail(name, "value anahtarsız kabul edildi")
	if bool(no_prop["ok"]):
		return _fail(name, "boş property kabul edildi")
	return _ok(name)


static func _test_script_attach_rules() -> Dictionary:
	var name := "SCRIPT_ATTACH: yalnız güvenli .gd"
	var ok_r: Dictionary = _p().plan_script_attach({
		"node_path": "Root", "script_path": "res://game/scripts/p.gd",
	})
	var not_gd: Dictionary = _p().plan_script_attach({
		"node_path": "Root", "script_path": "res://game/scripts/p.txt",
	})
	var unsafe: Dictionary = _p().plan_script_attach({
		"node_path": "Root", "script_path": "/etc/passwd",
	})
	if not bool(ok_r["ok"]):
		return _fail(name, "geçerli .gd reddedildi: " + str(ok_r["reason"]))
	if bool(not_gd["ok"]) or bool(unsafe["ok"]):
		return _fail(name, "geçersiz/güvensiz script kabul edildi")
	return _ok(name)


static func _test_project_setting_rules() -> Dictionary:
	var name := "PROJECT_SETTING: key+value anahtarı zorunlu"
	var ok_r: Dictionary = _p().plan_project_setting({
		"key": "display/window/size/viewport_width", "value": 1080,
	})
	var no_key: Dictionary = _p().plan_project_setting({"value": 1})
	var no_val: Dictionary = _p().plan_project_setting({"key": "x"})
	if not bool(ok_r["ok"]):
		return _fail(name, "geçerli ayar reddedildi")
	if bool(no_key["ok"]) or bool(no_val["ok"]):
		return _fail(name, "eksik key/value kabul edildi")
	return _ok(name)


static func _test_plan_for_unknown() -> Dictionary:
	var name := "plan_for: bilinmeyen tip dürüst RET"
	var r: Dictionary = _p().plan_for(
		AIActionSpec.ActionType.FILE_WRITE, {}
	)
	if bool(r["ok"]):
		return _fail(name, "ilgisiz tip kabul edildi")
	return _ok(name)


static func _test_executor_skips_no_editor() -> Dictionary:
	var name := "Executor: editör yokken NODE_ADD SKIP (sahte 'yapıldı' yok)"
	var eng := AIExecutorEngine.new()
	var spec := AIActionSpec.create(
		AIActionSpec.ActionType.NODE_ADD, "res://game/scenes/m.tscn",
		"SceneEngineer"
	)
	spec.params = {"node_type": "Node2D", "node_name": "Player"}
	var node := AIPlanNode.create(AIPlanNode.Level.ACTION, "node ekle")
	var res: AIVerificationResult = eng.execute_action(node, spec)
	if res.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "editör yokken PASS demek SAHTE başarı olur")
	if res.outcome != AIVerificationResult.Outcome.SKIP:
		return _fail(name, "dürüst SKIP beklenir: " + res.outcome_name())
	return _ok(name)


static func _test_executor_fails_bad_plan() -> Dictionary:
	var name := "Executor: geçersiz NODE_ADD planı FAIL (mock policy)"
	var eng := AIExecutorEngine.new()
	var spec := AIActionSpec.create(
		AIActionSpec.ActionType.NODE_ADD, "res://game/scenes/m.tscn",
		"SceneEngineer"
	)
	spec.params = {"node_type": "Notreal__Xyz", "node_name": "A"}
	var node := AIPlanNode.create(AIPlanNode.Level.ACTION, "node ekle")
	var res: AIVerificationResult = eng.execute_action(node, spec)
	if res.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "geçersiz plan FAIL olmalı: " + res.outcome_name())
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}
