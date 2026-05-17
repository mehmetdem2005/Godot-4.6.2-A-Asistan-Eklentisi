@tool
extends EditorPlugin

## AI Asistan — ana eklenti giriş noktası (Aşama 5).
##
## Bu, ana eklentinin İLK kez var olan plugin.cfg/plugin.gd'sidir.
## Önceden sadece ayrı ai_contract_tests plugin'i vardı; asıl asistan
## editöre HİÇ takılmıyordu (devir §2.3 / "bitti" #1 yapısal engel).
##
## Açılınca sol dock'a görünür panel (main_dock.gd) ekler — kodla
## kurulan, kanıtlanmış uçtan uca orkestratöre bağlı.
##
## Aktive: Project > Project Settings > Plugins > "AI Asistan" enable.

var _dock: Control = null


func _enter_tree() -> void:
	var DockClass := preload(
		"res://addons/ai_assistant/main_dock.gd"
	)
	_dock = DockClass.new()
	_dock.name = "AI Asistan"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, _dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
