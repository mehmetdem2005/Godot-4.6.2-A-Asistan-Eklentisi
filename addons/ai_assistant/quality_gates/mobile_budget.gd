@tool
class_name AIMobileBudget
extends RefCounted

## MobileBudget — mobil performans bütçesi (Layer 10 / Quality Gates).
##
## Bu eklenti Android telefon için oyun üretiyor. Üretilen sahne
## telefonu kasmamali. Bunun için DONANIM SINIRLARI tanımlanmalı:
## bir karede kaç vertex, kaç draw call, kaç ışık "güvenli".
##
## Bu sınıf üç bütçe profili sunar:
##   LOW_END   — zayıf/eski telefon (geniş kitle, güvenli taban)
##   MID_RANGE — orta telefon (varsayılan hedef)
##   HIGH_END  — güçlü telefon (daha cömert)
##
## Sayılar, Godot Forward Mobile renderer'ı + tipik Android GPU'lar
## göz önüne alınarak seçilmiş muhafazakar değerlerdir. 60 FPS hedefi.
##
## Mock policy: bütçe gerçek donanım sınırlarını yansıtır.

## Bütçe profilleri — hedef telefon sınıfı.
enum Tier { LOW_END, MID_RANGE, HIGH_END }

const TIER_NAMES: Dictionary = {
	Tier.LOW_END: "low_end",
	Tier.MID_RANGE: "mid_range",
	Tier.HIGH_END: "high_end",
}

## Her profil için kare-başına bütçe limitleri.
## Anahtarlar: vertices, draw_calls, lights, textures_mb, bones, materials.
const TIER_BUDGETS: Dictionary = {
	Tier.LOW_END: {
		"vertices": 80000,        ## kare başına toplam vertex
		"draw_calls": 80,         ## kare başına draw call
		"lights": 4,              ## aynı anda aktif ışık
		"textures_mb": 128,       ## toplam texture bellek (MB)
		"bones": 48,              ## tek iskelette kemik
		"materials": 24,          ## benzersiz materyal
	},
	Tier.MID_RANGE: {
		"vertices": 200000,
		"draw_calls": 150,
		"lights": 8,
		"textures_mb": 256,
		"bones": 80,
		"materials": 48,
	},
	Tier.HIGH_END: {
		"vertices": 500000,
		"draw_calls": 300,
		"lights": 16,
		"textures_mb": 512,
		"bones": 128,
		"materials": 96,
	},
}

## Aktif hedef profil — varsayılan MID_RANGE.
var tier: int = Tier.MID_RANGE


func _init(p_tier: int = Tier.MID_RANGE) -> void:
	if TIER_NAMES.has(p_tier):
		tier = p_tier


# ============================================================
# BÜTÇE SORGULARI
# ============================================================

## Aktif profilin bütçe sözlüğünü döndürür.
func current_budget() -> Dictionary:
	return TIER_BUDGETS.get(tier, TIER_BUDGETS[Tier.MID_RANGE])


## Belirli bir kaynağın limitini döndürür.
## resource: "vertices" | "draw_calls" | "lights" | "textures_mb" |
##           "bones" | "materials".
## Bilinmeyen kaynak için -1.
func limit_for(resource: String) -> int:
	var budget: Dictionary = current_budget()
	return int(budget.get(resource, -1))


## Bir değerin bütçe içinde olup olmadığını kontrol eder.
## Dönen: {within: bool, limit: int, value: int, ratio: float}
func check_value(resource: String, value: int) -> Dictionary:
	var limit: int = limit_for(resource)
	if limit < 0:
		return {
			"within": false,
			"limit": -1,
			"value": value,
			"ratio": 0.0,
			"error": "Bilinmeyen kaynak: " + resource,
		}
	var ratio: float = float(value) / float(limit) if limit > 0 else 0.0
	return {
		"within": value <= limit,
		"limit": limit,
		"value": value,
		"ratio": ratio,
	}


# ============================================================
# PROFİL YÖNETİMİ
# ============================================================

## Hedef profili ayarlar.
func set_tier(p_tier: int) -> void:
	if TIER_NAMES.has(p_tier):
		tier = p_tier
	else:
		push_warning("MobileBudget: geçersiz tier %d" % p_tier)


## Aktif profilin adı.
func tier_name() -> String:
	return TIER_NAMES.get(tier, "mid_range")


## Bir değerin bütçenin uyarı bölgesinde olup olmadığı.
## warn_threshold (varsayılan 0.8) — limitin bu oranına ulaşınca uyarı.
func is_in_warn_zone(resource: String, value: int, warn_threshold: float = 0.8) -> bool:
	var limit: int = limit_for(resource)
	if limit <= 0:
		return false
	return float(value) >= float(limit) * warn_threshold


## Bütçe özeti — tüm limitler.
func summary() -> Dictionary:
	return {
		"tier": tier_name(),
		"budget": current_budget(),
	}
