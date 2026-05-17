@tool
class_name AIOperationJournal
extends RefCounted

## OperationJournal — işlem günlüğü / write-ahead log (Layer 4).
##
## Executor bir dosya işlemi yapmadan ÖNCE niyetini buraya yazar:
##   1. Journal'a "şunu yapacağım" kaydı düş (PENDING)
##   2. İşlemi gerçekleştir
##   3. Journal kaydını güncelle (DONE veya FAILED)
##
## Neden: editör/uygulama işlem ortasında çökerse, journal'da PENDING kalan
## kayıt "bu iş yarım kaldı" der. Sistem tutarsız durumda kalmaz.
##
## Her kayıt bir AIOperationRecord'dur (bu dosyada inner tip).

## İşlem tipleri.
enum OpType { CREATE, WRITE, DELETE, MOVE, MKDIR }

const OP_TYPE_NAMES: Dictionary = {
	OpType.CREATE: "create",
	OpType.WRITE: "write",
	OpType.DELETE: "delete",
	OpType.MOVE: "move",
	OpType.MKDIR: "mkdir",
}

## İşlem durumları.
enum OpStatus { PENDING, DONE, FAILED, REVERTED }

const OP_STATUS_NAMES: Dictionary = {
	OpStatus.PENDING: "pending",
	OpStatus.DONE: "done",
	OpStatus.FAILED: "failed",
	OpStatus.REVERTED: "reverted",
}


## Tek bir işlem kaydı.
class OperationRecord extends RefCounted:
	var id: String = ""
	var op_type: int = OpType.WRITE
	var target_path: String = ""
	var secondary_path: String = ""   ## MOVE için hedef yol
	var status: int = OpStatus.PENDING
	var created_at: String = ""
	var finished_at: String = ""
	var error_message: String = ""
	var undo_token: String = ""       ## UndoStack snapshot referansı

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"op_type": AIOperationJournal.OP_TYPE_NAMES.get(op_type, "write"),
			"target_path": target_path,
			"secondary_path": secondary_path,
			"status": AIOperationJournal.OP_STATUS_NAMES.get(status, "pending"),
			"created_at": created_at,
			"finished_at": finished_at,
			"error_message": error_message,
			"undo_token": undo_token,
		}

	func from_dict(data: Dictionary) -> void:
		id = data.get("id", "")
		op_type = AIOperationJournal._parse_op_type(data.get("op_type", "write"))
		target_path = data.get("target_path", "")
		secondary_path = data.get("secondary_path", "")
		status = AIOperationJournal._parse_op_status(data.get("status", "pending"))
		created_at = data.get("created_at", "")
		finished_at = data.get("finished_at", "")
		error_message = data.get("error_message", "")
		undo_token = data.get("undo_token", "")


## Journal disk yolu.
const JOURNAL_PATH: String = "user://ai_assistant/executor/journal.json"

## Tüm kayıtlar — id -> OperationRecord
var _records: Dictionary = {}

## Sıra korunsun diye kayıt id'leri ekleme sırasıyla.
var _order: PackedStringArray = PackedStringArray()


## Journal'daki kayıt sayısı.
func count() -> int:
	return _records.size()


# ============================================================
# KAYIT — write-ahead
# ============================================================

## Bir işlemi PENDING olarak kaydeder — işlem YAPILMADAN önce çağrılır.
## Dönen: oluşturulan OperationRecord (id'si ile).
func begin_operation(
	op_type: int, target_path: String, secondary_path: String = ""
) -> OperationRecord:
	var record := OperationRecord.new()
	record.id = AIContractBase.generate_id("op")
	record.op_type = op_type
	record.target_path = target_path
	record.secondary_path = secondary_path
	record.status = OpStatus.PENDING
	record.created_at = AIContractBase.now_iso()

	_records[record.id] = record
	_order.append(record.id)
	return record


## Bir işlemi başarılı olarak kapatır — işlem YAPILDIKTAN sonra çağrılır.
func mark_done(op_id: String, undo_token: String = "") -> bool:
	if not _records.has(op_id):
		return false
	var record: OperationRecord = _records[op_id]
	record.status = OpStatus.DONE
	record.finished_at = AIContractBase.now_iso()
	record.undo_token = undo_token
	return true


## Bir işlemi başarısız olarak kapatır.
func mark_failed(op_id: String, error_message: String) -> bool:
	if not _records.has(op_id):
		return false
	var record: OperationRecord = _records[op_id]
	record.status = OpStatus.FAILED
	record.finished_at = AIContractBase.now_iso()
	record.error_message = error_message
	return true


## Bir işlemi geri-alındı olarak işaretler.
func mark_reverted(op_id: String) -> bool:
	if not _records.has(op_id):
		return false
	_records[op_id].status = OpStatus.REVERTED
	return true


# ============================================================
# SORGULAMA
# ============================================================

## Bir kaydı id ile getirir.
func get_record(op_id: String) -> OperationRecord:
	return _records.get(op_id, null)


## Tüm kayıtları ekleme sırasıyla döndürür.
func all_records() -> Array:
	var result: Array = []
	for id in _order:
		if _records.has(id):
			result.append(_records[id])
	return result


## Belirli durumdaki kayıtları döndürür.
func records_with_status(status: int) -> Array:
	var result: Array = []
	for id in _order:
		if _records.has(id) and _records[id].status == status:
			result.append(_records[id])
	return result


## Yarım kalan (PENDING) işlemler — çökme sonrası kurtarma için kritik.
## Sistem açılışta bunu kontrol etmeli: PENDING varsa tutarsızlık olabilir.
func pending_operations() -> Array:
	return records_with_status(OpStatus.PENDING)


## Son tamamlanan işlemi döndürür (geri-alma için en yeni hedef).
func last_done() -> OperationRecord:
	for i in range(_order.size() - 1, -1, -1):
		var record: OperationRecord = _records.get(_order[i], null)
		if record != null and record.status == OpStatus.DONE:
			return record
	return null


# ============================================================
# DİSK KALICILIĞI (atomik)
# ============================================================

## Journal'ı diske yazar — atomik (.tmp + rename).
func save_to_disk() -> bool:
	var data: Dictionary = {
		"saved_at": AIContractBase.now_iso(),
		"records": [],
	}
	for record in all_records():
		(data["records"] as Array).append(record.to_dict())

	var dir_path: String = JOURNAL_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp_path: String = JOURNAL_PATH + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Journal.save: dosya açılamadı")
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()

	var rename_err: int = DirAccess.rename_absolute(tmp_path, JOURNAL_PATH)
	return rename_err == OK


## Journal'ı diskten yükler.
func load_from_disk() -> bool:
	if not FileAccess.file_exists(JOURNAL_PATH):
		return true  # ilk çalıştırma

	var f: FileAccess = FileAccess.open(JOURNAL_PATH, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("Journal.load: bozuk JSON")
		return false

	_records.clear()
	_order.clear()
	for rec_dict in (parsed as Dictionary).get("records", []):
		var record := OperationRecord.new()
		record.from_dict(rec_dict)
		if not record.id.is_empty():
			_records[record.id] = record
			_order.append(record.id)
	return true


## Journal'ı tamamen temizler.
func clear() -> void:
	_records.clear()
	_order.clear()


# ============================================================
# ENUM PARSE YARDIMCILARI
# ============================================================

static func _parse_op_type(s: String) -> int:
	for key in OP_TYPE_NAMES:
		if OP_TYPE_NAMES[key] == s:
			return key
	return OpType.WRITE


static func _parse_op_status(s: String) -> int:
	for key in OP_STATUS_NAMES:
		if OP_STATUS_NAMES[key] == s:
			return key
	return OpStatus.PENDING
