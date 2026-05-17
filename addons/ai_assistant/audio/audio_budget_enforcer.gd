@tool
class_name AIAudioBudgetEnforcer
extends RefCounted

## AudioBudgetEnforcer — ses bütçe denetçisi (Madde 08 / budget).
##
## Mobil cihazda ses için ayrılan bellek sınırlıdır. Bu sınıf bir
## SES BÜTÇESİ uygular: yüklü seslerin toplam belleği bir limiti
## aşamaz.
##
## Quality Gates'in (Madde 11) ses tarafı: yeni bir ses yüklemeden
## önce "bütçeye sığar mı" sorulur. Sığmıyorsa ya reddet ya da yer
## açmak için eski ses boşalt (LRU benzeri).
##
## "Mock yasak": bütçe aşımını gizlemez — açıkça reddeder veya
## boşaltma planı üretir.
##
## Mock policy: bütçe kararı gerçek bellek tahmininden.

## Mobil tier'lara göre ses bellek bütçeleri (bayt).
const TIER_BUDGETS: Dictionary = {
	0: 16 * 1024 * 1024,   # düşük tier — 16 MB
	1: 32 * 1024 * 1024,   # orta tier — 32 MB
	2: 64 * 1024 * 1024,   # yüksek tier — 64 MB
}

## Uyarı eşiği — bütçenin bu oranı dolunca uyar.
const WARN_RATIO: float = 0.80


## Aktif bellek bütçesi (bayt).
var budget_bytes: int = 32 * 1024 * 1024

## Şu an yüklü seslerin toplam belleği (bayt).
var used_bytes: int = 0

## Yüklü ses kayıtları — ses_id -> bayt.
var _loaded: Dictionary = {}


func _init(tier: int = 1) -> void:
	budget_bytes = int(TIER_BUDGETS.get(tier, TIER_BUDGETS[1]))


# ============================================================
# BÜTÇE AYARI
# ============================================================

## Mobil tier'a göre bütçeyi ayarlar.
func set_tier(tier: int) -> void:
	if TIER_BUDGETS.has(tier):
		budget_bytes = int(TIER_BUDGETS[tier])


# ============================================================
# YÜKLEME DENETİMİ
# ============================================================

## Yeni bir ses yüklemenin bütçeye sığıp sığmadığını kontrol eder.
## sound_id: ses kimliği. size_bytes: sesin bellek boyutu.
## Dönen: {allowed: bool, reason: String, free_needed: int}
func check_load(sound_id: String, size_bytes: int) -> Dictionary:
	# Zaten yüklüyse — sorun yok
	if _loaded.has(sound_id):
		return {
			"allowed": true, "reason": "Ses zaten yüklü",
			"free_needed": 0,
		}

	var projected: int = used_bytes + size_bytes

	# Bütçeye sığıyor mu
	if projected <= budget_bytes:
		return {
			"allowed": true,
			"reason": "Bütçeye sığıyor",
			"free_needed": 0,
		}

	# Sığmıyor — ne kadar yer açılması gerek
	var free_needed: int = projected - budget_bytes
	return {
		"allowed": false,
		"reason": "Bütçe aşımı — %d bayt yer açılmalı" % free_needed,
		"free_needed": free_needed,
	}


## Bir sesi bütçeye kaydeder (yükleme onaylandıktan sonra).
## Dönen: true = kaydedildi.
func register_load(sound_id: String, size_bytes: int) -> bool:
	if _loaded.has(sound_id):
		return true  # zaten kayıtlı
	var check: Dictionary = check_load(sound_id, size_bytes)
	if not bool(check["allowed"]):
		return false
	_loaded[sound_id] = size_bytes
	used_bytes += size_bytes
	return true


## Bir sesi bütçeden çıkarır (boşaltıldığında).
## Dönen: true = vardı ve çıkarıldı.
func register_unload(sound_id: String) -> bool:
	if not _loaded.has(sound_id):
		return false
	used_bytes -= int(_loaded[sound_id])
	_loaded.erase(sound_id)
	return true


# ============================================================
# DURUM
# ============================================================

## Bütçenin ne kadarı dolu (0.0 - 1.0).
func usage_ratio() -> float:
	if budget_bytes <= 0:
		return 1.0
	return float(used_bytes) / float(budget_bytes)


## Bütçe uyarı bölgesinde mi (%80+ dolu)?
func is_in_warning_zone() -> bool:
	return usage_ratio() >= WARN_RATIO


## Bütçe aşıldı mı?
func is_over_budget() -> bool:
	return used_bytes > budget_bytes


## Kalan boş bütçe (bayt).
func free_bytes() -> int:
	return maxi(budget_bytes - used_bytes, 0)


## Yüklü ses sayısı.
func loaded_count() -> int:
	return _loaded.size()


## Durum özeti.
func summary() -> Dictionary:
	return {
		"budget_bytes": budget_bytes,
		"used_bytes": used_bytes,
		"usage_ratio": usage_ratio(),
		"loaded_count": _loaded.size(),
		"warning": is_in_warning_zone(),
	}
