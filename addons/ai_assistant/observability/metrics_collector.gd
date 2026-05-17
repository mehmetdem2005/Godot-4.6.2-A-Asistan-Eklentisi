@tool
class_name AIMetricsCollector
extends RefCounted

## MetricsCollector — sayısal ölçüm toplayıcı (Layer 6).
##
## TraceCollector "ne oldu" der (olay akışı). MetricsCollector "ne kadar"
## der (sayısal özet): kaç task, kaç başarı, ortalama süre, geçiş oranı.
##
## Üç metrik tipi:
##   COUNTER   — sadece artan sayaç (toplam task sayısı)
##   GAUGE     — anlık değer, artar/azalır (aktif task sayısı)
##   HISTOGRAM — değer dağılımı (task süreleri — min/max/ortalama/toplam)
##
## Mock policy: ölçümler gerçek kayıttan gelir — uydurma sayı yok.

## Metrik tipleri.
enum MetricType { COUNTER, GAUGE, HISTOGRAM }


## Histogram istatistiği — bir değer dağılımının özeti.
class HistogramStat extends RefCounted:
	var count: int = 0
	var sum: float = 0.0
	var min_value: float = 0.0
	var max_value: float = 0.0
	var _has_value: bool = false

	func observe(value: float) -> void:
		count += 1
		sum += value
		if not _has_value:
			min_value = value
			max_value = value
			_has_value = true
		else:
			min_value = minf(min_value, value)
			max_value = maxf(max_value, value)

	func average() -> float:
		return sum / float(count) if count > 0 else 0.0

	func to_dict() -> Dictionary:
		return {
			"count": count,
			"sum": sum,
			"min": min_value,
			"max": max_value,
			"average": average(),
		}


## Sayaçlar — isim -> int
var _counters: Dictionary = {}

## Gauge'ler — isim -> float
var _gauges: Dictionary = {}

## Histogramlar — isim -> HistogramStat
var _histograms: Dictionary = {}


# ============================================================
# COUNTER — artan sayaç
# ============================================================

## Bir sayacı artırır (varsayılan +1).
func increment(metric_name: String, amount: int = 1) -> void:
	_counters[metric_name] = int(_counters.get(metric_name, 0)) + amount


## Bir sayacın değerini döndürür.
func counter_value(metric_name: String) -> int:
	return int(_counters.get(metric_name, 0))


# ============================================================
# GAUGE — anlık değer
# ============================================================

## Bir gauge değerini ayarlar (mutlak).
func set_gauge(metric_name: String, value: float) -> void:
	_gauges[metric_name] = value


## Bir gauge'i değiştirir (göreli — artar/azalır).
func adjust_gauge(metric_name: String, delta: float) -> void:
	_gauges[metric_name] = float(_gauges.get(metric_name, 0.0)) + delta


## Bir gauge değerini döndürür.
func gauge_value(metric_name: String) -> float:
	return float(_gauges.get(metric_name, 0.0))


# ============================================================
# HISTOGRAM — değer dağılımı
# ============================================================

## Bir histograma değer ekler (örn. bir task'ın süresi).
func observe(metric_name: String, value: float) -> void:
	if not _histograms.has(metric_name):
		_histograms[metric_name] = HistogramStat.new()
	(_histograms[metric_name] as HistogramStat).observe(value)


## Bir histogramın istatistiğini döndürür.
## Yoksa boş (count=0) istatistik.
func histogram_stat(metric_name: String) -> HistogramStat:
	if _histograms.has(metric_name):
		return _histograms[metric_name]
	return HistogramStat.new()


# ============================================================
# TÜRETİLMİŞ METRİKLER
# ============================================================

## İki sayaçtan oran hesaplar — örn. başarı oranı.
## success / (success + failure). Payda 0 ise 0.0.
func ratio(numerator_metric: String, denominator_metric: String) -> float:
	var num: int = counter_value(numerator_metric)
	var den: int = counter_value(denominator_metric)
	if den == 0:
		return 0.0
	return float(num) / float(den)


## Başarı oranı kısayolu — passed / total.
func success_rate(passed_metric: String, total_metric: String) -> float:
	return ratio(passed_metric, total_metric)


# ============================================================
# RAPOR
# ============================================================

## Tüm metriklerin anlık görüntüsü.
func snapshot() -> Dictionary:
	var hist: Dictionary = {}
	for key in _histograms:
		hist[key] = (_histograms[key] as HistogramStat).to_dict()
	return {
		"counters": _counters.duplicate(),
		"gauges": _gauges.duplicate(),
		"histograms": hist,
		"captured_at": AIContractBase.now_iso(),
	}


## Tüm metrikleri sıfırlar.
func reset() -> void:
	_counters.clear()
	_gauges.clear()
	_histograms.clear()


## Kaç farklı metrik izleniyor (toplam).
func metric_count() -> int:
	return _counters.size() + _gauges.size() + _histograms.size()
