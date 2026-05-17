@tool
class_name AILifecycleBatteryMonitor
extends RefCounted

## BatteryMonitor — pil izleyici (Madde 10 / App Lifecycle).
##
## Oyun pili hızlı tüketir. Pil azaldığında oyun nazik davranmalı:
## kare hızını düşür, parlaklığı azalt, ağır efektleri kapat. Şarj
## takılıysa tam performans serbest.
##
## Bu sınıf pil yüzdesi + şarj durumunu SEVİYELENDİRİR ve güç
## tasarrufu önerir. Gerçek pil değeri OS'tan okunur (ince
## sarmalayıcı); bu sınıf seviyelendirme mantığıdır.
##
## Mock policy: seviye gerçek pil değerinden hesaplanır.

## Pil durumu seviyeleri.
enum BatteryLevel { FULL, NORMAL, LOW, CRITICAL }

const LEVEL_NAMES: Dictionary = {
	BatteryLevel.FULL: "full",
	BatteryLevel.NORMAL: "normal",
	BatteryLevel.LOW: "low",
	BatteryLevel.CRITICAL: "critical",
}

## Pil yüzde eşikleri.
const FULL_THRESHOLD: float = 80.0
const LOW_THRESHOLD: float = 20.0
const CRITICAL_THRESHOLD: float = 10.0


## Son durum.
var current_level: int = BatteryLevel.NORMAL
var is_charging: bool = false
var battery_percent: float = 100.0


# ============================================================
# SEVİYELENDİRME
# ============================================================

## Pil yüzdesi ve şarj durumundan seviye hesaplar.
## percent: pil yüzdesi (0-100). charging: şarjda mı.
## Dönen: BatteryLevel.
func evaluate(percent: float, charging: bool) -> int:
	battery_percent = clampf(percent, 0.0, 100.0)
	is_charging = charging

	if battery_percent <= CRITICAL_THRESHOLD:
		current_level = BatteryLevel.CRITICAL
	elif battery_percent <= LOW_THRESHOLD:
		current_level = BatteryLevel.LOW
	elif battery_percent >= FULL_THRESHOLD:
		current_level = BatteryLevel.FULL
	else:
		current_level = BatteryLevel.NORMAL
	return current_level


## Mevcut seviyenin adı.
func level_name() -> String:
	return LEVEL_NAMES.get(current_level, "?")


# ============================================================
# GÜÇ TASARRUFU
# ============================================================

## Güç tasarrufu uygulanmalı mı?
## Şarjdaysa asla — priz takılıyken tasarrufa gerek yok.
## Şarjda değilse LOW ve altında tasarruf.
func should_save_power() -> bool:
	if is_charging:
		return false
	return current_level == BatteryLevel.LOW \
		or current_level == BatteryLevel.CRITICAL


## Önerilen kare hızı (FPS) — pil durumuna göre.
## Şarjdaysa veya pil iyiyse tam; düşükse kısıtlı.
func recommended_fps() -> int:
	if is_charging:
		return 60
	match current_level:
		BatteryLevel.CRITICAL:
			return 30  # agresif tasarruf
		BatteryLevel.LOW:
			return 45
		_:
			return 60


## Pil uyarısı gösterilmeli mi? (CRITICAL + şarjda değil)
func needs_warning() -> bool:
	return current_level == BatteryLevel.CRITICAL and not is_charging


## Önerilen güç tasarrufu adımları.
func recommended_actions() -> PackedStringArray:
	if not should_save_power():
		return PackedStringArray()
	if current_level == BatteryLevel.CRITICAL:
		return PackedStringArray([
			"Kare hızını 30'a düşür",
			"Parlaklığı azalt",
			"Ağır görsel efektleri kapat",
			"Titreşimi kapat",
		])
	return PackedStringArray([
		"Kare hızını 45'e düşür",
		"Arka plan efektlerini azalt",
	])


## Durum özeti.
func summary() -> Dictionary:
	return {
		"level": level_name(),
		"percent": battery_percent,
		"is_charging": is_charging,
		"should_save_power": should_save_power(),
		"recommended_fps": recommended_fps(),
	}
