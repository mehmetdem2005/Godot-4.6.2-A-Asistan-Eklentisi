@tool
class_name AIStudioScreen
extends Control

## AIStudioScreen — büyük "AI Asistan" ana ekranı (Plan B).
##
## SORUN: panel sol dock'a sıkışıyordu, telefonda çok küçüktü.
## ÇÖZÜM: editör üst sekmesi (2D/3D/Script yanında) olan tam ekran
## bir Control. Ortada SOHBET; "≡ Menü" ile AYARLAR ve 9 sekmelik
## WORKSPACE görünümlerine geçilir.
##
## Tüm KARAR mantığı AIMainPanelController'da (sahnesiz test edilir).
## Bu Control ince görsel kabuk; kodla kurulur (.tscn YOK — proje
## disiplini). Gerçek çalıştırma kanıtlanmış AIPipelineOrchestrator
## (Aşama 4c) ile yapılır. Görseli kullanıcı telefonda doğrular.

enum View { CHAT, SETTINGS, WORKSPACE }

const VIEW_TITLES: Dictionary = {
	View.CHAT: "Sohbet Ekranı",
	View.SETTINGS: "Ayarlar",
	View.WORKSPACE: "Çalışma Alanı (9 Sekme)",
}

var _ctrl: AIMainPanelController = null
var _bridge: AIAgentLiveBridge = null
var _orch: AIPipelineOrchestrator = null

var _active_view: int = View.CHAT
var _title_label: Label = null
var _menu_popup: PopupMenu = null

# Sohbet görünümü
var _chat_view: Control = null
var _chat_log: RichTextLabel = null
var _input_edit: TextEdit = null
var _send_btn: Button = null
var _status_label: Label = null

# Ayarlar görünümü
var _settings_view: Control = null
var _key_edit: LineEdit = null
var _model_option: OptionButton = null

# Workspace görünümü
var _workspace_view: Control = null
var _workspace_panel: AIWorkspacePanel = null

var _running: bool = false


func _init() -> void:
	_ctrl = AIMainPanelController.new()


func _ready() -> void:
	_build_ui()
	_apply_view(View.CHAT)
	_redraw_chat()
	_refresh_status()


# ============================================================
# UI KURULUMU — programatik
# ============================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_build_header())

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 10)
	body.add_theme_constant_override("margin_right", 10)
	body.add_theme_constant_override("margin_bottom", 10)
	root.add_child(body)

	_chat_view = _build_chat_view()
	_settings_view = _build_settings_view()
	_workspace_view = _build_workspace_view()
	body.add_child(_chat_view)
	body.add_child(_settings_view)
	body.add_child(_workspace_view)


func _build_header() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)

	var menu_btn := MenuButton.new()
	menu_btn.text = "≡ Menü"
	menu_btn.flat = false
	_menu_popup = menu_btn.get_popup()
	_menu_popup.add_item("Sohbet", View.CHAT)
	_menu_popup.add_item("Ayarlar", View.SETTINGS)
	_menu_popup.add_item("Çalışma Alanı (9 Sekme)", View.WORKSPACE)
	_menu_popup.id_pressed.connect(_on_menu_selected)
	bar.add_child(menu_btn)

	_title_label = Label.new()
	_title_label.text = "AI Asistan — " + str(VIEW_TITLES[View.CHAT])
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title_label)

	return bar


func _build_chat_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	# Durum şeridi — Canlı/Anahtar/Model neden gönderilemiyor belli olsun.
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status_label)

	# Konuşma alanı — TÜM boş dikey alanı kaplar (en büyük bölge).
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.selection_enabled = true
	_chat_log.focus_mode = Control.FOCUS_NONE
	_chat_log.custom_minimum_size = Vector2(0, 240)
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_chat_log)

	# Giriş + Gönder — en ALTTA. Klavye açılınca OS bu bölgeyi yukarı iter.
	_input_edit = TextEdit.new()
	_input_edit.placeholder_text = (
		"Ne yapmamı istersin? (Ctrl+Enter ile gönder)"
	)
	_input_edit.custom_minimum_size = Vector2(0, 110)
	_input_edit.size_flags_vertical = Control.SIZE_SHRINK_END
	_input_edit.gui_input.connect(_on_input_gui)
	col.add_child(_input_edit)

	_send_btn = Button.new()
	_send_btn.text = "Gönder"
	_send_btn.custom_minimum_size = Vector2(0, 48)
	_send_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	_send_btn.pressed.connect(_on_send)
	col.add_child(_send_btn)

	return col


func _build_settings_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)

	var key_lbl := Label.new()
	key_lbl.text = "DeepSeek API Anahtarı:"
	col.add_child(key_lbl)

	var key_row := HBoxContainer.new()
	col.add_child(key_row)
	_key_edit = LineEdit.new()
	_key_edit.secret = true
	_key_edit.placeholder_text = "sk-..."
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(_key_edit)
	var key_btn := Button.new()
	key_btn.text = "Anahtarı Kaydet"
	key_btn.pressed.connect(_on_save_key)
	key_row.add_child(key_btn)

	var key_hint := Label.new()
	key_hint.text = (
		"Anahtarı kaydedince hazır olur — Gönder doğrudan çalışır."
	)
	key_hint.add_theme_font_size_override("font_size", 12)
	col.add_child(key_hint)

	var model_lbl := Label.new()
	model_lbl.text = "Yapay Zeka Modeli:"
	col.add_child(model_lbl)
	_model_option = OptionButton.new()
	for i in AIMainPanelController.ALLOWED_MODELS.size():
		_model_option.add_item(
			str(AIMainPanelController.ALLOWED_MODELS[i]), i
		)
	_model_option.item_selected.connect(_on_model_selected)
	col.add_child(_model_option)

	var sys_lbl := Label.new()
	sys_lbl.text = "Sistem İşlemleri:"
	col.add_child(sys_lbl)
	var reset_btn := Button.new()
	reset_btn.text = "Hafızayı ve Kuyruğu Sıfırla"
	reset_btn.pressed.connect(_on_reset)
	col.add_child(reset_btn)

	return col


func _build_workspace_view() -> Control:
	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workspace_panel = AIWorkspacePanel.new()
	_workspace_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(_workspace_panel)
	return holder


# ============================================================
# GÖRÜNÜM GEÇİŞİ
# ============================================================

func _on_menu_selected(id: int) -> void:
	_apply_view(id)


func _apply_view(view: int) -> void:
	_active_view = view
	if _title_label != null:
		_title_label.text = "AI Asistan — " + str(VIEW_TITLES.get(view, "?"))
	if _chat_view != null:
		_chat_view.visible = view == View.CHAT
	if _settings_view != null:
		_settings_view.visible = view == View.SETTINGS
	if _workspace_view != null:
		_workspace_view.visible = view == View.WORKSPACE
	if view == View.WORKSPACE and _workspace_panel != null:
		_workspace_panel.connect_feed(_ctrl.feed())
	if view == View.CHAT:
		_refresh_status()


## Aktif görünüm — test/dış erişim.
func active_view() -> int:
	return _active_view


# ============================================================
# SOHBET
# ============================================================

func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if (k.pressed and not k.echo
				and k.keycode == KEY_ENTER and k.ctrl_pressed):
			accept_event()
			_on_send()


func _on_send() -> void:
	if _running:
		return
	var task: String = _input_edit.text.strip_edges()
	if task.is_empty():
		return
	_ctrl.add_message("user", task)
	_input_edit.text = ""
	_redraw_chat()

	var gate: Dictionary = _ctrl.can_run_task(task)
	if not bool(gate["ok"]):
		_ctrl.add_message("system", "⚠ " + str(gate["reason"]))
		_redraw_chat()
		return

	var key_res: Dictionary = _ctrl.resolve_api_key()
	if not bool(key_res["ok"]):
		_ctrl.add_message(
			"system", "⚠ Anahtar çözülemedi: " + str(key_res["reason"])
		)
		_redraw_chat()
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
	_orch.pipeline_progress.connect(_on_progress)
	_orch.pipeline_completed.connect(_on_pipeline_done)

	_running = true
	_send_btn.disabled = true
	var intent: int = _ctrl.classify_intent(task)
	if intent == AIMainPanelController.Intent.CHAT:
		_ctrl.add_message("system", "… Asistan yanıtlıyor…")
		_redraw_chat()
		_orch.run_chat(task, _ctrl.model_name())
	else:
		_ctrl.add_message("system", "… Ajan düşünüyor (kod üretimi)…")
		_redraw_chat()
		_orch.run_task(
			"Sohbet görevi", _ctrl.default_target_path(task),
			task, AICellRoles.Role.CODE_ENGINEER, _ctrl.model_name()
		)


func _on_progress(step: String) -> void:
	_ctrl.add_message("system", "… " + step)
	_redraw_chat()


func _on_pipeline_done(result: Dictionary) -> void:
	_ctrl.record_result(result)
	var stage: String = str(result.get("stage", "?"))
	if stage == "chat":
		# Düz sohbet — ✓/✗ etiketi, aşama, dosya YOK; sadece yanıt.
		_ctrl.add_message("assistant", str(result.get("message", "")))
	else:
		var ok: bool = bool(result.get("ok", false))
		var prefix: String = "✓" if ok else "✗"
		var msg: String = "%s [%s] %s" % [
			prefix, stage, str(result.get("message", "")),
		]
		if result.has("path"):
			msg += "\nDosya: " + str(result["path"])
		_ctrl.add_message("assistant", msg)
	_running = false
	_send_btn.disabled = false
	_redraw_chat()
	_refresh_status()


func _redraw_chat() -> void:
	if _chat_log == null:
		return
	_chat_log.clear()
	for m in _ctrl.messages():
		var role: String = str(m["role"])
		var who: String = "Sen"
		var color: String = "#9CDCFE"
		if role == "assistant":
			who = "Asistan"
			color = "#4EC9B0"
		elif role == "system":
			who = "Sistem"
			color = "#C586C0"
		_chat_log.append_text(
			"[color=%s][b]%s:[/b][/color] %s\n" % [
				color, who, str(m["text"])
			]
		)


# ============================================================
# AYARLAR EYLEMLERİ
# ============================================================

func _on_save_key() -> void:
	var res: Dictionary = _ctrl.save_api_key(_key_edit.text)
	if bool(res["ok"]):
		_key_edit.text = ""
		_ctrl.add_message(
			"system", "✓ API anahtarı kaydedildi — hazırsın, Gönder çalışır"
		)
	else:
		_ctrl.add_message("system", "⚠ " + str(res["reason"]))
	_redraw_chat()
	_refresh_status()


## Durum şeridini günceller — neden gönderilebilir/gönderilemez belli.
func _refresh_status() -> void:
	if _status_label == null:
		return
	var s: Dictionary = _ctrl.summary()
	var has_key: bool = bool(s["has_key"])
	var head: String = (
		"● HAZIR" if has_key else "○ API anahtarı gerekli (≡ Menü → Ayarlar)"
	)
	_status_label.text = "%s  |  Anahtar: %s  |  Model: %s" % [
		head,
		("var" if has_key else "YOK"),
		str(s["model"]),
	]


func _on_model_selected(index: int) -> void:
	if index < 0 or index >= AIMainPanelController.ALLOWED_MODELS.size():
		return
	var model_id: String = str(
		AIMainPanelController.ALLOWED_MODELS[index]
	)
	if _ctrl.set_model(model_id):
		_ctrl.add_message("system", "✓ Model: " + model_id)
		_redraw_chat()
		_refresh_status()


func _on_reset() -> void:
	var res: Dictionary = _ctrl.reset_memory_and_queue()
	_ctrl.add_message("system", str(res["message"]))
	_redraw_chat()
	_refresh_status()


## Test/dış erişim — ekranın beyni.
func controller() -> AIMainPanelController:
	return _ctrl
