@tool
class_name AIOfflineDataMeter
extends RefCounted

## DataMeter — veri sayacı (Madde 07 / Offline / bandwidth).
##
## Mobil veri pahalı ve sınırlı. Bu sistem ağ kullanan işlemler yapar:
## LLM çağrısı, embedding üretimi, varlık indirme. Her biri veri yer.
##
## Bu sınıf her işlem türü için veri kullanımını KAYDEDER: kaç bayt
## gönderildi, kaç bayt alındı, hangi kategoride. "LLM çağrıları bu
## ay 12 MB yedi" gibi raporlar üretir.
##
## Kategori bazlı kayıt önemli: kullanıcı hangi özelliğin veri yediğini
## görür, governor hangi kategoriyi kısacağını bilir.
##
## Mock policy: sayımlar gerçek kaydedilen işlemlerden.

## İşlem kategorileri.
const CATEGORY_LLM: String = "llm"
const CATEGORY_EMBEDDING: String = "embedding"
const CATEGORY_ASSET: String = "asset"
const CATEGORY_SYNC: String = "sync"
const CATEGORY_OTHER: String = "other"


## Kategori başına kayıt — kategori -> {sent, received, count}.
var _records: Dictionary = {}

## Sayacın başladığı zaman (unix) — dönem takibi.
var period_start_unix: int = 0


func _init(start_unix: int = 0) -> void:
	period_start_unix = start_unix


# ============================================================
# KAYIT
# ============================================================

## Bir ağ işleminin veri kullanımını kaydeder.
## category: işlem kategorisi.
## bytes_sent: gönderilen bayt. bytes_received: alınan bayt.
func record(
	category: String, bytes_sent: int, bytes_received: int
) -> void:
	if not _records.has(category):
		_records[category] = {"sent": 0, "received": 0, "count": 0}
	var rec: Dictionary = _records[category]
	rec["sent"] = int(rec["sent"]) + maxi(bytes_sent, 0)
	rec["received"] = int(rec["received"]) + maxi(bytes_received, 0)
	rec["count"] = int(rec["count"]) + 1


# ============================================================
# SORGULAMA — KATEGORİ
# ============================================================

## Bir kategorinin toplam veri kullanımı (gönderilen + alınan).
func category_total(category: String) -> int:
	if not _records.has(category):
		return 0
	var rec: Dictionary = _records[category]
	return int(rec["sent"]) + int(rec["received"])


## Bir kategorideki işlem sayısı.
func category_count(category: String) -> int:
	if not _records.has(category):
		return 0
	return int(_records[category]["count"])


## Bir kategorinin gönderilen baytı.
func category_sent(category: String) -> int:
	if not _records.has(category):
		return 0
	return int(_records[category]["sent"])


## Bir kategorinin alınan baytı.
func category_received(category: String) -> int:
	if not _records.has(category):
		return 0
	return int(_records[category]["received"])


# ============================================================
# SORGULAMA — TOPLAM
# ============================================================

## Tüm kategorilerin toplam veri kullanımı.
func total_usage() -> int:
	var total: int = 0
	for category in _records:
		total += category_total(category)
	return total


## En çok veri yiyen kategoriyi döndürür. Kayıt yoksa boş string.
func top_consumer() -> String:
	var top_category: String = ""
	var top_amount: int = -1
	for category in _records:
		var amount: int = category_total(category)
		if amount > top_amount:
			top_amount = amount
			top_category = category
	return top_category


## Kategori bazlı kullanım dökümü.
func breakdown() -> Dictionary:
	var result: Dictionary = {}
	for category in _records:
		result[category] = category_total(category)
	return result


# ============================================================
# DÖNEM YÖNETİMİ
# ============================================================

## Sayacı sıfırlar — yeni veri dönemi (örn. aylık reset).
func reset(new_period_start_unix: int) -> void:
	_records.clear()
	period_start_unix = new_period_start_unix


## Baytı megabayta çevirir.
func bytes_to_mb(bytes: int) -> float:
	return float(bytes) / (1024.0 * 1024.0)
