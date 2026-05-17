@tool
class_name AISaveVersionChecker
extends RefCounted

## VersionCompatibilityChecker — sürüm uyumluluk denetçisi (Madde 09).
##
## Oyun güncellenir, kayıt şeması değişir. Eski kayıt yeni oyunda
## açılınca: uyumlu mu? Bu sınıf kayıt sürümü ile oyun sürümünü
## karşılaştırır ve üç sonuçtan birini verir:
##
##   COMPATIBLE   — aynı sürüm, doğrudan yüklenebilir
##   NEEDS_MIGRATION — eski kayıt, geçiş (migration) gerekli
##   TOO_NEW      — kayıt oyundan yeni (oyuncu downgrade yapmış?)
##                  — yüklenemez, veri kaybı riski
##
## Semantic sürümleme: major.minor. Major değişimi kırıcıdır,
## minor geriye uyumludur.
##
## Mock policy: karar gerçek sürüm karşılaştırmasından.

## Uyumluluk sonuçları.
enum Compatibility { COMPATIBLE, NEEDS_MIGRATION, TOO_NEW, INVALID }

const COMPAT_NAMES: Dictionary = {
	Compatibility.COMPATIBLE: "compatible",
	Compatibility.NEEDS_MIGRATION: "needs_migration",
	Compatibility.TOO_NEW: "too_new",
	Compatibility.INVALID: "invalid",
}


## Oyunun mevcut şema sürümü.
var current_version: int = 1


func _init(p_current_version: int = 1) -> void:
	current_version = maxi(p_current_version, 1)


# ============================================================
# UYUMLULUK KONTROLÜ
# ============================================================

## Bir kayıt sürümünü mevcut oyun sürümüyle karşılaştırır.
## save_version: kayıt dosyasındaki şema sürümü.
## Dönen: {compatibility: String, can_load: bool, reason: String}
func check(save_version: int) -> Dictionary:
	# Geçersiz sürüm
	if save_version < 1:
		return {
			"compatibility": COMPAT_NAMES[Compatibility.INVALID],
			"can_load": false,
			"reason": "Geçersiz kayıt sürümü: %d" % save_version,
		}

	# Aynı sürüm — doğrudan uyumlu
	if save_version == current_version:
		return {
			"compatibility": COMPAT_NAMES[Compatibility.COMPATIBLE],
			"can_load": true,
			"reason": "Kayıt güncel sürümle uyumlu",
		}

	# Kayıt eski — geçiş gerekli
	if save_version < current_version:
		return {
			"compatibility": COMPAT_NAMES[Compatibility.NEEDS_MIGRATION],
			"can_load": true,
			"reason": "Eski kayıt (v%d -> v%d) — geçiş gerekli" % [
				save_version, current_version
			],
		}

	# Kayıt oyundan yeni — yüklenemez
	return {
		"compatibility": COMPAT_NAMES[Compatibility.TOO_NEW],
		"can_load": false,
		"reason": "Kayıt oyundan yeni (v%d > v%d) — yüklenemez" % [
			save_version, current_version
		],
	}


# ============================================================
# SORGULAMA
# ============================================================

## Bir kayıt sürümü yüklenebilir mi (geçişle veya doğrudan)?
func can_load(save_version: int) -> bool:
	return bool(check(save_version)["can_load"])


## Bir kayıt sürümü geçiş gerektiriyor mu?
func needs_migration(save_version: int) -> bool:
	var result: Dictionary = check(save_version)
	return str(result["compatibility"]) == COMPAT_NAMES[
		Compatibility.NEEDS_MIGRATION
	]


## Kayıt sürümü oyundan yeni mi (yüklenemez)?
func is_too_new(save_version: int) -> bool:
	var result: Dictionary = check(save_version)
	return str(result["compatibility"]) == COMPAT_NAMES[
		Compatibility.TOO_NEW
	]


## Kaç sürüm geriden geliyor? (geçiş adımı sayısı)
func version_gap(save_version: int) -> int:
	if save_version >= current_version:
		return 0
	return current_version - save_version
