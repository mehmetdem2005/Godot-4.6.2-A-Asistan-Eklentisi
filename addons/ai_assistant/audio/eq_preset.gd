@tool
class_name AIAudioEQPreset
extends RefCounted

## EQPreset — ekolayzer ön ayarları (Madde 08 / Audio System).
##
## EQ (ekolayzer) sesin frekans dengesini ayarlar — bası artır, tizi
## kıs gibi. Oyunda bağlama göre EQ değişir: su altında sesler boğuk
## (tiz düşük), mağarada yankılı, savaşta net ve keskin.
##
## Bu sınıf hazır EQ profilleri sunar. Her profil bir frekans bandı
## kazanç (dB) seti. Gerçek AudioEffectEQ kurulumu Node sarmalayıcının
## işi; bu model test edilebilir profil tanımıdır.
##
## Standart 6 bant: alt-bas, bas, alt-orta, orta, üst-orta, tiz.
##
## Mock policy: profiller sabit, makul ses mühendisliği değerleri.

## Frekans bantları — düşükten yükseğe.
const BANDS: Array = [
	"sub_bass",    ## ~60 Hz   — derin bas
	"bass",        ## ~150 Hz  — bas
	"low_mid",     ## ~400 Hz  — alt orta
	"mid",         ## ~1 kHz   — orta (vokal netliği)
	"high_mid",    ## ~3 kHz   — üst orta (parlaklık)
	"treble",      ## ~8 kHz   — tiz
]

## Bant kazanç sınırları (dB).
const MIN_GAIN: float = -24.0
const MAX_GAIN: float = 12.0

## Hazır EQ profilleri — her biri 6 bant kazanç sözlüğü (dB).
const PRESETS: Dictionary = {
	"flat": {
		"sub_bass": 0.0, "bass": 0.0, "low_mid": 0.0,
		"mid": 0.0, "high_mid": 0.0, "treble": 0.0,
	},
	"underwater": {  # boğuk — tizler kesik
		"sub_bass": 2.0, "bass": 1.0, "low_mid": -2.0,
		"mid": -6.0, "high_mid": -12.0, "treble": -18.0,
	},
	"cave": {  # yankılı — orta vurgulu
		"sub_bass": 1.0, "bass": 2.0, "low_mid": 3.0,
		"mid": 2.0, "high_mid": -2.0, "treble": -4.0,
	},
	"combat": {  # net, keskin — orta + üst-orta vurgu
		"sub_bass": 0.0, "bass": 1.0, "low_mid": -1.0,
		"mid": 3.0, "high_mid": 4.0, "treble": 2.0,
	},
	"radio": {  # telefon/radyo — bas ve tiz kesik
		"sub_bass": -18.0, "bass": -8.0, "low_mid": 2.0,
		"mid": 4.0, "high_mid": 3.0, "treble": -10.0,
	},
}


# ============================================================
# PROFİL ERİŞİMİ
# ============================================================

## Bir profilin bant kazançlarını döndürür.
## Tanımsız profil için flat (düz) döner.
func get_preset(preset_name: String) -> Dictionary:
	if PRESETS.has(preset_name):
		return PRESETS[preset_name].duplicate()
	return PRESETS["flat"].duplicate()


## Bir profil tanımlı mı?
func has_preset(preset_name: String) -> bool:
	return PRESETS.has(preset_name)


## Tüm profil adları.
func preset_names() -> Array:
	return PRESETS.keys()


## Bir profildeki belirli bir bandın kazancını döndürür.
func band_gain(preset_name: String, band: String) -> float:
	var preset: Dictionary = get_preset(preset_name)
	return float(preset.get(band, 0.0))


# ============================================================
# ÖZEL PROFİL
# ============================================================

## Bir bant kazanç sözlüğünü doğrular ve sınırlar.
## custom_bands: {band: gain} — eksik bantlar 0.0 alır, sınır dışı
## değerler kırpılır.
## Dönen: 6 bandın hepsini içeren, sınırlanmış sözlük.
func sanitize_custom(custom_bands: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for band in BANDS:
		var raw: float = float(custom_bands.get(band, 0.0))
		result[band] = clampf(raw, MIN_GAIN, MAX_GAIN)
	return result


## İki profil arasında geçiş (interpolasyon) — yumuşak EQ değişimi.
## from_preset / to_preset: profil adları. t: 0.0-1.0 geçiş oranı.
## Dönen: ara profil bant sözlüğü.
func blend(from_preset: String, to_preset: String, t: float) -> Dictionary:
	var from_bands: Dictionary = get_preset(from_preset)
	var to_bands: Dictionary = get_preset(to_preset)
	var clamped_t: float = clampf(t, 0.0, 1.0)
	var result: Dictionary = {}
	for band in BANDS:
		var a: float = float(from_bands.get(band, 0.0))
		var b: float = float(to_bands.get(band, 0.0))
		result[band] = lerpf(a, b, clamped_t)
	return result
