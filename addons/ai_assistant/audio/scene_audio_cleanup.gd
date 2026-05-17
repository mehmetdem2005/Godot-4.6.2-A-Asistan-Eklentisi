@tool
class_name AIAudioSceneCleanup
extends RefCounted

## SceneAudioCleanup — sahne ses temizliği (Madde 08 / lifecycle).
##
## Oyun bir sahneden diğerine geçer (menü -> oyun -> menü). Eski
## sahnenin sesleri TEMİZLENMELİ — yoksa yeni sahnede hâlâ eski
## ses çalar, bellek sızar.
##
## Ama dikkat: bazı sesler sahne geçişinde DEVAM ETMELİDİR — ana
## menü müziği, ortam müziği. Hepsini kapatmak kaba olur.
##
## Bu sınıf bir sahne geçişinde her sesin ne olacağını belirler:
##   STOP      — sahneye özel ses, durdurulmalı
##   KEEP      — kalıcı ses (müzik), devam etmeli
##   FADE_OUT  — yumuşakça susmalı (çarpıcı kesinti olmasın)
##
## Mock policy: temizlik kararı gerçek ses kategorisinden.

## Bir ses için sahne geçiş eylemi.
enum CleanupAction { STOP, KEEP, FADE_OUT }

const ACTION_NAMES: Dictionary = {
	CleanupAction.STOP: "stop",
	CleanupAction.KEEP: "keep",
	CleanupAction.FADE_OUT: "fade_out",
}

## Ses kategorileri ve sahne geçiş davranışları.
const CATEGORY_BEHAVIOR: Dictionary = {
	"sfx": CleanupAction.STOP,            # ses efekti — anında dur
	"ambient": CleanupAction.FADE_OUT,    # ortam sesi — yumuşak sus
	"music": CleanupAction.KEEP,          # müzik — devam et
	"ui": CleanupAction.STOP,             # arayüz sesi — dur
	"voice": CleanupAction.FADE_OUT,      # diyalog — yumuşak sus
}


## Kayıtlı aktif sesler — sound_id -> kategori.
var _active_sounds: Dictionary = {}


# ============================================================
# SES KAYDI
# ============================================================

## Aktif bir ses kaydeder.
## sound_id: ses kimliği. category: ses kategorisi.
func register_sound(sound_id: String, category: String) -> void:
	if sound_id.is_empty():
		return
	_active_sounds[sound_id] = category


## Bir sesi kayıttan çıkarır.
func unregister_sound(sound_id: String) -> void:
	_active_sounds.erase(sound_id)


## Aktif ses sayısı.
func active_count() -> int:
	return _active_sounds.size()


# ============================================================
# SAHNE GEÇİŞ PLANI
# ============================================================

## Bir sahne geçişi için temizlik planı üretir.
## Her aktif ses için ne yapılacağını belirler.
## Dönen: {stop, keep, fade_out} listeleri içeren plan.
func build_cleanup_plan() -> Dictionary:
	var to_stop: PackedStringArray = PackedStringArray()
	var to_keep: PackedStringArray = PackedStringArray()
	var to_fade: PackedStringArray = PackedStringArray()

	for sound_id in _active_sounds:
		var category: String = str(_active_sounds[sound_id])
		var action: int = action_for_category(category)
		match action:
			CleanupAction.STOP:
				to_stop.append(sound_id)
			CleanupAction.KEEP:
				to_keep.append(sound_id)
			CleanupAction.FADE_OUT:
				to_fade.append(sound_id)

	return {
		"stop": to_stop,
		"keep": to_keep,
		"fade_out": to_fade,
		"total": _active_sounds.size(),
	}


## Bir ses kategorisi için sahne geçiş eylemini döndürür.
## Bilinmeyen kategori — güvenli taraf, STOP.
func action_for_category(category: String) -> int:
	return int(CATEGORY_BEHAVIOR.get(category, CleanupAction.STOP))


## Bir temizlik planını uygular — durdurulan/susan sesleri kayıttan
## çıkarır, kalanları tutar.
## plan: build_cleanup_plan'in çıktısı.
func apply_cleanup(plan: Dictionary) -> void:
	# Durdurulanları ve susanları kayıttan çıkar
	var stopped: PackedStringArray = plan.get("stop", PackedStringArray())
	var faded: PackedStringArray = plan.get(
		"fade_out", PackedStringArray()
	)
	for sound_id in stopped:
		_active_sounds.erase(sound_id)
	for sound_id in faded:
		_active_sounds.erase(sound_id)
	# 'keep' sesleri kayıtta kalır


# ============================================================
# SORGULAMA
# ============================================================

## Bir eylemin adı.
func action_name(action: int) -> String:
	return ACTION_NAMES.get(action, "?")


## Sahne geçişinde kaç ses durdurulacak/susacak?
func cleanup_count() -> int:
	var count: int = 0
	for sound_id in _active_sounds:
		var action: int = action_for_category(
			str(_active_sounds[sound_id])
		)
		if action != CleanupAction.KEEP:
			count += 1
	return count
