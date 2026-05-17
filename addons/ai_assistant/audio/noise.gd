@tool
class_name AIAudioNoise
extends RefCounted

## Noise — gürültü üreteci (Madde 08 / procedural_synth).
##
## Bazı sesler dalga formuyla değil GÜRÜLTÜYLE yapılır: patlama,
## rüzgar, ateş, statik, davul vuruşu. Gürültü rastgele örneklerdir.
##
## İki tip:
##   WHITE — saf rastgele, her frekans eşit (tiz, "şşş" sesi)
##   PINK  — alçak frekanslar daha güçlü (daha doğal, "huuu" — rüzgar)
##
## Deterministik tohum (seed) kullanır — aynı tohum aynı gürültü.
## Bu önemli: prosedürel ses üretiminde tekrarlanabilirlik gerekir
## (aynı patlama sesi her seferinde aynı olmalı).
##
## Bu sınıf saf matematiktir — Godot RNG'sine bağlı değil, kendi
## deterministik üretecini kullanır.
##
## Mock policy: gürültü deterministik tohumdan üretilir.

## Gürültü tipleri.
enum NoiseType { WHITE, PINK }

const TYPE_NAMES: Dictionary = {
	NoiseType.WHITE: "white",
	NoiseType.PINK: "pink",
}


## Gürültü tipi.
var noise_type: int = NoiseType.WHITE

## Deterministik üreteç durumu (LCG — lineer kongruent).
var _rng_state: int = 12345

## Pink noise için filtre durumu (alçak frekans birikimi).
var _pink_accumulator: float = 0.0


func _init(p_type: int = NoiseType.WHITE, p_seed: int = 12345) -> void:
	if TYPE_NAMES.has(p_type):
		noise_type = p_type
	_rng_state = p_seed if p_seed != 0 else 12345


# ============================================================
# DETERMİNİSTİK RASTGELE
# ============================================================

## Bir sonraki rastgele örneği üretir (-1..1).
## Lineer kongruent üreteç — deterministik, hızlı.
func _next_random() -> float:
	# LCG: state = (a * state + c) mod m
	_rng_state = (_rng_state * 1103515245 + 12345) & 0x7FFFFFFF
	# 0..1 aralığına normalize et, sonra -1..1
	var normalized: float = float(_rng_state) / float(0x7FFFFFFF)
	return (normalized * 2.0) - 1.0


# ============================================================
# ÖRNEK ÜRETİMİ
# ============================================================

## Tek bir gürültü örneği üretir.
## Dönen: örnek değeri (-1..1).
func next_sample() -> float:
	var white: float = _next_random()

	if noise_type == NoiseType.WHITE:
		return white

	# Pink noise — beyaz gürültüyü alçak-geçiren ile yumuşat
	# Birikim, alçak frekansları güçlendirir
	_pink_accumulator = _pink_accumulator * 0.96 + white * 0.04
	# Birikim + biraz beyaz — pembe karakteri
	return clampf(_pink_accumulator * 3.5 + white * 0.3, -1.0, 1.0)


## Bir gürültü tamponu üretir.
## sample_count: üretilecek örnek sayısı.
## Dönen: gürültü tamponu.
func generate_buffer(sample_count: int) -> PackedFloat32Array:
	var buffer: PackedFloat32Array = PackedFloat32Array()
	for i in range(maxi(sample_count, 0)):
		buffer.append(next_sample())
	return buffer


# ============================================================
# DURUM
# ============================================================

## Üreteci başlangıç tohumuna sıfırlar — tekrarlanabilir gürültü.
func reseed(new_seed: int) -> void:
	_rng_state = new_seed if new_seed != 0 else 12345
	_pink_accumulator = 0.0


## Gürültü tipinin adı.
func type_name() -> String:
	return TYPE_NAMES.get(noise_type, "?")
