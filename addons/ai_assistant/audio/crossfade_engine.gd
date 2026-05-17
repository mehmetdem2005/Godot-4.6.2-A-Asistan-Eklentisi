@tool
class_name AIAudioCrossfadeEngine
extends RefCounted

## CrossfadeEngine — çapraz geçiş motoru (Madde 08 / music_layering).
##
## Müzik bir parçadan diğerine geçerken ANİ kesinti kötü duyulur.
## Çapraz geçiş (crossfade): eski parça yavaşça susarken yeni parça
## yavaşça yükselir — iki ses bir an üst üste biner, geçiş duyulmaz.
##
## Bu sınıf geçişin her anında iki sesin SES SEVİYESİNİ hesaplar:
## "şu anda eski %30, yeni %70 sesle çalmalı".
##
## Geçiş eğrisi önemli: doğrusal geçişte ortada ses düşer (iki ses
## de yarı seviyede). Eşit-güç (equal-power) eğrisi bunu düzeltir —
## toplam algılanan ses sabit kalır.
##
## Bu sınıf saf matematiktir — Godot gerektirmez.
##
## Mock policy: ses seviyeleri gerçek geçiş matematiğinden.

## Geçiş eğrisi tipleri.
enum FadeCurve { LINEAR, EQUAL_POWER }

const CURVE_NAMES: Dictionary = {
	FadeCurve.LINEAR: "linear",
	FadeCurve.EQUAL_POWER: "equal_power",
}


## Geçiş süresi (saniye).
var duration: float = 2.0

## Geçiş eğrisi.
var curve: int = FadeCurve.EQUAL_POWER

## Geçişin başından bu yana geçen süre.
var elapsed: float = 0.0

## Geçiş aktif mi.
var _active: bool = false


func _init(p_duration: float = 2.0) -> void:
	duration = maxf(p_duration, 0.01)


# ============================================================
# GEÇİŞ KONTROLÜ
# ============================================================

## Bir çapraz geçiş başlatır.
func start() -> void:
	elapsed = 0.0
	_active = true


## Zamanı ilerletir.
func tick(delta_seconds: float) -> void:
	if not _active or delta_seconds < 0.0:
		return
	elapsed += delta_seconds
	if elapsed >= duration:
		elapsed = duration
		_active = false


## Geçiş ilerlemesi (0 = başlangıç, 1 = tamamlandı).
func progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)


# ============================================================
# SES SEVİYELERİ
# ============================================================

## Geçişin şu anki ilerlemesinde ESKİ sesin seviyesini hesaplar.
## Dönen: ses çarpanı (0-1).
func fade_out_level() -> float:
	var p: float = progress()
	if curve == FadeCurve.EQUAL_POWER:
		# Eşit-güç: cos eğrisi — toplam güç sabit
		return cos(p * PI * 0.5)
	# Doğrusal: 1'den 0'a düz iniş
	return 1.0 - p


## Geçişin şu anki ilerlemesinde YENİ sesin seviyesini hesaplar.
## Dönen: ses çarpanı (0-1).
func fade_in_level() -> float:
	var p: float = progress()
	if curve == FadeCurve.EQUAL_POWER:
		# Eşit-güç: sin eğrisi
		return sin(p * PI * 0.5)
	# Doğrusal: 0'dan 1'e düz yükseliş
	return p


## Her iki ses seviyesini birlikte döndürür.
## Dönen: {out_level: float, in_level: float}
func levels() -> Dictionary:
	return {
		"out_level": fade_out_level(),
		"in_level": fade_in_level(),
	}


## Geçiş ortasında toplam algılanan gücü hesaplar.
## Eşit-güç eğrisinde ~1.0 olmalı; doğrusalda ortada düşer.
func combined_power() -> float:
	var out_l: float = fade_out_level()
	var in_l: float = fade_in_level()
	# Güç = seviyelerin karelerinin toplamının karekökü
	return sqrt(out_l * out_l + in_l * in_l)


# ============================================================
# SORGULAMA
# ============================================================

## Geçiş hâlâ devam ediyor mu?
func is_active() -> bool:
	return _active


## Geçiş tamamlandı mı?
func is_complete() -> bool:
	return not _active and elapsed >= duration


## Eğri adı.
func curve_name() -> String:
	return CURVE_NAMES.get(curve, "?")
