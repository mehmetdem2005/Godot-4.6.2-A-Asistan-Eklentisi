@tool
class_name AIAudioGenreRegistry
extends RefCounted

## GenreAudioRegistry — tür ses kayıt defteri (Madde 08 / templates).
##
## Her oyun türünün karakteristik bir ses kimliği vardır: korku oyunu
## boğuk/gergin, retro platformer parlak/8-bit, yarış oyunu güçlü/bas
## ağırlıklı. Geliştirici sıfırdan ses tasarlamak zorunda kalmamalı.
##
## Bu sınıf her tür için hazır bir SES ŞABLONU tutar: hangi bus
## yapısı, hangi EQ profili, hangi sfxr önayarları, hangi müzik
## yoğunluğu varsayılanı.
##
## template_applier bu şablonu alıp gerçek bus/ses kurulumuna çevirir.
##
## Mock policy: şablonlar sabit, tür-uygun ses kimlikleri.

## Tür -> ses şablonu eşlemesi.
## Her şablon: EQ profili, varsayılan sfxr önayarları, bus vurgusu.
const GENRE_AUDIO: Dictionary = {
	"fps_3d": {
		"eq_profile": "punchy",
		"reverb": "medium_hall",
		"default_sfx": ["laser_shoot", "explosion", "hit_hurt"],
		"music_intensity_bias": 0.6,
		"description": "Güçlü, mekânsal, aksiyon odaklı",
	},
	"platformer_2d": {
		"eq_profile": "bright",
		"reverb": "none",
		"default_sfx": ["jump", "pickup_coin", "powerup"],
		"music_intensity_bias": 0.3,
		"description": "Parlak, retro, neşeli",
	},
	"rpg_topdown": {
		"eq_profile": "warm",
		"reverb": "small_room",
		"default_sfx": ["blip_select", "pickup_coin", "powerup"],
		"music_intensity_bias": 0.4,
		"description": "Sıcak, atmosferik, melodik",
	},
	"puzzle": {
		"eq_profile": "clean",
		"reverb": "none",
		"default_sfx": ["blip_select", "powerup"],
		"music_intensity_bias": 0.2,
		"description": "Temiz, sakin, minimal",
	},
	"racing_3d": {
		"eq_profile": "bass_heavy",
		"reverb": "none",
		"default_sfx": ["engine_loop", "alarm"],
		"music_intensity_bias": 0.7,
		"description": "Bas ağırlıklı, enerjik, hızlı",
	},
	"survival_3d": {
		"eq_profile": "natural",
		"reverb": "outdoor",
		"default_sfx": ["footstep", "hit_hurt", "pickup_coin"],
		"music_intensity_bias": 0.35,
		"description": "Doğal, atmosferik, gergin",
	},
	"horror_3d": {
		"eq_profile": "muffled",
		"reverb": "large_hall",
		"default_sfx": ["footstep", "alarm", "hit_hurt"],
		"music_intensity_bias": 0.25,
		"description": "Boğuk, gergin, ürkütücü",
	},
	"visual_novel": {
		"eq_profile": "clean",
		"reverb": "small_room",
		"default_sfx": ["blip_select"],
		"music_intensity_bias": 0.3,
		"description": "Temiz, duygusal, diyalog odaklı",
	},
	"strategy_isometric": {
		"eq_profile": "balanced",
		"reverb": "medium_hall",
		"default_sfx": ["blip_select", "alarm", "powerup"],
		"music_intensity_bias": 0.4,
		"description": "Dengeli, görkemli, düşünceli",
	},
}


# ============================================================
# ŞABLON ERİŞİMİ
# ============================================================

## Bir tür için ses şablonu kayıtlı mı?
func has_genre(genre_name: String) -> bool:
	return GENRE_AUDIO.has(genre_name)


## Bir tür için ses şablonunu döndürür. Yoksa boş sözlük.
func get_template(genre_name: String) -> Dictionary:
	if not GENRE_AUDIO.has(genre_name):
		return {}
	return (GENRE_AUDIO[genre_name] as Dictionary).duplicate(true)


## Bir türün ses kimliği açıklamasını döndürür.
func describe(genre_name: String) -> String:
	if not GENRE_AUDIO.has(genre_name):
		return ""
	return str(GENRE_AUDIO[genre_name]["description"])


## Bir tür için önerilen sfxr önayarlarını döndürür.
func default_sfx_for(genre_name: String) -> PackedStringArray:
	if not GENRE_AUDIO.has(genre_name):
		return PackedStringArray()
	var sfx: Array = GENRE_AUDIO[genre_name]["default_sfx"]
	return PackedStringArray(sfx)


# ============================================================
# SORGULAMA
# ============================================================

## Kayıtlı tüm tür adları.
func genre_names() -> Array:
	var names: Array = GENRE_AUDIO.keys()
	names.sort()
	return names


## Kayıtlı tür şablonu sayısı.
func genre_count() -> int:
	return GENRE_AUDIO.size()


## Bir türün varsayılan müzik yoğunluğu eğilimini döndürür.
func intensity_bias(genre_name: String) -> float:
	if not GENRE_AUDIO.has(genre_name):
		return 0.5
	return float(GENRE_AUDIO[genre_name]["music_intensity_bias"])
