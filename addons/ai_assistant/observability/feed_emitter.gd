@tool
class_name AIFeedEmitter
extends RefCounted

## FeedEmitter — canlı olay yayıncısı (Layer 6).
##
## TraceCollector iç gözlem içindir (geliştirici tanısı). FeedEmitter ise
## KULLANICIYA dönüktür — UI'da görünecek gerçek zamanlı olay akışı:
## "Task başladı", "Sahne oluşturuldu", "Doğrulama geçti".
##
## Her olay bir AIFeedEvent'tir (Layer 0 contract). Emitter:
##   - Olayları sıralı yayınlar (monoton sequence)
##   - Abonelere (UI panelleri) Callable ile haber verir
##   - Son N olayı bellekte tutar (UI ilk açılışta geçmişi göstersin)
##
## Mock policy: yayınlanan her olay gerçek bir sistem olayını yansıtır.

## Bellekte tutulan maksimum olay (ring buffer).
const MAX_FEED_EVENTS: int = 500

## Yayınlanmış olaylar (AIFeedEvent listesi) — en yeni sonda.
var _events: Array = []

## Monoton sıra sayacı — aynı ms'de bile deterministik sıra.
var _sequence: int = 0

## Aboneler — her biri bir Callable, yeni olayda çağrılır.
var _subscribers: Array = []


## Yayınlanmış olay sayısı.
func count() -> int:
	return _events.size()


# ============================================================
# YAYIN
# ============================================================

## Bir olay yayınlar. event_type örn: "TASK_STARTED", "VERIFY_PASSED".
## Dönen: oluşturulan ve yayınlanan AIFeedEvent.
func emit_event(
	event_type: String, message: String, owner_role: String = "system",
	severity: int = AIFeedEvent.Severity.INFO, metadata: Dictionary = {}
) -> AIFeedEvent:
	var event := AIFeedEvent.create(event_type, message, owner_role, severity)
	event.sequence = _sequence
	_sequence += 1
	event.metadata = metadata

	_events.append(event)
	# Ring buffer — kapasiteyi aşınca en eskiyi at
	if _events.size() > MAX_FEED_EVENTS:
		_events.pop_front()

	# Abonelere haber ver
	_notify_subscribers(event)
	return event


## Kısa yol — bilgi olayı.
func emit_info(event_type: String, message: String, owner_role: String = "system") -> AIFeedEvent:
	return emit_event(event_type, message, owner_role, AIFeedEvent.Severity.INFO)


## Kısa yol — uyarı olayı.
func emit_warning(event_type: String, message: String, owner_role: String = "system") -> AIFeedEvent:
	return emit_event(event_type, message, owner_role, AIFeedEvent.Severity.WARNING)


## Kısa yol — hata olayı.
func emit_error(event_type: String, message: String, owner_role: String = "system") -> AIFeedEvent:
	return emit_event(event_type, message, owner_role, AIFeedEvent.Severity.ERROR)


# ============================================================
# ABONELİK
# ============================================================

## Bir abone ekler. callback her yeni olayda AIFeedEvent ile çağrılır.
## UI panelleri buraya abone olur.
func subscribe(callback: Callable) -> void:
	if not callback.is_valid():
		push_warning("FeedEmitter.subscribe: geçersiz callable")
		return
	if not _subscribers.has(callback):
		_subscribers.append(callback)


## Bir aboneyi çıkarır.
func unsubscribe(callback: Callable) -> void:
	var idx: int = _subscribers.find(callback)
	if idx >= 0:
		_subscribers.remove_at(idx)


## Abone sayısı.
func subscriber_count() -> int:
	return _subscribers.size()


## Tüm abonelere bir olayı bildirir.
func _notify_subscribers(event: AIFeedEvent) -> void:
	# Kopya üzerinde gez — callback abonelik değiştirebilir
	var current: Array = _subscribers.duplicate()
	for callback in current:
		if (callback as Callable).is_valid():
			(callback as Callable).call(event)


# ============================================================
# GEÇMİŞ SORGULAMA
# ============================================================

## Tüm olayları sıralı döndürür (en eski -> en yeni).
func all_events() -> Array:
	return _events


## Son n olayı döndürür — UI ilk açılışta bunu gösterir.
func recent_events(n: int) -> Array:
	if n >= _events.size():
		return _events.duplicate()
	return _events.slice(_events.size() - n, _events.size())


## Belirli severity ve üstündeki olayları döndürür.
func events_at_least(min_severity: int) -> Array:
	var result: Array = []
	for e in _events:
		if (e as AIFeedEvent).severity >= min_severity:
			result.append(e)
	return result


## Belirli bir task'a ait olayları döndürür.
func events_for_task(task_ref: String) -> Array:
	var result: Array = []
	for e in _events:
		if (e as AIFeedEvent).task_ref == task_ref:
			result.append(e)
	return result


## En son yayınlanan olay. Yoksa null.
func last_event() -> AIFeedEvent:
	if _events.is_empty():
		return null
	return _events[_events.size() - 1]


# ============================================================
# YÖNETİM
# ============================================================

## Olay geçmişini temizler — aboneler korunur.
func clear_history() -> void:
	_events.clear()


## Her şeyi sıfırlar — olaylar + aboneler.
func reset() -> void:
	_events.clear()
	_subscribers.clear()
	_sequence = 0
