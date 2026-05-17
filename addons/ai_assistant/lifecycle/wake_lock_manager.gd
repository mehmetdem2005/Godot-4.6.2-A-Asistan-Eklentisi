@tool
class_name AILifecycleWakeLock
extends RefCounted

## WakeLockManager — uyanık tutma yöneticisi (Madde 10 / device_control).
##
## Android telefon, dokunulmadığında ekranı söndürür (pil tasarrufu).
## Ama bazı oyun anları dokunmasız geçer: ara sahne (cutscene),
## otomatik oynanan bölüm, uzun bir video. O sırada ekran sönerse
## oyuncu rahatsız olur.
##
## Wake lock = "ekranı söndürme" talebi. Bu sınıf wake lock'ları
## yönetir. Kritik: pil için, gerektiğinde AÇ, işi bitince KAPAT.
## Açık unutulan wake lock pili tüketir.
##
## Birden fazla sistem wake lock isteyebilir (cutscene + video aynı
## anda) — sayaçla yönetilir: hepsi bırakana kadar ekran açık kalır.
##
## Mock policy: kilit durumu gerçek talep sayımından.

## Aktif wake lock talepleri — talep_sahibi -> true.
var _holders: Dictionary = {}

## Wake lock toplam açılma sayısı (istatistik).
var _total_acquisitions: int = 0


# ============================================================
# KİLİT YÖNETİMİ
# ============================================================

## Bir wake lock talep eder.
## holder: talep eden sistemin adı (örn. "cutscene_player").
## Dönen: {acquired: bool, active_holders: int, reason: String}
func acquire(holder: String) -> Dictionary:
	if holder.is_empty():
		return {
			"acquired": false, "active_holders": _holders.size(),
			"reason": "Geçersiz talep sahibi",
		}
	# Zaten bu sahip tutuyorsa — tekrar sayma
	if _holders.has(holder):
		return {
			"acquired": true, "active_holders": _holders.size(),
			"reason": "Bu sahip zaten wake lock tutuyor",
		}
	_holders[holder] = true
	_total_acquisitions += 1
	return {
		"acquired": true,
		"active_holders": _holders.size(),
		"reason": "Wake lock alındı — ekran açık kalacak",
	}


## Bir wake lock'u bırakır.
## holder: bırakan sistemin adı.
## Dönen: {released: bool, active_holders: int, screen_can_sleep: bool}
func release(holder: String) -> Dictionary:
	if not _holders.has(holder):
		return {
			"released": false, "active_holders": _holders.size(),
			"screen_can_sleep": _holders.is_empty(),
		}
	_holders.erase(holder)
	return {
		"released": true,
		"active_holders": _holders.size(),
		"screen_can_sleep": _holders.is_empty(),
	}


## Tüm wake lock'ları bırakır — acil durum/temizlik.
func release_all() -> void:
	_holders.clear()


# ============================================================
# SORGULAMA
# ============================================================

## Ekran şu an açık tutuluyor mu (en az bir wake lock var)?
func is_screen_kept_awake() -> bool:
	return not _holders.is_empty()


## Ekran sönebilir mi (hiç wake lock yok)?
func can_screen_sleep() -> bool:
	return _holders.is_empty()


## Aktif wake lock sahibi sayısı.
func active_holder_count() -> int:
	return _holders.size()


## Bir sistem şu an wake lock tutuyor mu?
func is_held_by(holder: String) -> bool:
	return _holders.has(holder)


## Durum özeti.
func summary() -> Dictionary:
	return {
		"screen_kept_awake": is_screen_kept_awake(),
		"active_holders": _holders.size(),
		"total_acquisitions": _total_acquisitions,
	}
