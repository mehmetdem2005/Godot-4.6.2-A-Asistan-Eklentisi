@tool
class_name AIOfflineBandwidthDashboard
extends RefCounted

## BandwidthDashboard — veri panosu (Madde 07 / offline / ui).
##
## DataMeter + BandwidthGovernor verilerini görsel bir panoya çevirir:
## kategori bazlı kullanım grafiği, sınır göstergesi, hız durumu.
##
## Kullanıcı "bu ay ne kadar veri yedim, hangi özellik, sınıra ne
## kadar kaldı" sorularının cevabını burada görür.
##
## data_meter + bandwidth_governor + bandwidth_tracker (mantık
## katmanı) ile beslenir; bu sınıf onları görsel veriye çevirir.
##
## Mock policy: pano gerçek ölçüm verilerinden.

## Sınır göstergesi durumu.
enum CapStatus { HEALTHY, WARNING, EXCEEDED, UNLIMITED }

const CAP_STATUS_NAMES: Dictionary = {
	CapStatus.HEALTHY: "healthy",
	CapStatus.WARNING: "warning",
	CapStatus.EXCEEDED: "exceeded",
	CapStatus.UNLIMITED: "unlimited",
}

const CAP_STATUS_COLOR: Dictionary = {
	CapStatus.HEALTHY: "#4caf50",
	CapStatus.WARNING: "#ff9800",
	CapStatus.EXCEEDED: "#f44336",
	CapStatus.UNLIMITED: "#9e9e9e",
}

## Uyarı bölgesi eşiği — kullanımın bu oranı dolunca uyar.
const WARNING_RATIO: float = 0.80

## Kategori -> kullanıcı-dostu etiket.
const CATEGORY_LABELS: Dictionary = {
	"llm": "AI Çağrıları",
	"embedding": "Embedding",
	"asset": "Varlık İndirme",
	"sync": "Senkronizasyon",
	"other": "Diğer",
}


# ============================================================
# KULLANIM GRAFİĞİ
# ============================================================

## Kategori bazlı kullanım dökümünü grafik verisine çevirir.
## breakdown: data_meter.breakdown() çıktısı — kategori -> bayt.
## Dönen: her biri {category, label, bytes, mb, percent} dizi.
func build_usage_chart(breakdown: Dictionary) -> Array:
	# Toplam — yüzde hesabı için
	var total: int = 0
	for category in breakdown:
		total += int(breakdown[category])

	var chart: Array = []
	for category in breakdown:
		var bytes: int = int(breakdown[category])
		var percent: float = 0.0
		if total > 0:
			percent = (float(bytes) / float(total)) * 100.0
		chart.append({
			"category": category,
			"label": CATEGORY_LABELS.get(category, category),
			"bytes": bytes,
			"mb": float(bytes) / (1024.0 * 1024.0),
			"percent": percent,
		})
	# Büyükten küçüğe sırala
	chart.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["bytes"]) > int(b["bytes"]))
	return chart


# ============================================================
# SINIR GÖSTERGESİ
# ============================================================

## Veri sınırı göstergesinin durumunu hesaplar.
## used_bytes: kullanılan veri. cap_bytes: sınır (0 = sınırsız).
## Dönen: {status, status_name, color, ratio, label}
func build_cap_gauge(used_bytes: int, cap_bytes: int) -> Dictionary:
	# Sınırsız
	if cap_bytes <= 0:
		return {
			"status": CapStatus.UNLIMITED,
			"status_name": CAP_STATUS_NAMES[CapStatus.UNLIMITED],
			"color": CAP_STATUS_COLOR[CapStatus.UNLIMITED],
			"ratio": 0.0,
			"label": "Sınırsız",
		}

	var ratio: float = clampf(
		float(used_bytes) / float(cap_bytes), 0.0, 1.0
	)

	var status: int
	if used_bytes >= cap_bytes:
		status = CapStatus.EXCEEDED
	elif ratio >= WARNING_RATIO:
		status = CapStatus.WARNING
	else:
		status = CapStatus.HEALTHY

	var used_mb: float = float(used_bytes) / (1024.0 * 1024.0)
	var cap_mb: float = float(cap_bytes) / (1024.0 * 1024.0)

	return {
		"status": status,
		"status_name": CAP_STATUS_NAMES.get(status, "?"),
		"color": CAP_STATUS_COLOR.get(status, "#9e9e9e"),
		"ratio": ratio,
		"label": "%.1f / %.1f MB" % [used_mb, cap_mb],
	}


# ============================================================
# HIZ GÖSTERGESİ
# ============================================================

## Bağlantı hızı göstergesini hazırlar.
## avg_speed_bps: ortalama hız (bayt/saniye). is_slow: yavaş mı.
## Dönen: {mbps, label, is_slow}
func build_speed_indicator(
	avg_speed_bps: float, is_slow: bool
) -> Dictionary:
	var mbps: float = (avg_speed_bps * 8.0) / 1000000.0
	return {
		"mbps": mbps,
		"label": "%.1f Mbps" % mbps,
		"is_slow": is_slow,
	}
