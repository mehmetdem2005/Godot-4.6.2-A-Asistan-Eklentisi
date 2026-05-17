@tool
class_name AIAudioSfxrPresets
extends RefCounted

## SfxrPresets — retro ses önayarları (Madde 08 / procedural_synth).
##
## Sfxr, retro oyun ses efektleri üretmenin klasik yöntemidir:
## birkaç parametre ayarla, 8-bit "bleep bloop" sesi çıksın. Bu
## sınıf 10 hazır önayar tutar — oyuncu tek tıkla kullanıma hazır
## ses alır, sıfırdan sentez bilmesi gerekmez.
##
## Her önayar bir parametre seti: dalga formu, frekans, ADSR zarfı,
## frekans kayması (slide), filtre. synth_engine bu parametreleri
## alıp gerçek ses tamponu üretir.
##
## LLM gerektirmez — tamamen deterministik, ücretsiz, anında.
##
## Mock policy: önayarlar sabit, denenmiş retro ses parametreleri.

## 10 retro önayar — id -> parametre sözlüğü.
const PRESETS: Dictionary = {
	"pickup_coin": {
		"waveform": "square", "frequency": 880.0,
		"attack": 0.0, "decay": 0.05, "sustain": 0.3, "release": 0.1,
		"freq_slide": 400.0, "description": "Para/eşya toplama",
	},
	"laser_shoot": {
		"waveform": "saw", "frequency": 1200.0,
		"attack": 0.0, "decay": 0.1, "sustain": 0.2, "release": 0.1,
		"freq_slide": -800.0, "description": "Lazer/mermi atışı",
	},
	"explosion": {
		"waveform": "noise", "frequency": 200.0,
		"attack": 0.0, "decay": 0.2, "sustain": 0.4, "release": 0.4,
		"freq_slide": -150.0, "description": "Patlama",
	},
	"powerup": {
		"waveform": "square", "frequency": 440.0,
		"attack": 0.01, "decay": 0.1, "sustain": 0.6, "release": 0.2,
		"freq_slide": 600.0, "description": "Güçlenme/yükseltme",
	},
	"hit_hurt": {
		"waveform": "noise", "frequency": 400.0,
		"attack": 0.0, "decay": 0.08, "sustain": 0.2, "release": 0.1,
		"freq_slide": -200.0, "description": "Hasar alma",
	},
	"jump": {
		"waveform": "square", "frequency": 300.0,
		"attack": 0.0, "decay": 0.05, "sustain": 0.4, "release": 0.1,
		"freq_slide": 350.0, "description": "Zıplama",
	},
	"blip_select": {
		"waveform": "square", "frequency": 600.0,
		"attack": 0.0, "decay": 0.02, "sustain": 0.5, "release": 0.03,
		"freq_slide": 0.0, "description": "Menü seçim sesi",
	},
	"engine_loop": {
		"waveform": "saw", "frequency": 80.0,
		"attack": 0.1, "decay": 0.1, "sustain": 0.8, "release": 0.2,
		"freq_slide": 0.0, "description": "Motor/araç döngüsü",
	},
	"alarm": {
		"waveform": "triangle", "frequency": 660.0,
		"attack": 0.02, "decay": 0.05, "sustain": 0.7, "release": 0.1,
		"freq_slide": 0.0, "description": "Alarm/uyarı",
	},
	"footstep": {
		"waveform": "noise", "frequency": 150.0,
		"attack": 0.0, "decay": 0.04, "sustain": 0.1, "release": 0.05,
		"freq_slide": -50.0, "description": "Ayak sesi",
	},
}


# ============================================================
# ÖNAYAR ERİŞİMİ
# ============================================================

## Bir önayar tanımlı mı?
func has_preset(preset_id: String) -> bool:
	return PRESETS.has(preset_id)


## Tüm önayar kimlikleri.
func preset_ids() -> Array:
	return PRESETS.keys()


## Bir önayarın parametrelerini döndürür. Yoksa boş sözlük.
func get_preset(preset_id: String) -> Dictionary:
	if not PRESETS.has(preset_id):
		return {}
	# Kopya döndür — çağıran değiştirebilsin, sabit bozulmasın
	return (PRESETS[preset_id] as Dictionary).duplicate(true)


## Bir önayarın açıklamasını döndürür.
func describe(preset_id: String) -> String:
	if not PRESETS.has(preset_id):
		return ""
	return str(PRESETS[preset_id]["description"])


# ============================================================
# ÖZELLEŞTİRME
# ============================================================

## Bir önayarı temel alıp belirli parametreleri değiştirir.
## preset_id: temel önayar. overrides: değiştirilecek parametreler.
## Dönen: özelleştirilmiş parametre sözlüğü.
func customize(preset_id: String, overrides: Dictionary) -> Dictionary:
	var params: Dictionary = get_preset(preset_id)
	if params.is_empty():
		return {}
	for key in overrides:
		# Sadece var olan parametreler değiştirilebilir
		if params.has(key):
			params[key] = overrides[key]
	return params


## Toplam önayar sayısı.
func preset_count() -> int:
	return PRESETS.size()
