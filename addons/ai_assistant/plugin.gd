@tool
extends EditorPlugin

## AI Asistan — ana eklenti giriş noktası (Aşama 5).
##
## Bu, ana eklentinin İLK kez var olan plugin.cfg/plugin.gd'sidir.
## Önceden sadece ayrı ai_contract_tests plugin'i vardı; asıl asistan
## editöre HİÇ takılmıyordu (devir §2.3 / "bitti" #1 yapısal engel).
##
## İKİ erişim yolu (telefonda keşfedilebilirlik için):
##   1. Sol dock'a görünür panel (main_dock.gd).
##   2. Project > Tools > "AI Asistan Panel" — paneli büyük bir
##      pencere olarak açar (Android'de dock bulmak zor; bu yol
##      ai_contract_tests ile aynı, kanıtlanmış keşfedilebilir desen).
##
## Aktive: Project > Project Settings > Plugins > "AI Asistan" enable.

const MENU_ITEM := "AI Asistan Panel"

var _dock: Control = null
var _window: Window = null


func _enter_tree() -> void:
	var DockClass := preload(
		"res://addons/ai_assistant/main_dock.gd"
	)
	_dock = DockClass.new()
	_dock.name = "AI Asistan"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, _dock)
	add_tool_menu_item(MENU_ITEM, _open_window)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if is_instance_valid(_window):
		_window.queue_free()
		_window = null


## Paneli ayrı, büyük bir pencere olarak açar (telefon dostu).
func _open_window() -> void:
	if is_instance_valid(_window):
		_window.move_to_foreground()
		_window.grab_focus()
		return
	var DockClass := preload(
		"res://addons/ai_assistant/main_dock.gd"
	)
	_window = Window.new()
	_window.title = "AI Asistan — Otonom Oyun Geliştirici"
	_window.size = Vector2i(1000, 1300)
	_window.min_size = Vector2i(420, 600)
	var panel := DockClass.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.add_child(panel)
	_window.close_requested.connect(_on_window_closed)
	EditorInterface.get_base_control().add_child(_window)
	_window.popup_centered_ratio(0.85)


func _on_window_closed() -> void:
	if is_instance_valid(_window):
		_window.queue_free()
	_window = null
