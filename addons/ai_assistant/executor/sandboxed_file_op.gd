@tool
class_name AISandboxedFileOp
extends RefCounted

## SandboxedFileOp — korumalı gerçek dosya işlemleri (Layer 4).
##
## Executor'ın dosya sistemine DOKUNAN tek noktası. Her işlem zinciri:
##   1. PathGuard      — yol güvenli mi? değilse reddet
##   2. UndoStack      — eski hâli snapshot'la (geri-alınabilirlik)
##   3. OperationJournal — PENDING kaydı düş (çökme dayanıklılığı)
##   4. GERÇEK I/O     — atomik yazım (.tmp + rename)
##   5. Journal güncelle — DONE / FAILED
##
## Mock policy: işlem gerçekten yapılır; başarısızlık gizlenmez, raporlanır.
## Her metod {ok, error, op_id, undo_token} döndürür.

var _journal: AIOperationJournal
var _undo: AIUndoStack


func _init(journal: AIOperationJournal, undo: AIUndoStack) -> void:
	_journal = journal
	_undo = undo


# ============================================================
# OKUMA
# ============================================================

## Bir dosyayı okur. Dönen: {ok, content, error}
func read_file(path: String) -> Dictionary:
	var guard: Dictionary = AIPathGuard.check_read(path)
	if not guard["allowed"]:
		return {"ok": false, "content": "", "error": guard["reason"]}
	if not FileAccess.file_exists(path):
		return {"ok": false, "content": "", "error": "Dosya yok: %s" % path}

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {
			"ok": false, "content": "",
			"error": "Dosya açılamadı (kod %d)" % FileAccess.get_open_error(),
		}
	var content: String = f.get_as_text()
	f.close()
	return {"ok": true, "content": content, "error": ""}


## Bir dosyanın var olup olmadığı (guard'dan geçerek).
func file_exists(path: String) -> bool:
	if not AIPathGuard.can_read(path):
		return false
	return FileAccess.file_exists(path)


# ============================================================
# YAZMA / OLUŞTURMA
# ============================================================

## Bir dosyaya yazar. Dosya yoksa oluşturur, varsa içeriğini değiştirir.
## Tam koruma zinciri uygulanır. Dönen: {ok, error, op_id, undo_token}
func write_file(path: String, content: String) -> Dictionary:
	# 1. PathGuard
	var guard: Dictionary = AIPathGuard.check_write(path)
	if not guard["allowed"]:
		return _fail_result(guard["reason"])

	var exists: bool = FileAccess.file_exists(path)
	var op_kind: int = (
		AIOperationJournal.OpType.WRITE if exists
		else AIOperationJournal.OpType.CREATE
	)

	# 2. UndoStack — eski hâli snapshot'la
	var undo_token: String = ""
	if exists:
		var old: Dictionary = read_file(path)
		if old["ok"]:
			undo_token = _undo.snapshot_existing(path, old["content"])
		else:
			# Var ama okunamıyor — riskli, işlemi durdur
			return _fail_result("Mevcut dosya okunamadı, üzerine yazma iptal")
	else:
		undo_token = _undo.snapshot_absent(path)

	# 3. Journal — PENDING kaydı
	var record: AIOperationJournal.OperationRecord = _journal.begin_operation(
		op_kind, path
	)

	# 4. GERÇEK I/O — önce klasörü garantile, sonra atomik yaz
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk_err: int = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			_journal.mark_failed(record.id, "Klasör oluşturulamadı")
			return _fail_result("Klasör oluşturulamadı: %s" % dir_path)

	var atomic: Dictionary = _atomic_write(path, content)
	if not atomic["ok"]:
		_journal.mark_failed(record.id, atomic["error"])
		return _fail_result(atomic["error"])

	# 5. Journal — DONE
	_journal.mark_done(record.id, undo_token)
	return {"ok": true, "error": "", "op_id": record.id, "undo_token": undo_token}


## Bir klasör oluşturur (iç içe). Dönen: {ok, error, op_id}
func make_dir(path: String) -> Dictionary:
	var guard: Dictionary = AIPathGuard.check_write(path)
	if not guard["allowed"]:
		return _fail_result(guard["reason"])

	if DirAccess.dir_exists_absolute(path):
		return {"ok": true, "error": "", "op_id": ""}  # zaten var — sorun değil

	var record: AIOperationJournal.OperationRecord = _journal.begin_operation(
		AIOperationJournal.OpType.MKDIR, path
	)
	var err: int = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		_journal.mark_failed(record.id, "mkdir hatası kod %d" % err)
		return _fail_result("Klasör oluşturulamadı (kod %d)" % err)

	_journal.mark_done(record.id)
	return {"ok": true, "error": "", "op_id": record.id}


# ============================================================
# SİLME
# ============================================================

## Bir dosyayı siler. Silmeden önce içeriği snapshot'lanır (geri-alınabilir).
## Dönen: {ok, error, op_id, undo_token}
func delete_file(path: String) -> Dictionary:
	var guard: Dictionary = AIPathGuard.check_write(path)
	if not guard["allowed"]:
		return _fail_result(guard["reason"])
	if not FileAccess.file_exists(path):
		return _fail_result("Silinecek dosya yok: %s" % path)

	# Snapshot — silmeden önce içeriği sakla
	var old: Dictionary = read_file(path)
	if not old["ok"]:
		return _fail_result("Silinecek dosya okunamadı, silme iptal")
	var undo_token: String = _undo.snapshot_existing(path, old["content"])

	var record: AIOperationJournal.OperationRecord = _journal.begin_operation(
		AIOperationJournal.OpType.DELETE, path
	)

	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		_journal.mark_failed(record.id, "silme hatası kod %d" % err)
		return _fail_result("Dosya silinemedi (kod %d)" % err)

	_journal.mark_done(record.id, undo_token)
	return {"ok": true, "error": "", "op_id": record.id, "undo_token": undo_token}


# ============================================================
# TAŞIMA
# ============================================================

## Bir dosyayı taşır/yeniden adlandırır. Hem kaynak hem hedef guard'dan geçer.
## Dönen: {ok, error, op_id, undo_token}
func move_file(from_path: String, to_path: String) -> Dictionary:
	var guard_from: Dictionary = AIPathGuard.check_write(from_path)
	if not guard_from["allowed"]:
		return _fail_result("Kaynak reddedildi: %s" % guard_from["reason"])
	var guard_to: Dictionary = AIPathGuard.check_write(to_path)
	if not guard_to["allowed"]:
		return _fail_result("Hedef reddedildi: %s" % guard_to["reason"])
	if not FileAccess.file_exists(from_path):
		return _fail_result("Taşınacak dosya yok: %s" % from_path)
	if FileAccess.file_exists(to_path):
		return _fail_result("Hedef zaten var (üzerine yazılmaz): %s" % to_path)

	# Snapshot — taşınan dosyanın eski konumdaki içeriği, hedefin yokluğu
	var old: Dictionary = read_file(from_path)
	if not old["ok"]:
		return _fail_result("Taşınacak dosya okunamadı")
	var undo_token: String = _undo.snapshot_existing(from_path, old["content"])

	var record: AIOperationJournal.OperationRecord = _journal.begin_operation(
		AIOperationJournal.OpType.MOVE, from_path, to_path
	)

	# Hedef klasörü garantile
	var dir_path: String = to_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var err: int = DirAccess.rename_absolute(from_path, to_path)
	if err != OK:
		_journal.mark_failed(record.id, "taşıma hatası kod %d" % err)
		return _fail_result("Dosya taşınamadı (kod %d)" % err)

	_journal.mark_done(record.id, undo_token)
	return {"ok": true, "error": "", "op_id": record.id, "undo_token": undo_token}


# ============================================================
# GERİ-ALMA
# ============================================================

## Bir undo token'ı kullanarak işlemi geri alır.
## FILE_CONTENT -> eski içeriği geri yaz; FILE_ABSENT -> dosyayı sil.
## Dönen: {ok, error}
func undo(token: String) -> Dictionary:
	var inst: Dictionary = _undo.get_undo_instruction(token)
	if not inst["found"]:
		return {"ok": false, "error": "Undo token bulunamadı: %s" % token}

	var path: String = inst["path"]
	# Geri-alma da guard'dan geçer — savunma derinliği
	var guard: Dictionary = AIPathGuard.check_write(path)
	if not guard["allowed"]:
		return {"ok": false, "error": "Undo guard reddi: %s" % guard["reason"]}

	if inst["kind"] == AIUndoStack.SnapshotKind.FILE_ABSENT:
		# Dosya yoktu — geri-al = sil
		if FileAccess.file_exists(path):
			var err: int = DirAccess.remove_absolute(path)
			if err != OK:
				return {"ok": false, "error": "Undo silme hatası kod %d" % err}
		return {"ok": true, "error": ""}
	else:
		# Dosya vardı — eski içeriği geri yaz (atomik)
		var atomic: Dictionary = _atomic_write(path, inst["restore_content"])
		return {"ok": atomic["ok"], "error": atomic["error"]}


# ============================================================
# DAHİLİ — atomik yazım
# ============================================================

## Atomik yazım: önce .tmp dosyaya yaz, başarılıysa rename ile asıl dosyaya geç.
## Yazma ortasında çökme olsa bile asıl dosya bozulmaz.
func _atomic_write(path: String, content: String) -> Dictionary:
	var tmp_path: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {
			"ok": false,
			"error": "Geçici dosya açılamadı (kod %d)" % FileAccess.get_open_error(),
		}
	f.store_string(content)
	f.close()

	var rename_err: int = DirAccess.rename_absolute(tmp_path, path)
	if rename_err != OK:
		# .tmp'i temizlemeye çalış — çöp bırakma
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {"ok": false, "error": "Atomik rename başarısız (kod %d)" % rename_err}
	return {"ok": true, "error": ""}


## Standart başarısızlık sonucu.
func _fail_result(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "op_id": "", "undo_token": ""}
