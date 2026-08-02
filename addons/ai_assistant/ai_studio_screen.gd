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
## Faz 7: sabit piksel varsayımları AIMobileLayoutPolicy profiline
## taşındı. 360 px portre, landscape ve editör yeniden boyutlandırması
## aynı canlı responsive yolu kullanır. Ana etkileşim hedefleri en az
## 48 mantıksal pikseldir.
##
## Tüm KARAR mantığı AIMainPanelController'da (sahnesiz test edilir).
## Bu Control ince görsel kabuk; kodla kurulur (.tscn YOK — proje
## disiplini). Gerçek çalıştırma kanıtlanmış AIPipelineOrchestrator
## (Aşama 4c) ile yapılır. Görseli kullanıcı telefonda doğrular.

enum View { CHAT, TASKS, SETTINGS, WORKSPACE }

const VIEW_TITLES: Dictionary = {
	View.CHAT: "Sohbet Ekranı",
	View.TASKS: "Görevler",
	View.SETTINGS: "Ayarlar",
	View.WORKSPACE: "Çalışma Alanı (9 Sekme)",
}

## Görev durumu → renk (panel).
const STATUS_COLORS: Dictionary = {
	"bekliyor": "#888888",
	"çalışıyor": "#DCDCAA",
	"onarılıyor": "#D7BA7D",
	"onay-bekliyor": "#C586C0",
	"tamam": "#4EC9B0",
	"başarısız": "#F44747",
}

var _ctrl: AIMainPanelController = null
var _bridge: AIAgentLiveBridge = null
var _orch: AIPipelineOrchestrator = null

var _active_view: int = View.CHAT
var _title_label: Label = null
var _menu_popup: PopupMenu = null

# Responsive kökler
var _root_layout: VBoxContainer = null
var _header_bar: HBoxContainer = null
var _menu_button: MenuButton = null
var _body_margin: MarginContainer = null
var _layout_profile: Dictionary = {}

# Sohbet görünümü
var _chat_view: Control = null
var _chat_log: RichTextLabel = null
var _input_edit: TextEdit = null
var _send_btn: Button = null
var _status_label: Label = null

# Ayarlar görünümü
var _settings_view: Control = null
var _settings_column: VBoxContainer = null
var _key_grid: GridContainer = null
var _key_edit: LineEdit = null
var _key_save_btn: Button = null
var _model_option: OptionButton = null
var _reset_btn: Button = null

# Görevler görünümü — canlı dinamik görev listesi
var _tasks_view: Control = null
var _tasks_log: RichTextLabel = null
var _last_tasks: Array = []

# Workspace görünümü
var _workspace_view: Control = null
var _workspace_panel: AIWorkspacePanel = null

var _running: bool = false


func _init() -> void:
	_ctrl = AIMainPanelController.new()


func _ready() -> void:
	_build_ui()
	if not resized.is_connected(_on_viewport_resized):
		resized.connect(_on_viewport_resized)
	_apply_responsive_layout()
	_apply_view(View.CHAT)
	_redraw_chat()
	_refresh_status()


# ============================================================
# UI KURULUMU — programatik
# ============================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_root_layout = VBoxContainer.new()
	_root_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layout.add_theme_constant_override("separation", 6)
	add_child(_root_layout)

	_root_layout.add_child(_build_header())

	_body_margin = MarginContainer.new()
	_body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_margin.add_theme_constant_override("margin_left", 10)
	_body_margin.add_theme_constant_override("margin_right", 10)
	_body_margin.add_theme_constant_override("margin_bottom", 10)
	_root_layout.add_child(_body_margin)

	_chat_view = _build_chat_view()
	_tasks_view = _build_tasks_view()
	_settings_view = _build_settings_view()
	_workspace_view = _build_workspace_view()
	_body_margin.add_child(_chat_view)
	_body_margin.add_child(_tasks_view)
	_body_margin.add_child(_settings_view)
	_body_margin.add_child(_workspace_view)


func _build_header() -> Control:
	_header_bar = HBoxContainer.new()
	_header_bar.add_theme_constant_override("separation", 10)

	_menu_button = MenuButton.new()
	_menu_button.text = "≡ Menü"
	_menu_button.flat = false
	_menu_popup = _menu_button.get_popup()
	_menu_popup.add_item("Sohbet", View.CHAT)
	_menu_popup.add_item("Görevler", View.TASKS)
	_menu_popup.add_item("Ayarlar", View.SETTINGS)
	_menu_popup.add_item("Çalışma Alanı (9 Sekme)", View.WORKSPACE)
	_menu_popup.id_pressed.connect(_on_menu_selected)
	_header_bar.add_child(_menu_button)

	_title_label = Label.new()
	_title_label.text = "AI Asistan — " + str(VIEW_TITLES[View.CHAT])
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_bar.add_child(_title_label)

	return _header_bar


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

	# Giriş + Gönder — en ALTTA. Klavye açılınca responsive profil bu
	# bölgenin minimum yüksekliğini landscape/portreye göre sınırlar.
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
	# Dar portrede ayarlar dikey uzayabilir; ScrollContainer tüm alanlara
	# klavye açıkken dahi erişimi korur.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_settings_column = VBoxContainer.new()
	_settings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_column.add_theme_constant_override("separation", 10)
	scroll.add_child(_settings_column)

	var key_lbl := Label.new()
	key_lbl.text = "DeepSeek API Anahtarı:"
	_settings_column.add_child(key_lbl)

	_key_grid = GridContainer.new()
	_key_grid.columns = 2
	_key_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_column.add_child(_key_grid)

	_key_edit = LineEdit.new()
	_key_edit.secret = true
	_key_edit.placeholder_text = "sk-..."
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_grid.add_child(_key_edit)

	_key_save_btn = Button.new()
	_key_save_btn.text = "Anahtarı Kaydet"
	_key_save_btn.pressed.connect(_on_save_key)
	_key_grid.add_child(_key_save_btn)

	var key_hint := Label.new()
	key_hint.text = (
		"Anahtarı kaydedince hazır olur — Gönder doğrudan çalışır."
	)
	key_hint.add_theme_font_size_override("font_size", 12)
	key_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_column.add_child(key_hint)

	var model_lbl := Label.new()
	model_lbl.text = "Yapay Zeka Modeli:"
	_settings_column.add_child(model_lbl)
	_model_option = OptionButton.new()
	_model_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in AIMainPanelController.ALLOWED_MODELS.size():
		_model_option.add_item(
			str(AIMainPanelController.ALLOWED_MODELS[i]), i
		)
	_model_option.item_selected.connect(_on_model_selected)
	_settings_column.add_child(_model_option)

	var sys_lbl := Label.new()
	sys_lbl.text = "Sistem İşlemleri:"
	_settings_column.add_child(sys_lbl)
	_reset_btn = Button.new()
	_reset_btn.text = "Hafızayı ve Kuyruğu Sıfırla"
	_reset_btn.pressed.connect(_on_reset)
	_settings_column.add_child(_reset_btn)

	return scroll


func _build_tasks_view() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = (
		"Çok-adımlı üretimde oluşan görevler ve canlı durumları. "
		+ "Hata olursa otomatik onarım görevi eklenir."
	)
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_tasks_log = RichTextLabel.new()
	_tasks_log.bbcode_enabled = true
	_tasks_log.scroll_following = true
	_tasks_log.selection_enabled = true
	_tasks_log.focus_mode = Control.FOCUS_NONE
	_tasks_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tasks_log)
	return col


## Canlı görev listesini çizer (orkestratör tasks_updated → bu).
func _render_tasks() -> void:
	if _tasks_log == null:
		return
	_tasks_log.clear()
	if _last_tasks.is_empty():
		_tasks_log.append_text(
			"[color=#888888]Henüz görev yok. Sohbette bir üretim "
			+ "isteği gönder (ör. 'envanter sistemi olan oyun yap').[/color]"
		)
		return
	for t in _last_tasks:
		var st: String = str(t.get("status", "bekliyor"))
		var color: String = str(STATUS_COLORS.get(st, "#CCCCCC"))
		var kind: String = (
			" (onarım)" if str(t.get("kind", "")) == "repair" else ""
		)
		_tasks_log.append_text(
			"[color=%s]●[/color] [b]#%d[/b] %s%s — [color=%s]%s[/color]\n" % [
				color, int(t.get("id", 0)), str(t.get("title", "")),
				kind, color, st,
			]
		)
		_tasks_log.append_text(
			"   [color=#9CDCFE]%s[/color]\n" % str(t.get("target_file", ""))
		)
		var err: String = str(t.get("error", ""))
		if not err.is_empty():
			_tasks_log.append_text(
				"   [color=#F44747]⚠ %s[/color]\n" % err
			)


func _on_tasks_updated(registry: Array) -> void:
	_last_tasks = registry
	_render_tasks()


func _build_workspace_view() -> Control:
	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workspace_panel = AIWorkspacePanel.new()
	_workspace_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_child(_workspace_panel)
	return holder


# ============================================================
# RESPONSIVE / ANDROID DÜZEN
# ============================================================

func _on_viewport_resized() -> void:
	_apply_responsive_layout()


func _current_viewport_size() -> Vector2i:
	var local_size := Vector2i(int(size.x), int(size.y))
	if local_size.x > 1 and local_size.y > 1:
		return local_size
	return DisplayServer.window_get_size()


func _apply_responsive_layout() -> void:
	if _root_layout == null:
		return
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		dpi = 160
	_layout_profile = AIMobileLayoutPolicy.profile(
		_current_viewport_size(), dpi
	)

	var margin: int = int(_layout_profile["margin"])
	var separation: int = int(_layout_profile["separation"])
	var touch: int = int(_layout_profile["touch_target"])
	var body_font: int = int(_layout_profile["body_font"])
	var compact: bool = bool(_layout_profile["compact"])

	_root_layout.add_theme_constant_override("separation", separation)
	_header_bar.add_theme_constant_override("separation", separation)
	_body_margin.add_theme_constant_override("margin_left", margin)
	_body_margin.add_theme_constant_override("margin_right", margin)
	_body_margin.add_theme_constant_override("margin_top", margin)
	_body_margin.add_theme_constant_override("margin_bottom", margin)

	_title_label.add_theme_font_size_override(
		"font_size", int(_layout_profile["header_font"])
	)
	_status_label.add_theme_font_size_override("font_size", body_font)
	_menu_button.custom_minimum_size = Vector2(88, touch)
	_send_btn.custom_minimum_size = Vector2(0, touch)
	_key_edit.custom_minimum_size = Vector2(0, touch)
	_key_save_btn.custom_minimum_size = Vector2(0, touch)
	_model_option.custom_minimum_size = Vector2(0, touch)
	_reset_btn.custom_minimum_size = Vector2(0, touch)

	_chat_log.custom_minimum_size = Vector2(
		0, int(_layout_profile["chat_min_height"])
	)
	_input_edit.custom_minimum_size = Vector2(
		0, int(_layout_profile["input_min_height"])
	)
	_key_grid.columns = int(_layout_profile["settings_columns"])
	_key_save_btn.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if compact else Control.SIZE_SHRINK_END
	)
	_settings_column.add_theme_constant_override("separation", separation)
	_update_title()


func _update_title() -> void:
	if _title_label == null:
		return
	var view_title: String = str(VIEW_TITLES.get(_active_view, "?"))
	var title_mode: String = str(_layout_profile.get("title_mode", "full"))
	_title_label.text = AIMobileLayoutPolicy.title_for(view_title, title_mode)
	_title_label.visible = not _title_label.text.is_empty()


## Son uygulanan saf layout profili — cihaz smoke/debug için.
func layout_profile() -> Dictionary:
	return _layout_profile.duplicate(true)


# ============================================================
# GÖRÜNÜM GEÇİŞİ
# ============================================================

func _on_menu_selected(id: int) -> void:
	_apply_view(id)


func _apply_view(view: int) -> void:
	_active_view = view
	_update_title()
	if _chat_view != null:
		_chat_view.visible = view == View.CHAT
	if _tasks_view != null:
		_tasks_view.visible = view == View.TASKS
	if _settings_view != null:
		_settings_view.visible = view == View.SETTINGS
	if _workspace_view != null:
		_workspace_view.visible = view == View.WORKSPACE
	if view == View.WORKSPACE and _workspace_panel != null:
		_workspace_panel.connect_feed(_ctrl.feed())
	if view == View.TASKS:
		_render_tasks()
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
	_orch.tasks_updated.connect(_on_tasks_updated)

	_running = true
	_send_btn.disabled = true
	var intent: int = _ctrl.classify_intent(task)
	var proj: String = _ctrl.project_context()
	# İnteraktif okuma: "res://...gd oku/aç" → gerçek içerik bağlama.
	proj += _ctrl.requested_file_context(task)
	if intent == AIMainPanelController.Intent.CHAT:
		_ctrl.add_message("system", "… Asistan yanıtlıyor…")
		_redraw_chat()
		_orch.run_chat(
			task, _ctrl.model_name(), _ctrl.conversation_history(), proj
		)
	else:
		_ctrl.add_message(
			"system", "… Plan çıkarılıyor (çok-adımlı üretim)…"
		)
		_redraw_chat()
		_orch.run_build_plan(task, task, _ctrl.model_name(), proj)


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
		if result.has("paths"):
			for p in result["paths"]:
				msg += "\nDosya: " + str(p)
		if result.has("failed_tasks"):
			for ft in result["failed_tasks"]:
				msg += "\n⚠ Başarısız: %s — %s" % [
					str(ft.get("title", "")), str(ft.get("reason", "")),
				]
		_ctrl.add_message("assistant", msg)
	_running = false
	_send_btn.disabled = false
	_redraw_chat()
	_refresh_status()
	# Üretilen dosyalar res://game/ altına yazıldı — editör dosya
	# sistemini tara ki Godot class_name'leri/sahneleri kaydetsin
	# (yalnız editör; orkestratör sahnesiz/test-edilebilir kalır).
	if stage != "chat" and Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.scan()


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
