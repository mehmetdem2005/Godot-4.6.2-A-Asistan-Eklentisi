@tool
class_name AIWorkspaceTest
extends RefCounted

## Phase 11 / Layer 11 — Workspace UI Self-Test
##
## Sıkı testler: WorkspaceState (sekme + DPI), KanbanModel (kolon akışı),
## LiveFeedModel (filtreleme), IterationModel (faz akışı).
##
## NOT: AIWorkspacePanel bir Control node — görsel UI, test panelinde
## doğrulanmaz, gözle/telefonda görülür. Burada UI'ın ALTINDAKI
## test edilebilir 4 model sınanır.


static func run_all() -> Array:
	var results: Array = []

	# WorkspaceState
	results.append(_b("Workspace: State", _test_state_switch()))
	results.append(_b("Workspace: State", _test_state_back()))
	results.append(_b("Workspace: State", _test_state_all_tabs()))
	results.append(_b("Workspace: State", _test_state_dpi_scale()))
	results.append(_b("Workspace: State", _test_state_narrow_screen()))

	# KanbanModel
	results.append(_b("Workspace: Kanban", _test_kanban_add()))
	results.append(_b("Workspace: Kanban", _test_kanban_valid_move()))
	results.append(_b("Workspace: Kanban", _test_kanban_invalid_move()))
	results.append(_b("Workspace: Kanban", _test_kanban_full_flow()))
	results.append(_b("Workspace: Kanban", _test_kanban_priority_sort()))
	results.append(_b("Workspace: Kanban", _test_kanban_completion()))

	# LiveFeedModel
	results.append(_b("Workspace: Feed", _test_feed_collect()))
	results.append(_b("Workspace: Feed", _test_feed_severity_filter()))
	results.append(_b("Workspace: Feed", _test_feed_category_filter()))
	results.append(_b("Workspace: Feed", _test_feed_error_count()))
	results.append(_b("Workspace: Feed", _test_feed_attach_emitter()))

	# IterationModel
	results.append(_b("Workspace: Iter", _test_iter_phase_advance()))
	results.append(_b("Workspace: Iter", _test_iter_blocked_advance()))
	results.append(_b("Workspace: Iter", _test_iter_progress()))
	results.append(_b("Workspace: Iter", _test_iter_close()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# WORKSPACE STATE
# ============================================================

static func _test_state_switch() -> Dictionary:
	var name := "State sekme geçişi"
	var s := AIWorkspaceState.new()
	s.switch_tab(AIWorkspaceState.Tab.KANBAN)
	if s.active_tab != AIWorkspaceState.Tab.KANBAN:
		return _fail(name, "sekme değişmedi")
	return _ok(name)


static func _test_state_back() -> Dictionary:
	var name := "State geri navigasyon"
	var s := AIWorkspaceState.new()
	s.switch_tab(AIWorkspaceState.Tab.KANBAN)
	s.switch_tab(AIWorkspaceState.Tab.LIVE_FEED)
	s.go_back()
	if s.active_tab != AIWorkspaceState.Tab.KANBAN:
		return _fail(name, "geri navigasyon yanlış sekmeye gitti")
	# Geçmiş boşken go_back
	var empty := AIWorkspaceState.new()
	if empty.go_back():
		return _fail(name, "boş geçmişte go_back true dönmemeli")
	return _ok(name)


static func _test_state_all_tabs() -> Dictionary:
	var name := "State 9 sekme tanımlı"
	var s := AIWorkspaceState.new()
	if s.all_tabs().size() != 9:
		return _fail(name, "9 sekme bekleniyordu")
	return _ok(name)


static func _test_state_dpi_scale() -> Dictionary:
	var name := "State DPI-aware ölçek"
	var s := AIWorkspaceState.new()
	# Yüksek DPI daha büyük ölçek vermeli
	var low: float = s.compute_ui_scale(1080, 160)
	var high: float = s.compute_ui_scale(1080, 480)
	if high <= low:
		return _fail(name, "yüksek DPI daha büyük ölçek vermeli")
	# Üst sınır 3.0 aşılmamalı
	if s.compute_ui_scale(2000, 960) > 3.0:
		return _fail(name, "ölçek üst sınırı 3.0 aşıldı")
	return _ok(name)


static func _test_state_narrow_screen() -> Dictionary:
	var name := "State dar ekran küçültme"
	var s := AIWorkspaceState.new()
	# Dar ekran, normalden küçük ölçek vermeli (aynı DPI'da)
	var narrow: float = s.compute_ui_scale(600, 160)
	var normal: float = s.compute_ui_scale(1080, 160)
	if narrow >= normal:
		return _fail(name, "dar ekran daha küçük ölçek vermeli")
	return _ok(name)


# ============================================================
# KANBAN MODEL
# ============================================================

static func _test_kanban_add() -> Dictionary:
	var name := "Kanban kart ekleme"
	var k := AIKanbanModel.new()
	k.add_card("t1", "Task 1")
	if k.card_count() != 1:
		return _fail(name, "kart eklenmedi")
	var card: AIKanbanModel.Card = k.get_card("t1")
	if card == null or card.column != AIKanbanModel.Column.BACKLOG:
		return _fail(name, "yeni kart BACKLOG'da olmalı")
	return _ok(name)


static func _test_kanban_valid_move() -> Dictionary:
	var name := "Kanban geçerli taşıma"
	var k := AIKanbanModel.new()
	k.add_card("t1", "Task 1")
	var result: Dictionary = k.move_card("t1", AIKanbanModel.Column.READY)
	if not result["ok"]:
		return _fail(name, "BACKLOG->READY geçerli olmalı")
	return _ok(name)


static func _test_kanban_invalid_move() -> Dictionary:
	var name := "Kanban geçersiz taşıma reddi"
	var k := AIKanbanModel.new()
	k.add_card("t1", "Task 1")
	# BACKLOG'dan doğrudan DONE'a — geçersiz akış
	var result: Dictionary = k.move_card("t1", AIKanbanModel.Column.DONE)
	if result["ok"]:
		return _fail(name, "BACKLOG->DONE doğrudan geçiş reddedilmeliydi")
	return _ok(name)


static func _test_kanban_full_flow() -> Dictionary:
	var name := "Kanban tam akış"
	var k := AIKanbanModel.new()
	k.add_card("t1", "Task 1")
	k.move_card("t1", AIKanbanModel.Column.READY)
	k.move_card("t1", AIKanbanModel.Column.IN_PROGRESS)
	k.move_card("t1", AIKanbanModel.Column.VERIFY)
	var result: Dictionary = k.move_card("t1", AIKanbanModel.Column.DONE)
	if not result["ok"]:
		return _fail(name, "tam akış DONE'a ulaşmalı")
	var card: AIKanbanModel.Card = k.get_card("t1")
	if card.column != AIKanbanModel.Column.DONE:
		return _fail(name, "kart DONE'da olmalı")
	return _ok(name)


static func _test_kanban_priority_sort() -> Dictionary:
	var name := "Kanban öncelik sıralaması"
	var k := AIKanbanModel.new()
	var low: AIKanbanModel.Card = k.add_card("low", "Düşük")
	low.priority = 1
	var high: AIKanbanModel.Card = k.add_card("high", "Yüksek")
	high.priority = 9
	var col: Array = k.cards_in_column(AIKanbanModel.Column.BACKLOG)
	if col.size() != 2:
		return _fail(name, "2 kart bekleniyordu")
	# Yüksek öncelik başta
	if (col[0] as AIKanbanModel.Card).task_id != "high":
		return _fail(name, "yüksek öncelik kart başta olmalı")
	return _ok(name)


static func _test_kanban_completion() -> Dictionary:
	var name := "Kanban tamamlanma oranı"
	var k := AIKanbanModel.new()
	k.add_card("t1", "T1")
	k.add_card("t2", "T2")
	# t1'i DONE'a taşı (tam akış)
	k.move_card("t1", AIKanbanModel.Column.READY)
	k.move_card("t1", AIKanbanModel.Column.IN_PROGRESS)
	k.move_card("t1", AIKanbanModel.Column.VERIFY)
	k.move_card("t1", AIKanbanModel.Column.DONE)
	# 1/2 tamamlandı -> 0.5
	if abs(k.completion_ratio() - 0.5) > 0.01:
		return _fail(name, "tamamlanma oranı 0.5 olmalı")
	return _ok(name)


# ============================================================
# LIVE FEED MODEL
# ============================================================

static func _test_feed_collect() -> Dictionary:
	var name := "Feed olay biriktirme"
	var f := AILiveFeedModel.new()
	var e := AIFeedEvent.create("TEST", "mesaj", "system")
	f.on_event(e)
	if f.total_count() != 1:
		return _fail(name, "olay biriktirilmemiş")
	return _ok(name)


static func _test_feed_severity_filter() -> Dictionary:
	var name := "Feed severity filtresi"
	var f := AILiveFeedModel.new()
	f.on_event(AIFeedEvent.create("INFO_EV", "x", "system",
		AIFeedEvent.Severity.INFO))
	f.on_event(AIFeedEvent.create("ERR_EV", "y", "system",
		AIFeedEvent.Severity.ERROR))
	# Sadece ERROR ve üstü göster
	f.set_severity_filter(AIFeedEvent.Severity.ERROR)
	if f.visible_count() != 1:
		return _fail(name, "severity filtresi 1 olay göstermeli")
	return _ok(name)


static func _test_feed_category_filter() -> Dictionary:
	var name := "Feed kategori filtresi"
	var f := AILiveFeedModel.new()
	f.on_event(AIFeedEvent.create("TASK_STARTED", "x", "system"))
	f.on_event(AIFeedEvent.create("BUDGET_WARN", "y", "system"))
	f.set_category_filter("TASK")
	if f.visible_count() != 1:
		return _fail(name, "kategori filtresi 1 olay göstermeli")
	# Filtre temizlenince hepsi
	f.clear_filters()
	if f.visible_count() != 2:
		return _fail(name, "filtre temizlenince 2 olay")
	return _ok(name)


static func _test_feed_error_count() -> Dictionary:
	var name := "Feed hata sayısı"
	var f := AILiveFeedModel.new()
	f.on_event(AIFeedEvent.create("OK_EV", "x", "system",
		AIFeedEvent.Severity.INFO))
	f.on_event(AIFeedEvent.create("ERR_EV", "y", "system",
		AIFeedEvent.Severity.ERROR))
	if f.error_count() != 1:
		return _fail(name, "hata sayısı 1 olmalı")
	return _ok(name)


static func _test_feed_attach_emitter() -> Dictionary:
	var name := "Feed emitter'a bağlanma"
	var f := AILiveFeedModel.new()
	var emitter := AIFeedEmitter.new()
	f.attach_to(emitter)
	# Bağlandıktan sonra emitter'ın yaydığı olay model'e düşmeli
	emitter.emit_info("LIVE_EV", "canlı olay")
	if f.total_count() != 1:
		return _fail(name, "emitter olayı model'e ulaşmadı")
	return _ok(name)


# ============================================================
# ITERATION MODEL
# ============================================================

static func _test_iter_phase_advance() -> Dictionary:
	var name := "Iteration faz ilerleme"
	var it := AIIterationModel.new()
	# PLANNING -> ACTIVE
	var result: Dictionary = it.advance_phase()
	if not result["ok"]:
		return _fail(name, "PLANNING->ACTIVE başarısız")
	if it.current_phase != AIIteration.Phase.ACTIVE:
		return _fail(name, "faz ACTIVE olmalı")
	return _ok(name)


static func _test_iter_blocked_advance() -> Dictionary:
	var name := "Iteration tamamlanmamış task ilerlemeyi engeller"
	var it := AIIterationModel.new()
	it.advance_phase()  # PLANNING -> ACTIVE
	it.add_task("t1")   # tamamlanmamış task
	# ACTIVE -> REVIEW engellenmali (task bitmedi)
	var result: Dictionary = it.advance_phase()
	if result["ok"]:
		return _fail(name, "tamamlanmamış task ile ilerlenmemeli")
	# Task'ı bitir, şimdi ilerleyebilmeli
	it.set_task_complete("t1", true)
	var result2: Dictionary = it.advance_phase()
	if not result2["ok"]:
		return _fail(name, "task bitince ilerleyebilmeli")
	return _ok(name)


static func _test_iter_progress() -> Dictionary:
	var name := "Iteration ilerleme oranı"
	var it := AIIterationModel.new()
	it.add_task("t1")
	it.add_task("t2")
	it.set_task_complete("t1", true)
	# 1/2 -> 0.5
	if abs(it.progress() - 0.5) > 0.01:
		return _fail(name, "ilerleme 0.5 olmalı")
	return _ok(name)


static func _test_iter_close() -> Dictionary:
	var name := "Iteration kapanışı"
	var it := AIIterationModel.new()
	# PLANNING -> ACTIVE -> REVIEW -> RETRO -> CLOSED
	it.advance_phase()  # ACTIVE
	it.advance_phase()  # REVIEW (task yok, geçer)
	it.advance_phase()  # RETRO
	it.advance_phase()  # CLOSED
	if not it.is_closed():
		return _fail(name, "iteration kapanmış olmalı")
	# Kapalıyken ilerleyemez
	var result: Dictionary = it.advance_phase()
	if result["ok"]:
		return _fail(name, "kapalı iteration ilerlememeli")
	return _ok(name)
