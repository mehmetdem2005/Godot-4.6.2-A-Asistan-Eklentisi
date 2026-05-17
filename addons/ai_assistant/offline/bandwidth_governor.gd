@tool
class_name AIOfflineBandwidthGovernor
extends RefCounted

## BandwidthGovernor — bant genişliği yöneticisi (Madde 07 / bandwidth).
##
## DataMeter sayar, BandwidthTracker hızı izler — Governor KARAR VERİR.
## Bir veri ÜST SINIRI (cap) uygular: kullanıcı "ayda en fazla 100 MB
## mobil veri kullan" der, governor bunu zorlar.
##
## Yeni bir ağ işlemi yapılmadan önce governor'a sorulur: "bu işlem
## izinli mi". Sınır aşılacaksa REDDEDİLİR — büyük indirmeler Wi-Fi'ye
## ertelenir.
##
## Akıllı: bağlantı türünü dikkate alır. Wi-Fi'de sınır yok (veya
## yüksek), mobil veride sıkı. Kritik işlemler (küçük senkr.) sınır
## dolsa bile geçebilir.
##
## "Mock yasak": sınır aşımını gizlemez — açıkça reddeder.
##
## Mock policy: karar gerçek kullanım + sınırdan.

## İşlem izin sonuçları.
enum Verdict { ALLOWED, DENIED_OVER_CAP, DEFER_TO_WIFI, ALLOWED_CRITICAL }

const VERDICT_NAMES: Dictionary = {
	Verdict.ALLOWED: "allowed",
	Verdict.DENIED_OVER_CAP: "denied_over_cap",
	Verdict.DEFER_TO_WIFI: "defer_to_wifi",
	Verdict.ALLOWED_CRITICAL: "allowed_critical",
}

## Büyük işlem eşiği (bayt) — bundan büyükse Wi-Fi tercih edilir.
const LARGE_OPERATION_BYTES: int = 5 * 1024 * 1024  # 5 MB


## Mobil veri üst sınırı (bayt). 0 = sınırsız.
var mobile_cap_bytes: int = 100 * 1024 * 1024  # 100 MB

## Mobil veride şu ana kadar kullanılan (bayt).
var mobile_used_bytes: int = 0

## Şu an Wi-Fi'de mi (true ise sınır gevşek).
var on_wifi: bool = false

## Veri tasarrufu modu — kullanıcı isteğiyle ekstra sıkı.
var data_saver: bool = false


# ============================================================
# AYAR
# ============================================================

## Mobil veri üst sınırını ayarlar (bayt). 0 = sınırsız.
func set_mobile_cap(bytes: int) -> void:
	mobile_cap_bytes = maxi(bytes, 0)


## Bağlantı türünü günceller.
func set_connection(p_on_wifi: bool) -> void:
	on_wifi = p_on_wifi


## Veri tasarrufu modunu ayarlar.
func set_data_saver(enabled: bool) -> void:
	data_saver = enabled


# ============================================================
# İŞLEM İZNİ
# ============================================================

## Bir ağ işleminin yapılıp yapılamayacağına karar verir.
## operation_bytes: işlemin tahmini veri boyutu.
## is_critical: kritik işlem mi (sınır dolsa da geçer).
## Dönen: {verdict: String, allowed: bool, reason: String}
func authorize(
	operation_bytes: int, is_critical: bool = false
) -> Dictionary:
	# Wi-Fi'de — mobil sınır uygulanmaz
	if on_wifi:
		return {
			"verdict": VERDICT_NAMES[Verdict.ALLOWED],
			"allowed": true,
			"reason": "Wi-Fi bağlantısı — mobil sınır yok",
		}

	# Mobil veride — sınır kontrolü
	# Büyük işlem + veri tasarrufu — Wi-Fi'ye ertele
	if data_saver and operation_bytes >= LARGE_OPERATION_BYTES \
			and not is_critical:
		return {
			"verdict": VERDICT_NAMES[Verdict.DEFER_TO_WIFI],
			"allowed": false,
			"reason": "Büyük işlem — veri tasarrufunda Wi-Fi bekleniyor",
		}

	# Sınır var mı
	if mobile_cap_bytes > 0:
		var projected: int = mobile_used_bytes + operation_bytes
		if projected > mobile_cap_bytes:
			# Sınır aşılıyor — kritikse yine de izin ver
			if is_critical:
				return {
					"verdict": VERDICT_NAMES[Verdict.ALLOWED_CRITICAL],
					"allowed": true,
					"reason": "Sınır aşıldı ama kritik işlem — izin verildi",
				}
			return {
				"verdict": VERDICT_NAMES[Verdict.DENIED_OVER_CAP],
				"allowed": false,
				"reason": "Mobil veri sınırı aşılır — işlem reddedildi",
			}

	# Sınır içinde — izin
	return {
		"verdict": VERDICT_NAMES[Verdict.ALLOWED],
		"allowed": true,
		"reason": "İşlem mobil veri sınırı içinde",
	}


## Bir işlem yapıldıktan sonra kullanımı kaydeder.
## Sadece mobil veride kullanım sayılır.
func record_usage(bytes: int) -> void:
	if not on_wifi:
		mobile_used_bytes += maxi(bytes, 0)


# ============================================================
# DURUM
# ============================================================

## Mobil verinin ne kadarı kullanıldı (0.0 - 1.0). Sınırsızsa 0.
func usage_ratio() -> float:
	if mobile_cap_bytes <= 0:
		return 0.0
	return clampf(
		float(mobile_used_bytes) / float(mobile_cap_bytes), 0.0, 1.0
	)


## Mobil veri sınırı aşıldı mı?
func is_over_cap() -> bool:
	if mobile_cap_bytes <= 0:
		return false
	return mobile_used_bytes >= mobile_cap_bytes


## Kalan mobil veri bütçesi (bayt). Sınırsızsa -1.
func remaining_budget() -> int:
	if mobile_cap_bytes <= 0:
		return -1
	return maxi(mobile_cap_bytes - mobile_used_bytes, 0)


## Kullanımı sıfırlar — yeni dönem.
func reset_usage() -> void:
	mobile_used_bytes = 0


## Durum özeti.
func summary() -> Dictionary:
	return {
		"mobile_cap_bytes": mobile_cap_bytes,
		"mobile_used_bytes": mobile_used_bytes,
		"usage_ratio": usage_ratio(),
		"on_wifi": on_wifi,
		"over_cap": is_over_cap(),
	}
