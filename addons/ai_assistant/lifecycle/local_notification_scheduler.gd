@tool
class_name AILifecycleNotificationScheduler
extends RefCounted

## LocalNotificationScheduler — bildirim zamanlayıcı (Madde 10).
##
## Yerel bildirimler oyuncuyu geri çağırır: "Enerjin doldu!", "Günlük
## ödülün hazır!". Sunucu gerekmez — cihaz kendi zamanlar.
##
## Bu sınıf bildirimleri PLANLAR: gelecekte bir zamanda gösterilmek
## üzere kaydeder, iptal eder, çakışmaları yönetir.
##
## Kritik kurallar:
##   - geçmiş zamana bildirim planlanamaz
##   - aynı id ile ikinci plan eskisini değiştirir (çift bildirim yok)
##   - her bildirim bir kanala ait olmalı
##
## Gerçek bildirim gösterimi native eklenti işidir; bu sınıf
## zamanlama mantığını tutar — test edilebilir.
##
## Mock policy: zamanlama gerçek planlardan; çakışmalar engellenir.

## Planlanmış bir bildirim.
class ScheduledNotification extends RefCounted:
	var notification_id: String = ""
	var channel_id: String = ""
	var title: String = ""
	var body: String = ""
	var fire_at_unix: int = 0          ## Gösterileceği zaman

	func to_dict() -> Dictionary:
		return {
			"id": notification_id, "channel": channel_id,
			"title": title, "fire_at": fire_at_unix,
		}


## Planlanmış bildirimler — notification_id -> ScheduledNotification.
var _scheduled: Dictionary = {}

## Bildirim kanalları — geçerlilik kontrolü için.
var _channels: AILifecycleNotificationChannels


func _init(channels: AILifecycleNotificationChannels = null) -> void:
	if channels != null:
		_channels = channels
	else:
		_channels = AILifecycleNotificationChannels.new()
		_channels.define_default_channels()


# ============================================================
# ZAMANLAMA
# ============================================================

## Bir bildirim planlar.
## notification_id: benzersiz kimlik (aynı id eskisini değiştirir).
## channel_id: bildirim kanalı (tanımlı olmalı).
## title/body: bildirim içeriği.
## fire_at_unix: gösterim zamanı (unix).
## current_unix: şu anki zaman — geçmiş kontrolü için.
## Dönen: {scheduled: bool, reason: String}
func schedule(
	notification_id: String, channel_id: String,
	title: String, body: String,
	fire_at_unix: int, current_unix: int
) -> Dictionary:
	# Kimlik geçerli mi
	if notification_id.is_empty():
		return {"scheduled": false, "reason": "Geçersiz bildirim kimliği"}

	# Kanal tanımlı mı
	if not _channels.has_channel(channel_id):
		return {
			"scheduled": false,
			"reason": "Tanımsız bildirim kanalı: " + channel_id,
		}

	# Geçmiş zamana planlanamaz
	if fire_at_unix <= current_unix:
		return {
			"scheduled": false,
			"reason": "Geçmiş zamana bildirim planlanamaz",
		}

	# Planla (aynı id varsa değiştirir — çift bildirim önlenir)
	var notification := ScheduledNotification.new()
	notification.notification_id = notification_id
	notification.channel_id = channel_id
	notification.title = title
	notification.body = body
	notification.fire_at_unix = fire_at_unix
	_scheduled[notification_id] = notification

	return {
		"scheduled": true,
		"reason": "Bildirim planlandı",
	}


## Bir planlanmış bildirimi iptal eder.
## Dönen: true = vardı ve iptal edildi.
func cancel(notification_id: String) -> bool:
	if not _scheduled.has(notification_id):
		return false
	_scheduled.erase(notification_id)
	return true


## Tüm planlanmış bildirimleri iptal eder.
func cancel_all() -> void:
	_scheduled.clear()


# ============================================================
# SORGULAMA
# ============================================================

## Bir bildirim planlı mı?
func is_scheduled(notification_id: String) -> bool:
	return _scheduled.has(notification_id)


## Planlanmış bildirim sayısı.
func scheduled_count() -> int:
	return _scheduled.size()


## Belirli bir zamana kadar gösterilecek bildirimleri döndürür.
## until_unix: bu zamana kadar olanlar.
## Dönen: gösterilecek ScheduledNotification dizisi.
func due_notifications(until_unix: int) -> Array:
	var due: Array = []
	for nid in _scheduled:
		var notification: ScheduledNotification = _scheduled[nid]
		if notification.fire_at_unix <= until_unix:
			due.append(notification)
	return due


## En yakın planlanmış bildirimin zamanını döndürür. Yoksa -1.
func next_fire_time() -> int:
	var earliest: int = -1
	for nid in _scheduled:
		var fire_at: int = (_scheduled[nid] as ScheduledNotification) \
			.fire_at_unix
		if earliest == -1 or fire_at < earliest:
			earliest = fire_at
	return earliest
