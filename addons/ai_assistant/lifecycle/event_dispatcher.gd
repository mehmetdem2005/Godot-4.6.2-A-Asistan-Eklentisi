@tool
class_name AILifecycleEventDispatcher
extends RefCounted

## EventDispatcher — olay dağıtıcısı (Madde 10 / App Lifecycle).
##
## Android sistem olayları (low memory, battery low, focus lost,
## back button...) tek bir yerden gelir. Bu sınıf o olayları KAYITLI
## HANDLER'lara dağıtır — her olayı dinleyen kod parçası tepki verir.
##
## Gözlemci (observer) deseni: bir modül "battery_low olayını dinle"
## der, dağıtıcı o olay geldiğinde onu çağırır. Modüller birbirini
## bilmez — gevşek bağlı.
##
## Bilinen sistem olayları sabitlerde tanımlı; bilinmeyen olay
## reddedilir (sessizce kaybolmaz — yazım hatası yakalanır).
##
## Mock policy: dağıtım gerçek kayıtlı handler'lara; çağrılmayan
## olay açıkça raporlanır.

## Bilinen sistem olay tipleri.
const EVENT_FOCUS_LOST: String = "focus_lost"
const EVENT_FOCUS_GAINED: String = "focus_gained"
const EVENT_LOW_MEMORY: String = "low_memory"
const EVENT_BATTERY_LOW: String = "battery_low"
const EVENT_BATTERY_OK: String = "battery_ok"
const EVENT_NETWORK_LOST: String = "network_lost"
const EVENT_NETWORK_GAINED: String = "network_gained"
const EVENT_ORIENTATION_CHANGED: String = "orientation_changed"
const EVENT_BACK_BUTTON: String = "back_button"
const EVENT_APP_PAUSE: String = "app_pause"
const EVENT_APP_RESUME: String = "app_resume"

## Tüm bilinen olaylar — yazım hatası yakalama için.
const KNOWN_EVENTS: Array = [
	EVENT_FOCUS_LOST, EVENT_FOCUS_GAINED, EVENT_LOW_MEMORY,
	EVENT_BATTERY_LOW, EVENT_BATTERY_OK, EVENT_NETWORK_LOST,
	EVENT_NETWORK_GAINED, EVENT_ORIENTATION_CHANGED,
	EVENT_BACK_BUTTON, EVENT_APP_PAUSE, EVENT_APP_RESUME,
]


## Olay dinleyicileri — event -> [Callable].
var _handlers: Dictionary = {}

## Toplam dağıtılan olay sayısı.
var _dispatch_count: int = 0


# ============================================================
# KAYIT
# ============================================================

## Bir olaya dinleyici ekler.
## event: olay tipi (KNOWN_EVENTS'ten biri). handler: çağrılacak.
## Dönen: true = kayıt başarılı.
func register(event: String, handler: Callable) -> bool:
	if not KNOWN_EVENTS.has(event):
		push_warning("EventDispatcher: bilinmeyen olay: " + event)
		return false
	if not handler.is_valid():
		push_warning("EventDispatcher: geçersiz handler")
		return false
	if not _handlers.has(event):
		_handlers[event] = []
	_handlers[event].append(handler)
	return true


## Bir olaydaki tüm dinleyicileri kaldırır.
func unregister_all(event: String) -> void:
	_handlers.erase(event)


## Bir olayın kaç dinleyicisi var?
func listener_count(event: String) -> int:
	if not _handlers.has(event):
		return 0
	return (_handlers[event] as Array).size()


# ============================================================
# DAĞITIM
# ============================================================

## Bir olayı tüm dinleyicilerine dağıtır.
## event: olay tipi. payload: olayla gelen veri (opsiyonel).
## Dönen: {ok: bool, dispatched_to: int, reason: String}
func dispatch(event: String, payload: Dictionary = {}) -> Dictionary:
	if not KNOWN_EVENTS.has(event):
		return {
			"ok": false, "dispatched_to": 0,
			"reason": "Bilinmeyen olay: " + event,
		}

	_dispatch_count += 1
	var handlers: Array = _handlers.get(event, [])
	var delivered: int = 0
	for handler in handlers:
		if (handler as Callable).is_valid():
			(handler as Callable).call(payload)
			delivered += 1

	return {
		"ok": true,
		"dispatched_to": delivered,
		"reason": "%d dinleyiciye ulaştı" % delivered,
	}


## Birden fazla olayı sırayla dağıtır.
## events: [olay_adı] dizisi.
## Dönen: başarıyla dağıtılan olay sayısı.
func dispatch_sequence(events: Array) -> int:
	var dispatched: int = 0
	for event in events:
		if dispatch(str(event))["ok"]:
			dispatched += 1
	return dispatched


# ============================================================
# DURUM
# ============================================================

## Toplam dağıtılan olay sayısı.
func total_dispatched() -> int:
	return _dispatch_count


## Dağıtıcı durum özeti.
func summary() -> Dictionary:
	var total_listeners: int = 0
	for event in _handlers:
		total_listeners += (_handlers[event] as Array).size()
	return {
		"registered_events": _handlers.size(),
		"total_listeners": total_listeners,
		"total_dispatched": _dispatch_count,
	}
