@tool
class_name AIObservabilityTest
extends RefCounted

## Phase 6 / Layer 6 — Observability Self-Test
##
## Sıkı testler: TraceCollector (iz + span), MetricsCollector (counter/
## gauge/histogram), CostTracker (bütçe), FeedEmitter (yayın/abone),
## ReplayEngine (geri sarma), ObservabilityHub (birleşik koordinasyon).


static func run_all() -> Array:
	var results: Array = []

	# TraceCollector
	results.append(_b("Obs: Trace", _test_trace_record()))
	results.append(_b("Obs: Trace", _test_trace_sequence()))
	results.append(_b("Obs: Trace", _test_trace_span()))
	results.append(_b("Obs: Trace", _test_trace_nested_span()))
	results.append(_b("Obs: Trace", _test_trace_filter()))
	results.append(_b("Obs: Trace", _test_trace_errors()))

	# MetricsCollector
	results.append(_b("Obs: Metrics", _test_metrics_counter()))
	results.append(_b("Obs: Metrics", _test_metrics_gauge()))
	results.append(_b("Obs: Metrics", _test_metrics_histogram()))
	results.append(_b("Obs: Metrics", _test_metrics_ratio()))

	# CostTracker
	results.append(_b("Obs: Cost", _test_cost_total()))
	results.append(_b("Obs: Cost", _test_cost_budget_warn()))
	results.append(_b("Obs: Cost", _test_cost_budget_exceed()))
	results.append(_b("Obs: Cost", _test_cost_unlimited()))
	results.append(_b("Obs: Cost", _test_cost_distribution()))

	# FeedEmitter
	results.append(_b("Obs: Feed", _test_feed_emit()))
	results.append(_b("Obs: Feed", _test_feed_subscribe()))
	results.append(_b("Obs: Feed", _test_feed_recent()))
	results.append(_b("Obs: Feed", _test_feed_severity_filter()))

	# ReplayEngine
	results.append(_b("Obs: Replay", _test_replay_step()))
	results.append(_b("Obs: Replay", _test_replay_sort()))
	results.append(_b("Obs: Replay", _test_replay_seek_error()))
	results.append(_b("Obs: Replay", _test_replay_error_context()))

	# ObservabilityHub
	results.append(_b("Obs: Hub", _test_hub_report_event()))
	results.append(_b("Obs: Hub", _test_hub_task_lifecycle()))
	results.append(_b("Obs: Hub", _test_hub_diagnose()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# TRACE COLLECTOR
# ============================================================

static func _test_trace_record() -> Dictionary:
	var name := "Trace iz kaydı"
	var t := AITraceCollector.new()
	var entry: AITraceCollector.TraceEntry = t.record(
		AITraceCollector.TraceLevel.INFO, "executor", "task_started", "Test"
	)
	if entry.event != "task_started":
		return _fail(name, "olay kaydedilmedi")
	if t.count() != 1:
		return _fail(name, "iz sayısı 1 olmalı")
	return _ok(name)


static func _test_trace_sequence() -> Dictionary:
	var name := "Trace monoton sequence"
	var t := AITraceCollector.new()
	var e1: AITraceCollector.TraceEntry = t.info("x", "a")
	var e2: AITraceCollector.TraceEntry = t.info("x", "b")
	if e1.sequence != 0 or e2.sequence != 1:
		return _fail(name, "sequence monoton artmıyor")
	return _ok(name)


static func _test_trace_span() -> Dictionary:
	var name := "Trace span bağlama"
	var t := AITraceCollector.new()
	var span_id: String = t.begin_span("task1")
	var inside: AITraceCollector.TraceEntry = t.info("exec", "step")
	if inside.span_id != span_id:
		return _fail(name, "iz aktif span'e bağlanmadı")
	t.end_span("task1")
	var outside: AITraceCollector.TraceEntry = t.info("exec", "after")
	if not outside.span_id.is_empty():
		return _fail(name, "span sonrası bağ kalkmadı")
	return _ok(name)


static func _test_trace_nested_span() -> Dictionary:
	var name := "Trace iç içe span"
	var t := AITraceCollector.new()
	var outer: String = t.begin_span("outer")
	var inner: String = t.begin_span("inner")
	var e: AITraceCollector.TraceEntry = t.info("x", "y")
	if e.span_id != inner or e.parent_span_id != outer:
		return _fail(name, "iç içe span hiyerarşisi yanlış")
	return _ok(name)


static func _test_trace_filter() -> Dictionary:
	var name := "Trace kategori filtresi"
	var t := AITraceCollector.new()
	t.info("executor", "a")
	t.info("verifier", "b")
	t.info("executor", "c")
	if t.traces_by_category("executor").size() != 2:
		return _fail(name, "kategori filtresi yanlış")
	return _ok(name)


static func _test_trace_errors() -> Dictionary:
	var name := "Trace hata filtresi"
	var t := AITraceCollector.new()
	t.info("x", "ok")
	t.error("x", "fail", "bir hata")
	if t.errors().size() != 1:
		return _fail(name, "hata filtresi yanlış")
	return _ok(name)


# ============================================================
# METRICS COLLECTOR
# ============================================================

static func _test_metrics_counter() -> Dictionary:
	var name := "Metrics counter"
	var m := AIMetricsCollector.new()
	m.increment("tasks")
	m.increment("tasks", 4)
	if m.counter_value("tasks") != 5:
		return _fail(name, "counter toplama yanlış")
	return _ok(name)


static func _test_metrics_gauge() -> Dictionary:
	var name := "Metrics gauge"
	var m := AIMetricsCollector.new()
	m.set_gauge("active", 10.0)
	m.adjust_gauge("active", -3.0)
	if m.gauge_value("active") != 7.0:
		return _fail(name, "gauge ayar/değişim yanlış")
	return _ok(name)


static func _test_metrics_histogram() -> Dictionary:
	var name := "Metrics histogram"
	var m := AIMetricsCollector.new()
	m.observe("dur", 100.0)
	m.observe("dur", 200.0)
	m.observe("dur", 300.0)
	var stat: AIMetricsCollector.HistogramStat = m.histogram_stat("dur")
	if stat.average() != 200.0:
		return _fail(name, "histogram ortalama yanlış")
	if stat.min_value != 100.0 or stat.max_value != 300.0:
		return _fail(name, "histogram min/max yanlış")
	return _ok(name)


static func _test_metrics_ratio() -> Dictionary:
	var name := "Metrics oran hesabı"
	var m := AIMetricsCollector.new()
	m.increment("pass", 8)
	m.increment("total", 10)
	if abs(m.ratio("pass", "total") - 0.8) > 0.0001:
		return _fail(name, "oran yanlış")
	# Sıfır payda güvenliği
	if m.ratio("pass", "yok") != 0.0:
		return _fail(name, "sıfır payda 0 dönmeli")
	return _ok(name)


# ============================================================
# COST TRACKER
# ============================================================

static func _make_cost(amount: float, cache: bool = false) -> AICostRecord:
	var r := AICostRecord.create("deepseek", "TestRole")
	r.total_cost_usd = amount
	r.was_cache_hit = cache
	return r


static func _test_cost_total() -> Dictionary:
	var name := "Cost toplam hesabı"
	var c := AICostTracker.new()
	c.add_cost(_make_cost(0.3))
	c.add_cost(_make_cost(0.5))
	if abs(c.total_cost() - 0.8) > 0.0001:
		return _fail(name, "toplam maliyet yanlış")
	return _ok(name)


static func _test_cost_budget_warn() -> Dictionary:
	var name := "Cost bütçe uyarısı"
	var c := AICostTracker.new()
	c.budget_limit_usd = 1.0
	c.add_cost(_make_cost(0.5))
	var status: Dictionary = c.add_cost(_make_cost(0.35))
	# 0.85 >= 0.8 eşik — uyarı
	if not status["warn"]:
		return _fail(name, "uyarı eşiği aşıldı ama warn false")
	return _ok(name)


static func _test_cost_budget_exceed() -> Dictionary:
	var name := "Cost bütçe aşımı"
	var c := AICostTracker.new()
	c.budget_limit_usd = 1.0
	c.add_cost(_make_cost(0.8))
	var status: Dictionary = c.add_cost(_make_cost(0.5))
	# 1.3 > 1.0 — aşım
	if status["within_budget"]:
		return _fail(name, "bütçe aşıldı ama within true")
	# check_budget de reddetmeli
	var check: Dictionary = c.check_budget(0.0)
	if check["allowed"]:
		return _fail(name, "check_budget aşımı reddetmeli")
	return _ok(name)


static func _test_cost_unlimited() -> Dictionary:
	var name := "Cost sınırsız bütçe"
	var c := AICostTracker.new()
	# budget_limit_usd = 0 -> sınırsız
	var check: Dictionary = c.check_budget(9999.0)
	if not check["allowed"]:
		return _fail(name, "sınırsız bütçe reddetti")
	return _ok(name)


static func _test_cost_distribution() -> Dictionary:
	var name := "Cost cache hit oranı"
	var c := AICostTracker.new()
	c.add_cost(_make_cost(0.1, true))
	c.add_cost(_make_cost(0.1, false))
	if abs(c.cache_hit_rate() - 0.5) > 0.0001:
		return _fail(name, "cache hit oranı yanlış")
	return _ok(name)


# ============================================================
# FEED EMITTER
# ============================================================

static func _test_feed_emit() -> Dictionary:
	var name := "Feed olay yayını"
	var f := AIFeedEmitter.new()
	var e: AIFeedEvent = f.emit_info("TASK_STARTED", "Test", "system")
	if e.event_type != "TASK_STARTED":
		return _fail(name, "olay yayınlanmadı")
	if f.count() != 1:
		return _fail(name, "olay sayısı 1 olmalı")
	return _ok(name)


static func _test_feed_subscribe() -> Dictionary:
	var name := "Feed abonelik"
	var f := AIFeedEmitter.new()
	var received: Array = []
	var cb: Callable = func(e): received.append(e)
	f.subscribe(cb)
	f.emit_info("E1", "m1")
	f.emit_info("E2", "m2")
	if received.size() != 2:
		return _fail(name, "abone olayları almadı")
	return _ok(name)


static func _test_feed_recent() -> Dictionary:
	var name := "Feed son olaylar"
	var f := AIFeedEmitter.new()
	f.emit_info("E1", "m1")
	f.emit_info("E2", "m2")
	f.emit_info("E3", "m3")
	var recent: Array = f.recent_events(2)
	if recent.size() != 2:
		return _fail(name, "recent_events 2 dönmeli")
	if (recent[1] as AIFeedEvent).event_type != "E3":
		return _fail(name, "son olay E3 olmalı")
	return _ok(name)


static func _test_feed_severity_filter() -> Dictionary:
	var name := "Feed severity filtresi"
	var f := AIFeedEmitter.new()
	f.emit_info("E1", "info")
	f.emit_error("E2", "error")
	var errors: Array = f.events_at_least(AIFeedEvent.Severity.ERROR)
	if errors.size() != 1:
		return _fail(name, "severity filtresi yanlış")
	return _ok(name)


# ============================================================
# REPLAY ENGINE
# ============================================================

static func _make_trace(seq: int, level: int) -> AITraceCollector.TraceEntry:
	var e := AITraceCollector.TraceEntry.new()
	e.sequence = seq
	e.level = level
	e.category = "test"
	e.event = "ev" + str(seq)
	return e


static func _test_replay_step() -> Dictionary:
	var name := "Replay ileri/geri adım"
	var r := AIReplayEngine.new()
	r.load_traces([
		_make_trace(0, AITraceCollector.TraceLevel.INFO),
		_make_trace(1, AITraceCollector.TraceLevel.INFO),
	])
	var f1: Variant = r.step_forward()
	if f1 == null or f1.sequence != 0:
		return _fail(name, "ilk ileri adım yanlış")
	var f2: Variant = r.step_forward()
	if f2 == null or f2.sequence != 1:
		return _fail(name, "ikinci ileri adım yanlış")
	var b: Variant = r.step_backward()
	if b == null or b.sequence != 0:
		return _fail(name, "geri adım yanlış")
	return _ok(name)


static func _test_replay_sort() -> Dictionary:
	var name := "Replay sequence sıralama"
	var r := AIReplayEngine.new()
	# Karışık sırada yükle
	r.load_traces([
		_make_trace(2, AITraceCollector.TraceLevel.INFO),
		_make_trace(0, AITraceCollector.TraceLevel.INFO),
		_make_trace(1, AITraceCollector.TraceLevel.INFO),
	])
	var first: Variant = r.step_forward()
	if first == null or first.sequence != 0:
		return _fail(name, "sıralama sonrası ilk 0 olmalı")
	return _ok(name)


static func _test_replay_seek_error() -> Dictionary:
	var name := "Replay hataya atlama"
	var r := AIReplayEngine.new()
	r.load_traces([
		_make_trace(0, AITraceCollector.TraceLevel.INFO),
		_make_trace(1, AITraceCollector.TraceLevel.ERROR),
		_make_trace(2, AITraceCollector.TraceLevel.INFO),
	])
	var err: Variant = r.seek_to_first_error()
	if err == null or err.sequence != 1:
		return _fail(name, "hataya atlama yanlış")
	return _ok(name)


static func _test_replay_error_context() -> Dictionary:
	var name := "Replay hata bağlamı"
	var r := AIReplayEngine.new()
	r.load_traces([
		_make_trace(0, AITraceCollector.TraceLevel.INFO),
		_make_trace(1, AITraceCollector.TraceLevel.INFO),
		_make_trace(2, AITraceCollector.TraceLevel.ERROR),
		_make_trace(3, AITraceCollector.TraceLevel.INFO),
	])
	var ctx: Array = r.error_context(1)
	# hata indeks 2, ±1 -> indeks 1,2,3 = 3 iz
	if ctx.size() != 3:
		return _fail(name, "hata bağlamı boyutu yanlış: %d" % ctx.size())
	return _ok(name)


# ============================================================
# OBSERVABILITY HUB
# ============================================================

static func _test_hub_report_event() -> Dictionary:
	var name := "Hub birleşik olay kaydı"
	var hub := AIObservabilityHub.new()
	hub.report_event("executor", "TASK_STARTED", "Test task", "system", false)
	# Trace, feed, metrics hepsi güncellenmiş olmalı
	if hub.trace.count() == 0:
		return _fail(name, "trace'e iz düşmedi")
	if hub.feed.count() == 0:
		return _fail(name, "feed'e olay düşmedi")
	if hub.metrics.counter_value("events.total") != 1:
		return _fail(name, "metrics sayacı artmadı")
	return _ok(name)


static func _test_hub_task_lifecycle() -> Dictionary:
	var name := "Hub task yaşam döngüsü"
	var hub := AIObservabilityHub.new()
	hub.begin_task("task_1", "Test task")
	if hub.metrics.gauge_value("tasks.active") != 1.0:
		return _fail(name, "aktif task gauge artmadı")
	hub.end_task("task_1", true, 150.0)
	if hub.metrics.gauge_value("tasks.active") != 0.0:
		return _fail(name, "task bitince gauge düşmedi")
	if hub.metrics.counter_value("tasks.succeeded") != 1:
		return _fail(name, "başarı sayacı artmadı")
	return _ok(name)


static func _test_hub_diagnose() -> Dictionary:
	var name := "Hub tanı (diagnose)"
	var hub := AIObservabilityHub.new()
	hub.report_event("x", "ok_event", "normal", "system", false)
	hub.report_event("y", "bad_event", "hata oldu", "system", true)
	var diag: Dictionary = hub.diagnose()
	if not diag["has_error"]:
		return _fail(name, "hata tespit edilmedi")
	if diag["error_trace"] == null:
		return _fail(name, "hata izi null")
	return _ok(name)
