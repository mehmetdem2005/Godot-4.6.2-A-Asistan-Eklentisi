@tool
class_name AILifecycleNotificationSettings
extends RefCounted

## NotificationSettings — bildirim ayarları (Madde 10 / ui).
##
## Bildirim kanallarının kullanıcı ayar paneli: her kanal (günlük
## ödül, etkinlik, enerji dolumu...) tek tek açılıp kapatılabilir.
## Kullanıcı hangi bildirimleri almak istediğini seçer.
##
## Bu view-model her kanalın açık/kapalı durumunu tutar ve görsel
## anahtarlara çevirir. Üst düzey "tüm bildirimler" anahtarı da var.
##
## notification_channel_setup (mantık katmanı) ile beslenir.
##
## Mock policy: ayarlar gerçek kullanıcı tercihlerinden.

## Bildirim kanalları — anahtar -> {label, default_enabled}.
const CHANNELS: Dictionary = {
	"daily_reward": {
		"label": "Günlük Ödüller", "default_enabled": true,
	},
	"events": {
		"label": "Etkinlikler", "default_enabled": true,
	},
	"energy_refill": {
		"label": "Enerji Dolumu", "default_enabled": false,
	},
	"general": {
		"label": "Genel Bildirimler", "default_enabled": true,
	},
}


## Üst düzey ana anahtar — kapalıysa hiçbir bildirim gitmez.
var master_enabled: bool = true

## Her kanalın açık/kapalı durumu — channel_key -> bool.
var _channel_states: Dictionary = {}


func _init() -> void:
	_load_defaults()


## Kanalları varsayılan durumlarına yükler.
func _load_defaults() -> void:
	for key in CHANNELS:
		_channel_states[key] = bool(CHANNELS[key]["default_enabled"])
	master_enabled = true


# ============================================================
# AYAR DEĞİŞTİRME
# ============================================================

## Ana bildirim anahtarını ayarlar.
## Kapalıysa hiçbir kanal bildirim göndermez (kanal durumları korunur).
func set_master(enabled: bool) -> void:
	master_enabled = enabled


## Bir kanalın durumunu ayarlar.
## channel_key: kanal anahtarı. enabled: açık mı.
## Dönen: true = geçerli kanal.
func set_channel(channel_key: String, enabled: bool) -> bool:
	if not CHANNELS.has(channel_key):
		return false
	_channel_states[channel_key] = enabled
	return true


# ============================================================
# EFEKTİF DURUM
# ============================================================

## Bir kanal GERÇEKTEN bildirim gönderir mi?
## Hem ana anahtar hem kanal anahtarı açık olmalı.
func is_channel_effective(channel_key: String) -> bool:
	if not master_enabled:
		return false
	return bool(_channel_states.get(channel_key, false))


## Bir kanalın kendi anahtarı açık mı (ana anahtardan bağımsız)?
func is_channel_on(channel_key: String) -> bool:
	return bool(_channel_states.get(channel_key, false))


# ============================================================
# SUNUM
# ============================================================

## Tüm kanal ayarlarının görsel listesini üretir.
## Dönen: her biri {key, label, enabled, effective} dizi.
##   enabled: kanalın kendi anahtarı.
##   effective: ana anahtar dahil gerçekten aktif mi.
func build_list() -> Array:
	var list: Array = []
	for key in CHANNELS:
		list.append({
			"key": key,
			"label": str(CHANNELS[key]["label"]),
			"enabled": is_channel_on(key),
			"effective": is_channel_effective(key),
		})
	return list


# ============================================================
# KALICILIK
# ============================================================

## Ayarları kaydetmek için sözlüğe çevirir.
func to_dict() -> Dictionary:
	return {
		"master_enabled": master_enabled,
		"channels": _channel_states.duplicate(true),
	}


## Kaydedilmiş ayarları yükler.
func from_dict(data: Dictionary) -> void:
	_load_defaults()
	master_enabled = bool(data.get("master_enabled", true))
	var channels: Dictionary = data.get("channels", {})
	for key in CHANNELS:
		if channels.has(key):
			_channel_states[key] = bool(channels[key])


# ============================================================
# SORGULAMA
# ============================================================

## Şu an kaç kanal gerçekten aktif?
func active_channel_count() -> int:
	var count: int = 0
	for key in CHANNELS:
		if is_channel_effective(key):
			count += 1
	return count


## Hiç bildirim gönderilmiyor mu (ana kapalı veya tüm kanallar kapalı)?
func all_silent() -> bool:
	return active_channel_count() == 0


## Toplam kanal sayısı.
func channel_count() -> int:
	return CHANNELS.size()
