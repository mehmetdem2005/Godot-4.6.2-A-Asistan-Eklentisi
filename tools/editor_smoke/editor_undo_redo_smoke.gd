@tool
class_name AIEditorUndoRedoSmoke
extends EditorScript

## Canlı Godot editörü için izole Undo/Redo smoke harness.
##
## Güvenlik: yalnız FIXTURE_SCENE açıkken çalışır. Kullanıcının gerçek
## oyun sahnelerine dokunmaz. Üç gerçek mutasyonu doğrular:
##   1. NODE_ADD
##   2. PROPERTY_SET
##   3. SCRIPT_ATTACH
## Her işlem için do -> undo -> redo -> cleanup undo zinciri kanıtlanır ve
## fixture başlangıç durumuna geri getirilip kaydedilir.

const FIXTURE_SCENE: String = "res://tools/editor_smoke/fixture.tscn"
const FIXTURE_SCRIPT: String = "res://tools/editor_smoke/fixture_script.gd"
const TARGET_PATH: NodePath = NodePath("Target")
const ADDED_PATH: NodePath = NodePath("AddedByAI")


func _run() -> void:
	print("=== AI Editor Undo/Redo Smoke ===")
	var result: Dictionary = run_smoke()
	_finish(bool(result.get("ok", false)), str(result.get("message", "")))


## Hem elle çalıştırılan EditorScript hem de CI eklentisi aynı kanıt
## çekirdeğini kullanır. Sonuç sözlüğü sayesinde CI log metnini tahmin
## etmek yerine gerçek başarı durumuyla çıkış kodu verebilir.
func run_smoke() -> Dictionary:
	if not Engine.is_editor_hint():
		return _result(false, "Godot editör bağlamı yok", 0, 3)

	var root: Node = EditorInterface.get_edited_scene_root()
	var fixture_error: String = _fixture_error(root)
	if not fixture_error.is_empty():
		return _result(false, fixture_error, 0, 3)

	var manager: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	if manager == null:
		return _result(false, "EditorUndoRedoManager alınamadı", 0, 3)

	var history_id: int = manager.get_object_history_id(root)
	if history_id == EditorUndoRedoManager.INVALID_HISTORY:
		return _result(false, "Fixture için geçerli undo history bulunamadı", 0, 3)
	manager.clear_history(history_id, false)
	var history: UndoRedo = manager.get_history_undo_redo(history_id)
	if history == null:
		return _result(false, "Fixture UndoRedo nesnesi alınamadı", 0, 3)

	var planner := AISceneActionPlanner.new()
	var applier := AIEditorActionApplier.new()
	var results: Array[Dictionary] = []
	results.append(_test_node_add(root, planner, applier, history))
	results.append(_test_property(root, planner, applier, history))
	results.append(_test_script(root, planner, applier, history))

	var passed: int = 0
	for test_result in results:
		if bool(test_result.get("ok", false)):
			passed += 1
			print("  ✓ " + str(test_result.get("name", "")))
		else:
			printerr(
				"  ✗ %s — %s" % [
					str(test_result.get("name", "")),
					str(test_result.get("reason", "")),
				]
			)

	var final_error: String = _fixture_error(root)
	if not final_error.is_empty():
		return _result(
			false,
			"Test sonrası fixture başlangıç durumuna dönmedi: " + final_error,
			passed,
			results.size()
		)

	var save_error: int = EditorInterface.save_scene()
	if save_error != OK:
		return _result(
			false,
			"Fixture temizlendi ancak kaydedilemedi: %d" % save_error,
			passed,
			results.size()
		)

	return _result(
		passed == results.size(),
		"%d/%d smoke testi geçti" % [passed, results.size()],
		passed,
		results.size()
	)


func _test_node_add(
	root: Node,
	planner: AISceneActionPlanner,
	applier: AIEditorActionApplier,
	history: UndoRedo
) -> Dictionary:
	var name := "NODE_ADD do/undo/redo"
	var plan: Dictionary = planner.plan_node_add({
		"scene_path": FIXTURE_SCENE,
		"node_type": "Node2D",
		"node_name": str(ADDED_PATH),
		"parent": ".",
	})
	if not bool(plan.get("ok", false)):
		return _fail(name, "plan reddedildi: " + str(plan.get("reason", "")))

	var applied: Dictionary = applier.apply_node_add(plan)
	if not bool(applied.get("ok", false)):
		return _fail(name, "do başarısız: " + str(applied.get("reason", "")))
	if root.get_node_or_null(ADDED_PATH) == null:
		return _fail(name, "do sonrası node yok")

	history.undo()
	if root.get_node_or_null(ADDED_PATH) != null:
		return _fail(name, "undo node'u kaldırmadı")
	history.redo()
	if root.get_node_or_null(ADDED_PATH) == null:
		return _fail(name, "redo node'u geri getirmedi")
	history.undo()
	if root.get_node_or_null(ADDED_PATH) != null:
		return _fail(name, "cleanup undo node'u kaldırmadı")
	return _ok(name)


func _test_property(
	root: Node,
	planner: AISceneActionPlanner,
	applier: AIEditorActionApplier,
	history: UndoRedo
) -> Dictionary:
	var name := "PROPERTY_SET do/undo/redo"
	var target: Node2D = root.get_node_or_null(TARGET_PATH) as Node2D
	if target == null:
		return _fail(name, "Target bulunamadı")

	var plan: Dictionary = planner.plan_property_set({
		"scene_path": FIXTURE_SCENE,
		"node_path": str(TARGET_PATH),
		"property": "visible",
		"value": false,
	})
	if not bool(plan.get("ok", false)):
		return _fail(name, "plan reddedildi: " + str(plan.get("reason", "")))

	var applied: Dictionary = applier.apply_property_set(plan)
	if not bool(applied.get("ok", false)):
		return _fail(name, "do başarısız: " + str(applied.get("reason", "")))
	if target.visible:
		return _fail(name, "do visible=false uygulamadı")

	history.undo()
	if not target.visible:
		return _fail(name, "undo visible=true yapmadı")
	history.redo()
	if target.visible:
		return _fail(name, "redo visible=false yapmadı")
	history.undo()
	if not target.visible:
		return _fail(name, "cleanup undo başlangıç değerini döndürmedi")
	return _ok(name)


func _test_script(
	root: Node,
	planner: AISceneActionPlanner,
	applier: AIEditorActionApplier,
	history: UndoRedo
) -> Dictionary:
	var name := "SCRIPT_ATTACH do/undo/redo"
	var target: Node2D = root.get_node_or_null(TARGET_PATH) as Node2D
	if target == null:
		return _fail(name, "Target bulunamadı")

	var plan: Dictionary = planner.plan_script_attach({
		"scene_path": FIXTURE_SCENE,
		"node_path": str(TARGET_PATH),
		"script_path": FIXTURE_SCRIPT,
	})
	if not bool(plan.get("ok", false)):
		return _fail(name, "plan reddedildi: " + str(plan.get("reason", "")))

	var applied: Dictionary = applier.apply_script_attach(plan)
	if not bool(applied.get("ok", false)):
		return _fail(name, "do başarısız: " + str(applied.get("reason", "")))
	if target.get_script() == null:
		return _fail(name, "do script bağlamadı")

	history.undo()
	if target.get_script() != null:
		return _fail(name, "undo script'i kaldırmadı")
	history.redo()
	if target.get_script() == null:
		return _fail(name, "redo script'i geri bağlamadı")
	history.undo()
	if target.get_script() != null:
		return _fail(name, "cleanup undo script'i kaldırmadı")
	return _ok(name)


func _fixture_error(root: Node) -> String:
	if root == null:
		return "Önce fixture sahnesini aç: " + FIXTURE_SCENE
	var actual: String = root.scene_file_path.strip_edges().simplify_path()
	if actual != FIXTURE_SCENE:
		return "Yanlış sahne açık. Beklenen: %s, açık: %s" % [FIXTURE_SCENE, actual]
	if root.get_node_or_null(ADDED_PATH) != null:
		return "Fixture kirli: AddedByAI zaten var; sahneyi diskten yeniden aç"
	var target: Node2D = root.get_node_or_null(TARGET_PATH) as Node2D
	if target == null:
		return "Fixture kirli: Target yok"
	if not target.visible:
		return "Fixture kirli: Target.visible true olmalı"
	if target.get_script() != null:
		return "Fixture kirli: Target üzerinde script olmamalı"
	return ""


func _finish(ok: bool, message: String) -> void:
	if ok:
		print("SMOKE_OK: " + message)
	else:
		printerr("SMOKE_FAIL: " + message)
	print("=== Smoke tamamlandı ===")


func _result(ok: bool, message: String, passed: int, total: int) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"passed": passed,
		"total": total,
	}


func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
