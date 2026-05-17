@tool
class_name AILifecycleInactivityMonitor
extends RefCounted

## InactivityMonitor — hareketsizlik izleyici (Madde 10 / Lifecycle).
##
## Kullanıcı bir süre dokunmazsa oyun tepki vermeli: önce ekranı
## kararma uyarısı, sonra otomatik duraklat (pil ve oyun ilerlemesi
## korunur — telefon cebe girmiş olabilir).
##
## Bu sınıf "son etkileşimden bu yana ne kadar geçti" izler ve
## hareketsizlik EŞİKLERİNE göre durum bildirir.
##
## Bu sınıf zamanı kendi tutmaz — kendisine "şu kadar saniye geçti"
## bildirilir (test edilebilir saf mantık). Gerçek zaman sayımı
## çağıran tarafın işi.
##
## Mock policy: durum gerçek geçen süreden hesaplanır.

## Hareketsizlik durumu.
enum InactivityState { ACTIVE, IDLE_WARNING, AUTO_PAUSED }

const STATE_NAMES: Dictionary = {
	InactivityState.ACTIVE: "active",
	InactivityState.IDLE_WARNING: "idle_warning",
	InactivityState.AUTO_PAUSED: "auto_paused",
}

## Varsayılan eşikler (saniye).
const DEFAULT_WARNING_SECONDS: float = 60.0
const DEFAULT_PAUSE_SECONDS: float = 120.0


## Eşikler.
var warning_threshold: float = DEFAULT_WARNING_SECONDS
var pause_threshold: float = DEFAULT_PAUSE_SECONDS

## Son etkileşimden bu yana geçen süre (saniye).
var idle_seconds: float = 0.0

## Mevcut durum.
var current_state: int = InactivityState.ACTIVE


# ============================================================
# EŞİK AYARI
# ============================================================

## Hareketsizlik eşiklerini ayarlar.
## warning: uyarı eşiği. pause: otomatik duraklatma eşiği.
## pause her zaman warning'den büyük olmalı — düzeltilir.
func set_thresholds(warning: float, pause: float) -> void:
	warning_threshold = maxf(warning, 1.0)
	# Duraklatma eşiği uyarıdan küçük olamaz
	pause_threshold = maxf(pause, warning_threshold + 1.0)


# ============================================================
# ETKİLEŞİM + SÜRE
# ============================================================

## Kullanıcı etkileşimi bildirir — sayacı sıfırlar.
func register_activity() -> void:
	idle_seconds = 0.0
	current_state = InactivityState.ACTIVE


## Geçen süreyi ekler ve durumu günceller.
## delta_seconds: son çağrıdan bu yana geçen süre.
## Dönen: {state: String, changed: bool}
func tick(delta_seconds: float) -> Dictionary:
	if delta_seconds < 0.0:
		return {"state": state_name(), "changed": false}

	idle_seconds += delta_seconds
	var previous: int = current_state

	# Eşiklere göre durum
	if idle_seconds >= pause_threshold:
		current_state = InactivityState.AUTO_PAUSED
	elif idle_seconds >= warning_threshold:
		current_state = InactivityState.IDLE_WARNING
	else:
		current_state = InactivityState.ACTIVE

	return {
		"state": state_name(),
		"changed": current_state != previous,
	}


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut durumun adı.
func state_name() -> String:
	return STATE_NAMES.get(current_state, "?")


## Otomatik duraklatma tetiklendi mi?
func is_auto_paused() -> bool:
	return current_state == InactivityState.AUTO_PAUSED


## Uyarı gösterilmeli mi?
func should_show_warning() -> bool:
	return current_state == InactivityState.IDLE_WARNING


## Uyarıya kalan süre (saniye). Zaten uyarı/duraklamada 0.
func seconds_until_warning() -> float:
	return maxf(warning_threshold - idle_seconds, 0.0)


## Durum özeti.
func summary() -> Dictionary:
	return {
		"state": state_name(),
		"idle_seconds": idle_seconds,
		"is_auto_paused": is_auto_paused(),
	}
