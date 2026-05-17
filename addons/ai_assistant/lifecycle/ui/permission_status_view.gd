@tool
class_name AILifecyclePermissionView
extends RefCounted

## PermissionStatusView — izin durumu görünümü (Madde 10 / ui).
##
## Android uygulaması bazı izinler ister: bildirim, depolama, internet.
## Bu panel her iznin mevcut durumunu gösterir (verildi / reddedildi /
## sorulmadı) ve izin isteme/gerekçe gösterme akışını yönetir.
##
## Bu view-model izin durumlarını tutar ve görsel listeye çevirir.
## permission_rationale şablonu (lifecycle_templates) ile entegre.
##
## Mock policy: durum gerçek izin sorgularından.

## İzin durumları.
enum PermStatus { GRANTED, DENIED, NOT_REQUESTED, PERMANENTLY_DENIED }

const STATUS_NAMES: Dictionary = {
	PermStatus.GRANTED: "granted",
	PermStatus.DENIED: "denied",
	PermStatus.NOT_REQUESTED: "not_requested",
	PermStatus.PERMANENTLY_DENIED: "permanently_denied",
}

const STATUS_COLOR: Dictionary = {
	PermStatus.GRANTED: "#4caf50",
	PermStatus.DENIED: "#ff9800",
	PermStatus.NOT_REQUESTED: "#9e9e9e",
	PermStatus.PERMANENTLY_DENIED: "#f44336",
}

## İzlenen izinler — anahtar -> {label, rationale}.
const PERMISSIONS: Dictionary = {
	"notifications": {
		"label": "Bildirimler",
		"rationale": "Günlük ödül ve etkinlik hatırlatmaları için.",
	},
	"storage": {
		"label": "Depolama",
		"rationale": "Oyun kayıtlarını cihazda saklamak için.",
	},
	"internet": {
		"label": "İnternet",
		"rationale": "Bulut senkronizasyonu ve AI özellikleri için.",
	},
}


## İzin durumları — permission_key -> PermStatus.
var _statuses: Dictionary = {}


func _init() -> void:
	# Başlangıçta tüm izinler "sorulmadı"
	for key in PERMISSIONS:
		_statuses[key] = PermStatus.NOT_REQUESTED


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Bir iznin durumunu günceller.
## permission_key: izin anahtarı. status: PermStatus değeri.
## Dönen: true = geçerli güncelleme.
func update_status(permission_key: String, status: int) -> bool:
	if not PERMISSIONS.has(permission_key):
		return false
	if not STATUS_NAMES.has(status):
		return false
	_statuses[permission_key] = status
	return true


## Bir iznin mevcut durumunu döndürür.
func status_of(permission_key: String) -> int:
	return int(_statuses.get(
		permission_key, PermStatus.NOT_REQUESTED
	))


# ============================================================
# İZİN İSTEME AKIŞI
# ============================================================

## Bir izin için istek akışını belirler.
## Dönen: {action: String, show_rationale: bool, rationale: String}
##   action: "request" | "show_rationale_first" | "open_settings" | "none"
func resolve_request_flow(permission_key: String) -> Dictionary:
	if not PERMISSIONS.has(permission_key):
		return {
			"action": "none", "show_rationale": false,
			"rationale": "",
		}

	var status: int = status_of(permission_key)
	var rationale: String = str(
		PERMISSIONS[permission_key]["rationale"]
	)

	match status:
		PermStatus.GRANTED:
			# Zaten verildi — istek gerekmez
			return {
				"action": "none", "show_rationale": false,
				"rationale": "",
			}
		PermStatus.NOT_REQUESTED:
			# İlk istek — doğrudan iste
			return {
				"action": "request", "show_rationale": false,
				"rationale": rationale,
			}
		PermStatus.DENIED:
			# Bir kez reddedildi — önce gerekçe göster
			return {
				"action": "show_rationale_first",
				"show_rationale": true, "rationale": rationale,
			}
		PermStatus.PERMANENTLY_DENIED:
			# Kalıcı reddedildi — sistem ayarlarına yönlendir
			return {
				"action": "open_settings", "show_rationale": false,
				"rationale": rationale,
			}
		_:
			return {
				"action": "none", "show_rationale": false,
				"rationale": "",
			}


# ============================================================
# SUNUM
# ============================================================

## Tüm izinlerin görsel listesini üretir.
## Dönen: her biri {key, label, status, status_name, color} dizi.
func build_list() -> Array:
	var list: Array = []
	for key in PERMISSIONS:
		var status: int = status_of(key)
		list.append({
			"key": key,
			"label": str(PERMISSIONS[key]["label"]),
			"status": status,
			"status_name": STATUS_NAMES.get(status, "?"),
			"color": STATUS_COLOR.get(status, "#9e9e9e"),
		})
	return list


# ============================================================
# SORGULAMA
# ============================================================

## Bir izin verildi mi?
func is_granted(permission_key: String) -> bool:
	return status_of(permission_key) == PermStatus.GRANTED


## Tüm izinler verildi mi?
func all_granted() -> bool:
	for key in PERMISSIONS:
		if status_of(key) != PermStatus.GRANTED:
			return false
	return true


## Verilen izin sayısı.
func granted_count() -> int:
	var count: int = 0
	for key in PERMISSIONS:
		if status_of(key) == PermStatus.GRANTED:
			count += 1
	return count


## İzlenen toplam izin sayısı.
func permission_count() -> int:
	return PERMISSIONS.size()
