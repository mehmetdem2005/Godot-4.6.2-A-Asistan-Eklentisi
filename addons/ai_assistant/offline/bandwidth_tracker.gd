@tool
class_name AIOfflineBandwidthTracker
extends RefCounted

## BandwidthTracker — bant genişliği izleyici (Madde 07 / bandwidth).
##
## DataMeter TOPLAM veri sayar (kümülatif). BandwidthTracker ise
## ANLIK HIZ izler: "şu an saniyede kaç bayt akıyor".
##
## Bu, yavaş bağlantı tespiti için gerekli. Hız düşükse büyük
## işlemler (varlık indirme) ertelenebilir, kullanıcıya "bağlantı
## yavaş" denebilir.
##
## Kayan pencere (sliding window) ortalaması kullanır: son birkaç
## ölçümün ortalaması — anlık dalgalanmayı yumuşatır.
##
## Mock policy: hız gerçek kaydedilen transferlerden hesaplanır.

## Kayan pencere boyutu — kaç ölçüm ortalanır.
const WINDOW_SIZE: int = 10

## Yavaş bağlantı eşiği (bayt/saniye) — ~50 KB/s.
const SLOW_THRESHOLD: float = 51200.0


## Son ölçümler — her biri bayt/saniye hızı.
var _samples: Array = []

## Toplam kaydedilen transfer sayısı.
var _sample_count: int = 0


# ============================================================
# ÖLÇÜM KAYDI
# ============================================================

## Bir transfer ölçümü kaydeder.
## bytes: aktarılan bayt. duration_seconds: transferin süresi.
func record_transfer(bytes: int, duration_seconds: float) -> void:
	if duration_seconds <= 0.0 or bytes < 0:
		return
	# Bu transferin hızı (bayt/saniye)
	var speed: float = float(bytes) / duration_seconds
	_samples.append(speed)
	_sample_count += 1
	# Pencereyi sınırla — eski ölçümleri at
	while _samples.size() > WINDOW_SIZE:
		_samples.pop_front()


# ============================================================
# HIZ SORGULAMA
# ============================================================

## Kayan pencere ortalama hızı (bayt/saniye).
func average_speed() -> float:
	if _samples.is_empty():
		return 0.0
	var total: float = 0.0
	for speed in _samples:
		total += speed
	return total / float(_samples.size())


## En son ölçülen hız (bayt/saniye). Ölçüm yoksa 0.
func latest_speed() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples[_samples.size() - 1])


## Ortalama hızı megabit/saniyeye çevirir — insan-okunur.
func average_mbps() -> float:
	# bayt/sn -> bit/sn -> megabit/sn
	return (average_speed() * 8.0) / 1000000.0


# ============================================================
# DURUM
# ============================================================

## Bağlantı şu an yavaş mı (eşiğin altında)?
func is_slow() -> bool:
	# Ölçüm yoksa "yavaş" varsayma — bilinmiyor
	if _samples.is_empty():
		return false
	return average_speed() < SLOW_THRESHOLD


## Belirli bir veri miktarının tahmini transfer süresi (saniye).
## bytes: aktarılacak veri.
## Dönen: tahmini süre; hız bilinmiyorsa -1.
func estimate_transfer_time(bytes: int) -> float:
	var speed: float = average_speed()
	if speed <= 0.0:
		return -1.0
	return float(bytes) / speed


## Yeterli ölçüm var mı (güvenilir tahmin için)?
func has_reliable_data() -> bool:
	return _samples.size() >= 3


## İzleyiciyi sıfırlar.
func reset() -> void:
	_samples.clear()
	_sample_count = 0


## Durum özeti.
func summary() -> Dictionary:
	return {
		"average_speed": average_speed(),
		"average_mbps": average_mbps(),
		"is_slow": is_slow(),
		"sample_count": _sample_count,
		"reliable": has_reliable_data(),
	}
