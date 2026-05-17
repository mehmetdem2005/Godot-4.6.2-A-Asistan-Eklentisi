@tool
class_name AIOfflineSyncQueue
extends RefCounted

## SyncQueue — senkronizasyon kuyruğu (Madde 07 / Offline / queue).
##
## Çevrimdışıyken yapılamayan ağ işlemleri kaybolmamalı — bir KUYRUĞA
## yazılır, bağlantı gelince işlenir. "Çevrimdışı önce" (offline-first)
## mimarisinin kalbi.
##
## Kuyruk KALICI olmalı: uygulama kapanıp açılsa bile bekleyen işlemler
## durmalı. Bu sınıf kuyruğun MANTIK durumunu tutar; gerçek diske
## yazma Save/Load ile entegre (serileştirilebilir yapı).
##
## Her işlem: kimlik, tür, veri yükü, eklenme zamanı, deneme sayısı.
## priority_resolver işlenme sırasını belirler.
##
## Mock policy: kuyruk gerçek eklenen işlemlerden.

## Bir kuyruk işlemi.
class QueuedOperation extends RefCounted:
	var op_id: String = ""
	var op_type: String = ""
	var payload: Dictionary = {}
	var enqueued_at_unix: int = 0
	var retry_count: int = 0

	func to_dict() -> Dictionary:
		return {
			"id": op_id, "type": op_type, "payload": payload,
			"enqueued_at": enqueued_at_unix, "retry_count": retry_count,
		}

	## Serileştirilmiş sözlükten yükler — disk geri yükleme için.
	static func from_dict(data: Dictionary) -> QueuedOperation:
		var op := QueuedOperation.new()
		op.op_id = str(data.get("id", ""))
		op.op_type = str(data.get("type", ""))
		op.payload = data.get("payload", {})
		op.enqueued_at_unix = int(data.get("enqueued_at", 0))
		op.retry_count = int(data.get("retry_count", 0))
		return op


## Bekleyen işlemler — op_id -> QueuedOperation.
var _operations: Dictionary = {}

## Maksimum kuyruk boyutu — sınırsız büyümeyi önler.
var max_size: int = 500


func _init(p_max_size: int = 500) -> void:
	max_size = maxi(p_max_size, 1)


# ============================================================
# KUYRUĞA EKLEME
# ============================================================

## Kuyruğa bir işlem ekler.
## op_id: benzersiz kimlik. op_type: işlem türü. payload: veri yükü.
## enqueued_at_unix: eklenme zamanı.
## Dönen: {enqueued: bool, reason: String}
func enqueue(
	op_id: String, op_type: String, payload: Dictionary,
	enqueued_at_unix: int
) -> Dictionary:
	if op_id.is_empty():
		return {"enqueued": false, "reason": "Geçersiz işlem kimliği"}

	# Aynı kimlik zaten varsa — değiştir (çift işlem önle)
	var is_replace: bool = _operations.has(op_id)

	# Kuyruk dolu mu (yeni işlemse)
	if not is_replace and _operations.size() >= max_size:
		return {
			"enqueued": false,
			"reason": "Kuyruk dolu (%d) — işlem eklenemedi" % max_size,
		}

	var op := QueuedOperation.new()
	op.op_id = op_id
	op.op_type = op_type
	op.payload = payload.duplicate(true)
	op.enqueued_at_unix = enqueued_at_unix
	op.retry_count = 0
	_operations[op_id] = op

	return {
		"enqueued": true,
		"reason": "İşlem kuyruğa eklendi" if not is_replace \
			else "İşlem güncellendi",
	}


# ============================================================
# KUYRUKTAN ÇIKARMA
# ============================================================

## Bir işlemi kuyruktan çıkarır — başarıyla işlendiğinde.
## Dönen: true = vardı ve çıkarıldı.
func dequeue(op_id: String) -> bool:
	if not _operations.has(op_id):
		return false
	_operations.erase(op_id)
	return true


## Bir işlemin deneme sayısını artırır — işlem başarısız olunca.
## Dönen: yeni deneme sayısı; işlem yoksa -1.
func mark_retry(op_id: String) -> int:
	if not _operations.has(op_id):
		return -1
	var op: QueuedOperation = _operations[op_id]
	op.retry_count += 1
	return op.retry_count


## Tüm kuyruğu temizler.
func clear() -> void:
	_operations.clear()


# ============================================================
# SORGULAMA
# ============================================================

## Bir işlem kuyrukta mı?
func has_operation(op_id: String) -> bool:
	return _operations.has(op_id)


## Bir işlemi döndürür. Yoksa null.
func get_operation(op_id: String) -> QueuedOperation:
	return _operations.get(op_id, null)


## Kuyruktaki işlem sayısı.
func size() -> int:
	return _operations.size()


## Kuyruk boş mu?
func is_empty() -> bool:
	return _operations.is_empty()


## Kuyruk dolu mu?
func is_full() -> bool:
	return _operations.size() >= max_size


## Tüm işlemleri sözlük dizisi olarak döndürür — priority_resolver için.
## current_unix: bekleme süresi hesabı için şu anki zaman.
func all_operations(current_unix: int) -> Array:
	var result: Array = []
	for op_id in _operations:
		var op: QueuedOperation = _operations[op_id]
		result.append({
			"id": op.op_id,
			"type": op.op_type,
			"payload": op.payload,
			"wait_seconds": float(current_unix - op.enqueued_at_unix),
			"retry_count": op.retry_count,
		})
	return result


# ============================================================
# KALICILIK — disk serileştirme
# ============================================================

## Kuyruğu serileştirilebilir bir sözlüğe çevirir — diske yazmak için.
func serialize() -> Dictionary:
	var ops: Array = []
	for op_id in _operations:
		ops.append((_operations[op_id] as QueuedOperation).to_dict())
	return {"max_size": max_size, "operations": ops}


## Serileştirilmiş bir sözlükten kuyruğu geri yükler — diskten okumak.
func deserialize(data: Dictionary) -> void:
	_operations.clear()
	max_size = int(data.get("max_size", 500))
	var ops: Array = data.get("operations", [])
	for op_data in ops:
		if typeof(op_data) != TYPE_DICTIONARY:
			continue
		var op: QueuedOperation = QueuedOperation.from_dict(op_data)
		if not op.op_id.is_empty():
			_operations[op.op_id] = op
