@tool
extends EditorPlugin

## AI Asistan — ana eklenti giriş noktası (Plan B: büyük ana ekran).
##
## ÖNCE: panel dar sol dock'a sıkışıyordu, telefonda çok küçüktü.
## ŞİMDI: editörün ÜST sekmesi (2D / 3D / Script yanında) olan tam
## ekran bir ana ekran (main screen) — büyük SOHBET; "≡ Menü" ile
## Ayarlar ve 9 sekmelik Çalışma Alanı görünümlerine geçilir.
##
## İKİ erişim yolu (telefonda keşfedilebilirlik için):
##   1. Üst sekme "AI Asistan" (ana ekran — _has_main_screen).
##   2. Project > Tools > "AI Asistan Panel" — aynı ekranı büyük bir
##      pencere olarak açar (kanıtlanmış keşfedilebilir desen).
##
## Aktive: Project > Project Settings > Plugins > "AI Asistan" enable.

const MENU_ITEM := "AI Asistan Panel"

var _screen: Control = null
var _window: Window = null


func _enter_tree() -> void:
	_screen = AIStudioScreen.new()
	_screen.name = "AI Asistan"
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_screen.visible = false
	add_tool_menu_item(MENU_ITEM, _open_window)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
	if is_instance_valid(_window):
		_window.queue_free()
		_window = null


# ============================================================
# ANA EKRAN (main screen) — üst sekme
# ============================================================

func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "AI Asistan"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(
		"Node", "EditorIcons"
	)


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_screen):
		_screen.visible = visible


# ============================================================
# PENCERE FALLBACK — Project > Tools (telefon dostu)
# ============================================================

## Aynı ekranı ayrı, büyük bir pencere olarak açar.
func _open_window() -> void:
	if is_instance_valid(_window):
		_window.move_to_foreground()
		_window.grab_focus()
		return
	_window = Window.new()
	_window.title = "AI Asistan — Otonom Oyun Geliştirici"
	_window.size = Vector2i(1000, 1300)
	_window.min_size = Vector2i(420, 600)
	var panel := AIStudioScreen.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.add_child(panel)
	_window.close_requested.connect(_on_window_closed)
	EditorInterface.get_base_control().add_child(_window)
	_window.popup_centered_ratio(0.85)


func _on_window_closed() -> void:
	if is_instance_valid(_window):
		_window.queue_free()
	_window = null
