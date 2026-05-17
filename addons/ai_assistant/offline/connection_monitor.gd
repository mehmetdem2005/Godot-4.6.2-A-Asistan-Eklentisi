@tool
class_name AIOfflineConnectionMonitor
extends RefCounted

## ConnectionMonitor — bağlantı izleyici (Madde 07 / Offline).
##
## İnternet bir zorunluluk değil, bir araç. Sistem internet yokken
## çökmez; daraltılmış ama anlamlı kapasitede çalışır.
##
## Bu sınıf bağlantının sadece var/yok değil, KALİTESİNİ izler:
##   ONLINE   — bağlantı var, hızlı
##   DEGRADED — bağlantı var ama yavaş (LLM çağrısı riskli)
##   OFFLINE  — bağlantı yok
##   CHECKING — durum belirleniyor
##
## Lifecycle'daki network_state_monitor "kablo bağlı mı" der; bu sınıf
## "bağlantı işime yarar mı" der — gecikme ve başarı oranına bakar.
##
## Mock policy: durum gerçek ölçümlerden (gecikme, başarı/hata
## sayısı); sahte "online" yok.

## Bağlantı kalite durumları.
enum ConnState { CHECKING, ONLINE, DEGRADED, OFFLINE }

const STATE_NAMES: Dictionary = {
	ConnState.CHECKING: "checking",
	ConnState.ONLINE: "online",
	ConnState.DEGRADED: "degraded",
	ConnState.OFFLINE: "offline",
}

## Gecikme bu eşiğin üstündeyse bağlantı "yavaş" (ms).
const SLOW_LATENCY_MS: float = 2000.0

## Bağlantıyı offline saymak için ardışık başarısızlık eşiği.
const FAILURE_THRESHOLD: int = 3


## Mevcut durum.
var state: int = ConnState.CHECKING

## Ardışık başarısız bağlantı denemesi sayısı.
var _consecutive_failures: int = 0

## Son ölçülen gecikme (ms).
var last_latency_ms: float = 0.0

## Ölçülü (metered) bağlantı mı — büyük transferden kaçınılmalı.
var is_metered: bool = false


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Başarılı bir bağlantı denemesi bildirir.
## latency_ms: ölçülen gecikme.
## Dönen: yeni durum (int).
func report_success(latency_ms: float) -> int:
	_consecutive_failures = 0
	last_latency_ms = maxf(latency_ms, 0.0)
	# Gecikmeye göre online/degraded
	if last_latency_ms > SLOW_LATENCY_MS:
		state = ConnState.DEGRADED
	else:
		state = ConnState.ONLINE
	return state


## Başarısız bir bağlantı denemesi bildirir.
## Dönen: yeni durum (int).
func report_failure() -> int:
	_consecutive_failures += 1
	# Eşik aşılınca offline kabul et
	if _consecutive_failures >= FAILURE_THRESHOLD:
		state = ConnState.OFFLINE
	else:
		# Henüz emin değil — geçici sorun olabilir
		state = ConnState.DEGRADED
	return state


## Ölçülü bağlantı bayrağını ayarlar.
func set_metered(metered: bool) -> void:
	is_metered = metered


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut durumun adı.
func state_name() -> String:
	return STATE_NAMES.get(state, "?")


## Bağlantı kullanılabilir mi (online veya degraded)?
func is_usable() -> bool:
	return state == ConnState.ONLINE or state == ConnState.DEGRADED


## Tam çevrimdışı mı?
func is_offline() -> bool:
	return state == ConnState.OFFLINE


## Ağ çağrısı yapmak güvenli mi?
## ONLINE — evet. DEGRADED — riskli ama denenebilir. OFFLINE — hayır.
func should_attempt_network() -> bool:
	return state == ConnState.ONLINE or state == ConnState.DEGRADED


## Büyük transfer (model indirme vb.) güvenli mi?
## Sadece ONLINE + ölçülü değil.
func is_safe_for_large_transfer() -> bool:
	return state == ConnState.ONLINE and not is_metered


## Ardışık başarısızlık sayısı.
func failure_count() -> int:
	return _consecutive_failures


## Durum özeti.
func summary() -> Dictionary:
	return {
		"state": state_name(),
		"is_usable": is_usable(),
		"is_metered": is_metered,
		"last_latency_ms": last_latency_ms,
		"failures": _consecutive_failures,
	}
