@tool
class_name AIOfflineCacheManagement
extends RefCounted

## CacheManagement — önbellek yönetimi (Madde 07 / offline / ui).
##
## Sistem birçok önbellek tutar: LLM yanıtları, embedding'ler, RAG
## sonuçları, varlık metadata'sı, doğrulama sonuçları. Hepsi disk/RAM
## yer. Kullanıcı "ne kadar yer kaplıyor, türe göre temizleyebilir
## miyim" görmek ister.
##
## Bu view-model her önbellek türünün durumunu (boyut, girdi sayısı,
## isabet oranı) görsel bir panele çevirir + "türe göre temizle"
## eylemlerini tanımlar.
##
## Çeşitli cache modülleri (mantık katmanı) ile beslenir; bu sınıf
## onları görsel özetlere çevirir.
##
## Mock policy: pano gerçek önbellek istatistiklerinden.

## İzlenen önbellek türleri ve kullanıcı-dostu etiketleri.
const CACHE_TYPES: Dictionary = {
	"llm_response": "AI Yanıtları",
	"embedding": "Embedding'ler",
	"rag_result": "Bilgi Araması",
	"asset_metadata": "Varlık Bilgisi",
	"validation": "Doğrulama Sonuçları",
}


## Her önbellek türünün son bilinen istatistiği.
## cache_type -> {entries, hit_ratio, estimated_bytes}
var _stats: Dictionary = {}


# ============================================================
# İSTATİSTİK GÜNCELLEME
# ============================================================

## Bir önbellek türünün istatistiğini günceller.
## cache_type: önbellek türü. entries: girdi sayısı.
## hit_ratio: isabet oranı (0-1). estimated_bytes: tahmini boyut.
func update_stats(
	cache_type: String, entries: int,
	hit_ratio: float, estimated_bytes: int
) -> void:
	if not CACHE_TYPES.has(cache_type):
		return
	_stats[cache_type] = {
		"entries": maxi(entries, 0),
		"hit_ratio": clampf(hit_ratio, 0.0, 1.0),
		"estimated_bytes": maxi(estimated_bytes, 0),
	}


# ============================================================
# PANEL LİSTESİ
# ============================================================

## Tüm önbellek türlerinin görsel listesini üretir.
## Dönen: her biri {type, label, entries, hit_percent, mb} dizi.
func build_list() -> Array:
	var list: Array = []
	for cache_type in CACHE_TYPES:
		var stat: Dictionary = _stats.get(cache_type, {
			"entries": 0, "hit_ratio": 0.0, "estimated_bytes": 0,
		})
		list.append({
			"type": cache_type,
			"label": str(CACHE_TYPES[cache_type]),
			"entries": int(stat["entries"]),
			"hit_percent": float(stat["hit_ratio"]) * 100.0,
			"mb": float(stat["estimated_bytes"]) / (1024.0 * 1024.0),
		})
	return list


# ============================================================
# ÖZET
# ============================================================

## Tüm önbelleklerin toplam istatistiği.
## Dönen: {total_entries, total_mb, type_count}
func build_summary() -> Dictionary:
	var total_entries: int = 0
	var total_bytes: int = 0
	for cache_type in _stats:
		var stat: Dictionary = _stats[cache_type]
		total_entries += int(stat["entries"])
		total_bytes += int(stat["estimated_bytes"])
	return {
		"total_entries": total_entries,
		"total_mb": float(total_bytes) / (1024.0 * 1024.0),
		"type_count": CACHE_TYPES.size(),
	}


# ============================================================
# TEMİZLEME EYLEMİ
# ============================================================

## Bir önbellek türü için temizleme eylem tanımı üretir.
## UI butonu bu tanımı kullanır; gerçek temizlik ilgili cache
## modülünün clear() çağrısıyla yapılır.
## Dönen: {type, label, can_clear, reason}
func clear_action(cache_type: String) -> Dictionary:
	if not CACHE_TYPES.has(cache_type):
		return {
			"type": cache_type, "label": "", "can_clear": false,
			"reason": "Bilinmeyen önbellek türü",
		}
	var stat: Dictionary = _stats.get(cache_type, {"entries": 0})
	var entries: int = int(stat["entries"])
	return {
		"type": cache_type,
		"label": str(CACHE_TYPES[cache_type]),
		"can_clear": entries > 0,
		"reason": "%d girdi temizlenebilir" % entries if entries > 0 \
			else "Önbellek zaten boş",
	}


## Bir önbellek türü temizlendiğinde istatistiği sıfırlar.
func mark_cleared(cache_type: String) -> void:
	if _stats.has(cache_type):
		_stats[cache_type] = {
			"entries": 0, "hit_ratio": 0.0, "estimated_bytes": 0,
		}


# ============================================================
# SORGULAMA
# ============================================================

## İzlenen önbellek türü sayısı.
func cache_type_count() -> int:
	return CACHE_TYPES.size()
