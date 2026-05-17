@tool
class_name AIOfflineQueueProcessor
extends RefCounted

## QueueProcessor — kuyruk işleyici (Madde 07 / Offline / queue).
##
## SyncQueue işlemleri tutar, PriorityResolver sıralar — Processor
## bağlantı gelince kuyruğu İŞLER. Çevrimdışı biriken işlemleri
## çevrimiçi olunca tek tek gönderir.
##
## Akıllı işleme:
##   - öncelik sırasıyla işle (priority_resolver)
##   - her seferde sınırlı sayıda (batch — ağı boğmamak için)
##   - başarısız işlemi yeniden dene (retry sayacı)
##   - çok denenmiş işlemi vazgeç (kalıcı hata — sonsuz döngü olmasın)
##   - bağlantı kesilirse dur (yarım işleme tehlikeli)
##
## "Mock yasak": işlemin gerçekten gönderilmesi dış sistemin işi;
## bu sınıf işleme PLANINI ve sonuç takibini yapar.
##
## Mock policy: işleme durumu gerçek kuyruk + bağlantıdan.

## Bir işlemin maksimum deneme sayısı — bundan sonra vazgeçilir.
const MAX_RETRIES: int = 5

## Tek seferde işlenecek maksimum işlem sayısı (batch).
const DEFAULT_BATCH_SIZE: int = 10


## Senkronizasyon kuyruğu.
var _queue: AIOfflineSyncQueue

## Öncelik çözücü.
var _resolver: AIOfflinePriorityResolver

## Tek batch'te işlenecek işlem sayısı.
var batch_size: int = DEFAULT_BATCH_SIZE

## İşleme istatistikleri.
var _total_processed: int = 0
var _total_succeeded: int = 0
var _total_abandoned: int = 0


func _init(
	queue: AIOfflineSyncQueue = null,
	resolver: AIOfflinePriorityResolver = null
) -> void:
	_queue = queue if queue != null else AIOfflineSyncQueue.new()
	_resolver = resolver if resolver != null \
		else AIOfflinePriorityResolver.new()


# ============================================================
# İŞLEME PLANI
# ============================================================

## Bir batch için işlenecek işlemleri belirler — öncelik sırasıyla.
## is_online: bağlantı var mı.
## current_unix: şu anki zaman (bekleme süresi hesabı).
## Dönen: {can_process: bool, batch: Array, reason: String}
func plan_batch(is_online: bool, current_unix: int) -> Dictionary:
	# Çevrimdışı — işleme yapılamaz
	if not is_online:
		return {
			"can_process": false, "batch": [],
			"reason": "Bağlantı yok — kuyruk işlenemez",
		}

	# Kuyruk boş
	if _queue.is_empty():
		return {
			"can_process": false, "batch": [],
			"reason": "Kuyruk boş — işlenecek işlem yok",
		}

	# İşlemleri önceliğe göre sırala, batch kadar al
	var all_ops: Array = _queue.all_operations(current_unix)
	var sorted_ops: Array = _resolver.sort_by_priority(all_ops)
	var batch: Array = []
	for i in range(mini(batch_size, sorted_ops.size())):
		batch.append(sorted_ops[i])

	return {
		"can_process": true,
		"batch": batch,
		"reason": "%d işlem işlenmeye hazır" % batch.size(),
	}


# ============================================================
# SONUÇ İŞLEME
# ============================================================

## Bir işlemin sonucunu kaydeder ve kuyruğu günceller.
## op_id: işlem kimliği. succeeded: işlem başarılı oldu mu.
## Dönen: {action: String, reason: String}
##   action: "removed" | "retry_scheduled" | "abandoned"
func report_result(op_id: String, succeeded: bool) -> Dictionary:
	_total_processed += 1

	# Başarılı — kuyruktan çıkar
	if succeeded:
		_queue.dequeue(op_id)
		_total_succeeded += 1
		return {
			"action": "removed",
			"reason": "İşlem başarılı — kuyruktan çıkarıldı",
		}

	# Başarısız — deneme sayısını artır
	var retry_count: int = _queue.mark_retry(op_id)
	if retry_count == -1:
		return {
			"action": "removed",
			"reason": "İşlem kuyrukta bulunamadı",
		}

	# Çok denendi — vazgeç (sonsuz döngü önle)
	if retry_count >= MAX_RETRIES:
		_queue.dequeue(op_id)
		_total_abandoned += 1
		return {
			"action": "abandoned",
			"reason": "İşlem %d kez başarısız — vazgeçildi" % retry_count,
		}

	# Tekrar denenecek — kuyrukta kalır
	return {
		"action": "retry_scheduled",
		"reason": "İşlem başarısız — %d. denemeye bırakıldı" % \
			(retry_count + 1),
	}


# ============================================================
# SORGULAMA
# ============================================================

## İşlenmeyi bekleyen işlem var mı?
func has_pending() -> bool:
	return not _queue.is_empty()


## Bekleyen işlem sayısı.
func pending_count() -> int:
	return _queue.size()


## Kuyruğa erişim.
func queue() -> AIOfflineSyncQueue:
	return _queue


## İşleme istatistikleri.
func stats() -> Dictionary:
	return {
		"total_processed": _total_processed,
		"total_succeeded": _total_succeeded,
		"total_abandoned": _total_abandoned,
		"pending": _queue.size(),
	}
