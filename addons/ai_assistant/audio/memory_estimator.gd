@tool
class_name AIAudioMemoryEstimator
extends RefCounted

## MemoryEstimator — ses bellek tahmincisi (Madde 08 / budget).
##
## Mobilde bellek kısıtlı. Sesler bellek yer: yüklü her ses akışı RAM
## tutar. Çok fazla ses yüklemek oyunu çökertebilir.
##
## Bu sınıf ses varlıklarının bellek kullanımını TAHMİN eder — bir
## ses kaç bayt yer, toplam ses bütçesi ne kadar. Bütçe aşımını
## önceden görmek için.
##
## Hesap basit: süre × örnekleme hızı × kanal × bayt/örnek. Sıkıştırma
## (OGG) bunu azaltır ama OGG bellekte de açılır — burası tahmin.
##
## Bu sınıf saf matematiktir — Godot gerektirmez.
##
## Mock policy: tahmin gerçek ses parametrelerinden hesaplanır.

const SAMPLE_RATE: int = 44100

## Sıkıştırılmamış (PCM) örnek başına bayt — 16-bit.
const BYTES_PER_SAMPLE: int = 2

## OGG bellekte açıldığında tipik sıkıştırma oranı (kabaca).
const OGG_MEMORY_RATIO: float = 0.15

## Ses depolama tipleri.
enum StorageType { PCM_UNCOMPRESSED, OGG_COMPRESSED }


# ============================================================
# TEK SES TAHMİNİ
# ============================================================

## Bir ses akışının bellek kullanımını tahmin eder.
## duration_seconds: ses süresi. channels: kanal sayısı (1=mono, 2=stereo).
## storage: depolama tipi.
## Dönen: tahmini bayt.
func estimate_stream(
	duration_seconds: float, channels: int = 1,
	storage: int = StorageType.PCM_UNCOMPRESSED
) -> int:
	if duration_seconds <= 0.0:
		return 0
	var ch: int = maxi(channels, 1)
	# Ham PCM boyutu
	var raw_bytes: float = duration_seconds * float(SAMPLE_RATE) \
		* float(ch) * float(BYTES_PER_SAMPLE)
	# OGG ise bellekteki tahmini boyut daha küçük
	if storage == StorageType.OGG_COMPRESSED:
		return int(raw_bytes * OGG_MEMORY_RATIO)
	return int(raw_bytes)


## Bir örnek tamponunun bellek boyutunu hesaplar.
## sample_count: örnek sayısı.
func estimate_buffer(sample_count: int) -> int:
	return maxi(sample_count, 0) * BYTES_PER_SAMPLE


# ============================================================
# TOPLU TAHMİN
# ============================================================

## Birden fazla ses akışının toplam bellek kullanımını tahmin eder.
## streams: her biri {duration, channels, storage} sözlüğü.
## Dönen: toplam tahmini bayt.
func estimate_total(streams: Array) -> int:
	var total: int = 0
	for stream in streams:
		if typeof(stream) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = stream
		total += estimate_stream(
			float(dict.get("duration", 0.0)),
			int(dict.get("channels", 1)),
			int(dict.get("storage", StorageType.PCM_UNCOMPRESSED))
		)
	return total


# ============================================================
# BİRİM ÇEVRİMİ
# ============================================================

## Baytı megabayta çevirir — insan-okunur.
func bytes_to_mb(bytes: int) -> float:
	return float(bytes) / (1024.0 * 1024.0)


## Megabaytı bayta çevirir.
func mb_to_bytes(mb: float) -> int:
	return int(mb * 1024.0 * 1024.0)


# ============================================================
# SORGULAMA
# ============================================================

## Bir ses akışı bir bellek limitine sığar mı?
## duration: süre. channels: kanal. storage: depolama. limit_bytes: limit.
func fits_within(
	duration_seconds: float, channels: int, storage: int,
	limit_bytes: int
) -> bool:
	return estimate_stream(duration_seconds, channels, storage) \
		<= limit_bytes


## OGG sıkıştırmanın bir ses için kaç bayt tasarruf ettiğini hesaplar.
func ogg_savings(duration_seconds: float, channels: int = 1) -> int:
	var pcm: int = estimate_stream(
		duration_seconds, channels, StorageType.PCM_UNCOMPRESSED
	)
	var ogg: int = estimate_stream(
		duration_seconds, channels, StorageType.OGG_COMPRESSED
	)
	return pcm - ogg
