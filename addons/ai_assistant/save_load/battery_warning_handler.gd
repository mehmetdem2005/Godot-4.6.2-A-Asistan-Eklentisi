@tool
class_name AISaveBatteryWarningHandler
extends RefCounted

## BatteryWarningHandler — pil uyarısı kayıt tetikleyici (Madde 09).
##
## Telefonun pili biterse oyun aniden kapanır — kaydedilmemiş her şey
## gider. Bu sınıf pil durumunu izler ve KRİTİK seviyede koruyucu
## bir kayıt tetikler: telefon ölmeden önce ilerlemeyi güvene al.
##
## Lifecycle (Madde 10) pil seviyesini bildirir; bu sınıf Save/Load
## tarafının tepkisi — "pil kritik, şimdi kaydet".
##
## Tek seferlik tetik: pil kritiğe ilk düştüğünde kaydet, sonra
## tekrar tekrar kaydetme (pil kritikte uzun süre kalabilir, her
## tick'te kayıt israf). Pil toparlanırsa tetik yeniden silahlanır.
##
## Mock policy: tetik gerçek pil seviyesinden.

## Kritik pil eşiği (yüzde).
const CRITICAL_THRESHOLD: float = 15.0

## Toparlanma eşiği — pil bunun üstüne çıkınca tetik resetlenir.
const RECOVERY_THRESHOLD: float = 25.0


## Koruyucu kayıt bu döngüde yapıldı mı (tek-seferlik tetik).
var _save_triggered: bool = false

## Toplam pil-kaynaklı kayıt sayısı.
var _battery_save_count: int = 0

## Son bilinen pil yüzdesi.
var last_battery_percent: float = 100.0


# ============================================================
# PİL İZLEME
# ============================================================

## Pil seviyesi bildirir ve koruyucu kayıt gerekip gerekmediğini söyler.
## percent: pil yüzdesi (0-100). charging: şarjda mı.
## Dönen: {should_save: bool, reason: String}
func report_battery(percent: float, charging: bool) -> Dictionary:
	last_battery_percent = clampf(percent, 0.0, 100.0)

	# Şarjdaysa — pil tehlikesi yok, tetiği resetle
	if charging:
		_save_triggered = false
		return {
			"should_save": false,
			"reason": "Şarjda — pil kaydı gereksiz",
		}

	# Pil toparlandı — tetiği yeniden silahla
	if last_battery_percent >= RECOVERY_THRESHOLD:
		_save_triggered = false
		return {
			"should_save": false,
			"reason": "Pil yeterli seviyede",
		}

	# Pil kritik mi
	if last_battery_percent <= CRITICAL_THRESHOLD:
		# Zaten tetiklendiyse tekrar kaydetme
		if _save_triggered:
			return {
				"should_save": false,
				"reason": "Pil kritik ama koruyucu kayıt zaten yapıldı",
			}
		# İlk kez kritiğe düştü — koruyucu kayıt
		_save_triggered = true
		_battery_save_count += 1
		return {
			"should_save": true,
			"reason": "Pil kritik (%.0f%%) — koruyucu kayıt" % \
				last_battery_percent,
		}

	# Pil düşük ama kritik değil — uyarı bölgesi, kayıt yok
	return {
		"should_save": false,
		"reason": "Pil düşük ama kritik değil",
	}


# ============================================================
# SORGULAMA
# ============================================================

## Pil şu an kritik seviyede mi?
func is_critical() -> bool:
	return last_battery_percent <= CRITICAL_THRESHOLD


## Koruyucu kayıt bu döngüde yapıldı mı?
func save_triggered() -> bool:
	return _save_triggered


## Toplam pil-kaynaklı kayıt sayısı.
func battery_save_count() -> int:
	return _battery_save_count


## Durum özeti.
func summary() -> Dictionary:
	return {
		"last_battery_percent": last_battery_percent,
		"is_critical": is_critical(),
		"save_triggered": _save_triggered,
		"battery_save_count": _battery_save_count,
	}
