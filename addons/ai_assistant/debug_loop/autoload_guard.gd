@tool
class_name AIDebugAutoloadGuard
extends RefCounted

## AutoloadGuard — autoload koruyucusu (Madde 02 / Debug Loop / core).
##
## Debug Loop kodu sandbox'ta çalıştırır. Tehlike: sandbox'taki kod
## projenin GERÇEK autoload singleton'larını (oyunun global durumu)
## değiştirebilir. Bir test çalışması oyunun kalıcı verisini bozmamalı.
##
## Bu sınıf bir KORUMA KATMANI: sandbox kodunun hangi autoload'lara
## dokunmaya çalıştığını izler, korumalı olanlara yazmayı reddeder.
##
## Salt-okunur autoload'lar: oyunun konfigürasyonu, kayıt verisi.
## Sandbox bunları OKUYABİLİR ama DEĞİŞTİREMEZ.
##
## Mock policy: koruma gerçek erişim denemelerinden; izin gerçek
## kurallardan.

## Bir erişim denemesinin türü.
enum AccessKind { READ, WRITE }

## Bir erişim kararı.
enum AccessVerdict { ALLOWED, BLOCKED }

const VERDICT_NAMES: Dictionary = {
	AccessVerdict.ALLOWED: "allowed",
	AccessVerdict.BLOCKED: "blocked",
}


## Korumalı autoload adları — sandbox bunlara yazamaz.
var _protected: Dictionary = {}

## Engellenen yazma denemelerinin kaydı.
var _blocked_attempts: Array = []


# ============================================================
# KORUMA TANIMLAMA
# ============================================================

## Bir autoload'ı korumalı olarak işaretler — sandbox yazamaz.
func protect(autoload_name: String) -> void:
	if autoload_name.is_empty():
		return
	_protected[autoload_name] = true


## Birden fazla autoload'ı korur.
func protect_all(autoload_names: Array) -> void:
	for name in autoload_names:
		protect(str(name))


## Bir autoload korumalı mı?
func is_protected(autoload_name: String) -> bool:
	return _protected.has(autoload_name)


## Korumalı autoload sayısı.
func protected_count() -> int:
	return _protected.size()


# ============================================================
# ERİŞİM DENETİMİ
# ============================================================

## Sandbox'tan bir autoload erişim denemesini denetler.
## autoload_name: erişilen autoload. kind: READ veya WRITE.
## Dönen: {verdict: String, allowed: bool, reason: String}
func check_access(autoload_name: String, kind: int) -> Dictionary:
	# Okuma her zaman serbest — sandbox global durumu okuyabilir
	if kind == AccessKind.READ:
		return {
			"verdict": VERDICT_NAMES[AccessVerdict.ALLOWED],
			"allowed": true,
			"reason": "Okuma serbest",
		}

	# Yazma — korumalı autoload'a izin yok
	if is_protected(autoload_name):
		_blocked_attempts.append({
			"autoload": autoload_name,
			"kind": "write",
		})
		return {
			"verdict": VERDICT_NAMES[AccessVerdict.BLOCKED],
			"allowed": false,
			"reason": "Korumalı autoload — sandbox yazamaz: " \
				+ autoload_name,
		}

	# Korumasız autoload'a yazma serbest
	return {
		"verdict": VERDICT_NAMES[AccessVerdict.ALLOWED],
		"allowed": true,
		"reason": "Korumasız autoload — yazma serbest",
	}


## Bir yazma denemesi izinli mi — hızlı kontrol.
func can_write(autoload_name: String) -> bool:
	return check_access(autoload_name, AccessKind.WRITE)["allowed"]


# ============================================================
# RAPOR
# ============================================================

## Engellenen yazma denemesi sayısı.
func blocked_count() -> int:
	return _blocked_attempts.size()


## Engellenen denemelerin listesi.
func blocked_attempts() -> Array:
	return _blocked_attempts.duplicate()


## Bir sandbox çalışması bittiğinde engelleme kaydını temizler.
func reset() -> void:
	_blocked_attempts.clear()


## Durum özeti.
func summary() -> Dictionary:
	return {
		"protected_count": _protected.size(),
		"blocked_attempts": _blocked_attempts.size(),
	}
