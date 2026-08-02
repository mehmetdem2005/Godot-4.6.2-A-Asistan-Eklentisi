@tool
class_name AISceneActionPlannerTest
extends RefCounted

## Scene action doğrulama, hedef sahne bağlama ve executor izin testleri.

static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Plan: Node", _test_node_add_valid()))
	results.append(_b("Plan: Node", _test_node_add_bad_type()))
	results.append(_b("Plan: Node", _test_node_add_non_node()))
	results.append(_b("Plan: Node", _test_node_add_bad_name()))
	results.append(_b("Plan: Node", _test_node_remove_rules()))
	results.append(_b("Plan: Yol", _test_node_path_traversal_rejected()))
	results.append(_b("Plan: Sahne", _test_scene_path_rules()))
	results.append(_b("Plan: Prop", _test_property_set_rules()))
	results.append(_b("Plan: Script", _test_script_attach_rules()))
	results.append(_b("Plan: Ayar", _test_project_setting_rules()))
	results.append(_b("Plan: Ayar", _test_security_settings_blocked()))
	results.append(_b("Plan: Yön", _test_plan_for_unknown()))
	results.append(_b("Exec: Dürüst", _test_executor_skips_no_editor()))
	results.append(_b("Exec: Dürüst", _test_executor_fails_bad_plan()))
	results.append(_b("Exec: İzin", _test_scoped_destructive_approval()))
	return results


static func _p() -> AISceneActionPlanner:
	return AISceneActionPlanner.new()


static func _test_node_add_valid() -> Dictionary:
	var name := "NODE_ADD: geçerli tip+ad kabul"
	var result: Dictionary = _p().plan_node_add({
		"node_type": "Node2D",
		"node_name": "Player",
		"parent": ".",
		"scene_path": "res://game/scenes/main.tscn",
	})
	if not bool(result["ok"]):
		return _fail(name, "geçerli plan reddedildi: " + str(result["reason"]))
	if str(result["node_type"]) != "Node2D":
		return _fail(name, "node tipi korunmadı")
	if str(result["scene_path"]) != "res://game/scenes/main.tscn":
		return _fail(name, "hedef sahne plana bağlanmadı")
	return _ok(name)


static func _test_node_add_bad_type() -> Dictionary:
	var name := "NODE_ADD: uydurma tip reddedilir"
	var result: Dictionary = _p().plan_node_add({
		"node_type": "Notreal__Xyz", "node_name": "A",
	})
	if bool(result["ok"]):
		return _fail(name, "geçersiz tip kabul edildi")
	return _ok(name)


static func _test_node_add_non_node() -> Dictionary:
	var name := "NODE_ADD: Node olmayan sınıf reddedilir"
	var result: Dictionary = _p().plan_node_add({
		"node_type": "Resource", "node_name": "A",
	})
	if bool(result["ok"]):
		return _fail(name, "Node olmayan tip kabul edildi")
	return _ok(name)


static func _test_node_add_bad_name() -> Dictionary:
	var name := "NODE_ADD: yasak karakterli veya boş ad reddedilir"
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
	var name := "NODE_REMOVE: yol gerekir ve kök silinemez"
	var valid: Dictionary = _p().plan_node_remove({"node_path": "Enemies/Boss"})
	var empty: Dictionary = _p().plan_node_remove({"node_path": ""})
	var root: Dictionary = _p().plan_node_remove({"node_path": "."})
	if not bool(valid["ok"]):
		return _fail(name, "geçerli yol reddedildi")
	if bool(empty["ok"]) or bool(root["ok"]):
		return _fail(name, "boş yol veya kök kabul edildi")
	return _ok(name)


static func _test_node_path_traversal_rejected() -> Dictionary:
	var name := "Node yollarında traversal ve mutlak yol engellenir"
	var traversal: Dictionary = _p().plan_node_remove({
		"node_path": "Enemies/../Player",
	})
	var absolute: Dictionary = _p().plan_property_set({
		"node_path": "/root/Main", "property": "name", "value": "X",
	})
	if bool(traversal["ok"]) or bool(absolute["ok"]):
		return _fail(name, "güvensiz node yolu kabul edildi")
	return _ok(name)


static func _test_scene_path_rules() -> Dictionary:
	var name := "Hedef sahne yalnız güvenli res:// scene yolu olabilir"
	var valid: Dictionary = _p().plan_node_add({
		"node_type": "Node",
		"node_name": "A",
		"scene_path": "res://game/scenes/a.tscn",
	})
	var external: Dictionary = _p().plan_node_add({
		"node_type": "Node", "node_name": "A", "scene_path": "/tmp/a.tscn",
	})
	var wrong_type: Dictionary = _p().plan_node_add({
		"node_type": "Node",
		"node_name": "A",
		"scene_path": "res://game/scenes/a.txt",
	})
	if not bool(valid["ok"]):
		return _fail(name, "geçerli sahne yolu reddedildi")
	if bool(external["ok"]) or bool(wrong_type["ok"]):
		return _fail(name, "güvensiz sahne yolu kabul edildi")
	return _ok(name)


static func _test_property_set_rules() -> Dictionary:
	var name := "PROPERTY_SET: node, property ve value zorunlu"
	var valid: Dictionary = _p().plan_property_set({
		"node_path": "Player", "property": "position", "value": Vector2(1, 2),
	})
	var no_value: Dictionary = _p().plan_property_set({
		"node_path": "Player", "property": "position",
	})
	var subname: Dictionary = _p().plan_property_set({
		"node_path": "Player", "property": "position:x", "value": 1,
	})
	if not bool(valid["ok"]):
		return _fail(name, "geçerli property planı reddedildi")
	if bool(no_value["ok"]) or bool(subname["ok"]):
		return _fail(name, "eksik veya belirsiz property planı kabul edildi")
	return _ok(name)


static func _test_script_attach_rules() -> Dictionary:
	var name := "SCRIPT_ATTACH: yalnız güvenli .gd"
	var valid: Dictionary = _p().plan_script_attach({
		"node_path": "Player", "script_path": "res://game/scripts/player.gd",
	})
	var not_gd: Dictionary = _p().plan_script_attach({
		"node_path": "Player", "script_path": "res://game/scripts/player.txt",
	})
	var unsafe: Dictionary = _p().plan_script_attach({
		"node_path": "Player", "script_path": "/etc/passwd",
	})
	if not bool(valid["ok"]):
		return _fail(name, "geçerli script reddedildi: " + str(valid["reason"]))
	if bool(not_gd["ok"]) or bool(unsafe["ok"]):
		return _fail(name, "geçersiz script kabul edildi")
	return _ok(name)


static func _test_project_setting_rules() -> Dictionary:
	var name := "PROJECT_SETTING: tam anahtar yolu ve value zorunlu"
	var valid: Dictionary = _p().plan_project_setting({
		"key": "display/window/size/viewport_width", "value": 1080,
	})
	var no_key: Dictionary = _p().plan_project_setting({"value": 1})
	var short_key: Dictionary = _p().plan_project_setting({"key": "x", "value": 1})
	if not bool(valid["ok"]):
		return _fail(name, "geçerli ayar reddedildi")
	if bool(no_key["ok"]) or bool(short_key["ok"]):
		return _fail(name, "geçersiz ayar anahtarı kabul edildi")
	return _ok(name)


static func _test_security_settings_blocked() -> Dictionary:
	var name := "Güvenlik-kritik proje ayarları modelden değiştirilemez"
	for key in [
		"editor_plugins/enabled",
		"application/config/project_settings_override",
		"application/run/disable_stdout",
		"application/run/disable_stderr",
	]:
		var result: Dictionary = _p().plan_project_setting({"key": key, "value": true})
		if bool(result["ok"]):
			return _fail(name, "yasak ayar kabul edildi: " + key)
	return _ok(name)


static func _test_plan_for_unknown() -> Dictionary:
	var name := "plan_for: bilinmeyen tip açıkça reddedilir"
	var result: Dictionary = _p().plan_for(AIActionSpec.ActionType.FILE_WRITE, {})
	if bool(result["ok"]):
		return _fail(name, "ilgisiz action tipi kabul edildi")
	return _ok(name)


static func _test_executor_skips_no_editor() -> Dictionary:
	var name := "Executor editör yokken sahte başarı üretmez"
	var engine := AIExecutorEngine.new()
	var spec := AIActionSpec.create(
		AIActionSpec.ActionType.NODE_ADD,
		"res://game/scenes/main.tscn",
		"SceneEngineer"
	)
	spec.params = {"node_type": "Node2D", "node_name": "Player"}
	var node := AIPlanNode.create(AIPlanNode.Level.ACTION, "node ekle")
	var result: AIVerificationResult = engine.execute_action(node, spec)
	if result.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "editör bağlamı olmadan PASS döndü")
	return _ok(name)


static func _test_executor_fails_bad_plan() -> Dictionary:
	var name := "Executor geçersiz editor planını FAIL eder"
	var engine := AIExecutorEngine.new()
	var spec := AIActionSpec.create(
		AIActionSpec.ActionType.NODE_ADD,
		"res://game/scenes/main.tscn",
		"SceneEngineer"
	)
	spec.params = {"node_type": "Notreal__Xyz", "node_name": "A"}
	var node := AIPlanNode.create(AIPlanNode.Level.ACTION, "node ekle")
	var result: AIVerificationResult = engine.execute_action(node, spec)
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "geçersiz plan FAIL olmadı: " + result.outcome_name())
	return _ok(name)


static func _test_scoped_destructive_approval() -> Dictionary:
	var name := "Yıkıcı izin ActionSpec kimliğine bağlı ve iptal edilebilir"
	var engine := AIExecutorEngine.new()
	var approved := AIActionSpec.create(
		AIActionSpec.ActionType.FILE_DELETE, "res://game/a.gd", "Test"
	)
	var other := AIActionSpec.create(
		AIActionSpec.ActionType.FILE_DELETE, "res://game/b.gd", "Test"
	)
	var approval: Dictionary = engine.approve_destructive_action(approved)
	if not bool(approval["ok"]) or engine.pending_destructive_approvals() != 1:
		return _fail(name, "izin üretilemedi")
	if engine.revoke_destructive_action(other):
		return _fail(name, "başka action aynı izni iptal edebildi")
	if not engine.revoke_destructive_action(approved):
		return _fail(name, "doğru action izni iptal edemedi")
	if engine.pending_destructive_approvals() != 0:
		return _fail(name, "iptal sonrası izin kaldı")
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


static func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
