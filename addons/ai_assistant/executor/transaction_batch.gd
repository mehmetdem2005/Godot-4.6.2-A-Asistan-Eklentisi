@tool
class_name AITransactionBatch
extends RefCounted

## TransactionBatch — atomik işlem grubu (Layer 4).
##
## Bir plan tek seferde 20 dosya yazabilir. 12.'de hata olursa ne olur?
## Yarım proje = bozuk durum. Bu sınıf "all-or-nothing" garantisi verir:
##   - Tüm işlemler başarılı  -> commit (hepsi kalıcı)
##   - Herhangi biri başarısız -> rollback (yapılanların HEPSİ geri alınır)
##
## Veritabanı transaction'ı gibi: ya tamamı, ya hiçbiri.
##
## Akış:
##   1. add_write/add_delete/add_move ile işlemler kuyruğa eklenir
##   2. commit() çağrılır — sırayla uygulanır
##   3. Bir adım başarısız olursa, o ana dek başarılı olanlar geri alınır
##   4. Sonuç raporlanır: {ok, applied, rolled_back, failed_at}

## Batch'teki bekleyen işlem tipleri.
enum BatchOpType { WRITE, DELETE, MOVE, MKDIR }

## Bekleyen tek bir işlem tanımı.
class BatchOp extends RefCounted:
	var op_type: int = BatchOpType.WRITE
	var path: String = ""
	var content: String = ""
	var secondary_path: String = ""   ## MOVE hedefi


var _file_op: AISandboxedFileOp
var _ops: Array = []                   ## BatchOp listesi
var _committed: bool = false


func _init(file_op: AISandboxedFileOp) -> void:
	_file_op = file_op


## Batch'teki bekleyen işlem sayısı.
func size() -> int:
	return _ops.size()


## Batch boş mu?
func is_empty() -> bool:
	return _ops.is_empty()


## Batch zaten commit edilmiş mi?
func is_committed() -> bool:
	return _committed


# ============================================================
# İŞLEM EKLEME
# ============================================================

## Bir dosya yazma işlemi ekler (henüz uygulanmaz).
func add_write(path: String, content: String) -> AITransactionBatch:
	var op := BatchOp.new()
	op.op_type = BatchOpType.WRITE
	op.path = path
	op.content = content
	_ops.append(op)
	return self  # zincirlenebilir


## Bir dosya silme işlemi ekler.
func add_delete(path: String) -> AITransactionBatch:
	var op := BatchOp.new()
	op.op_type = BatchOpType.DELETE
	op.path = path
	_ops.append(op)
	return self


## Bir dosya taşıma işlemi ekler.
func add_move(from_path: String, to_path: String) -> AITransactionBatch:
	var op := BatchOp.new()
	op.op_type = BatchOpType.MOVE
	op.path = from_path
	op.secondary_path = to_path
	_ops.append(op)
	return self


## Bir klasör oluşturma işlemi ekler.
func add_mkdir(path: String) -> AITransactionBatch:
	var op := BatchOp.new()
	op.op_type = BatchOpType.MKDIR
	op.path = path
	_ops.append(op)
	return self


# ============================================================
# COMMIT / ROLLBACK
# ============================================================

## Batch'i uygular — all-or-nothing.
## Tüm işlemler başarılıysa commit. Biri başarısızsa, o ana dek
## başarılı olanların HEPSİ geri alınır (rollback).
##
## Dönen: {
##   ok: bool,              tüm batch başarılı mı
##   applied: int,          kaç işlem kalıcı uygulandı (ok ise = size)
##   rolled_back: int,      rollback'te kaç işlem geri alındı
##   failed_at: int,        hata hangi indekste oldu (-1 = hata yok)
##   error: String,
## }
func commit() -> Dictionary:
	if _committed:
		return _result(false, 0, 0, -1, "Batch zaten commit edilmiş")
	if _ops.is_empty():
		_committed = true
		return _result(true, 0, 0, -1, "")

	# Başarılı işlemlerin geri-alma token'ları — rollback için
	var undo_tokens: Array = []  # [{type, token, path, sec}]

	for i in range(_ops.size()):
		var op: BatchOp = _ops[i]
		var step: Dictionary = _apply_op(op)

		if not step["ok"]:
			# HATA — bu noktaya kadar başarılı olan her şeyi geri al
			var reverted: int = _rollback(undo_tokens)
			return _result(
				false, i, reverted, i,
				"Adım %d başarısız: %s — batch geri alındı" % [i, step["error"]]
			)

		# Başarılı — rollback için token sakla
		undo_tokens.append({
			"undo_token": step.get("undo_token", ""),
			"op_type": op.op_type,
		})

	# Tüm işlemler başarılı — commit
	_committed = true
	return _result(true, _ops.size(), 0, -1, "")


## Tek bir batch işlemini uygular.
func _apply_op(op: BatchOp) -> Dictionary:
	match op.op_type:
		BatchOpType.WRITE:
			return _file_op.write_file(op.path, op.content)
		BatchOpType.DELETE:
			return _file_op.delete_file(op.path)
		BatchOpType.MOVE:
			return _file_op.move_file(op.path, op.secondary_path)
		BatchOpType.MKDIR:
			return _file_op.make_dir(op.path)
		_:
			return {"ok": false, "error": "Bilinmeyen batch op tipi"}


## Başarılı işlemleri TERS sırada geri alır (LIFO — son yapılan ilk geri).
## Dönen: geri alınan işlem sayısı.
func _rollback(undo_tokens: Array) -> int:
	var reverted: int = 0
	# Ters sırada — son işlem ilk geri alınır
	for i in range(undo_tokens.size() - 1, -1, -1):
		var entry: Dictionary = undo_tokens[i]
		var token: String = entry.get("undo_token", "")
		if token.is_empty():
			# mkdir gibi undo token üretmeyen işlemler — atla
			continue
		var undo_result: Dictionary = _file_op.undo(token)
		if undo_result["ok"]:
			reverted += 1
		# Undo başarısız olsa bile devam et — kalan token'ları dene
	return reverted


## Standart sonuç sözlüğü.
func _result(
	ok: bool, applied: int, rolled_back: int, failed_at: int, error: String
) -> Dictionary:
	return {
		"ok": ok,
		"applied": applied,
		"rolled_back": rolled_back,
		"failed_at": failed_at,
		"error": error,
	}


## Batch'i sıfırlar — commit edilmemişse bekleyen işlemleri atar.
func clear() -> void:
	_ops.clear()
	_committed = false
