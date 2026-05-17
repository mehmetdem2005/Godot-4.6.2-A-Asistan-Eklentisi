@tool
class_name AIMainDock
extends Control

## MainDock — ana eklenti paneli, ince görsel kabuk (Aşama 5).
##
## Tüm KARAR mantığı AIMainPanelController'da (test edilebilir).
## Bu Control kodla kurulur (.tscn YOK — proje disiplini), gerçek
## çalıştırmayı kanıtlanmış AIPipelineOrchestrator (Aşama 4c) ile
## yapar. Görseli kullanıcı telefonda Godot'ta doğrular.

var _ctrl: AIMainPanelController = null
var _bridge: AIAgentLiveBridge = null
var _orch: AIPipelineOrchestrator = null

var _task_edit: TextEdit = null
var _key_edit: LineEdit = null
var _status_label: Label = null
var _live_check: CheckBox = null
var _tab_bar: TabBar = null
var _run_btn: Button = null


func _init() -> void:
	_ctrl = AIMainPanelController.new()


func _ready() -> void:
	_build_ui()
	_refresh_status()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "AI Asistan — Otonom Oyun Geliştirici"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	# --- Sekme çubuğu (9 sekme, #4) ---
	_tab_bar = TabBar.new()
	for n in _ctrl.tab_names():
		_tab_bar.add_tab(str(n))
	_tab_bar.scrolling_enabled = true
	_tab_bar.tab_changed.connect(_on_tab)
	root.add_child(_tab_bar)

	# --- Ayarlar: API anahtarı (#5) ---
	var key_row := HBoxContainer.new()
	root.add_child(key_row)
	var key_lbl := Label.new()
	key_lbl.text = "DeepSeek API Anahtarı:"
	key_row.add_child(key_lbl)
	_key_edit = LineEdit.new()
	_key_edit.secret = true
	_key_edit.placeholder_text = "sk-..."
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(_key_edit)
	var key_btn := Button.new()
	key_btn.text = "Kaydet"
	key_btn.pressed.connect(_on_save_key)
	key_row.add_child(key_btn)

	_live_check = CheckBox.new()
	_live_check.text = "Canlı mod (gerçek LLM çağrısı)"
	_live_check.toggled.connect(_on_live_toggled)
	root.add_child(_live_check)

	# --- Görev girişi + çalıştır (#3 yönetilebilir) ---
	var task_lbl := Label.new()
	task_lbl.text = "Görev (ne yapılsın?):"
	root.add_child(task_lbl)
	_task_edit = TextEdit.new()
	_task_edit.custom_minimum_size = Vector2(0, 90)
	_task_edit.placeholder_text = (
		"Örn: ekrana merhaba yazan bir script üret"
	)
	root.add_child(_task_edit)

	_run_btn = Button.new()
	_run_btn.text = "▶ Üret ve Uygula"
	_run_btn.pressed.connect(_on_run)
	root.add_child(_run_btn)

	# --- Durum (#2 izlenebilir) ---
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _on_tab(idx: int) -> void:
	_ctrl.switch_tab(idx)
	_refresh_status()


func _on_save_key() -> void:
	var res: Dictionary = _ctrl.save_api_key(_key_edit.text)
	_ctrl.set_status(
		("✓ Anahtar kaydedildi" if bool(res["ok"])
		else "✗ " + str(res["reason"]))
	)
	if bool(res["ok"]):
		_key_edit.text = ""
	_refresh_status()


func _on_live_toggled(pressed: bool) -> void:
	_ctrl.set_live_mode(pressed)
	_refresh_status()


func _on_run() -> void:
	var task: String = _task_edit.text
	var gate: Dictionary = _ctrl.can_run_task(task)
	if not bool(gate["ok"]):
		_ctrl.set_status("✗ " + str(gate["reason"]))
		_refresh_status()
		return

	var key_res: Dictionary = _ctrl.resolve_api_key()
	if not bool(key_res["ok"]):
		_ctrl.set_status("✗ Anahtar çözülemedi: " + str(key_res["reason"]))
		_refresh_status()
		return

	var router := AIProviderRouter.new()
	router.set_api_key(
		AIProviderRequest.Provider.DEEPSEEK, str(key_res["key"])
	)
	_bridge = AIAgentLiveBridge.new()
	add_child(_bridge)
	_bridge.attach_router(router)
	_orch = AIPipelineOrchestrator.new()
	add_child(_orch)
	_orch.attach_bridge(_bridge)
	_orch.pipeline_progress.connect(func(s: String) -> void:
		_ctrl.set_status("… " + s)
		_refresh_status()
	)
	_orch.pipeline_completed.connect(_on_pipeline_done)

	_run_btn.disabled = true
	_ctrl.set_status("… Ajan düşünüyor (canlı)…")
	_refresh_status()
	_orch.run_task(
		"Panel görevi", _ctrl.default_target_path(task),
		task, AICellRoles.Role.CODE_ENGINEER
	)


func _on_pipeline_done(result: Dictionary) -> void:
	_ctrl.record_result(result)
	_run_btn.disabled = false
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var s: Dictionary = _ctrl.summary()
	_status_label.text = (
		"Durum: %s\nSekme: %s | Canlı: %s | Anahtar: %s"
		% [
			str(s["status"]), str(s["active_tab"]),
			("açık" if bool(s["live_mode"]) else "kapalı"),
			("var" if bool(s["has_key"]) else "yok"),
		]
	)


## Test/dış erişim — panel beyni.
func controller() -> AIMainPanelController:
	return _ctrl
