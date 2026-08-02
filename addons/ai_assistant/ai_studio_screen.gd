@tool
class_name AIStudioScreen
extends Control

## Faz 13 — tek ekranlı mobil çalışma yüzeyi.
## Sohbet, görev ataması, paralel ajan akışı, doğrulama ve oluşturulan
## artefaktlar aynı zaman çizelgesinde görünür. Ayrı Görevler/Workspace
## sayfaları yoktur; ayarlar yalnız küçük açılır paneldir.

## Eski dış çağrıları kırmamak için enum korunur. CHAT/TASKS/WORKSPACE
## artık aynı birleşik zaman çizelgesine yönlenir; SETTINGS paneli açar.
enum View { CHAT, TASKS, SETTINGS, WORKSPACE }

## Eski görev-durum tüketicileri ve contract testleri için public sözleşme.
## Menü mimarisi geri getirilmez; birleşik zaman çizelgesi aynı renkleri
## durum mesajlarında kullanabilir.
const STATUS_COLORS: Dictionary = {
	"bekliyor": "#888888",
	"çalışıyor": "#DCDCAA",
	"onarılıyor": "#D7BA7D",
	"onay-bekliyor": "#C586C0",
	"tamam": "#4EC9B0",
	"başarısız": "#F44747",
}

const MAX_VISIBLE_AGENT_EVENTS: int = 180
const MAX_AGENT_RESULT_CHARS: int = 900

var _ctrl: AIMainPanelController = null
var _bridge: AIAgentLiveBridge = null
var _orch: AIPipelineOrchestrator = null

var _active_view: int = View.CHAT
var _layout_profile: Dictionary = {}
var _running: bool = false
var _settings_open: bool = false
var _live_event_count: int = 0
var _event_limit_reported: bool = false
var _active_agents: Dictionary = {}
var _task_states: Dictionary = {}
var _verified_paths: Dictionary = {}
var _opened_scene_path: String = ""

var _root_layout: VBoxContainer = null
var _header_bar: HBoxContainer = null
var _title_label: Label = null
var _active_agents_label: Label = null
var _settings_toggle: Button = null
var _status_label: Label = null
var _settings_panel: VBoxContainer = null
var _key_grid: GridContainer = null
var _key_edit: LineEdit = null
var _key_save_btn: Button = null
var _model_picker: OptionButton = null
var _model_detail_label: Label = null
var _reset_btn: Button = null
var _chat_log: RichTextLabel = null
var _input_edit: TextEdit = null
var _send_btn: Button = null


func _init() -> void:
	_ctrl = AIMainPanelController.new()


func _ready() -> void:
	_build_ui()
	if not resized.is_connected(_on_viewport_resized):
		resized.connect(_on_viewport_resized)
	_apply_responsive_layout()
	_redraw_chat()
	_refresh_status()
	_update_active_agents_label()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layout = VBoxContainer.new()
	_root_layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_layout.add_theme_constant_override("separation", 6)
	add_child(_root_layout)

	_root_layout.add_child(_build_header())

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_root_layout.add_child(_status_label)

	_settings_panel = _build_settings_panel()
	_settings_panel.visible = false
	_root_layout.add_child(_settings_panel)

	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = false
	_chat_log.scroll_following = true
	_chat_log.selection_enabled = true
	_chat_log.focus_mode = Control.FOCUS_NONE
	_chat_log.custom_minimum_size = Vector2(0, 240)
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_layout.add_child(_chat_log)

	_input_edit = TextEdit.new()
	_input_edit.placeholder_text = "Ne yapmamı istersin? (Ctrl+Enter ile gönder)"
	_input_edit.custom_minimum_size = Vector2(0, 100)
	_input_edit.size_flags_vertical = Control.SIZE_SHRINK_END
	_input_edit.gui_input.connect(_on_input_gui)
	_root_layout.add_child(_input_edit)

	_send_btn = Button.new()
	_send_btn.text = "Gönder"
	_send_btn.custom_minimum_size = Vector2(0, 48)
	_send_btn.pressed.connect(_on_send)
	_root_layout.add_child(_send_btn)


func _build_header() -> Control:
	_header_bar = HBoxContainer.new()
	_header_bar.add_theme_constant_override("separation", 8)

	_title_label = Label.new()
	_title_label.text = "AI Asistan"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_bar.add_child(_title_label)

	_active_agents_label = Label.new()
	_active_agents_label.text = "0 ajan"
	_active_agents_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_active_agents_label.add_theme_font_size_override("font_size", 12)
	_header_bar.add_child(_active_agents_label)

	_settings_toggle = Button.new()
	_settings_toggle.text = "⚙ Ayarlar"
	_settings_toggle.toggle_mode = true
	_settings_toggle.toggled.connect(_on_settings_toggled)
	_header_bar.add_child(_settings_toggle)
	return _header_bar


func _build_settings_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)

	var key_label := Label.new()
	key_label.text = "DeepSeek API anahtarı"
	panel.add_child(key_label)

	_key_grid = GridContainer.new()
	_key_grid.columns = 2
	_key_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_key_grid)

	_key_edit = LineEdit.new()
	_key_edit.secret = true
	_key_edit.placeholder_text = "sk-..."
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_grid.add_child(_key_edit)

	_key_save_btn = Button.new()
	_key_save_btn.text = "Kaydet"
	_key_save_btn.pressed.connect(_on_save_key)
	_key_grid.add_child(_key_save_btn)

	var model_label := Label.new()
	model_label.text = "Model ve çalışma profili"
	model_label.add_theme_font_size_override("font_size", 13)
	panel.add_child(model_label)

	_model_picker = OptionButton.new()
	_model_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in _ctrl.model_options():
		var item_index: int = _model_picker.item_count
		_model_picker.add_item(str(option.get("label", option.get("id", "Model"))))
		_model_picker.set_item_metadata(item_index, str(option.get("id", "")))
	_model_picker.item_selected.connect(_on_model_selected)
	panel.add_child(_model_picker)
	_sync_model_picker()

	_model_detail_label = Label.new()
	_model_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_model_detail_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(_model_detail_label)
	_update_model_detail()

	_reset_btn = Button.new()
	_reset_btn.text = "Çalışma hafızasını ve kuyruğu sıfırla"
	_reset_btn.pressed.connect(_on_reset)
	panel.add_child(_reset_btn)
	return panel


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
	_layout_profile = AIMobileLayoutPolicy.profile(_current_viewport_size(), dpi)
	var margin: int = int(_layout_profile.get("margin", 6))
	var separation: int = int(_layout_profile.get("separation", 6))
	var touch: int = int(_layout_profile.get("touch_target", 48))
	var body_font: int = int(_layout_profile.get("body_font", 13))
	var compact: bool = bool(_layout_profile.get("compact", false))

	_root_layout.offset_left = float(margin)
	_root_layout.offset_right = float(-margin)
	_root_layout.offset_top = float(margin)
	_root_layout.offset_bottom = float(-margin)
	_root_layout.add_theme_constant_override("separation", separation)
	_header_bar.add_theme_constant_override("separation", separation)
	_title_label.add_theme_font_size_override(
		"font_size", int(_layout_profile.get("header_font", 18))
	)
	_status_label.add_theme_font_size_override("font_size", body_font)
	_settings_toggle.custom_minimum_size = Vector2(92, touch)
	_key_edit.custom_minimum_size = Vector2(0, touch)
	_key_save_btn.custom_minimum_size = Vector2(0, touch)
	_model_picker.custom_minimum_size = Vector2(0, touch)
	_reset_btn.custom_minimum_size = Vector2(0, touch)
	_send_btn.custom_minimum_size = Vector2(0, touch)
	_chat_log.custom_minimum_size = Vector2(
		0, int(_layout_profile.get("chat_min_height", 220))
	)
	_input_edit.custom_minimum_size = Vector2(
		0, int(_layout_profile.get("input_min_height", 88))
	)
	_key_grid.columns = 1 if compact else 2
	_active_agents_label.visible = str(
		_layout_profile.get("title_mode", "full")
	) != "hidden"


func layout_profile() -> Dictionary:
	return _layout_profile.duplicate(true)


## Eski view API'si tek ekrana uyarlanır.
func _on_menu_selected(id: int) -> void:
	_apply_view(id)


func _apply_view(view: int) -> void:
	_active_view = view
	var open_settings: bool = view == View.SETTINGS
	_settings_open = open_settings
	if _settings_toggle != null:
		_settings_toggle.set_pressed_no_signal(open_settings)
	if _settings_panel != null:
		_settings_panel.visible = open_settings
	if view != View.SETTINGS:
		_active_view = View.CHAT


func active_view() -> int:
	return _active_view


func _on_settings_toggled(enabled: bool) -> void:
	_settings_open = enabled
	_active_view = View.SETTINGS if enabled else View.CHAT
	_settings_panel.visible = enabled


func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if (key_event.pressed and not key_event.echo
				and key_event.keycode == KEY_ENTER and key_event.ctrl_pressed):
			accept_event()
			_on_send()


func _on_send() -> void:
	if _running:
		return
	var task: String = _input_edit.text.strip_edges()
	if task.is_empty():
		return
	_append_message("user", task)
	_input_edit.text = ""

	var gate: Dictionary = _ctrl.can_run_task(task)
	if not bool(gate.get("ok", false)):
		_append_message("system", "⚠ " + str(gate.get("reason", "Görev çalıştırılamadı")))
		return
	var key_result: Dictionary = _ctrl.resolve_api_key()
	if not bool(key_result.get("ok", false)):
		_append_message(
			"system",
			"⚠ Anahtar çözülemedi: " + str(key_result.get("reason", "?"))
		)
		return

	_dispose_runtime()
	_reset_live_run_state()
	var router := AIProviderRouter.new()
	router.set_api_key(
		AIProviderRequest.Provider.DEEPSEEK,
		str(key_result.get("key", ""))
	)
	_bridge = AIAgentLiveBridge.new()
	_bridge.name = "MainLiveBridge"
	add_child(_bridge)
	_bridge.attach_router(router)
	_orch = AIPipelineOrchestrator.new()
	_orch.name = "LivePipeline"
	add_child(_orch)
	_orch.attach_bridge(_bridge)
	_orch.pipeline_progress.connect(_on_progress)
	_orch.pipeline_completed.connect(_on_pipeline_done)
	_orch.tasks_updated.connect(_on_tasks_updated)

	_running = true
	_send_btn.disabled = true
	_refresh_status()
	var intent: int = _ctrl.classify_intent(task)
	var project_context: String = _ctrl.project_context()
	project_context += _ctrl.requested_file_context(task)
	if intent == AIMainPanelController.Intent.CHAT:
		_append_message("system", "Asistan yanıt hazırlıyor…")
		_orch.run_chat(
			task,
			_ctrl.model_name(),
			_ctrl.conversation_history(),
			project_context
		)
	else:
		_append_message("system", "Plan ve bağımlılık grafiği hazırlanıyor…")
		var started: bool = _orch.run_build_plan(
			task, task, _ctrl.model_name(), project_context
		)
		_attach_chain_events()
		if not started:
			_append_message("system", "⚠ Üretim hattı başlatılamadı")


func _attach_chain_events() -> void:
	if _orch == null:
		return
	var candidate: Variant = _orch.get("_chain")
	if candidate is AIAdaptiveRoleGraphRunner:
		var runner := candidate as AIAdaptiveRoleGraphRunner
		if not runner.agent_event.is_connected(_on_agent_event):
			runner.agent_event.connect(_on_agent_event)


func _on_progress(step: String) -> void:
	# Katman/ajan satırları yapılandırılmış agent_event ile gelir.
	if step.begins_with("[Katman") or step.begins_with("["):
		return
	_append_message("system", step)


func _on_agent_event(event: Dictionary) -> void:
	var validation: Dictionary = AILiveAgentEvent.validate(event)
	if not bool(validation.get("ok", false)):
		return
	var event_type: String = str(event.get("type", ""))
	var node_id: String = str(event.get("node_id", ""))
	if event_type == AILiveAgentEvent.TYPE_STARTED:
		_active_agents[node_id] = event.duplicate(true)
	elif event_type == AILiveAgentEvent.TYPE_COMPLETED \
			or event_type == AILiveAgentEvent.TYPE_FAILED:
		_active_agents.erase(node_id)
	elif event_type == AILiveAgentEvent.TYPE_PROGRESS and _active_agents.has(node_id):
		_active_agents[node_id] = event.duplicate(true)
	_update_active_agents_label()

	if _live_event_count >= MAX_VISIBLE_AGENT_EVENTS:
		if not _event_limit_reported:
			_event_limit_reported = true
			_append_message(
				"system",
				"Canlı ajan akışı mobil performans için sınırlandı; görev çalışmaya devam ediyor."
			)
		return
	_live_event_count += 1

	var role_name: String = str(event.get("role_name", "Ajan"))
	var title: String = str(event.get("title", "Çalışma"))
	var layer: int = int(event.get("layer", 0))
	var confidence: float = float(event.get("confidence", 0.0))
	var text: String = str(event.get("text", ""))
	var headline: String = "Katman %d · %s" % [layer, title]
	match event_type:
		AILiveAgentEvent.TYPE_STARTED:
			text = headline + "\nBaşladı"
		AILiveAgentEvent.TYPE_PROGRESS:
			text = headline + "\n" + text
		AILiveAgentEvent.TYPE_COMPLETED:
			text = "%s · Güven %d%%\n%s" % [
				headline,
				int(round(confidence * 100.0)),
				text.left(MAX_AGENT_RESULT_CHARS),
			]
		AILiveAgentEvent.TYPE_FAILED:
			text = headline + "\nBaşarısız: " + text
	_append_message("agent::%s::%s" % [role_name, event_type], text)


func _on_tasks_updated(registry: Array) -> void:
	for task in registry:
		var task_id: int = int(task.get("id", 0))
		var state: String = str(task.get("status", "bekliyor"))
		var previous: String = str(_task_states.get(task_id, ""))
		if previous.is_empty():
			_append_message(
				"task",
				"#%d %s\nAjan: %s\nHedef: %s" % [
					task_id,
					str(task.get("title", "Görev")),
					str(task.get("primary_role_title", "atanıyor")),
					str(task.get("target_file", "")),
				]
			)
		elif previous != state:
			var update: String = "#%d %s → %s" % [
				task_id, str(task.get("title", "Görev")), state,
			]
			var error: String = str(task.get("error", "")).strip_edges()
			if not error.is_empty():
				update += "\n" + error
			_append_message("task", update)
		_task_states[task_id] = state
		if state == "tamam":
			_verify_and_report_artifact(str(task.get("target_file", "")))


func _verify_and_report_artifact(path: String) -> void:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty() or _verified_paths.has(clean_path):
		return
	_verified_paths[clean_path] = true
	var evidence: Dictionary = AIArtifactCommitVerifier.verify(clean_path, "", true)
	if bool(evidence.get("ok", false)):
		_append_message(
			"artifact",
			"✓ Gerçek Godot artefaktı doğrulandı\n%s\nTür: %s · %d bayt\nSHA-256: %s" % [
				clean_path,
				str(evidence.get("resource_type", "text")),
				int(evidence.get("bytes", 0)),
				str(evidence.get("sha256", "")).left(16) + "…",
			]
		)
		if clean_path.ends_with(".tscn") and _opened_scene_path.is_empty():
			_opened_scene_path = clean_path
			call_deferred("_open_generated_scene", clean_path)
	else:
		_append_message(
			"artifact",
			"✗ Artefakt Godot tarafından yüklenemedi\n%s\n%s" % [
				clean_path, str(evidence.get("reason", "Bilinmeyen hata")),
			]
		)


func _open_generated_scene(path: String) -> void:
	if not Engine.is_editor_hint():
		return
	EditorInterface.open_scene_from_path(path)
	_append_message("system", "Sahne editörde açıldı: " + path)


func _on_pipeline_done(result: Dictionary) -> void:
	_ctrl.record_result(result)
	var stage: String = str(result.get("stage", "?"))
	if stage == "chat":
		_append_message("assistant", str(result.get("message", "")))
	else:
		var ok: bool = bool(result.get("ok", false))
		var message: String = ("✓ " if ok else "✗ ") + str(
			result.get("message", "Üretim tamamlandı")
		)
		for path in result.get("paths", []):
			message += "\n" + str(path)
		for failed in result.get("failed_tasks", []):
			message += "\n⚠ %s — %s" % [
				str(failed.get("title", "Görev")),
				str(failed.get("reason", "Başarısız")),
			]
		_append_message("assistant", message)
	_running = false
	_active_agents.clear()
	_update_active_agents_label()
	_send_btn.disabled = false
	_refresh_status()
	if stage != "chat" and Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		if filesystem != null and not filesystem.is_scanning():
			filesystem.scan()


func _append_message(role: String, text: String) -> void:
	_ctrl.add_message(role, text)
	_redraw_chat()


func _redraw_chat() -> void:
	if _chat_log == null:
		return
	_chat_log.clear()
	for message in _ctrl.messages():
		_draw_message(
			str(message.get("role", "system")),
			str(message.get("text", ""))
		)


func _draw_message(role: String, text: String) -> void:
	var title: String = "Sistem"
	var color := Color(0.77, 0.53, 0.84)
	if role == "user":
		title = "Sen"
		color = Color(0.49, 0.77, 0.93)
	elif role == "assistant":
		title = "AI Asistan"
		color = Color(0.31, 0.79, 0.69)
	elif role == "task":
		title = "Görev"
		color = Color(0.86, 0.73, 0.47)
	elif role == "artifact":
		title = "Artefakt Doğrulama"
		color = Color(0.39, 0.82, 0.47)
	elif role.begins_with("agent::"):
		var parts: PackedStringArray = role.split("::")
		title = parts[1] if parts.size() > 1 else "Ajan"
		var event_type: String = parts[2] if parts.size() > 2 else "progress"
		color = (
			Color(0.93, 0.42, 0.42)
			if event_type == AILiveAgentEvent.TYPE_FAILED
			else Color(0.40, 0.67, 0.95)
		)
	_chat_log.push_color(color)
	_chat_log.push_bold()
	_chat_log.add_text(title + ":")
	_chat_log.pop()
	_chat_log.pop()
	_chat_log.add_text(" " + text + "\n\n")


func _update_active_agents_label() -> void:
	if _active_agents_label == null:
		return
	var count: int = _active_agents.size()
	_active_agents_label.text = (
		"%d ajan çalışıyor" % count if count > 0 else "Hazır"
	)


func _reset_live_run_state() -> void:
	_live_event_count = 0
	_event_limit_reported = false
	_active_agents.clear()
	_task_states.clear()
	_verified_paths.clear()
	_opened_scene_path = ""
	_update_active_agents_label()


func _dispose_runtime() -> void:
	if is_instance_valid(_orch):
		_orch.queue_free()
	if is_instance_valid(_bridge):
		_bridge.queue_free()
	_orch = null
	_bridge = null


func _on_save_key() -> void:
	var result: Dictionary = _ctrl.save_api_key(_key_edit.text)
	if bool(result.get("ok", false)):
		_key_edit.text = ""
		_append_message("system", "✓ API anahtarı güvenli biçimde kaydedildi")
		_settings_toggle.set_pressed_no_signal(false)
		_settings_open = false
		_active_view = View.CHAT
		_settings_panel.visible = false
	else:
		_append_message("system", "⚠ " + str(result.get("reason", "Kaydedilemedi")))
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var summary: Dictionary = _ctrl.summary()
	var has_key: bool = bool(summary.get("has_key", false))
	var model_label: String = str(
		summary.get("model_label", _ctrl.model_display_name())
	)
	var state: String = (
		"ÇALIŞIYOR"
		if _running
		else ("HAZIR" if has_key else "API ANAHTARI GEREKLİ")
	)
	_status_label.text = "● %s  ·  Model: %s  ·  %s" % [
		state,
		model_label,
		("anahtar var" if has_key else "⚙ Ayarlar'dan anahtar gir"),
	]
	_sync_model_picker()
	_update_model_detail()


func _sync_model_picker() -> void:
	if _model_picker == null:
		return
	var selected_model: String = _ctrl.model_name()
	for index in _model_picker.item_count:
		if str(_model_picker.get_item_metadata(index)) == selected_model:
			_model_picker.select(index)
			return


func _update_model_detail() -> void:
	if _model_detail_label == null:
		return
	_model_detail_label.text = (
		"Kimlik: %s · Profil: MAX · Düşünme: maksimum" % _ctrl.model_name()
	)


func _on_model_selected(index: int) -> void:
	if _model_picker == null or index < 0 or index >= _model_picker.item_count:
		return
	var model_id: String = str(_model_picker.get_item_metadata(index))
	if not _ctrl.set_model(model_id):
		_append_message("system", "⚠ Model seçimi reddedildi: " + model_id)
		_sync_model_picker()
		return
	_update_model_detail()
	_append_message("system", "✓ Model seçildi: " + _ctrl.model_display_name())
	_refresh_status()


func _on_reset() -> void:
	var result: Dictionary = _ctrl.reset_memory_and_queue()
	_append_message("system", str(result.get("message", "Sıfırlandı")))
	_refresh_status()


func controller() -> AIMainPanelController:
	return _ctrl
