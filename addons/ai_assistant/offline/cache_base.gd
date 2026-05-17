@tool
class_name AIOfflineCacheBase
extends RefCounted

## CacheBase — önbellek temel sınıfı (Madde 07 / Offline / cache).
##
## Offline çalışmanın anahtarı: önbellek. Sistem bir kez aldığı sonucu
## (LLM cevabı, embedding, RAG sonucu) saklar — internet gidince o
## önbellekten okur, çökmez.
##
## Bu temel sınıf TÜM önbellek tiplerinin paylaştığı mantığı tutar:
##   - LRU (Least Recently Used) — yer dolunca en az kullanılanı at
##   - TTL (Time To Live) — eski girdiler süresi dolunca geçersiz
##   - boyut sınırı — sınırsız büyüme yok (mobil bellek kısıtlı)
##
## Somut önbellekler (llm_response_cache, embedding_cache...) bunu
## genişletir, sadece kendi anahtar üretimini ekler.
##
## Mock policy: önbellek gerçek veriden dolar; süre/boyut gerçek
## kurallardan.

## Bir önbellek girdisi.
class CacheEntry extends RefCounted:
	var key: String = ""
	var value: Variant = null
	var stored_at: int = 0             ## Saklanma zamanı (unix)
	var last_access: int = 0           ## Son erişim sırası (monoton tick)
	var ttl_seconds: int = 0           ## Yaşam süresi (0 = sınırsız)

	## Girdi süresi doldu mu? now_unix: şu anki zaman.
	func is_expired(now_unix: int) -> bool:
		if ttl_seconds <= 0:
			return false  # TTL yok — hiç sona ermez
		return (now_unix - stored_at) >= ttl_seconds

	func to_dict() -> Dictionary:
		return {
			"key": key, "stored_at": stored_at,
			"last_access": last_access, "ttl_seconds": ttl_seconds,
		}


## Önbellek girdileri — key -> CacheEntry.
var _entries: Dictionary = {}

## Maksimum girdi sayısı — aşılınca LRU eviction.
var max_entries: int = 100

## Varsayılan TTL (saniye, 0 = sınırsız).
var default_ttl: int = 3600

## LRU sıralaması için monoton artan erişim sayacı.
## Saniye-hassasiyetli zamana güvenmek yanlış: aynı saniyede birden
## fazla put/get olabilir, last_access eşitlenir, LRU yanlış kurban
## seçer. Sayaç her erişimde artar — sıralama her zaman kesin.
var _access_tick: int = 0

## İstatistik — isabet/ıska.
var _hits: int = 0
var _misses: int = 0


func _init(p_max_entries: int = 100, p_default_ttl: int = 3600) -> void:
	max_entries = maxi(p_max_entries, 1)
	default_ttl = maxi(p_default_ttl, 0)


# ============================================================
# YAZMA
# ============================================================

## Bir değeri önbelleğe yazar.
## key: anahtar. value: saklanacak değer. ttl_override: -1 ise
## varsayılan TTL kullanılır.
func put(key: String, value: Variant, ttl_override: int = -1) -> void:
	if key.is_empty():
		push_warning("CacheBase: boş anahtar reddedildi")
		return
	var now: int = _now()
	_access_tick += 1
	var entry := CacheEntry.new()
	entry.key = key
	entry.value = value
	entry.stored_at = now
	entry.last_access = _access_tick
	entry.ttl_seconds = default_ttl if ttl_override < 0 else ttl_override
	_entries[key] = entry
	# Boyut sınırı — gerekirse LRU eviction
	_enforce_size_limit()


# ============================================================
# OKUMA
# ============================================================

## Bir değeri önbellekten okur.
## key: anahtar.
## Dönen: {hit: bool, value: Variant}
##   hit=false: anahtar yok VEYA süresi dolmuş.
func get_value(key: String) -> Dictionary:
	if not _entries.has(key):
		_misses += 1
		return {"hit": false, "value": null}

	var entry: CacheEntry = _entries[key]
	var now: int = _now()

	# Süre kontrolü — dolmuşsa ıska + temizle
	if entry.is_expired(now):
		_entries.erase(key)
		_misses += 1
		return {"hit": false, "value": null}

	# İsabet — son erişimi güncelle (LRU için)
	_access_tick += 1
	entry.last_access = _access_tick
	_hits += 1
	return {"hit": true, "value": entry.value}


## Bir anahtar önbellekte var ve geçerli mi?
func has_valid(key: String) -> bool:
	return get_value(key)["hit"]


# ============================================================
# GEÇERSİZ KILMA
# ============================================================

## Bir anahtarı önbellekten siler.
## Dönen: true = vardı ve silindi.
func invalidate(key: String) -> bool:
	if not _entries.has(key):
		return false
	_entries.erase(key)
	return true


## Tüm önbelleği temizler.
func clear() -> void:
	_entries.clear()


## Süresi dolmuş tüm girdileri temizler.
## Dönen: temizlenen girdi sayısı.
func purge_expired() -> int:
	var now: int = _now()
	var expired_keys: Array = []
	for key in _entries:
		if (_entries[key] as CacheEntry).is_expired(now):
			expired_keys.append(key)
	for key in expired_keys:
		_entries.erase(key)
	return expired_keys.size()


# ============================================================
# LRU EVICTION
# ============================================================

## Boyut sınırı aşıldıysa en az kullanılan girdileri atar.
func _enforce_size_limit() -> void:
	while _entries.size() > max_entries:
		var lru_key: String = _find_lru_key()
		if lru_key.is_empty():
			break
		_entries.erase(lru_key)


## En az yakında kullanılan (en eski last_access) anahtarı bulur.
func _find_lru_key() -> String:
	var oldest_key: String = ""
	var oldest_access: int = 9223372036854775807  # int max
	for key in _entries:
		var entry: CacheEntry = _entries[key]
		if entry.last_access < oldest_access:
			oldest_access = entry.last_access
			oldest_key = key
	return oldest_key


# ============================================================
# İSTATİSTİK
# ============================================================

## Önbellekteki girdi sayısı.
func size() -> int:
	return _entries.size()


## İsabet oranı (0.0 - 1.0).
func hit_ratio() -> float:
	var total: int = _hits + _misses
	if total == 0:
		return 0.0
	return float(_hits) / float(total)


## Önbellek istatistik özeti.
func summary() -> Dictionary:
	return {
		"size": _entries.size(),
		"max_entries": max_entries,
		"hits": _hits,
		"misses": _misses,
		"hit_ratio": hit_ratio(),
	}


# ============================================================
# DAHİLİ
# ============================================================

## Önbellekteki tüm anahtarları döndürür.
func keys() -> Array:
	return _entries.keys()


## Belirli bir önekle başlayan tüm anahtarları geçersizleştirir.
## prefix: anahtar öneki.
## Dönen: geçersizleşen girdi sayısı.
func invalidate_prefix(prefix: String) -> int:
	var to_remove: Array = []
	for key in _entries:
		if str(key).begins_with(prefix):
			to_remove.append(key)
	for key in to_remove:
		_entries.erase(key)
	return to_remove.size()


## Şu anki unix zamanı.
func _now() -> int:
	return int(Time.get_unix_time_from_system())
