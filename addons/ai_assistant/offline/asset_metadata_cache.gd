@tool
class_name AIOfflineAssetMetadataCache
extends RefCounted

## AssetMetadataCache — varlık metadata önbelleği (Madde 07 / cache).
##
## Oyun varlıkları (sahne, doku, model, ses) hakkında metadata vardır:
## boyut, bağımlılıklar, son değişiklik zamanı, içe-aktarım ayarları.
## Bu bilgiyi her seferinde diskten taramak yavaştır — özellikle
## büyük projelerde.
##
## Bu önbellek varlık metadata'sını tutar. Varlık dosyası değişince
## o varlığın metadata'sı geçersizleşir — dosya yolu anahtarıyla
## hedefli invalidate.
##
## CacheBase'i sarmalar. TTL orta süreli — varlıklar sık değişmez
## ama değişebilir.
##
## Mock policy: önbellek gerçek varlık taramalarından dolar.

## Varlık metadata orta süreli geçerli (saniye, 1 saat).
const ASSET_TTL: int = 3600

## Maksimum girdi — büyük proje çok varlık.
const ASSET_MAX_ENTRIES: int = 1000


## Alttaki genel önbellek.
var _cache: AIOfflineCacheBase


func _init() -> void:
	_cache = AIOfflineCacheBase.new(ASSET_MAX_ENTRIES, ASSET_TTL)


# ============================================================
# ANAHTAR
# ============================================================

## Bir varlık için önbellek anahtarı — dosya yolu.
func make_key(asset_path: String) -> String:
	return asset_path.strip_edges()


# ============================================================
# ÖNBELLEK İŞLEMLERİ
# ============================================================

## Bir varlığın metadata'sını önbelleğe alır.
## asset_path: varlık dosya yolu.
## metadata: {size, dependencies, modified_time, import_settings...}
func store(asset_path: String, metadata: Dictionary) -> void:
	if asset_path.strip_edges().is_empty():
		return
	_cache.put(make_key(asset_path), metadata.duplicate(true))


## Bir varlığın önbelleklenmiş metadata'sını döndürür.
## Dönen: {hit: bool, metadata: Dictionary}
func fetch(asset_path: String) -> Dictionary:
	var result: Dictionary = _cache.get_value(make_key(asset_path))
	if not bool(result.get("hit", false)):
		return {"hit": false, "metadata": {}}
	return {"hit": true, "metadata": result["value"]}


## Bir varlığın metadata'sı önbellekte geçerli mi?
func has(asset_path: String) -> bool:
	return _cache.has_valid(make_key(asset_path))


# ============================================================
# GEÇERSİZLEŞTİRME
# ============================================================

## Bir varlığın metadata'sını geçersizleştirir.
## Varlık dosyası değişince çağrılır.
## Dönen: true = vardı ve geçersizleşti.
func invalidate(asset_path: String) -> bool:
	return _cache.invalidate(make_key(asset_path))


## Bir klasördeki tüm varlıkların metadata'sını geçersizleştirir.
## folder_path: klasör yolu.
## Dönen: geçersizleşen girdi sayısı.
func invalidate_folder(folder_path: String) -> int:
	var prefix: String = folder_path.strip_edges()
	if not prefix.ends_with("/"):
		prefix += "/"
	return _cache.invalidate_prefix(prefix)


## Tüm varlık metadata önbelleğini temizler.
func clear() -> void:
	_cache.clear()


# ============================================================
# DURUM
# ============================================================

## Önbellekteki varlık sayısı.
func size() -> int:
	return _cache.size()


## Önbellek isabet oranı.
func hit_ratio() -> float:
	return _cache.hit_ratio()


## Durum özeti.
func summary() -> Dictionary:
	return _cache.summary()
