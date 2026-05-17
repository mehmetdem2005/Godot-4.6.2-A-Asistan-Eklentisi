@tool
class_name AILifecycleNotificationChannels
extends RefCounted

## NotificationChannelSetup — bildirim kanalları (Madde 10).
##
## Android 8+ tüm bildirimlerin bir KANALA ait olmasını zorunlu kılar.
## Kanal, bir bildirim kategorisidir: önem derecesi, ses, titreşim
## ayarları kanal seviyesinde belirlenir. Kullanıcı kanal kanal
## bildirimi kapatabilir.
##
## Oyun için tipik kanallar: günlük ödül hatırlatması, etkinlik
## duyurusu, enerji/can dolumu bildirimi.
##
## Bu sınıf kanal TANIMLARINI yönetir — gerçek Android kanal kaydı
## native eklenti işidir; bu sınıf tanım + doğrulama mantığıdır.
##
## Mock policy: kanal tanımları gerçek kayıtlardan.

## Kanal önem dereceleri (Android importance karşılığı).
enum Importance { LOW, DEFAULT, HIGH }

const IMPORTANCE_NAMES: Dictionary = {
	Importance.LOW: "low",        # sessiz, durum çubuğunda
	Importance.DEFAULT: "default", # ses + durum çubuğu
	Importance.HIGH: "high",      # ses + açılır (heads-up)
}


## Bir bildirim kanalı tanımı.
class Channel extends RefCounted:
	var channel_id: String = ""
	var channel_name: String = ""     ## Kullanıcıya görünen ad
	var importance: int = AILifecycleNotificationChannels.Importance \
		.DEFAULT
	var description: String = ""

	func _init(
		p_id: String, p_name: String, p_importance: int, p_desc: String
	) -> void:
		channel_id = p_id
		channel_name = p_name
		importance = p_importance
		description = p_desc

	func to_dict() -> Dictionary:
		return {
			"id": channel_id, "name": channel_name,
			"importance": AILifecycleNotificationChannels \
				.IMPORTANCE_NAMES.get(importance, "?"),
		}


## Kayıtlı kanallar — channel_id -> Channel.
var _channels: Dictionary = {}


# ============================================================
# KANAL KAYDI
# ============================================================

## Bir bildirim kanalı tanımlar.
## channel_id: benzersiz kanal kimliği. name: görünen ad.
## importance: önem derecesi. description: kanal açıklaması.
## Dönen: true = kayıt başarılı.
func define_channel(
	channel_id: String, channel_name: String,
	importance: int, description: String = ""
) -> bool:
	if channel_id.is_empty() or channel_name.is_empty():
		push_warning("NotificationChannels: geçersiz kanal tanımı")
		return false
	if not IMPORTANCE_NAMES.has(importance):
		push_warning("NotificationChannels: geçersiz önem derecesi")
		return false
	_channels[channel_id] = Channel.new(
		channel_id, channel_name, importance, description
	)
	return true


## Oyunlar için yaygın varsayılan kanalları tanımlar.
func define_default_channels() -> void:
	define_channel(
		"daily_reward", "Günlük Ödüller", Importance.DEFAULT,
		"Günlük giriş ödülü hatırlatmaları"
	)
	define_channel(
		"events", "Etkinlikler", Importance.HIGH,
		"Özel etkinlik ve kampanya duyuruları"
	)
	define_channel(
		"energy_refill", "Enerji Dolumu", Importance.LOW,
		"Enerji/can dolduğunda bildirim"
	)
	define_channel(
		"general", "Genel", Importance.DEFAULT,
		"Genel oyun bildirimleri"
	)


# ============================================================
# SORGULAMA
# ============================================================

## Bir kanal tanımlı mı?
func has_channel(channel_id: String) -> bool:
	return _channels.has(channel_id)


## Bir kanalı döndürür. Yoksa null.
func get_channel(channel_id: String) -> Channel:
	return _channels.get(channel_id, null)


## Tanımlı kanal sayısı.
func channel_count() -> int:
	return _channels.size()


## Tüm kanal kimlikleri.
func channel_ids() -> Array:
	return _channels.keys()


## Bir kanalın önem derecesini döndürür. Yoksa -1.
func importance_of(channel_id: String) -> int:
	if not _channels.has(channel_id):
		return -1
	return (_channels[channel_id] as Channel).importance
