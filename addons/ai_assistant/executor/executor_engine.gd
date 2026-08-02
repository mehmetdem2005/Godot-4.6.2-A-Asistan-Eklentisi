@tool
class_name AIExecutorEngine
extends RefCounted

## ExecutorEngine — doğrulanmış ActionSpec işlemlerini çalıştıran çekirdek.
##
## Dosya işlemleri sandbox + journal + undo snapshot hattından geçer.
## Editör işlemleri saf planner tarafından doğrulanır ve Godot'un kendi
## EditorUndoRedoManager geçmişi üzerinden uygulanır.

var _journal: AIOperationJournal
var _undo: AIUndoStack
var _file_op: AISandboxedFileOp
var _approved_destructive_actions: Dictionary = {}

var quota: AIResourceQuota
var rate_limiter: AIRateLimiter

## Geriye uyumluluk alanı. true yapılırsa yalnızca sıradaki TEK yıkıcı
## işlem için kullanılır ve hemen false'a döner. Kalıcı sınırsız yetki
## vermez. Yeni kod approve_destructive_action() kullanmalıdır.
var allow_high_risk: bool = false
var verify_after_write: bool = true


func _init() -> void:
	_journal = AIOperationJournal.new()
	_undo = AIUndoStack.new()
	_file_op = AISandboxedFileOp.new(_journal, _undo)
	quota = AIResourceQuota.new()
	rate_limiter = AIRateLimiter.new()


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


func read_existing(path: String) -> Dictionary:
	return _file_op.read_file(path)


static func is_high_risk(spec: AIActionSpec) -> bool:
	if spec == null:
		return true
	return spec.is_destructive()


## Belirli bir ActionSpec için tek kullanımlık yıkıcı işlem izni üretir.
## İzin action id + idempotency key'e bağlıdır; başka action kullanamaz.
func approve_destructive_action(spec: AIActionSpec) -> Dictionary:
	if spec == null:
		return {"ok": false, "reason": "ActionSpec null"}
	if not spec.is_destructive():
		return {"ok": false, "reason": "Action yıkıcı değil; izin gerekmiyor"}
	if spec.id.strip_edges().is_empty() or spec.idempotency_key.strip_edges().is_empty():
		return {"ok": false, "reason": "Action kimliği veya idempotency key eksik"}
	var key: String = _approval_key(spec)
	_approved_destructive_actions[key] = true
	return {"ok": true, "reason": "Tek kullanımlık izin üretildi", "key": key}


func revoke_destructive_action(spec: AIActionSpec) -> bool:
	if spec == null:
		return false
	var key: String = _approval_key(spec)
	if not _approved_destructive_actions.has(key):
		return false
	_approved_destructive_actions.erase(key)
	return true


func pending_destructive_approvals() -> int:
	return _approved_destructive_actions.size()


func _approval_key(spec: AIActionSpec) -> String:
	return "%s::%s" % [spec.id, spec.idempotency_key]


func _consume_destructive_approval(spec: AIActionSpec) -> bool:
	var key: String = _approval_key(spec)
	if _approved_destructive_actions.has(key):
		_approved_destructive_actions.erase(key)
		return true
	if allow_high_risk:
		# Eski entegrasyonları kırmadan geniş yetkiyi tek kullanımlığa indir.
		allow_high_risk = false
		return true
	return false


func execute_action(node: AIPlanNode, action_spec: AIActionSpec) -> AIVerificationResult:
	var result := AIVerificationResult.create(
		AIVerificationResult.VerifyLevel.RUNTIME,
		node.id if node != null else "?"
	)
	if node == null:
		result.mark_fail("Çalıştırılacak düğüm null")
		return result
	if node.level != AIPlanNode.Level.ACTION:
		result.mark_fail("Sadece ACTION seviyesi düğüm çalıştırılır")
		return result
	if action_spec == null:
		result.mark_fail("ActionSpec yok — işlem belirsiz")
		return result

	if is_high_risk(action_spec) and not _consume_destructive_approval(action_spec):
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = (
			"Yıkıcı işlem '%s' bu ActionSpec'e bağlı tek kullanımlık onay bekliyor"
			% action_spec.action_type_name()
		)
		return result

	match action_spec.action_type:
		AIActionSpec.ActionType.FILE_WRITE:
			return _exec_write(action_spec, result)
		AIActionSpec.ActionType.FILE_DELETE:
			return _exec_delete(action_spec, result)
		AIActionSpec.ActionType.SCENE_CREATE:
			return _exec_mkdir(action_spec, result)
		AIActionSpec.ActionType.CUSTOM:
			return _exec_custom(action_spec, result)
		AIActionSpec.ActionType.NODE_ADD, \
		AIActionSpec.ActionType.NODE_REMOVE, \
		AIActionSpec.ActionType.PROPERTY_SET, \
		AIActionSpec.ActionType.SCRIPT_ATTACH, \
		AIActionSpec.ActionType.PROJECT_SETTING:
			return _exec_editor_action(action_spec, result)
		_:
			result.outcome = AIVerificationResult.Outcome.SKIP
			result.message = "Action tipi desteklenmiyor: %s" % action_spec.action_type_name()
			return result


func execute_ready_actions(
	planner: AIHierarchicalPlanner, specs: Dictionary
) -> Array:
	var results: Array = []
	for node_id in planner.ready_nodes():
		var node: AIPlanNode = planner.tree.get_node(node_id)
		if node == null or node.level != AIPlanNode.Level.ACTION:
			continue
		var spec: AIActionSpec = specs.get(node_id, null)
		var action_result: AIVerificationResult = execute_action(node, spec)
		results.append(action_result)
		if action_result.outcome == AIVerificationResult.Outcome.PASS:
			planner.mark_completed(node_id)
	return results


func _exec_write(
	spec: AIActionSpec, result: AIVerificationResult
) -> AIVerificationResult:
	var path: String = str(spec.params.get("path", ""))
	var content: String = str(spec.params.get("content", ""))
	if path.is_empty():
		result.mark_fail("write_file: 'path' parametresi eksik")
		return result

	var now_unix: int = AIContractBase.iso_to_unix(AIContractBase.now_iso())
	var rate_check: Dictionary = rate_limiter.check_allowed(now_unix)
	if not bool(rate_check["allowed"]):
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = "Hız limiti: %s" % rate_check["reason"]
		return result

	var content_size: int = content.to_utf8_buffer().size()
	var is_new: bool = not _file_op.file_exists(path)
	var old_size: int = 0
	if not is_new:
		var old_read: Dictionary = _file_op.read_file(path)
		if bool(old_read["ok"]):
			old_size = str(old_read["content"]).to_utf8_buffer().size()
	var quota_check: Dictionary = quota.check_write_allowed(
		content_size, is_new, old_size
	)
	if not bool(quota_check["allowed"]):
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = "Kota: %s" % quota_check["reason"]
		return result

	var operation: Dictionary = _file_op.write_file(path, content)
	if not bool(operation["ok"]):
		result.mark_fail("write_file başarısız: %s" % operation["error"])
		return result
	quota.record_write(content_size, is_new, old_size)
	rate_limiter.record(now_unix)

	if verify_after_write:
		var integrity: Dictionary = AIIntegrityVerifier.verify_written(path, content)
		if not bool(integrity["ok"]):
			# Yazma gerçekleşti; bütünlük başarısızsa otomatik geri al.
			var rollback: Dictionary = _file_op.undo(str(operation["undo_token"]))
			result.mark_fail(
				"Bütünlük doğrulama başarısız: %s; rollback=%s" % [
					integrity["reason"], str(rollback.get("ok", false)),
				]
			)
			return result

	result.mark_pass(
		{
			"path": path,
			"op_id": operation["op_id"],
			"undo_token": operation["undo_token"],
			"size": content_size,
			"integrity_verified": verify_after_write,
		},
		"file_write"
	)
	result.message = "Dosya yazıldı ve doğrulandı: %s" % path
	return result


func _exec_delete(
	spec: AIActionSpec, result: AIVerificationResult
) -> AIVerificationResult:
	var path: String = str(spec.params.get("path", ""))
	if path.is_empty():
		result.mark_fail("delete_file: 'path' parametresi eksik")
		return result
	var operation: Dictionary = _file_op.delete_file(path)
	if bool(operation["ok"]):
		result.mark_pass(
			{
				"path": path,
				"op_id": operation["op_id"],
				"undo_token": operation["undo_token"],
			},
			"file_delete"
		)
		result.message = "Dosya silindi: %s" % path
	else:
		result.mark_fail("delete_file başarısız: %s" % operation["error"])
	return result


func _exec_custom(
	spec: AIActionSpec, result: AIVerificationResult
) -> AIVerificationResult:
	var sub_operation: String = str(spec.params.get("op", ""))
	match sub_operation:
		"move_file":
			var from_path: String = str(spec.params.get("from", ""))
			var to_path: String = str(spec.params.get("to", ""))
			if from_path.is_empty() or to_path.is_empty():
				result.mark_fail("move_file: 'from'/'to' parametresi eksik")
				return result
			var operation: Dictionary = _file_op.move_file(from_path, to_path)
			if bool(operation["ok"]):
				result.mark_pass(
					{
						"from": from_path,
						"to": to_path,
						"op_id": operation["op_id"],
					},
					"file_move"
				)
				result.message = "Dosya taşındı: %s -> %s" % [from_path, to_path]
			else:
				result.mark_fail("move_file başarısız: %s" % operation["error"])
			return result
		_:
			result.outcome = AIVerificationResult.Outcome.SKIP
			result.message = "CUSTOM alt-işlem desteklenmiyor: '%s'" % sub_operation
			return result


func _exec_mkdir(
	spec: AIActionSpec, result: AIVerificationResult
) -> AIVerificationResult:
	var path: String = str(spec.params.get("path", ""))
	if path.is_empty():
		result.mark_fail("make_dir: 'path' parametresi eksik")
		return result
	var operation: Dictionary = _file_op.make_dir(path)
	if bool(operation["ok"]):
		result.mark_pass({"path": path}, "dir_create")
		result.message = "Klasör oluşturuldu: %s" % path
	else:
		result.mark_fail("make_dir başarısız: %s" % operation["error"])
	return result


func _exec_editor_action(
	spec: AIActionSpec, result: AIVerificationResult
) -> AIVerificationResult:
	var planner_params: Dictionary = spec.params.duplicate(true)
	if spec.action_type != AIActionSpec.ActionType.PROJECT_SETTING:
		# ActionSpec.target_path editlenecek sahneyi tanımlar. Model yalnız
		# node_path vererek o anda açık olan farklı sahneyi değiştiremez.
		planner_params["scene_path"] = spec.target_path

	var planner := AISceneActionPlanner.new()
	var plan: Dictionary = planner.plan_for(spec.action_type, planner_params)
	if not bool(plan["ok"]):
		result.mark_fail("Editör action geçersiz: " + str(plan["reason"]))
		return result

	var applier := AIEditorActionApplier.new()
	var output: Dictionary
	match spec.action_type:
		AIActionSpec.ActionType.NODE_ADD:
			output = applier.apply_node_add(plan)
		AIActionSpec.ActionType.NODE_REMOVE:
			output = applier.apply_node_remove(plan)
		AIActionSpec.ActionType.PROPERTY_SET:
			output = applier.apply_property_set(plan)
		AIActionSpec.ActionType.SCRIPT_ATTACH:
			output = applier.apply_script_attach(plan)
		AIActionSpec.ActionType.PROJECT_SETTING:
			output = applier.apply_project_setting(plan)
		_:
			result.mark_fail("Editör action yönlendirilemedi")
			return result

	if not bool(output["available"]):
		result.outcome = AIVerificationResult.Outcome.SKIP
		result.message = "Editör bağlamı yok: %s" % output["reason"]
		return result
	if not bool(output["ok"]):
		result.mark_fail("Editör uygulaması başarısız: " + str(output["reason"]))
		return result

	result.mark_pass(
		{
			"action": spec.action_type_name(),
			"detail": str(output["reason"]),
			"undoable": bool(output.get("undoable", false)),
			"scene_path": str(output.get("scene_path", "")),
		},
		"editor_action"
	)
	result.message = str(output["reason"])
	return result


func undo_operation(undo_token: String) -> Dictionary:
	return _file_op.undo(undo_token)


func undo_last() -> Dictionary:
	var last: AIOperationJournal.OperationRecord = _journal.last_done()
	if last == null:
		return {"ok": false, "error": "Geri alınacak işlem yok", "reverted_path": ""}
	if last.undo_token.is_empty():
		return {
			"ok": false,
			"error": "İşlemin undo token'ı yok",
			"reverted_path": "",
		}
	var response: Dictionary = _file_op.undo(last.undo_token)
	if bool(response["ok"]):
		_journal.mark_reverted(last.id)
	return {
		"ok": response["ok"],
		"error": response["error"],
		"reverted_path": last.target_path,
	}


func create_batch() -> AITransactionBatch:
	return AITransactionBatch.new(_file_op)


func persist() -> bool:
	return _journal.save_to_disk()


func stats() -> Dictionary:
	return {
		"total_operations": _journal.count(),
		"done": _journal.records_with_status(AIOperationJournal.OpStatus.DONE).size(),
		"failed": _journal.records_with_status(AIOperationJournal.OpStatus.FAILED).size(),
		"pending": _journal.pending_operations().size(),
		"undo_snapshots": _undo.count(),
		"pending_destructive_approvals": _approved_destructive_actions.size(),
		"quota": quota.usage(),
	}
