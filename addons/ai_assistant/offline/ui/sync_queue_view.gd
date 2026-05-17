@tool
class_name AIOfflineSyncQueueView
extends RefCounted

## SyncQueueView — senkr. kuyruğu görünümü (Madde 07 / offline / ui).
##
## SyncQueue bekleyen işlemleri tutar. Kullanıcı "ne bekliyor, ne
## zaman gönderilecek" görmek ister. Bu view-model kuyruğu görsel
## bir listeye çevirir: işlem adı, durumu, öncelik sırası.
##
## sync_queue + priority_resolver (mantık katmanı) ile beslenir; bu
## sınıf onu kullanıcı-dostu satırlara dönüştürür.
##
## Mock policy: liste gerçek kuyruk içeriğinden.

## Bir kuyruk satırının görsel durumu.
enum RowStatus { PENDING, RETRYING, PROCESSING }

const STATUS_NAMES: Dictionary = {
	RowStatus.PENDING: "pending",
	RowStatus.RETRYING: "retrying",
	RowStatus.PROCESSING: "processing",
}

## İşlem türü -> kullanıcı-dostu etiket.
const TYPE_LABELS: Dictionary = {
	"save_sync": "Kayıt Senkronu",
	"purchase": "Satın Alma",
	"leaderboard": "Skor Tablosu",
	"achievement": "Başarım",
	"analytics": "Analitik",
	"cache_refresh": "Önbellek Tazeleme",
}


## Şu an işlenen işlemin kimliği (yoksa boş).
var processing_id: String = ""


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Şu an işlenmekte olan işlemi işaretler.
func set_processing(op_id: String) -> void:
	processing_id = op_id


## İşleme bitti — işaret temizlenir.
func clear_processing() -> void:
	processing_id = ""


# ============================================================
# GÖRÜNÜM LİSTESİ
# ============================================================

## Kuyruk işlemlerini görsel satırlara çevirir.
## operations: sync_queue.all_operations() çıktısı (öncelik sıralı).
## Dönen: her biri {id, label, status, status_name, retry_count} dizi.
func build_rows(operations: Array) -> Array:
	var rows: Array = []
	for op in operations:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = op
		var op_id: String = str(dict.get("id", ""))
		var op_type: String = str(dict.get("type", ""))
		var retry_count: int = int(dict.get("retry_count", 0))

		# Satır durumu
		var status: int = RowStatus.PENDING
		if op_id == processing_id:
			status = RowStatus.PROCESSING
		elif retry_count > 0:
			status = RowStatus.RETRYING

		rows.append({
			"id": op_id,
			"label": TYPE_LABELS.get(op_type, op_type),
			"status": status,
			"status_name": STATUS_NAMES.get(status, "?"),
			"retry_count": retry_count,
		})
	return rows


# ============================================================
# ÖZET
# ============================================================

## Kuyruk özeti — UI başlığında gösterilir.
## operations: kuyruk işlemleri.
## Dönen: {total, retrying, pending, summary_text}
func build_summary(operations: Array) -> Dictionary:
	var total: int = operations.size()
	var retrying: int = 0
	for op in operations:
		if typeof(op) == TYPE_DICTIONARY \
				and int((op as Dictionary).get("retry_count", 0)) > 0:
			retrying += 1

	var summary_text: String
	if total == 0:
		summary_text = "Bekleyen işlem yok"
	elif retrying > 0:
		summary_text = "%d işlem bekliyor (%d yeniden deneme)" % [
			total, retrying
		]
	else:
		summary_text = "%d işlem bekliyor" % total

	return {
		"total": total,
		"retrying": retrying,
		"pending": total - retrying,
		"summary_text": summary_text,
	}


## Kuyruk boş mu (gösterilecek satır yok)?
func is_empty(operations: Array) -> bool:
	return operations.is_empty()
