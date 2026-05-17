@tool
class_name AIObservabilityHub
extends RefCounted

## ObservabilityHub — gözlemlenebilirlik merkezi (Layer 6).
##
## Layer 6'nın tek giriş noktası. Beş bileşeni tek çatı altında birleştirir:
##   trace    — AITraceCollector  (yapılandırılmış iz)
##   metrics  — AIMetricsCollector (sayısal ölçüm)
##   cost     — AICostTracker      (maliyet takibi)
##   feed     — AIFeedEmitter      (canlı olay akışı)
##   replay   — AIReplayEngine     (iz geri sarma)
##
## Diğer katmanlar (Executor, Verifier...) buraya tek referansla bağlanır
## ve "olay oldu" der; Hub doğru bileşenlere dağıtır.
##
## Mock policy: Hub sadece gerçek olayları kaydeder/yayar.

var trace: AITraceCollector
var metrics: AIMetricsCollector
var cost: AICostTracker
var feed: AIFeedEmitter
var replay: AIReplayEngine


func _init() -> void:
	trace = AITraceCollector.new()
	metrics = AIMetricsCollector.new()
	cost = AICostTracker.new()
	feed = AIFeedEmitter.new()
	replay = AIReplayEngine.new()


# ============================================================
# BİRLEŞİK OLAY KAYDI
# ============================================================

## Bir sistem olayını TÜM ilgili bileşenlere tek çağrıda dağıtır.
## Bu, diğer katmanların kullanacağı ana API.
##   - trace'e yapılandırılmış iz düşer
##   - feed'e kullanıcı-dönük olay yayınlar
##   - metrics'te ilgili sayacı artırır
##
## category: "executor"/"verifier"/"planner"...
## event_type: "TASK_STARTED"/"VERIFY_PASSED"...
## is_error: hata olayı mı (trace seviyesi + metrik için)
func report_event(
	category: String, event_type: String, message: String,
	owner_role: String = "system", is_error: bool = false
) -> void:
	# 1. Trace — yapılandırılmış iz
	var trace_level: int = (
		AITraceCollector.TraceLevel.ERROR if is_error
		else AITraceCollector.TraceLevel.INFO
	)
	trace.record(trace_level, category, event_type, message)

	# 2. Feed — kullanıcı-dönük olay
	var severity: int = (
		AIFeedEvent.Severity.ERROR if is_error
		else AIFeedEvent.Severity.INFO
	)
	feed.emit_event(event_type, message, owner_role, severity)

	# 3. Metrics — olay sayacı
	metrics.increment("events.total")
	metrics.increment("events." + category)
	if is_error:
		metrics.increment("events.errors")


## Bir task'ın başladığını kaydeder — span açar.
## Dönen: span id (task bitince end_task_span'e geçilir).
func begin_task(task_ref: String, task_title: String) -> String:
	var span_id: String = trace.begin_span("task:" + task_ref)
	feed.emit_info("TASK_STARTED", task_title, "system")
	metrics.increment("tasks.started")
	metrics.adjust_gauge("tasks.active", 1.0)
	return span_id


## Bir task'ın bittiğini kaydeder — span kapatır.
## success: task başarılı mı. duration_ms: ne kadar sürdü.
func end_task(task_ref: String, success: bool, duration_ms: float) -> void:
	trace.end_span("task:" + task_ref)
	metrics.adjust_gauge("tasks.active", -1.0)
	metrics.observe("tasks.duration_ms", duration_ms)
	if success:
		metrics.increment("tasks.succeeded")
		feed.emit_info("TASK_COMPLETED", "Task tamamlandı: " + task_ref, "system")
	else:
		metrics.increment("tasks.failed")
		feed.emit_error("TASK_FAILED", "Task başarısız: " + task_ref, "system")


## Bir maliyet kaydını işler — cost tracker'a ekler, bütçe durumunu yayar.
func report_cost(record: AICostRecord) -> Dictionary:
	var status: Dictionary = cost.add_cost(record)
	metrics.set_gauge("cost.total_usd", cost.total_cost())
	if status["warn"]:
		feed.emit_warning(
			"BUDGET_WARNING",
			"Bütçe uyarı eşiği aşıldı: $%.4f" % status["total_after"],
			"system"
		)
		trace.warn("cost", "budget_warning", "Bütçe uyarı bölgesinde")
	if not status["within_budget"]:
		feed.emit_error(
			"BUDGET_EXCEEDED",
			"Bütçe sınırı aşıldı: $%.4f" % status["total_after"],
			"system"
		)
		trace.error("cost", "budget_exceeded", "Bütçe sınırı aşıldı")
	return status


# ============================================================
# TANI — replay hazırlığı
# ============================================================

## Mevcut izleri replay motoruna yükler — tanı oturumu için.
## Bir hata sonrası "ne oldu?" incelemesinden önce çağrılır.
func prepare_replay() -> AIReplayEngine:
	replay.load_traces(trace.all_traces())
	return replay


## Hızlı tanı — varsa ilk hatanın bağlamını döndürür.
## Dönen: {has_error: bool, error_trace, context: Array}
func diagnose() -> Dictionary:
	prepare_replay()
	var first_error: Variant = replay.seek_to_first_error()
	if first_error == null:
		return {"has_error": false, "error_trace": null, "context": []}
	return {
		"has_error": true,
		"error_trace": first_error,
		"context": replay.error_context(5),
	}


# ============================================================
# DURUM
# ============================================================

## Tüm Layer 6 durumunun anlık görüntüsü — UI dashboard için.
func dashboard() -> Dictionary:
	return {
		"traces": trace.count(),
		"errors": trace.errors().size(),
		"metrics": metrics.snapshot(),
		"cost": cost.summary(),
		"feed_events": feed.count(),
	}


## Tüm gözlem verisini diske yazar.
func persist() -> bool:
	return trace.save_to_disk()


## Tüm bileşenleri sıfırlar.
func reset() -> void:
	trace.clear()
	metrics.reset()
	cost.reset()
	feed.reset()
