@tool
extends EditorPlugin

## Contract Test Plugin — bağımsız test aracı.
##
## Bu, ana eklentiden AYRI bir plugin'dir. Sadece "Project > Tools" menüsüne
## "AI Contract Testleri" girdisi ekler. Bu girdiye tıklayınca test paneli açılır.
##
## Mevcut ana eklentiyi (DeepSeek AI Assistant) hiç etkilemez — yan yana çalışır.
##
## Aktive etmek için: Project > Project Settings > Plugins > "AI Contract Tests" enable.

const MENU_ITEM_NAME := "AI Contract Testleri"

var _test_panel: Window = null


func _enter_tree() -> void:
	# Tools menüsüne girdi ekle
	add_tool_menu_item(MENU_ITEM_NAME, _open_test_panel)


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
	# Editör penceresinin çocuğu olarak ekle (popup gibi davranır)
	EditorInterface.get_base_control().add_child(_test_panel)
	# Ekranın büyük kısmını kapla (yatay + dikey genişler)
	_test_panel.popup_centered_ratio(0.85)
	_test_panel.tree_exited.connect(_on_panel_closed)


func _on_panel_closed() -> void:
	_test_panel = null
