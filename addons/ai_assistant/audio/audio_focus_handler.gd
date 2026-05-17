@tool
class_name AIAudioFocusHandler
extends RefCounted

## AudioFocusHandler — ses odak yöneticisi (Madde 08 / lifecycle).
##
## Android'de ses "odak" (audio focus) ister. Telefon araması gelince,
## başka uygulama müzik çalınca, bildirim sesi olunca — oyun sesini
## KISMALI ya da DURDURMALI. Tersi kabalık: oyun, kullanıcının
## telefon görüşmesinin üstüne müzik basamaz.
##
## Bu sınıf Lifecycle (Madde 10) ile entegre çalışır: uygulama arka
## plana geçince/odak kaybedince doğru ses tepkisini belirler.
##
## Odak durumları:
##   FOCUSED        — odak bizde, normal ses
##   DUCKED         — geçici kıs (bildirim — ses %20'ye in)
##   LOST           — odak kaybedildi (arama — sesi durdur)
##
## Mock policy: ses kararı gerçek odak olayından.

## Ses odak durumları.
enum FocusState { FOCUSED, DUCKED, LOST }

const STATE_NAMES: Dictionary = {
	FocusState.FOCUSED: "focused",
	FocusState.DUCKED: "ducked",
	FocusState.LOST: "lost",
}

## Ducking sırasında ses seviyesi (normal sesin oranı).
const DUCK_VOLUME: float = 0.2


## Mevcut odak durumu.
var focus_state: int = FocusState.FOCUSED

## Odak kaybından önceki ses seviyesi — geri dönüşte restore için.
var _volume_before_loss: float = 1.0

## Şu an uygulanan ses çarpanı.
var _applied_volume: float = 1.0


# ============================================================
# ODAK OLAYLARI
# ============================================================

## Odak tamamen kaybedildi (telefon araması, başka tam ekran uygulama).
## Ses TAMAMEN durmalı.
## Dönen: {volume: float, should_pause: bool, reason: String}
func on_focus_lost() -> Dictionary:
	_volume_before_loss = _applied_volume
	focus_state = FocusState.LOST
	_applied_volume = 0.0
	return {
		"volume": 0.0,
		"should_pause": true,
		"reason": "Odak kaybedildi — ses durduruldu",
	}


## Geçici ducking — bildirim sesi gibi kısa kesinti.
## Ses kısılır ama durmaz.
## Dönen: {volume: float, should_pause: bool, reason: String}
func on_duck_requested() -> Dictionary:
	# Zaten kayıpsa ducking anlamsız
	if focus_state == FocusState.LOST:
		return {
			"volume": 0.0, "should_pause": true,
			"reason": "Odak zaten kayıp",
		}
	_volume_before_loss = _applied_volume
	focus_state = FocusState.DUCKED
	_applied_volume = DUCK_VOLUME
	return {
		"volume": DUCK_VOLUME,
		"should_pause": false,
		"reason": "Geçici kısma — bildirim sesi",
	}


## Odak geri kazanıldı — ses eski seviyesine döner.
## Dönen: {volume: float, should_resume: bool, reason: String}
func on_focus_gained() -> Dictionary:
	var was_lost: bool = focus_state == FocusState.LOST
	focus_state = FocusState.FOCUSED
	_applied_volume = _volume_before_loss
	return {
		"volume": _applied_volume,
		"should_resume": was_lost,
		"reason": "Odak geri kazanıldı — ses geri yüklendi",
	}


# ============================================================
# SORGULAMA
# ============================================================

## Şu an ses çalınabilir mi (odak tamamen kayıp değilse)?
func can_play_audio() -> bool:
	return focus_state != FocusState.LOST


## Ses şu an kısılmış mı (ducked)?
func is_ducked() -> bool:
	return focus_state == FocusState.DUCKED


## Şu an uygulanması gereken ses çarpanı.
func current_volume() -> float:
	return _applied_volume


## Mevcut odak durumunun adı.
func state_name() -> String:
	return STATE_NAMES.get(focus_state, "?")


## Durum özeti.
func summary() -> Dictionary:
	return {
		"focus_state": state_name(),
		"current_volume": _applied_volume,
		"can_play": can_play_audio(),
	}
