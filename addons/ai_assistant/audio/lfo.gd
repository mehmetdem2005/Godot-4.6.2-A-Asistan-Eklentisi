@tool
class_name AIAudioLFO
extends RefCounted

## LFO — düşük frekanslı osilatör (Madde 08 / procedural_synth).
##
## LFO (Low Frequency Oscillator) ses ÜRETMEZ — başka bir parametreyi
## YAVAŞÇA dalgalandırır. Duyulamayacak kadar yavaştır (genelde
## 0.1-20 Hz) ama etkisi duyulur:
##   - frekansı dalgalandır  -> vibrato (titreşen perde)
##   - genliği dalgalandır   -> tremolo (titreşen ses yüksekliği)
##   - filtre kesimini dalgalandır -> "wah" süpürme efekti
##
## Bir oscillator ile aynı dalga formlarını kullanır ama çok düşük
## frekansta ve bir değer aralığına eşlenmiş halde.
##
## Bu sınıf saf matematiktir — Godot gerektirmez.
##
## Mock policy: modülasyon değeri gerçek LFO matematiğinden.

## LFO çıkışını eşlemek için temel oscillator dalga formları.
enum LFOWaveform { SINE, TRIANGLE, SQUARE, SAW }

const WAVEFORM_NAMES: Dictionary = {
	LFOWaveform.SINE: "sine",
	LFOWaveform.TRIANGLE: "triangle",
	LFOWaveform.SQUARE: "square",
	LFOWaveform.SAW: "saw",
}


## LFO dalga formu.
var waveform: int = LFOWaveform.SINE

## LFO frekansı (Hz) — saniyedeki dalgalanma sayısı.
var rate: float = 5.0

## Modülasyon derinliği (0-1) — etkinin gücü.
var depth: float = 1.0


func _init(p_rate: float = 5.0, p_depth: float = 1.0) -> void:
	rate = clampf(p_rate, 0.01, 100.0)
	depth = clampf(p_depth, 0.0, 1.0)


# ============================================================
# MODÜLASYON DEĞERİ
# ============================================================

## Bir zaman anında LFO'nun ham çıkışını hesaplar (-1..1).
## time_seconds: ses başından bu yana geçen süre.
func raw_value(time_seconds: float) -> float:
	var phase: float = fposmod(time_seconds * rate, 1.0)
	var value: float = 0.0

	match waveform:
		LFOWaveform.SINE:
			value = sin(phase * TAU)
		LFOWaveform.TRIANGLE:
			if phase < 0.5:
				value = (phase * 4.0) - 1.0
			else:
				value = 3.0 - (phase * 4.0)
		LFOWaveform.SQUARE:
			value = 1.0 if phase < 0.5 else -1.0
		LFOWaveform.SAW:
			value = (phase * 2.0) - 1.0
		_:
			value = 0.0

	return value * depth


## LFO çıkışını belirli bir değer aralığına eşler.
## time_seconds: zaman. base_value: modüle edilen temel değer.
## modulation_range: dalgalanma genişliği.
## Dönen: base_value ± (modulation_range yarısı kadar) dalgalanmış.
func modulate(
	time_seconds: float, base_value: float, modulation_range: float
) -> float:
	var lfo: float = raw_value(time_seconds)  # -1..1
	# Yarı aralık kadar yukarı/aşağı dalgalan
	return base_value + lfo * (modulation_range * 0.5)


## LFO çıkışını 0-1 aralığına eşler (negatif olmayan modülasyon için).
## Tremolo gibi — genlik 0 altına inemez.
func unipolar_value(time_seconds: float) -> float:
	var bipolar: float = raw_value(time_seconds)  # -1..1
	# -1..1 -> 0..1
	return (bipolar + 1.0) * 0.5


# ============================================================
# SORGULAMA
# ============================================================

## Dalga formunun adı.
func waveform_name() -> String:
	return WAVEFORM_NAMES.get(waveform, "?")


## Bir tam LFO döngüsünün süresi (saniye).
func cycle_duration() -> float:
	if rate <= 0.0:
		return 0.0
	return 1.0 / rate
