@tool
class_name AILifecyclePermissionManager
extends RefCounted

## PermissionManager — izin yöneticisi (Madde 10 / App Lifecycle).
##
## Android'de bazı özellikler izin ister: mikrofon, kamera, depolama,
## bildirim. Bu sınıf izin DURUMLARINI izler — hangi izin verildi,
## hangi reddedildi, hangi hiç sorulmadı.
##
## İzin durumu basit "var/yok" değil:
##   UNKNOWN     — henüz sorulmadı
##   GRANTED     — verildi
##   DENIED      — reddedildi (tekrar sorulabilir)
##   DENIED_PERMANENTLY — kalıcı reddedildi (ayarlardan açılmalı)
##
## Gerçek Android izin API'si ince sarmalayıcının işi; bu sınıf
## durum takibi + karar mantığıdır — test edilebilir.
##
## Mock policy: izin durumu gerçek sistemden bildirilir; sınıf
## durumu izler, karar üretir.

## İzin durumları.
enum PermStatus { UNKNOWN, GRANTED, DENIED, DENIED_PERMANENTLY }

const STATUS_NAMES: Dictionary = {
	PermStatus.UNKNOWN: "unknown",
	PermStatus.GRANTED: "granted",
	PermStatus.DENIED: "denied",
	PermStatus.DENIED_PERMANENTLY: "denied_permanently",
}

## Bilinen izin tipleri.
const PERM_MICROPHONE: String = "microphone"
const PERM_CAMERA: String = "camera"
const PERM_STORAGE: String = "storage"
const PERM_NOTIFICATIONS: String = "notifications"
const PERM_LOCATION: String = "location"

const KNOWN_PERMISSIONS: Array = [
	PERM_MICROPHONE, PERM_CAMERA, PERM_STORAGE,
	PERM_NOTIFICATIONS, PERM_LOCATION,
]


## İzin durumları — permission -> PermStatus.
var _statuses: Dictionary = {}


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Bir iznin durumunu kaydeder — sistemden gelen sonuçtan.
## permission: izin tipi. status: PermStatus.
## Dönen: true = kayıt başarılı.
func set_status(permission: String, status: int) -> bool:
	if not KNOWN_PERMISSIONS.has(permission):
		push_warning("PermissionManager: bilinmeyen izin: " + permission)
		return false
	if not STATUS_NAMES.has(status):
		push_warning("PermissionManager: geçersiz izin durumu")
		return false
	_statuses[permission] = status
	return true


## Bir iznin durumunu döndürür. Kayıt yoksa UNKNOWN.
func get_status(permission: String) -> int:
	return int(_statuses.get(permission, PermStatus.UNKNOWN))


## Bir iznin durum adı.
func status_name(permission: String) -> String:
	return STATUS_NAMES.get(get_status(permission), "?")


# ============================================================
# SORGULAMA
# ============================================================

## Bir izin verildi mi?
func is_granted(permission: String) -> bool:
	return get_status(permission) == PermStatus.GRANTED


## Bir izin istenebilir mi?
## UNKNOWN veya DENIED — istenebilir. GRANTED — gerek yok.
## DENIED_PERMANENTLY — istenemez, kullanıcı ayarlardan açmalı.
func can_request(permission: String) -> bool:
	var status: int = get_status(permission)
	return status == PermStatus.UNKNOWN or status == PermStatus.DENIED


## Bir izin için kullanıcının ayarlara yönlendirilmesi mi gerekiyor?
func needs_settings_redirect(permission: String) -> bool:
	return get_status(permission) == PermStatus.DENIED_PERMANENTLY


## Bir özellik için gerekli izinlerin hepsi verildi mi?
## required: gerekli izin adları dizisi.
func all_granted(required: Array) -> bool:
	for permission in required:
		if not is_granted(str(permission)):
			return false
	return true


## Verilen izinlerin listesi.
func granted_permissions() -> PackedStringArray:
	var granted: PackedStringArray = PackedStringArray()
	for permission in _statuses:
		if int(_statuses[permission]) == PermStatus.GRANTED:
			granted.append(permission)
	return granted


## Durum özeti.
func summary() -> Dictionary:
	return {
		"tracked": _statuses.size(),
		"granted": granted_permissions().size(),
	}
