@tool
class_name AIRateLimiter
extends RefCounted

## RateLimiter — işlem hız sınırlayıcı (Layer 4).
##
## Saniyede sınırsız dosya işlemi = kontrolden çıkmış döngü riski.
## Hatalı bir plan veya sonsuz döngü diski/sistemi boğmasın.
##
## Sliding-window algoritması: son N saniyedeki işlem sayısı sayılır,
## limit aşılırsa yeni işlem reddedilir (pencere kayınca tekrar açılır).
##
## Zaman kaynağı dışarıdan verilebilir — bu, testlerin deterministik
## olmasını sağlar (gerçek saat beklemeden simüle edilir).

## Varsayılan: 10 saniyelik pencerede en fazla 100 işlem.
const DEFAULT_WINDOW_SECONDS: int = 10
const DEFAULT_MAX_OPS_IN_WINDOW: int = 100

var window_seconds: int = DEFAULT_WINDOW_SECONDS
var max_ops_in_window: int = DEFAULT_MAX_OPS_IN_WINDOW

## Pencere içindeki işlemlerin zaman damgaları (unix saniye).
var _timestamps: Array = []


## Tüm kayıtları temizler.
func reset() -> void:
	_timestamps.clear()


## Verilen anda yeni bir işleme izin var mı kontrol eder.
## now_unix: şu anki zaman (unix saniye). Test için dışarıdan verilir.
## Dönen: {allowed: bool, reason: String, current_count: int}
func check_allowed(now_unix: int) -> Dictionary:
	_evict_old(now_unix)
	var count: int = _timestamps.size()
	if count >= max_ops_in_window:
		return {
			"allowed": false,
			"reason": "Hız limiti: %d sn'de %d işlem (max %d)" % [
				window_seconds, count, max_ops_in_window
			],
			"current_count": count,
		}
	return {"allowed": true, "reason": "", "current_count": count}


## Bir işlemi kaydeder — işlem yapıldıktan sonra çağrılır.
func record(now_unix: int) -> void:
	_evict_old(now_unix)
	_timestamps.append(now_unix)


## İzin kontrolü + kayıt tek adımda — işlem yapılacaksa kullanışlı.
## Dönen: {allowed, reason, current_count}
func try_acquire(now_unix: int) -> Dictionary:
	var check: Dictionary = check_allowed(now_unix)
	if check["allowed"]:
		_timestamps.append(now_unix)
	return check


## Pencere dışına çıkmış (eski) zaman damgalarını atar.
func _evict_old(now_unix: int) -> void:
	var cutoff: int = now_unix - window_seconds
	var kept: Array = []
	for ts in _timestamps:
		if ts > cutoff:
			kept.append(ts)
	_timestamps = kept


## Şu anki pencere kullanımı.
func usage(now_unix: int) -> Dictionary:
	_evict_old(now_unix)
	var count: int = _timestamps.size()
	return {
		"current_count": count,
		"max_ops": max_ops_in_window,
		"window_seconds": window_seconds,
		"remaining": maxi(0, max_ops_in_window - count),
	}
