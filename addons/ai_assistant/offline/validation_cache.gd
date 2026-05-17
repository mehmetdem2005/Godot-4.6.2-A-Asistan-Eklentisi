@tool
class_name AIOfflineValidationCache
extends RefCounted

## ValidationCache — doğrulama önbelleği (Madde 07 / Offline / cache).
##
## AI ürettiği kod doğrulanır (Verifier — Madde): sözdizimi kontrolü,
## statik analiz, test çalıştırma. Bu pahalıdır. Aynı kod parçası
## tekrar doğrulanırsa — aynı sonuç.
##
## Bu önbellek doğrulama sonuçlarını tutar. Anahtar: kodun içeriği
## (içerik değişirse anahtar değişir, otomatik invalidate). Bir kod
## değişmediği sürece doğrulama sonucu geçerlidir.
##
## TTL kısa — doğrulama kuralları (linter sürümü vb.) değişebilir;
## çok eski sonuca güvenmemek güvenli.
##
## CacheBase'i sarmalar.
##
## Mock policy: önbellek gerçek doğrulama sonuçlarından dolar.

## Doğrulama sonuçları kısa süreli geçerli (saniye, 10 dk).
const VALIDATION_TTL: int = 600

## Maksimum girdi.
const VALIDATION_MAX_ENTRIES: int = 300


## Alttaki genel önbellek.
var _cache: AIOfflineCacheBase


func _init() -> void:
	_cache = AIOfflineCacheBase.new(
		VALIDATION_MAX_ENTRIES, VALIDATION_TTL
	)


# ============================================================
# ANAHTAR
# ============================================================

## Bir kod parçası için önbellek anahtarı — içerik özeti.
## İçerik değişirse anahtar değişir; bu otomatik invalidate sağlar.
## code: doğrulanan kod. validator: doğrulayıcı kimliği.
func make_key(code: String, validator: String) -> String:
	# İçeriğin hash'i — uzun kod yerine sabit boylu anahtar
	var content_hash: int = hash(code)
	return "%s::%d" % [validator, content_hash]


# ============================================================
# ÖNBELLEK İŞLEMLERİ
# ============================================================

## Bir doğrulama sonucunu önbelleğe alır.
## code: doğrulanan kod. validator: doğrulayıcı kimliği.
## passed: doğrulama geçti mi.
## issues: bulunan sorunlar (varsa).
func store(
	code: String, validator: String,
	passed: bool, issues: PackedStringArray
) -> void:
	var key: String = make_key(code, validator)
	_cache.put(key, {
		"passed": passed,
		"issues": issues,
	})


## Bir kodun önbelleklenmiş doğrulama sonucunu döndürür.
## Dönen: {hit: bool, passed: bool, issues: PackedStringArray}
func fetch(code: String, validator: String) -> Dictionary:
	var key: String = make_key(code, validator)
	var result: Dictionary = _cache.get_value(key)
	if not bool(result.get("hit", false)):
		return {
			"hit": false, "passed": false,
			"issues": PackedStringArray(),
		}
	var cached: Dictionary = result["value"]
	return {
		"hit": true,
		"passed": bool(cached["passed"]),
		"issues": cached["issues"],
	}


## Bir kodun doğrulama sonucu önbellekte geçerli mi?
func has(code: String, validator: String) -> bool:
	return _cache.has_valid(make_key(code, validator))


# ============================================================
# GEÇERSİZLEŞTİRME
# ============================================================

## Bir doğrulayıcının tüm önbelleklenmiş sonuçlarını geçersizleştirir.
## Linter/doğrulayıcı kuralları güncellenince çağrılır.
## validator: geçersizleşecek doğrulayıcı.
## Dönen: geçersizleşen girdi sayısı.
func invalidate_validator(validator: String) -> int:
	return _cache.invalidate_prefix(validator + "::")


## Tüm doğrulama önbelleğini temizler.
func clear() -> void:
	_cache.clear()


# ============================================================
# DURUM
# ============================================================

## Önbellekteki girdi sayısı.
func size() -> int:
	return _cache.size()


## Önbellek isabet oranı.
func hit_ratio() -> float:
	return _cache.hit_ratio()


## Durum özeti.
func summary() -> Dictionary:
	return _cache.summary()
