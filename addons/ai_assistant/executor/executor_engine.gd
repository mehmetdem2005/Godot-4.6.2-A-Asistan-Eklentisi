@tool
class_name AIExecutorEngine
extends RefCounted

## ExecutorEngine — çalıştırma motoru (Layer 4).
##
## Layer 3 Planner bir plan kurar. Bu motor o planın ACTION düğümlerini
## ALIR ve GERÇEKTEN çalıştırır — dosya oluşturur, yazar, siler, taşır.
##
## Her ACTION bir AIActionSpec taşır (Layer 0 contract). Motor:
##   1. ActionSpec'i okur — ne yapılacak?
##   2. Risk değerlendirir — yüksek riskli işlem işaretlenir (HITL Layer 8)
##   3. SandboxedFileOp ile çalıştırır — tam koruma zinciri
##   4. Sonucu AIVerificationResult olarak raporlar — kanıt-temelli
##
## Mock policy: işlem gerçekten yapılır. Desteklenmeyen action tipi için
## sahte başarı DÖNMEZ — NOT_IMPLEMENTED outcome'u ile açıkça raporlar.

## Bu motor AIActionSpec.ActionType enum değerlerini işler.
## Layer 4'ün desteklediği tipler (diğerleri NOT_IMPLEMENTED raporlanır):
##   FILE_WRITE, FILE_DELETE, SCENE_CREATE (mkdir benzeri), CUSTOM (move)
## NODE_*, SHADER_*, PROPERTY_SET gibi sahne-içi tipler Layer sonrası
## (SceneEngineer cell) eklenecek — şimdilik açıkça SKIP raporlanır.

var _journal: AIOperationJournal
var _undo: AIUndoStack
var _file_op: AISandboxedFileOp

## Kaynak kotası — disk/dosya sayısı/boyut limitleri.
var quota: AIResourceQuota

## Hız sınırlayıcı — saniye-pencere işlem limiti.
var rate_limiter: AIRateLimiter

## Onaysız yüksek-riskli (yıkıcı) işlem çalıştırılsın mı? Varsayılan: HAYIR.
## Layer 8 HITL gelene kadar yıkıcı işlemler güvenli tarafta tutulur.
var allow_high_risk: bool = false

## Yazımdan sonra IntegrityVerifier ile bütünlük doğrulansın mı? Varsayılan: EVET.
var verify_after_write: bool = true


func _init() -> void:
	_journal = AIOperationJournal.new()
	_undo = AIUndoStack.new()
	_file_op = AISandboxedFileOp.new(_journal, _undo)
	quota = AIResourceQuota.new()
	rate_limiter = AIRateLimiter.new()


## Çökme sonrası kurtarma — açılışta çağrılır.
## Journal'ı yükler; yarım kalan (PENDING) işlem varsa raporlar.
## Dönen: {ok, pending_count, pending_paths}
func initialize() -> Dictionary:
	var loaded: bool = _journal.load_from_disk()
	var pending: Array = _journal.pending_operations()
	var pending_paths: PackedStringArray = PackedStringArray()
	for record in pending:
		pending_paths.append(record.target_path)
	return {
		"ok": loaded,
		"pending_count": pending.size(),
		"pending_paths": pending_paths,
	}


## Mevcut bir dosyanın içeriğini güvenli okur (cerrahi düzenleme için —
## Pipeline, tüm dosyayı EZMEDEN SEARCH/REPLACE uygulayabilsin diye
## önce mevcut içeriği buradan okur). FS'e dokunan tek nokta yine
## SandboxedFileOp'tur (PathGuard korumalı). Dönen: {ok, content, error}
func read_existing(path: String) -> Dictionary:
	return _file_op.read_file(path)


# ============================================================
# RİSK DEĞERLENDİRME
# ============================================================

## Bir action'ın yüksek riskli (yıkıcı) olup olmadığını söyler.
## ActionSpec contract'ının kendi is_destructive() kararını kullanır —
## risk tanımı tek yerde (contract'ta) yaşar, burada tekrarlanmaz.
static func is_high_risk(spec: AIActionSpec) -> bool:
	if spec == null:
		return true  # bilinmeyen = güvenli tarafta, riskli say
	return spec.is_destructive()


# ============================================================
# ÇALIŞTIRMA
# ============================================================

## Tek bir ACTION düğümünü çalıştırır.
## node: AIPlanNode (ACTION seviyesi). action_spec parametreleri taşır.
## Dönen: AIVerificationResult — başarı/başarısızlık + kanıt.
func execute_action(node: AIPlanNode, action_spec: AIActionSpec) -> AIVerificationResult:
	var result := AIVerificationResult.create(
		AIVerificationResult.VerifyLevel.RUNTIME,
		node.id if node != null else "?"
	)

	# Girdi doğrulama
	if node == null:
		result.mark_fail("Çalıştırılacak düğüm null")
		return result
	if node.level != AIPlanNode.Level.ACTION:
		result.mark_fail("Sadece ACTION seviyesi düğüm çalıştırılır")
		return result
	if action_spec == null:
		result.mark_fail("ActionSpec yok — ne yapılacağı belirsiz")
		return result

	var action_type: int = action_spec.action_type

	# Risk kapısı — yıkıcı işlem onaysız çalışmaz
	if is_high_risk(action_spec) and not allow_high_risk:
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = (
			"Yıkıcı işlem '%s' HITL onayı bekliyor (Layer 8)"
			% action_spec.action_type_name()
		)
		return result

	# Action tipine göre yönlendir
	match action_type:
		AIActionSpec.ActionType.FILE_WRITE:
			return _exec_write(action_spec, result)
		AIActionSpec.ActionType.FILE_DELETE:
			return _exec_delete(action_spec, result)
		AIActionSpec.ActionType.SCENE_CREATE:
			# SCENE_CREATE şimdilik klasör+iskelet dosya olarak ele alınır;
			# tam sahne ağacı kurma SceneEngineer cell'inde gelecek.
			return _exec_mkdir(action_spec, result)
		AIActionSpec.ActionType.CUSTOM:
			# CUSTOM: params.op alanı alt-işlemi belirler (örn. taşıma)
			return _exec_custom(action_spec, result)
		_:
			# Desteklenmeyen tip — SAHTE BAŞARI YOK (mock policy)
			result.outcome = AIVerificationResult.Outcome.SKIP
			result.message = (
				"Action tipi '%s' Layer 4'te desteklenmiyor (NOT_IMPLEMENTED)"
				% action_spec.action_type_name()
			)
			return result


## Bir plan'ın tüm hazır ACTION'larını sırayla çalıştırır.
## planner: AIHierarchicalPlanner. specs: node_id -> AIActionSpec eşlemesi.
## Dönen: AIVerificationResult listesi (her çalıştırılan action için bir tane).
func execute_ready_actions(
	planner: AIHierarchicalPlanner, specs: Dictionary
) -> Array:
	var results: Array = []
	var ready: PackedStringArray = planner.ready_nodes()
	for node_id in ready:
		var node: AIPlanNode = planner.tree.get_node(node_id)
		if node == null or node.level != AIPlanNode.Level.ACTION:
			continue
		var spec: AIActionSpec = specs.get(node_id, null)
		var res: AIVerificationResult = execute_action(node, spec)
		results.append(res)
		# Başarılıysa planner'da tamamlandı işaretle
		if res.outcome == AIVerificationResult.Outcome.PASS:
			planner.mark_completed(node_id)
	return results


# ============================================================
# ACTION TİPİ UYGULAYICILARI
# ============================================================

func _exec_write(spec: AIActionSpec, result: AIVerificationResult) -> AIVerificationResult:
	var path: String = spec.params.get("path", "")
	var content: String = spec.params.get("content", "")
	if path.is_empty():
		result.mark_fail("write_file: 'path' parametresi eksik")
		return result

	# --- Hız limiti kontrolü ---
	var now_unix: int = AIContractBase.iso_to_unix(AIContractBase.now_iso())
	var rate_check: Dictionary = rate_limiter.check_allowed(now_unix)
	if not rate_check["allowed"]:
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = "Hız limiti: %s" % rate_check["reason"]
		return result

	# --- Kota kontrolü ---
	var content_size: int = content.to_utf8_buffer().size()
	var is_new: bool = not _file_op.file_exists(path)
	var old_size: int = 0
	if not is_new:
		var old_read: Dictionary = _file_op.read_file(path)
		if old_read["ok"]:
			old_size = (old_read["content"] as String).to_utf8_buffer().size()
	var quota_check: Dictionary = quota.check_write_allowed(content_size, is_new, old_size)
	if not quota_check["allowed"]:
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = "Kota: %s" % quota_check["reason"]
		return result

	# --- Gerçek yazma ---
	var op: Dictionary = _file_op.write_file(path, content)
	if not op["ok"]:
		result.mark_fail("write_file başarısız: %s" % op["error"])
		return result

	# --- Yazımdan sonra: sayaçları güncelle ---
	quota.record_write(content_size, is_new, old_size)
	rate_limiter.record(now_unix)

	# --- Bütünlük doğrulama: yazdığım DOĞRU mu? ---
	if verify_after_write:
		var integrity: Dictionary = AIIntegrityVerifier.verify_written(path, content)
		if not integrity["ok"]:
			# Yazıldı ama bozuk — bu bir BAŞARISIZLIK, gizlenmez
			result.mark_fail("Bütünlük doğrulama başarısız: %s" % integrity["reason"])
			return result

	result.mark_pass(
		{
			"path": path,
			"op_id": op["op_id"],
			"undo_token": op["undo_token"],
			"size": content_size,
			"integrity_verified": verify_after_write,
		},
		"file_write"
	)
	result.message = "Dosya yazıldı ve doğrulandı: %s" % path
	return result


func _exec_delete(spec: AIActionSpec, result: AIVerificationResult) -> AIVerificationResult:
	var path: String = spec.params.get("path", "")
	if path.is_empty():
		result.mark_fail("delete_file: 'path' parametresi eksik")
		return result

	var op: Dictionary = _file_op.delete_file(path)
	if op["ok"]:
		result.mark_pass(
			{"path": path, "op_id": op["op_id"], "undo_token": op["undo_token"]},
			"file_delete"
		)
		result.message = "Dosya silindi: %s" % path
	else:
		result.mark_fail("delete_file başarısız: %s" % op["error"])
	return result


func _exec_custom(spec: AIActionSpec, result: AIVerificationResult) -> AIVerificationResult:
	# CUSTOM action — params.op alt-işlemi belirler.
	var sub_op: String = spec.params.get("op", "")
	match sub_op:
		"move_file":
			var from_path: String = spec.params.get("from", "")
			var to_path: String = spec.params.get("to", "")
			if from_path.is_empty() or to_path.is_empty():
				result.mark_fail("move_file: 'from'/'to' parametresi eksik")
				return result
			var op: Dictionary = _file_op.move_file(from_path, to_path)
			if op["ok"]:
				result.mark_pass(
					{"from": from_path, "to": to_path, "op_id": op["op_id"]},
					"file_move"
				)
				result.message = "Dosya taşındı: %s -> %s" % [from_path, to_path]
			else:
				result.mark_fail("move_file başarısız: %s" % op["error"])
			return result
		_:
			result.outcome = AIVerificationResult.Outcome.SKIP
			result.message = "CUSTOM alt-işlem desteklenmiyor: '%s'" % sub_op
			return result


func _exec_mkdir(spec: AIActionSpec, result: AIVerificationResult) -> AIVerificationResult:
	var path: String = spec.params.get("path", "")
	if path.is_empty():
		result.mark_fail("make_dir: 'path' parametresi eksik")
		return result

	var op: Dictionary = _file_op.make_dir(path)
	if op["ok"]:
		result.mark_pass({"path": path}, "dir_create")
		result.message = "Klasör oluşturuldu: %s" % path
	else:
		result.mark_fail("make_dir başarısız: %s" % op["error"])
	return result


# ============================================================
# GERİ-ALMA
# ============================================================

## Bir işlemi undo token ile geri alır.
func undo_operation(undo_token: String) -> Dictionary:
	var res: Dictionary = _file_op.undo(undo_token)
	return res


## En son başarılı işlemi geri alır.
## Dönen: {ok, error, reverted_path}
func undo_last() -> Dictionary:
	var last: AIOperationJournal.OperationRecord = _journal.last_done()
	if last == null:
		return {"ok": false, "error": "Geri alınacak işlem yok", "reverted_path": ""}
	if last.undo_token.is_empty():
		return {"ok": false, "error": "İşlemin undo token'ı yok", "reverted_path": ""}

	var res: Dictionary = _file_op.undo(last.undo_token)
	if res["ok"]:
		_journal.mark_reverted(last.id)
	return {
		"ok": res["ok"],
		"error": res["error"],
		"reverted_path": last.target_path,
	}


## Yeni bir atomik işlem grubu (transaction) oluşturur.
## Birden çok dosya işlemini all-or-nothing yapmak için kullanılır.
## Örnek: bir plan 20 dosya yazacak — biri hata verirse hepsi geri alınır.
func create_batch() -> AITransactionBatch:
	return AITransactionBatch.new(_file_op)


# ============================================================
# DURUM
# ============================================================

## Journal'ı diske kaydeder — düzenli aralıklarla + kapanışta çağrılır.
func persist() -> bool:
	return _journal.save_to_disk()


## Executor durum özeti.
func stats() -> Dictionary:
	return {
		"total_operations": _journal.count(),
		"done": _journal.records_with_status(AIOperationJournal.OpStatus.DONE).size(),
		"failed": _journal.records_with_status(AIOperationJournal.OpStatus.FAILED).size(),
		"pending": _journal.pending_operations().size(),
		"undo_snapshots": _undo.count(),
		"quota": quota.usage(),
	}
