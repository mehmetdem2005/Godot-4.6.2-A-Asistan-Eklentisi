@tool
class_name AIOfflineLatencyTracker
extends RefCounted

## LatencyTracker — gecikme izleyici (Madde 07 / Offline / connection).
##
## Bağlantı "var" ama yavaş olabilir. Bu sınıf ağ çağrılarının
## gecikmesini izler — son N ölçümün HAREKETLİ ORTALAMASINI tutar
## ve yavaşlama eğilimini tespit eder.
##
## Neden hareketli ortalama: tek bir yavaş çağrı anlık tıkanma
## olabilir; ama son 10 çağrının ortalaması yavaşsa bağlantı gerçekten
## kötü — strateji değiştirmeli (önbelleğe yaslan, queue'ya al).
##
## Mock policy: gecikme gerçek ölçümlerden eklenir; istatistik
## gerçek veriden.

## Hareketli ortalama penceresi — son kaç ölçüm.
const WINDOW_SIZE: int = 10

## Bu ortalamanın üstü "yavaş" sayılır (ms).
const SLOW_THRESHOLD_MS: float = 2000.0


## Son gecikme ölçümleri (ms) — en fazla WINDOW_SIZE.
var _samples: Array = []


# ============================================================
# ÖLÇÜM
# ============================================================

## Bir gecikme ölçümü ekler.
## latency_ms: ölçülen gecikme (negatif değer yok sayılır).
func record(latency_ms: float) -> void:
	if latency_ms < 0.0:
		return
	_samples.append(latency_ms)
	# Pencere boyutunu aşınca en eskiyi at
	if _samples.size() > WINDOW_SIZE:
		_samples.pop_front()


# ============================================================
# İSTATİSTİK
# ============================================================

## Ölçüm sayısı.
func sample_count() -> int:
	return _samples.size()


## Hareketli ortalama gecikme (ms). Ölçüm yoksa 0.
func average() -> float:
	if _samples.is_empty():
		return 0.0
	var total: float = 0.0
	for s in _samples:
		total += s
	return total / float(_samples.size())


## Penceredeki en yüksek gecikme.
func peak() -> float:
	if _samples.is_empty():
		return 0.0
	var highest: float = 0.0
	for s in _samples:
		highest = maxf(highest, s)
	return highest


## En son ölçülen gecikme. Ölçüm yoksa 0.
func latest() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples[_samples.size() - 1])


# ============================================================
# DEĞERLENDİRME
# ============================================================

## Bağlantı yavaş mı? (hareketli ortalama eşiğin üstünde)
func is_slow() -> bool:
	return average() > SLOW_THRESHOLD_MS


## Bağlantı kötüleşiyor mu? Son ölçüm ortalamadan belirgin yüksekse.
## Yeterli örnek yoksa false (karar verilemez).
func is_degrading() -> bool:
	if _samples.size() < 3:
		return false
	# Son ölçüm ortalamanın 1.5 katından fazlaysa kötüleşme
	return latest() > average() * 1.5


## Ölçümleri temizler.
func clear() -> void:
	_samples.clear()


## Gecikme özeti.
func summary() -> Dictionary:
	return {
		"sample_count": _samples.size(),
		"average_ms": average(),
		"peak_ms": peak(),
		"is_slow": is_slow(),
	}
