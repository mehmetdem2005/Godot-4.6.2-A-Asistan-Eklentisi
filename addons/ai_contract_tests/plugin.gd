@tool
extends EditorPlugin

## Contract Test Plugin — bağımsız test aracı.
##
## Normal kullanımda yalnız Project > Tools menüsünü ekler. CI'da
## AI_EDITOR_SMOKE=1 ortam değişkeni verilirse izole fixture sahnesini açar,
## gerçek EditorUndoRedoManager smoke harness'ını çalıştırır ve editörü
## sonuçtan sonra kapatır. Kullanıcının oyun sahnelerine dokunulmaz.

const MENU_ITEM_NAME := "AI Contract Testleri"
const EDITOR_SMOKE_ENV := "AI_EDITOR_SMOKE"
const FIXTURE_SCENE := "res://tools/editor_smoke/fixture.tscn"

var _test_panel: Window = null
var _ci_smoke_started: bool = false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM_NAME, _open_test_panel)
	if OS.get_environment(EDITOR_SMOKE_ENV).strip_edges() == "1":
		call_deferred("_run_ci_editor_smoke")


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM_NAME)
	if is_instance_valid(_test_panel):
		_test_panel.queue_free()
		_test_panel = null


## Test panelini açar (zaten açıksa öne getirir).
func _open_test_panel() -> void:
	if is_instance_valid(_test_panel):
		_test_panel.grab_focus()
		_test_panel.move_to_foreground()
		return

	var PanelClass := preload("res://addons/ai_assistant/contracts/test_panel.gd")
	_test_panel = PanelClass.new()
	EditorInterface.get_base_control().add_child(_test_panel)
	_test_panel.popup_centered_ratio(0.85)
	_test_panel.tree_exited.connect(_on_panel_closed)


func _on_panel_closed() -> void:
	_test_panel = null


## CI-only gerçek editör smoke akışı.
## Plugin'in yüklenmesi ile sahne kökünün hazır olması aynı frame'e denk
## gelmediğinden birkaç frame beklenir. Harness tamamlandıktan sonra logun
## diske akması için iki frame daha verilir.
func _run_ci_editor_smoke() -> void:
	if _ci_smoke_started:
		return
	_ci_smoke_started = true
	print("CI_EDITOR_SMOKE_START")

	var open_error: int = EditorInterface.open_scene_from_path(FIXTURE_SCENE)
	if open_error != OK:
		printerr("SMOKE_FAIL: Fixture açılamadı: %d" % open_error)
		await _quit_ci_editor(51)
		return

	var root: Node = null
	for _attempt in range(120):
		await get_tree().process_frame
		root = EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path.simplify_path() == FIXTURE_SCENE:
			break
	if root == null or root.scene_file_path.simplify_path() != FIXTURE_SCENE:
		printerr("SMOKE_FAIL: Fixture editör kökü hazır olmadı")
		await _quit_ci_editor(52)
		return

	var SmokeClass := preload(
		"res://tools/editor_smoke/editor_undo_redo_smoke.gd"
	)
	var smoke: EditorScript = SmokeClass.new()
	var result: Dictionary = smoke.run_smoke()
	var ok: bool = bool(result.get("ok", false))
	var message: String = str(result.get("message", "sonuç yok"))
	if ok:
		print("SMOKE_OK: " + message)
	else:
		printerr("SMOKE_FAIL: " + message)
	await get_tree().process_frame
	await get_tree().process_frame
	print("CI_EDITOR_SMOKE_DONE")
	await _quit_ci_editor(0 if ok else 53)


func _quit_ci_editor(exit_code: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
