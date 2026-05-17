@tool
class_name AILifecycleOrientationHandler
extends RefCounted

## OrientationHandler — ekran yönü yöneticisi (Madde 10 / Lifecycle).
##
## Telefon çevrilince ekran döner: dikey (portrait) <-> yatay
## (landscape). Oyun buna tepki vermeli — arayüz yeniden
## yerleşmeli, kamera oranı değişmeli.
##
## Bazı oyunlar sadece tek yönde çalışır (kilitli); bazıları her
## ikisini destekler. Bu sınıf yön durumunu izler, KİLİT politikasını
## uygular ve değişimleri bildirir.
##
## Mock policy: yön dışarıdan bildirilir; sınıf kilit/değişim
## mantığını uygular.

## Ekran yönleri.
enum Orientation { PORTRAIT, LANDSCAPE, PORTRAIT_FLIPPED, LANDSCAPE_FLIPPED }

const ORIENTATION_NAMES: Dictionary = {
	Orientation.PORTRAIT: "portrait",
	Orientation.LANDSCAPE: "landscape",
	Orientation.PORTRAIT_FLIPPED: "portrait_flipped",
	Orientation.LANDSCAPE_FLIPPED: "landscape_flipped",
}

## Yön kilidi politikası.
enum LockPolicy { ANY, PORTRAIT_ONLY, LANDSCAPE_ONLY }


## Mevcut yön.
var current_orientation: int = Orientation.PORTRAIT

## Kilit politikası.
var lock_policy: int = LockPolicy.ANY


# ============================================================
# KİLİT POLİTİKASI
# ============================================================

## Kilit politikasını ayarlar.
func set_lock_policy(policy: int) -> void:
	if policy == LockPolicy.ANY or policy == LockPolicy.PORTRAIT_ONLY \
			or policy == LockPolicy.LANDSCAPE_ONLY:
		lock_policy = policy


## Bir yön mevcut politikada izinli mi?
func is_orientation_allowed(orientation: int) -> bool:
	match lock_policy:
		LockPolicy.PORTRAIT_ONLY:
			return orientation == Orientation.PORTRAIT \
				or orientation == Orientation.PORTRAIT_FLIPPED
		LockPolicy.LANDSCAPE_ONLY:
			return orientation == Orientation.LANDSCAPE \
				or orientation == Orientation.LANDSCAPE_FLIPPED
		_:
			return true  # ANY — hepsi izinli


# ============================================================
# YÖN DEĞİŞİMİ
# ============================================================

## Bir yön değişimi denemesi.
## new_orientation: cihazın yeni fiziksel yönü.
## Dönen: {applied: bool, orientation: String, reason: String}
##   applied=false: kilit politikası bu yönü engelledi.
func handle_change(new_orientation: int) -> Dictionary:
	if not ORIENTATION_NAMES.has(new_orientation):
		return {
			"applied": false, "orientation": orientation_name(),
			"reason": "Geçersiz yön",
		}

	# Kilit politikası izin veriyor mu
	if not is_orientation_allowed(new_orientation):
		return {
			"applied": false,
			"orientation": orientation_name(),
			"reason": "Kilit politikası bu yönü engelliyor",
		}

	# Değişiklik var mı
	if new_orientation == current_orientation:
		return {
			"applied": true, "orientation": orientation_name(),
			"reason": "Yön değişmedi",
		}

	current_orientation = new_orientation
	return {
		"applied": true,
		"orientation": ORIENTATION_NAMES[new_orientation],
		"reason": "Yön değişti",
	}


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut yönün adı.
func orientation_name() -> String:
	return ORIENTATION_NAMES.get(current_orientation, "?")


## Mevcut yön yatay mı?
func is_landscape() -> bool:
	return current_orientation == Orientation.LANDSCAPE \
		or current_orientation == Orientation.LANDSCAPE_FLIPPED


## Mevcut yön dikey mi?
func is_portrait() -> bool:
	return current_orientation == Orientation.PORTRAIT \
		or current_orientation == Orientation.PORTRAIT_FLIPPED


## Durum özeti.
func summary() -> Dictionary:
	return {
		"orientation": orientation_name(),
		"is_landscape": is_landscape(),
		"lock_policy": lock_policy,
	}
