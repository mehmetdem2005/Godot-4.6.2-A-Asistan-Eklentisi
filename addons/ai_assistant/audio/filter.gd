@tool
class_name AIAudioFilter
extends RefCounted

## Filter — ses filtresi (Madde 08 / procedural_synth).
##
## Ham bir dalga formu (özellikle saw/square) çok "parlak" ve sert
## olabilir. Filtre belirli frekansları kesip sesi şekillendirir:
##   LOW_PASS  — yüksek frekansları keser (sesi yumuşatır, boğuklaştırır)
##   HIGH_PASS — alçak frekansları keser (sesi inceltir, tizleştirir)
##
## Basit tek-kutuplu (one-pole) filtre kullanır: her örnek, önceki
## örnekle harmanlanır. Harmanlama oranı kesme frekansını belirler.
## Hafif ama mobil için yeterli — ağır biquad gerekmez.
##
## Bu sınıf saf DSP matematiğidir — durum tutar (önceki örnek),
## sıralı çağrılmalıdır.
##
## Mock policy: filtrelenmiş örnek gerçek filtre matematiğinden.

## Filtre tipleri.
enum FilterType { LOW_PASS, HIGH_PASS }

const TYPE_NAMES: Dictionary = {
	FilterType.LOW_PASS: "low_pass",
	FilterType.HIGH_PASS: "high_pass",
}

## Örnekleme hızı.
const SAMPLE_RATE: float = 44100.0


## Filtre tipi.
var filter_type: int = FilterType.LOW_PASS

## Kesme frekansı (Hz) — bu frekansın ötesi zayıflar.
var cutoff: float = 1000.0

## Filtrenin iç durumu — önceki çıkış örneği.
var _prev_output: float = 0.0


func _init(
	p_type: int = FilterType.LOW_PASS, p_cutoff: float = 1000.0
) -> void:
	if TYPE_NAMES.has(p_type):
		filter_type = p_type
	cutoff = clampf(p_cutoff, 20.0, SAMPLE_RATE / 2.0)


# ============================================================
# FİLTRELEME
# ============================================================

## Kesme frekansından harmanlama katsayısını hesaplar.
## Yüksek cutoff -> az filtreleme; düşük cutoff -> çok filtreleme.
func _smoothing_factor() -> float:
	# Basit tek-kutuplu katsayı: cutoff / (cutoff + sample_rate oranı)
	var dt: float = 1.0 / SAMPLE_RATE
	var rc: float = 1.0 / (TAU * cutoff)
	return dt / (rc + dt)


## Tek bir örneği filtreler. Durum güncellenir — sıralı çağrılmalı.
## input_sample: ham giriş örneği.
## Dönen: filtrelenmiş örnek.
func process(input_sample: float) -> float:
	var alpha: float = _smoothing_factor()

	# Alçak geçiren: çıkış = önceki çıkış + alpha * (giriş - önceki çıkış)
	var low_passed: float = _prev_output + alpha * (
		input_sample - _prev_output
	)
	_prev_output = low_passed

	if filter_type == FilterType.LOW_PASS:
		return low_passed
	# Yüksek geçiren = giriş - alçak geçiren kısım
	return input_sample - low_passed


## Bir örnek tamponunu filtreler.
## input_buffer: ham örnekler.
## Dönen: filtrelenmiş tampon.
func process_buffer(
	input_buffer: PackedFloat32Array
) -> PackedFloat32Array:
	var output: PackedFloat32Array = PackedFloat32Array()
	for sample in input_buffer:
		output.append(process(sample))
	return output


# ============================================================
# DURUM
# ============================================================

## Filtre iç durumunu sıfırlar — yeni ses başlatmadan önce.
func reset() -> void:
	_prev_output = 0.0


## Filtre tipinin adı.
func type_name() -> String:
	return TYPE_NAMES.get(filter_type, "?")


## Kesme frekansını ayarlar (geçerli aralıkta).
func set_cutoff(value: float) -> void:
	cutoff = clampf(value, 20.0, SAMPLE_RATE / 2.0)
