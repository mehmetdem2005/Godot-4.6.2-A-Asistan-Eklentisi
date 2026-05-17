@tool
class_name AIAudioVorbisEncoder
extends RefCounted

## VorbisEncoder — OGG kodlama hazırlığı (Madde 08 / procedural_synth).
##
## Sentezlenen ses bir float dizisidir (-1..1 örnekler). Oyunda
## kullanmak için bir ses dosyasına (OGG Vorbis) dönüştürülmeli.
##
## Gerçek OGG kodlaması Godot'un AudioStreamWAV/OGG sınıflarının
## işidir — ham örnekleri sıkıştırılmış dosyaya çevirmek motor
## seviyesinde olur. Bu sınıf KODLAMA ÖNCESİ hazırlığı yapar:
##   - örnekleri 16-bit PCM tamsayıya çevir (Godot'un beklediği format)
##   - kodlama metadata'sını hesapla (süre, boyut tahmini)
##   - tampon geçerliliğini doğrula
##
## "Mock yasak": gerçek OGG byte'ı üretmez (o Godot'un işi) —
## kodlamaya HAZIR PCM veri + tarif üretir.
##
## Mock policy: hazırlık gerçek tampon matematiğinden.

const SAMPLE_RATE: int = 44100

## 16-bit PCM'de bir örneğin maksimum değeri.
const PCM_16_MAX: int = 32767

## OGG için tipik kalite (0-1) — mobil dengeli.
const DEFAULT_QUALITY: float = 0.6


# ============================================================
# PCM DÖNÜŞÜMÜ
# ============================================================

## Float örnek tamponunu (-1..1) 16-bit PCM tamsayıya çevirir.
## Godot'un ses akışları PCM bekler.
## buffer: float örnekler.
## Dönen: 16-bit PCM değerleri (-32767..32767).
func to_pcm16(buffer: PackedFloat32Array) -> PackedInt32Array:
	var pcm: PackedInt32Array = PackedInt32Array()
	for sample in buffer:
		# Kliple, sonra 16-bit aralığa ölçekle
		var clamped: float = clampf(sample, -1.0, 1.0)
		pcm.append(int(clamped * float(PCM_16_MAX)))
	return pcm


## 16-bit PCM'yi geri float'a çevirir — round-trip doğrulama için.
func from_pcm16(pcm: PackedInt32Array) -> PackedFloat32Array:
	var buffer: PackedFloat32Array = PackedFloat32Array()
	for value in pcm:
		buffer.append(float(value) / float(PCM_16_MAX))
	return buffer


# ============================================================
# KODLAMA HAZIRLIĞI
# ============================================================

## Bir ses tamponu için kodlama isteği hazırlar.
## Godot tarafındaki kodlayıcı bu tarifi kullanır.
## buffer: ses tamponu. quality: OGG kalitesi (-1 = varsayılan).
## Dönen: {ok, pcm_data, metadata, reason}
func prepare_encoding(
	buffer: PackedFloat32Array, quality: float = -1.0
) -> Dictionary:
	# Tampon geçerli mi
	if buffer.is_empty():
		return {
			"ok": false, "pcm_data": PackedInt32Array(),
			"metadata": {}, "reason": "Boş tampon kodlanamaz",
		}

	var q: float = quality if quality >= 0.0 else DEFAULT_QUALITY
	q = clampf(q, 0.0, 1.0)

	var pcm: PackedInt32Array = to_pcm16(buffer)
	var metadata: Dictionary = make_metadata(buffer, q)

	return {
		"ok": true,
		"pcm_data": pcm,
		"metadata": metadata,
		"reason": "Kodlamaya hazır (%d örnek)" % buffer.size(),
	}


## Bir tampon için kodlama metadata'sı üretir.
func make_metadata(
	buffer: PackedFloat32Array, quality: float
) -> Dictionary:
	var duration: float = float(buffer.size()) / float(SAMPLE_RATE)
	return {
		"sample_count": buffer.size(),
		"sample_rate": SAMPLE_RATE,
		"duration_seconds": duration,
		"quality": quality,
		"channels": 1,  # mono — sentezlenmiş sesler tek kanal
		"estimated_bytes": estimate_size(buffer, quality),
	}


# ============================================================
# BOYUT TAHMİNİ
# ============================================================

## Kodlanmış OGG dosyasının yaklaşık boyutunu tahmin eder.
## OGG Vorbis kalite-bazlı sıkıştırır — kabaca tahmin.
## buffer: ses tamponu. quality: kalite (0-1).
## Dönen: tahmini bayt sayısı.
func estimate_size(
	buffer: PackedFloat32Array, quality: float
) -> int:
	var duration: float = float(buffer.size()) / float(SAMPLE_RATE)
	# OGG bitrate kabaca: kalite 0 ~64kbps, kalite 1 ~256kbps
	var bitrate: float = 64000.0 + quality * 192000.0
	# bayt = (bitrate / 8) * süre
	return int((bitrate / 8.0) * duration)


# ============================================================
# DOĞRULAMA
# ============================================================

## Bir tampon kodlamaya uygun mu?
func is_encodable(buffer: PackedFloat32Array) -> bool:
	return not buffer.is_empty()


## PCM round-trip kaybını ölçer — float->pcm->float doğruluğu.
## Dönen: ortalama mutlak hata (küçük olmalı, 16-bit hassasiyet).
func roundtrip_error(buffer: PackedFloat32Array) -> float:
	if buffer.is_empty():
		return 0.0
	var pcm: PackedInt32Array = to_pcm16(buffer)
	var restored: PackedFloat32Array = from_pcm16(pcm)
	var total_error: float = 0.0
	for i in range(buffer.size()):
		total_error += absf(buffer[i] - restored[i])
	return total_error / float(buffer.size())
