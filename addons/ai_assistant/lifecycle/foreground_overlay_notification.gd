@tool
class_name AILifecycleForegroundOverlay
extends RefCounted

## ForegroundOverlayNotification — ön plan bildirim overlay (Madde 10).
##
## Phase 1 geçici çözümü. Gerçek Android sistem bildirimleri native
## eklenti ister. Phase 1'de eklenti yokken, oyun ÖN PLANDAYKEN
## bildirimleri oyun içi bir OVERLAY ile gösterebiliriz — ekranın
## üstünde kayan bir banner.
##
## Bu, sistem bildiriminin tam yerini tutmaz (oyun kapalıyken
## çalışmaz) ama oyun açıkken "enerjin doldu" gibi mesajları
## göstermek için yeterli.
##
## Bu sınıf overlay KUYRUĞUNU yönetir: gösterilecek bildirimler,
## süre, öncelik sırası. Gerçek görsel banner UI katmanının işi.
##
## Mock policy: kuyruk gerçek bildirim taleplerinden.

## Bir overlay bildirimi.
class OverlayItem extends RefCounted:
	var item_id: String = ""
	var message: String = ""
	var priority: int = 0              ## Yüksek = önce gösterilir
	var display_seconds: float = 3.0

	func to_dict() -> Dictionary:
		return {
			"id": item_id, "message": message,
			"priority": priority,
		}


## Gösterim bekleyen overlay kuyruğu.
var _queue: Array = []

## Şu an gösterilen overlay (yoksa null).
var _current: OverlayItem = null

## Mevcut overlay'in kalan gösterim süresi.
var _remaining_time: float = 0.0


# ============================================================
# KUYRUĞA EKLEME
# ============================================================

## Bir overlay bildirimi kuyruğa ekler.
## item_id: kimlik. message: gösterilecek metin.
## priority: öncelik (yüksek önce). display_seconds: gösterim süresi.
func enqueue(
	item_id: String, message: String,
	priority: int = 0, display_seconds: float = 3.0
) -> bool:
	if item_id.is_empty() or message.is_empty():
		return false
	var item := OverlayItem.new()
	item.item_id = item_id
	item.message = message
	item.priority = priority
	item.display_seconds = maxf(display_seconds, 0.5)
	_queue.append(item)
	# Önceliğe göre sırala — yüksek öncelik öne
	_queue.sort_custom(func(a: OverlayItem, b: OverlayItem) -> bool:
		return a.priority > b.priority)
	return true


# ============================================================
# GÖSTERİM DÖNGÜSÜ
# ============================================================

## Zamanı ilerletir — mevcut overlay'in süresini azaltır, biterse
## kuyruktaki sıradakini gösterir.
## delta_seconds: geçen süre.
## Dönen: {showing: bool, message: String, changed: bool}
func tick(delta_seconds: float) -> Dictionary:
	var changed: bool = false

	# Mevcut overlay varsa süresini azalt
	if _current != null:
		_remaining_time -= delta_seconds
		if _remaining_time <= 0.0:
			_current = null
			changed = true

	# Mevcut yoksa kuyruktan al
	if _current == null and not _queue.is_empty():
		_current = _queue.pop_front()
		_remaining_time = _current.display_seconds
		changed = true

	return {
		"showing": _current != null,
		"message": _current.message if _current != null else "",
		"changed": changed,
	}


## Mevcut overlay'i hemen kapatır.
func dismiss_current() -> void:
	_current = null
	_remaining_time = 0.0


# ============================================================
# SORGULAMA
# ============================================================

## Şu an bir overlay gösteriliyor mu?
func is_showing() -> bool:
	return _current != null


## Kuyrukta bekleyen overlay sayısı.
func queue_length() -> int:
	return _queue.size()


## Mevcut overlay'in mesajı. Yoksa boş.
func current_message() -> String:
	if _current == null:
		return ""
	return _current.message


## Kuyruğu temizler.
func clear() -> void:
	_queue.clear()
	_current = null
	_remaining_time = 0.0
