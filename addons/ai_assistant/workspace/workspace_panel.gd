@tool
class_name AIWorkspacePanel
extends Control

## WorkspacePanel — workspace UI paneli (Layer 11).
##
## Sistemin GÖRÜNEN yüzü. 9 sekmeli Task Workspace. Bu sınıf bir
## Control node'u — sahneye eklenir, gözle görülür.
##
## ÖNEMLİ:
##   UI programatik kurulur (kodla, _build_ui'de) — .tscn elle
##   düzenlemek yerine. Mobilde bu daha güvenli ve DPI-aware ayar
##   kolay. Test panelinde DOĞRULANMAZ — UI gözle, telefonda görülür.
##
##   UI'ın ALTINDAKİ MANTIK ayrı RefCounted modellerde:
##   AIWorkspaceState, AIKanbanModel, AILiveFeedModel, AIIterationModel.
##   O modeller test edilir; bu panel onları çizer.
##
## Bu sürüm çekirdek 3 sekmeyi (Kanban, Live Feed, Iteration) +
## sekme altyapısını kurar. Kalan 6 sekme sonraki UI oturumuna.

## Mantık modelleri — UI bunları okuyup çizer.
var state: AIWorkspaceState
var kanban: AIKanbanModel
var live_feed: AILiveFeedModel
var iteration: AIIterationModel

## UI kök düğümleri.
var _tab_bar: TabBar = null
var _content_area: VBoxContainer = null

## Hesaplanan UI ölçeği (DPI-aware).
var _ui_scale: float = 1.0


func _init() -> void:
	state = AIWorkspaceState.new()
	kanban = AIKanbanModel.new()
	live_feed = AILiveFeedModel.new()
	iteration = AIIterationModel.new()


func _ready() -> void:
	# Ekran boyutuna göre DPI-aware ölçek
	var screen_size: Vector2i = DisplayServer.window_get_size()
	var dpi: int = DisplayServer.screen_get_dpi()
	_ui_scale = state.compute_ui_scale(screen_size.x, dpi)
	_build_ui()
	_refresh_active_tab()


# ============================================================
# UI KURULUMU — programatik
# ============================================================

## Tüm UI'ı kodla kurar — sekme çubuğu + içerik alanı.
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# --- Sekme çubuğu ---
	_tab_bar = TabBar.new()
	for tab_info in state.all_tabs():
		_tab_bar.add_tab(tab_info["name"])
	_tab_bar.tab_changed.connect(_on_tab_changed)
	# Dar ekranda sekmeler kayar
	var screen_w: int = DisplayServer.window_get_size().x
	if state.tabs_need_scroll(screen_w):
		_tab_bar.scrolling_enabled = true
	root.add_child(_tab_bar)

	# --- İçerik alanı ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_content_area = VBoxContainer.new()
	_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content_area)


## Aktif sekme değişince çağrılır.
func _on_tab_changed(tab_index: int) -> void:
	state.switch_tab(tab_index)
	_refresh_active_tab()


## Aktif sekmenin içeriğini yeniden çizer.
func _refresh_active_tab() -> void:
	if _content_area == null:
		return
	# Eski içeriği temizle
	for child in _content_area.get_children():
		child.queue_free()

	# Aktif sekmeye göre içerik
	match state.active_tab:
		AIWorkspaceState.Tab.KANBAN:
			_render_kanban()
		AIWorkspaceState.Tab.LIVE_FEED:
			_render_live_feed()
		AIWorkspaceState.Tab.ITERATION:
			_render_iteration()
		_:
			_render_placeholder()


# ============================================================
# SEKME ÇİZİMLERİ
# ============================================================

## Kanban sekmesi — kolonlar + kart sayıları.
func _render_kanban() -> void:
	var header := Label.new()
	header.text = "Kanban Panosu"
	_content_area.add_child(header)

	var counts: Dictionary = kanban.column_counts()
	for column in AIKanbanModel.COLUMN_NAMES:
		var row := Label.new()
		row.text = "%s: %d kart" % [
			AIKanbanModel.column_name(column), counts.get(column, 0)
		]
		_content_area.add_child(row)

	var progress := Label.new()
	progress.text = "Tamamlanma: %d%%" % int(kanban.completion_ratio() * 100.0)
	_content_area.add_child(progress)


## Live Feed sekmesi — son olaylar.
func _render_live_feed() -> void:
	var header := Label.new()
	header.text = "Canlı Akış (%d olay)" % live_feed.visible_count()
	_content_area.add_child(header)

	for event in live_feed.recent_visible(30):
		var row := Label.new()
		row.text = (event as AIFeedEvent).format_line()
		_content_area.add_child(row)


## Iteration sekmesi — faz + ilerleme.
func _render_iteration() -> void:
	var header := Label.new()
	header.text = "Iteration #%d — %s" % [
		iteration.iteration_number, iteration.phase_name()
	]
	_content_area.add_child(header)

	var goal := Label.new()
	goal.text = "Hedef: " + iteration.goal
	_content_area.add_child(goal)

	var prog := Label.new()
	prog.text = "İlerleme: %d/%d task (%d%%)" % [
		iteration.completed_count(), iteration.task_count(),
		int(iteration.progress() * 100.0),
	]
	_content_area.add_child(prog)


## Henüz uygulanmamış sekmeler için yer tutucu.
func _render_placeholder() -> void:
	var label := Label.new()
	label.text = "'%s' sekmesi sonraki UI oturumunda gelecek." % (
		state.active_tab_name()
	)
	_content_area.add_child(label)


# ============================================================
# BAĞLAMA — sistem verisine
# ============================================================

## Live Feed modelini bir AIFeedEmitter'a bağlar — canlı olaylar aksın.
func connect_feed(emitter: AIFeedEmitter) -> void:
	live_feed.attach_to(emitter)
	if state.active_tab == AIWorkspaceState.Tab.LIVE_FEED:
		_refresh_active_tab()


## Hesaplanan UI ölçeğini döndürür.
func ui_scale() -> float:
	return _ui_scale
