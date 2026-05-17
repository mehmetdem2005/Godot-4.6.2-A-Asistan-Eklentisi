@tool
class_name AIAudioSampleBuffer
extends RefCounted

## SampleBuffer — ses tamponu matematiği (Madde 08 / procedural_synth).
##
## Sentezlenmiş ses bir ÖRNEK DİZİSİDİR. Bu sınıf o dizi üzerinde
## yaygın işlemleri yapar: normalize et, karıştır (mix), kes,
## fade uygula, sessizlik ekle.
##
## Neden gerekli: oscillator + noise + envelope ayrı tamponlar üretir;
## bunları birleştirmek, dengelemek, kırpmak gerekir. Klipleme
## (clipping) önemli — örnekler -1..1 dışına çıkarsa ses bozulur.
##
## Bu sınıf saf matematiktir — Godot gerektirmez.
##
## Mock policy: tampon işlemleri gerçek örnek matematiğinden.

const SAMPLE_RATE: int = 44100


# ============================================================
# KARIŞTIRMA
# ============================================================

## İki tamponu karıştırır (toplar). Uzunluklar farklıysa uzun olan
## kadar; kısa tampon eksik kısımda 0 kabul edilir.
## a, b: karıştırılacak tamponlar.
## Dönen: karışmış tampon (klipленmiş -1..1).
static func mix(
	a: PackedFloat32Array, b: PackedFloat32Array
) -> PackedFloat32Array:
	var length: int = maxi(a.size(), b.size())
	var result: PackedFloat32Array = PackedFloat32Array()
	for i in range(length):
		var sample_a: float = a[i] if i < a.size() else 0.0
		var sample_b: float = b[i] if i < b.size() else 0.0
		result.append(clampf(sample_a + sample_b, -1.0, 1.0))
	return result


## Bir tamponu bir kazanç (gain) çarpanıyla ölçekler.
## buffer: tampon. gain: çarpan (1.0 = değişmez, 0.5 = yarı ses).
static func apply_gain(
	buffer: PackedFloat32Array, gain: float
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	for sample in buffer:
		result.append(clampf(sample * gain, -1.0, 1.0))
	return result


# ============================================================
# NORMALİZE
# ============================================================

## Bir tamponun en yüksek noktasını bulur (mutlak değer).
static func peak(buffer: PackedFloat32Array) -> float:
	var highest: float = 0.0
	for sample in buffer:
		highest = maxf(highest, absf(sample))
	return highest


## Bir tamponu normalize eder — en yüksek nokta tam 1.0 olur.
## Sessiz tampon değişmez (sıfıra bölme yok).
static func normalize(
	buffer: PackedFloat32Array
) -> PackedFloat32Array:
	var p: float = peak(buffer)
	if p <= 0.0:
		return buffer.duplicate()
	return apply_gain(buffer, 1.0 / p)


# ============================================================
# FADE
# ============================================================

## Tamponun başına fade-in uygular — 0'dan tam sese yükseliş.
## buffer: tampon. fade_samples: fade süresinin örnek sayısı.
static func fade_in(
	buffer: PackedFloat32Array, fade_samples: int
) -> PackedFloat32Array:
	var result: PackedFloat32Array = buffer.duplicate()
	var fade_len: int = mini(fade_samples, result.size())
	for i in range(fade_len):
		var factor: float = float(i) / float(maxi(fade_len, 1))
		result[i] = result[i] * factor
	return result


## Tamponun sonuna fade-out uygular — tam sesten 0'a iniş.
static func fade_out(
	buffer: PackedFloat32Array, fade_samples: int
) -> PackedFloat32Array:
	var result: PackedFloat32Array = buffer.duplicate()
	var fade_len: int = mini(fade_samples, result.size())
	var start: int = result.size() - fade_len
	for i in range(fade_len):
		var factor: float = 1.0 - float(i) / float(maxi(fade_len, 1))
		result[start + i] = result[start + i] * factor
	return result


# ============================================================
# YARDIMCI
# ============================================================

## Belirli süre için sessizlik tamponu üretir.
## duration_seconds: sessizlik süresi.
static func silence(duration_seconds: float) -> PackedFloat32Array:
	var count: int = int(duration_seconds * SAMPLE_RATE)
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(maxi(count, 0))
	return buffer


## Bir tamponun saniye cinsinden süresini hesaplar.
static func duration_of(buffer: PackedFloat32Array) -> float:
	return float(buffer.size()) / float(SAMPLE_RATE)


## Bir tamponun ortalama gücünü (RMS) hesaplar — algılanan yükseklik.
static func rms(buffer: PackedFloat32Array) -> float:
	if buffer.is_empty():
		return 0.0
	var sum_squares: float = 0.0
	for sample in buffer:
		sum_squares += sample * sample
	return sqrt(sum_squares / float(buffer.size()))
