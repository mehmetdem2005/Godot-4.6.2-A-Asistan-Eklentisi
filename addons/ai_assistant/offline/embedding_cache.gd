@tool
class_name AIOfflineEmbeddingCache
extends RefCounted

## EmbeddingCache — embedding önbelleği (Madde 07 / Offline / cache).
##
## Embedding = bir metnin sayısal vektör temsili (RAG aramada
## kullanılır). Üretmek ağ + hesap ister. Ama bir metnin embedding'i
## ASLA DEĞİŞMEZ — aynı metin her zaman aynı vektör.
##
## Bu yüzden embedding önbelleği özellikle değerli: bir kez üret,
## sonsuza dek kullan. TTL bile gerekmez (sınırsız) — sadece bellek
## sınırı için LRU.
##
## CacheBase'i sarmalar; embedding'ler PackedFloat32Array olarak
## saklanır.
##
## Mock policy: önbellek gerçek embedding'lerden dolar.

## Embedding'ler değişmez — TTL yok (sınırsız).
const EMBEDDING_TTL: int = 0

## Maksimum girdi.
const EMBEDDING_MAX_ENTRIES: int = 500


## Alttaki genel önbellek.
var _cache: AIOfflineCacheBase


func _init() -> void:
	_cache = AIOfflineCacheBase.new(EMBEDDING_MAX_ENTRIES, EMBEDDING_TTL)


# ============================================================
# ANAHTAR
# ============================================================

## Bir metin için embedding önbellek anahtarı.
## text: embedding'i alınacak metin. model: embedding modeli.
func make_key(text: String, model: String) -> String:
	var raw: String = "%s|%s" % [model, text]
	return "emb_" + str(raw.hash())


# ============================================================
# YAZMA / OKUMA
# ============================================================

## Bir embedding'i önbelleğe yazar.
## text/model: tanım. embedding: vektör (float dizisi).
func store(
	text: String, model: String, embedding: PackedFloat32Array
) -> void:
	var key: String = make_key(text, model)
	_cache.put(key, embedding)


## Bir metin için önbellekteki embedding'i arar.
## Dönen: {hit: bool, embedding: PackedFloat32Array}
func lookup(text: String, model: String) -> Dictionary:
	var key: String = make_key(text, model)
	var result: Dictionary = _cache.get_value(key)
	if result["hit"]:
		var value: Variant = result["value"]
		if value is PackedFloat32Array:
			return {"hit": true, "embedding": value}
	return {"hit": false, "embedding": PackedFloat32Array()}


## Bir metnin embedding'i önbellekte var mı?
func is_cached(text: String, model: String) -> bool:
	return _cache.has_valid(make_key(text, model))


# ============================================================
# YÖNETİM
# ============================================================

## Önbelleği temizler.
func clear() -> void:
	_cache.clear()


## Alttaki önbellek — istatistik için.
func cache() -> AIOfflineCacheBase:
	return _cache


## Özet.
func summary() -> Dictionary:
	return _cache.summary()
