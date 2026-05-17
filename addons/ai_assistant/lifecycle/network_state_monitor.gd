@tool
class_name AILifecycleNetworkMonitor
extends RefCounted

## NetworkStateMonitor — ağ durumu izleyici (Madde 10 / App Lifecycle).
##
## Mobilde ağ gelir gider: WiFi'dan mobil veriye geçiş, tünel,
## asansör, uçak modu. Bu sınıf ağ durumunu izler ve DEĞİŞİMLERİ
## bildirir — bağlantı kesildi/geri geldi.
##
## Madde 07 (Offline) ile paylaşılan kavram: ağ durumu. Bu sınıf
## lifecycle tarafının görüşü — "ağ değişti, ilgili sistemleri
## uyar". Offline modülü asıl ağ-kullanım stratejisini kurar.
##
## Bağlantı tipi de önemli: ölçülü (metered) bağlantıda büyük
## indirme yapmamalı (kullanıcının veri paketi).
##
## Mock policy: durum dışarıdan bildirilir; sınıf değişimi tespit
## eder.

## Ağ bağlantı tipi.
enum ConnectionType { NONE, WIFI, MOBILE, ETHERNET }

const TYPE_NAMES: Dictionary = {
	ConnectionType.NONE: "none",
	ConnectionType.WIFI: "wifi",
	ConnectionType.MOBILE: "mobile",
	ConnectionType.ETHERNET: "ethernet",
}


## Mevcut bağlantı tipi.
var connection_type: int = ConnectionType.NONE

## Önceki bağlantı tipi — değişim tespiti için.
var _previous_type: int = ConnectionType.NONE


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Ağ durumunu günceller.
## new_type: yeni bağlantı tipi.
## Dönen: {changed: bool, from: String, to: String, event: String}
##   event: "" | "network_lost" | "network_gained" | "type_changed"
func update(new_type: int) -> Dictionary:
	if not TYPE_NAMES.has(new_type):
		return {
			"changed": false, "from": type_name(),
			"to": "?", "event": "",
		}

	_previous_type = connection_type
	var changed: bool = new_type != connection_type
	connection_type = new_type

	if not changed:
		return {
			"changed": false, "from": type_name(),
			"to": type_name(), "event": "",
		}

	# Olay tipini belirle
	var event: String = "type_changed"
	if _previous_type == ConnectionType.NONE:
		event = "network_gained"  # bağlantı yoktu, geldi
	elif new_type == ConnectionType.NONE:
		event = "network_lost"    # bağlantı vardı, gitti

	return {
		"changed": true,
		"from": TYPE_NAMES[_previous_type],
		"to": TYPE_NAMES[new_type],
		"event": event,
	}


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut bağlantı tipinin adı.
func type_name() -> String:
	return TYPE_NAMES.get(connection_type, "?")


## Ağ bağlantısı var mı?
##
## NOT: Metot adı 'has_network' — 'is_connected' Object sınıfının
## yerleşik metodudur (sinyal bağlantı kontrolü), override çakışır.
func has_network() -> bool:
	return connection_type != ConnectionType.NONE


## Bağlantı ölçülü mü (metered)? Mobil veri = ölçülü.
## Büyük indirmeler ölçülü bağlantıda yapılmamalı.
func is_metered() -> bool:
	return connection_type == ConnectionType.MOBILE


## Büyük indirme güvenli mi? (bağlı + ölçülü değil)
func is_safe_for_large_download() -> bool:
	return has_network() and not is_metered()


## Durum özeti.
func summary() -> Dictionary:
	return {
		"connection_type": type_name(),
		"has_network": has_network(),
		"is_metered": is_metered(),
	}
