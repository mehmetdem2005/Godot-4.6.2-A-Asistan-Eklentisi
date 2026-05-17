@tool
class_name AILifecycleScreenBrightness
extends RefCounted

## ScreenBrightness — ekran parlaklığı yöneticisi (Madde 10).
##
## Oyun bazen ekran parlaklığını değiştirmek ister: korku oyununda
## karanlık sahne için kıs, fotoğraf modunda aç. Ama dikkatli olunmalı
## — kullanıcının sistem parlaklığını kalıcı bozmamalı.
##
## Doğru desen: oyun parlaklığı geçici DEĞİŞTİRİR, ama kullanıcının
## ORİJİNAL sistem parlaklığını saklar. Oyundan çıkınca eski değere
## DÖNER. Pil tasarrufu da bir faktör — kritik pilde parlaklık kıs.
##
## Bu sınıf parlaklık KARARINI yönetir; gerçek ekran ayarı
## DisplayServer'ın işi (ince sarmalayıcı). Test edilebilir mantık.
##
## Mock policy: parlaklık değeri gerçek talep + kısıtlardan.

## Parlaklık değeri sınırları (0.0 - 1.0).
const MIN_BRIGHTNESS: float = 0.05
const MAX_BRIGHTNESS: float = 1.0

## Pil tasarrufu modunda izin verilen maksimum parlaklık.
const POWER_SAVE_MAX: float = 0.6


## Kullanıcının orijinal sistem parlaklığı — geri dönüş için.
var _original_brightness: float = 0.8

## Oyunun şu an talep ettiği parlaklık.
var _requested_brightness: float = 0.8

## Pil tasarrufu modu aktif mi.
var _power_save: bool = false

## Oyun parlaklığı override etti mi (yoksa sistem değeri geçerli).
var _override_active: bool = false


# ============================================================
# BAŞLATMA
# ============================================================

## Kullanıcının mevcut sistem parlaklığını kaydeder.
## Oyun başında çağrılır — geri dönüş referansı.
func capture_original(system_brightness: float) -> void:
	_original_brightness = clampf(
		system_brightness, MIN_BRIGHTNESS, MAX_BRIGHTNESS
	)
	_requested_brightness = _original_brightness


# ============================================================
# PARLAKLIK TALEBİ
# ============================================================

## Oyun bir parlaklık değeri talep eder.
## value: istenen parlaklık (0-1).
## Dönen: {applied: float, clamped: bool, reason: String}
func request_brightness(value: float) -> Dictionary:
	var clamped_value: float = clampf(
		value, MIN_BRIGHTNESS, MAX_BRIGHTNESS
	)
	var was_clamped: bool = not is_equal_approx(value, clamped_value)

	# Pil tasarrufu — parlaklık tavanı düşük
	if _power_save and clamped_value > POWER_SAVE_MAX:
		clamped_value = POWER_SAVE_MAX
		was_clamped = true

	_requested_brightness = clamped_value
	_override_active = true
	return {
		"applied": clamped_value,
		"clamped": was_clamped,
		"reason": "Parlaklık ayarlandı" if not was_clamped \
			else "Parlaklık sınıra çekildi",
	}


## Oyun parlaklık kontrolünü bırakır — sistem değerine döner.
## Dönen: geri dönülen parlaklık değeri.
func release_to_system() -> float:
	_override_active = false
	_requested_brightness = _original_brightness
	return _original_brightness


# ============================================================
# PİL TASARRUFU
# ============================================================

## Pil tasarrufu modunu ayarlar.
## Aktifse mevcut parlaklık tavanı aşıyorsa kısılır.
func set_power_save(enabled: bool) -> void:
	_power_save = enabled
	# Tasarruf açıldı ve mevcut parlaklık tavanı aşıyorsa kıs
	if enabled and _requested_brightness > POWER_SAVE_MAX:
		_requested_brightness = POWER_SAVE_MAX


# ============================================================
# SORGULAMA
# ============================================================

## Şu an uygulanması gereken parlaklık değeri.
func effective_brightness() -> float:
	if _override_active:
		return _requested_brightness
	return _original_brightness


## Oyun parlaklığı override ediyor mu?
func is_override_active() -> bool:
	return _override_active


## Pil tasarrufu modu aktif mi?
func is_power_save() -> bool:
	return _power_save


## Durum özeti.
func summary() -> Dictionary:
	return {
		"effective_brightness": effective_brightness(),
		"original_brightness": _original_brightness,
		"override_active": _override_active,
		"power_save": _power_save,
	}
