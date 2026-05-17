@tool
class_name AIOfflineRAGResultCache
extends RefCounted

## RAGResultCache — RAG sonuç önbelleği (Madde 07 / Offline / cache).
##
## RAG araması (bilgi tabanında anlamsal sorgu) pahalıdır: embedding
## üret + vektör araması + sonuç sırala. Aynı soru tekrar sorulursa
## aynı sonuç döner — önbelleğe alınmalı.
##
## Embedding cache'ten farkı: RAG sonucu DEĞİŞEBİLİR. Bilgi tabanına
## yeni belge eklenirse eski sonuç eskir. Bu yüzden TTL var (orta
## süreli) ve bilgi tabanı değişince invalidate edilir.
##
## CacheBase'i sarmalar; sonuçlar sıralı belge kimliği dizisi olarak
## saklanır.
##
## Mock policy: önbellek gerçek RAG sonuçlarından dolar.

## RAG sonuçları orta süreli geçerli (saniye, 30 dk).
const RAG_TTL: int = 1800

## Maksimum girdi.
const RAG_MAX_ENTRIES: int = 200


## Alttaki genel önbellek.
var _cache: AIOfflineCacheBase


func _init() -> void:
	_cache = AIOfflineCacheBase.new(RAG_MAX_ENTRIES, RAG_TTL)


# ============================================================
# ANAHTAR
# ============================================================

## Bir RAG sorgusu için önbellek anahtarı.
## query: arama sorgusu. top_k: istenen sonuç sayısı.
## collection: hangi bilgi koleksiyonu.
func make_key(query: String, top_k: int, collection: String) -> String:
	return "%s::%d::%s" % [
		collection, top_k, query.strip_edges().to_lower()
	]


# ============================================================
# ÖNBELLEK İŞLEMLERİ
# ============================================================

## Bir RAG sonucunu önbelleğe alır.
## query/top_k/collection: sorgu kimliği.
## result_ids: sıralı sonuç belge kimlikleri.
## scores: her sonucun benzerlik skoru (isteğe bağlı).
func store(
	query: String, top_k: int, collection: String,
	result_ids: PackedStringArray, scores: PackedFloat32Array
) -> void:
	var key: String = make_key(query, top_k, collection)
	_cache.put(key, {
		"result_ids": result_ids,
		"scores": scores,
	})


## Bir RAG sorgusunun önbelleklenmiş sonucunu döndürür.
## Dönen: {hit: bool, result_ids: PackedStringArray, scores: ...}
func fetch(
	query: String, top_k: int, collection: String
) -> Dictionary:
	var key: String = make_key(query, top_k, collection)
	var result: Dictionary = _cache.get_value(key)
	if not bool(result.get("hit", false)):
		return {
			"hit": false,
			"result_ids": PackedStringArray(),
			"scores": PackedFloat32Array(),
		}
	var cached: Dictionary = result["value"]
	return {
		"hit": true,
		"result_ids": cached["result_ids"],
		"scores": cached["scores"],
	}


## Bir RAG sorgusu önbellekte geçerli mi?
func has(query: String, top_k: int, collection: String) -> bool:
	return _cache.has_valid(make_key(query, top_k, collection))


# ============================================================
# GEÇERSİZLEŞTİRME
# ============================================================

## Bir koleksiyondaki tüm önbelleklenmiş sonuçları geçersizleştirir.
## Bilgi tabanına yeni belge eklenince çağrılır.
## collection: geçersizleşecek koleksiyon.
## Dönen: geçersizleşen girdi sayısı.
func invalidate_collection(collection: String) -> int:
	# Koleksiyon önekli tüm anahtarları sil
	return _cache.invalidate_prefix(collection + "::")


## Tüm RAG önbelleğini temizler.
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
