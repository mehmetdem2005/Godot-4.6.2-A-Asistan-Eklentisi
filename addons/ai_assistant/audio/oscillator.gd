@tool
class_name AIAudioOscillator
extends RefCounted

## Oscillator — dalga formu üreteci (Madde 08 / procedural_synth).
##
## Prosedürel ses üretiminin temeli: bir frekansta periyodik dalga
## üreten birim. Tüm sentezlenmiş sesler bununla başlar.
##
## Dört temel dalga formu:
##   SINE     — saf ton, yumuşak (flüt benzeri)
##   SQUARE   — sert, retro (8-bit oyun sesi)
##   SAW      — parlak, zengin (synth bass)
##   TRIANGLE — yumuşak ama biraz parlak (yumuşak bleep)
##
## Bir örnek (sample) tek bir an için dalga değeridir (-1..1).
## Bir ses, binlerce örneğin saniyede dizilmesidir.
##
## Bu sınıf saf DSP matematiğidir — Godot gerektirmez, tam test
## edilebilir.
##
## Mock policy: örnek değerleri gerçek dalga matematiğinden.

## Dalga formu tipleri.
enum Waveform { SINE, SQUARE, SAW, TRIANGLE }

const WAVEFORM_NAMES: Dictionary = {
	Waveform.SINE: "sine",
	Waveform.SQUARE: "square",
	Waveform.SAW: "saw",
	Waveform.TRIANGLE: "triangle",
}

## Standart örnekleme hızı (saniyedeki örnek sayısı).
const SAMPLE_RATE: int = 44100


## Dalga formu.
var waveform: int = Waveform.SINE

## Frekans (Hz) — saniyedeki titreşim sayısı.
var frequency: float = 440.0  # A4 notası

## Genlik (0-1) — sesin yüksekliği.
var amplitude: float = 1.0


func _init(
	p_waveform: int = Waveform.SINE, p_frequency: float = 440.0
) -> void:
	if WAVEFORM_NAMES.has(p_waveform):
		waveform = p_waveform
	frequency = maxf(p_frequency, 0.0)


# ============================================================
# ÖRNEK ÜRETİMİ
# ============================================================

## Belirli bir fazda (0-1 arası) tek bir dalga örneği üretir.
## phase: dalga döngüsündeki konum (0.0 = başlangıç, 1.0 = tam tur).
## Dönen: örnek değeri (-amplitude .. +amplitude).
func sample_at_phase(phase: float) -> float:
	# Fazı 0-1 aralığına sar
	var p: float = fposmod(phase, 1.0)
	var value: float = 0.0

	match waveform:
		Waveform.SINE:
			value = sin(p * TAU)
		Waveform.SQUARE:
			# İlk yarı +1, ikinci yarı -1
			value = 1.0 if p < 0.5 else -1.0
		Waveform.SAW:
			# 0'da -1, 1'de +1 — doğrusal yükseliş
			value = (p * 2.0) - 1.0
		Waveform.TRIANGLE:
			# 0'da -1, 0.5'te +1, 1'de -1
			if p < 0.5:
				value = (p * 4.0) - 1.0
			else:
				value = 3.0 - (p * 4.0)
		_:
			value = 0.0

	return value * amplitude


## Belirli bir zaman anında (saniye) örnek üretir.
## time_seconds: ses başından bu yana geçen süre.
func sample_at_time(time_seconds: float) -> float:
	# Zaman * frekans = kaç tam döngü geçti; ondalık kısmı faz
	var phase: float = time_seconds * frequency
	return sample_at_phase(phase)


## Bir örnek tamponu üretir — belirli sayıda ardışık örnek.
## sample_count: üretilecek örnek sayısı.
## start_time: tamponun başlangıç zamanı (saniye).
## Dönen: örnek dizisi.
func generate_buffer(
	sample_count: int, start_time: float = 0.0
) -> PackedFloat32Array:
	var buffer: PackedFloat32Array = PackedFloat32Array()
	if sample_count <= 0:
		return buffer
	var time_step: float = 1.0 / float(SAMPLE_RATE)
	for i in range(sample_count):
		var t: float = start_time + float(i) * time_step
		buffer.append(sample_at_time(t))
	return buffer


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut dalga formunun adı.
func waveform_name() -> String:
	return WAVEFORM_NAMES.get(waveform, "?")


## Bir frekansın bir saniyede kaç tam döngü yaptığı.
func cycles_per_second() -> float:
	return frequency


## Bir tam dalga döngüsünün süresi (saniye).
func period() -> float:
	if frequency <= 0.0:
		return 0.0
	return 1.0 / frequency
