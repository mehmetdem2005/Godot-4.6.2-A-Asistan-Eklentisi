@tool
class_name AIExecutorTest
extends RefCounted

## Phase 4 / Layer 4 — Executor & Sandbox Self-Test
##
## Sıkı testler: PathGuard saldırı senaryoları, Journal write-ahead,
## UndoStack snapshot/restore, SandboxedFileOp gerçek dosya I/O,
## ExecutorEngine action çalıştırma + risk kapısı.
##
## Gerçek dosya testleri user://ai_assistant/executor/test/ altında
## geçici dosya kullanır ve sonunda temizler.

const TEST_DIR: String = "user://ai_assistant/executor/test"


static func run_all() -> Array:
	var results: Array = []

	# PathGuard — güvenlik
	results.append(_b("Exec: PathGuard", _test_guard_allows_valid()))
	results.append(_b("Exec: PathGuard", _test_guard_blocks_traversal()))
	results.append(_b("Exec: PathGuard", _test_guard_blocks_system()))
	results.append(_b("Exec: PathGuard", _test_guard_blocks_self()))
	results.append(_b("Exec: PathGuard", _test_guard_blocks_readonly()))
	results.append(_b("Exec: PathGuard", _test_guard_blocks_engine_dirs()))
	results.append(_b("Exec: PathGuard", _test_generated_write_clamp()))

	# OperationJournal — write-ahead
	results.append(_b("Exec: Journal", _test_journal_lifecycle()))
	results.append(_b("Exec: Journal", _test_journal_pending()))
	results.append(_b("Exec: Journal", _test_journal_last_done()))
	results.append(_b("Exec: Journal", _test_journal_roundtrip()))

	# UndoStack — snapshot
	results.append(_b("Exec: Undo", _test_undo_snapshot_content()))
	results.append(_b("Exec: Undo", _test_undo_snapshot_absent()))
	results.append(_b("Exec: Undo", _test_undo_dedup()))
	results.append(_b("Exec: Undo", _test_undo_lifo()))

	# SandboxedFileOp — gerçek I/O
	results.append(_b("Exec: FileOp", _test_fileop_write_read()))
	results.append(_b("Exec: FileOp", _test_fileop_overwrite()))
	results.append(_b("Exec: FileOp", _test_fileop_delete()))
	results.append(_b("Exec: FileOp", _test_fileop_blocked_path()))
	results.append(_b("Exec: FileOp", _test_fileop_undo_create()))
	results.append(_b("Exec: FileOp", _test_fileop_undo_modify()))
	results.append(_b("Exec: FileOp", _test_fileop_atomic()))

	# ExecutorEngine — action çalıştırma
	results.append(_b("Exec: Engine", _test_engine_write_action()))
	results.append(_b("Exec: Engine", _test_engine_high_risk_gate()))
	results.append(_b("Exec: Engine", _test_engine_unsupported()))
	results.append(_b("Exec: Engine", _test_engine_null_safety()))
	results.append(_b("Exec: Engine", _test_engine_undo_last()))

	# ResourceQuota — kaynak limitleri
	results.append(_b("Exec: Quota", _test_quota_allows_normal()))
	results.append(_b("Exec: Quota", _test_quota_single_file_limit()))
	results.append(_b("Exec: Quota", _test_quota_file_count_limit()))
	results.append(_b("Exec: Quota", _test_quota_total_bytes()))

	# RateLimiter — hız sınırı
	results.append(_b("Exec: RateLimit", _test_rate_allows_within()))
	results.append(_b("Exec: RateLimit", _test_rate_blocks_over()))
	results.append(_b("Exec: RateLimit", _test_rate_window_slides()))

	# IntegrityVerifier — yazım sonrası doğrulama
	results.append(_b("Exec: Integrity", _test_integrity_verifies_ok()))
	results.append(_b("Exec: Integrity", _test_integrity_catches_missing()))

	# TransactionBatch — atomik grup
	results.append(_b("Exec: Batch", _test_batch_all_success()))
	results.append(_b("Exec: Batch", _test_batch_rollback()))
	results.append(_b("Exec: Batch", _test_batch_empty()))

	# Temizlik
	_cleanup()
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


## Test dosyalarını temizler.
static func _cleanup() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	var dir: DirAccess = DirAccess.open(TEST_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(TEST_DIR + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()


# ============================================================
# PATHGUARD
# ============================================================

static func _test_guard_allows_valid() -> Dictionary:
	var name := "PathGuard geçerli yola izin verir"
	if not AIPathGuard.can_write("res://scenes/main.tscn"):
		return _fail(name, "res:// yolu reddedildi")
	if not AIPathGuard.can_write("user://ai_assistant/data.json"):
		return _fail(name, "user:// yolu reddedildi")
	return _ok(name)


static func _test_guard_blocks_traversal() -> Dictionary:
	var name := "PathGuard path traversal engeller"
	if AIPathGuard.can_write("res://../../etc/passwd"):
		return _fail(name, "traversal geçti")
	if AIPathGuard.can_write("res://a/../../b"):
		return _fail(name, "gizli traversal geçti")
	return _ok(name)


static func _test_guard_blocks_system() -> Dictionary:
	var name := "PathGuard sistem yollarını engeller"
	if AIPathGuard.can_write("/etc/passwd"):
		return _fail(name, "unix sistem yolu geçti")
	if AIPathGuard.can_write("C:/Windows/System32"):
		return _fail(name, "windows yolu geçti")
	if AIPathGuard.can_write("scenes/main.tscn"):
		return _fail(name, "köksüz yol geçti")
	return _ok(name)


static func _test_guard_blocks_self() -> Dictionary:
	var name := "PathGuard kendi kodunu korur"
	if AIPathGuard.can_write("res://addons/ai_assistant/executor/path_guard.gd"):
		return _fail(name, "sistem kendi kodunu değiştirebiliyor")
	return _ok(name)


static func _test_guard_blocks_readonly() -> Dictionary:
	var name := "PathGuard project.godot korur"
	if AIPathGuard.can_write("res://project.godot"):
		return _fail(name, "project.godot yazılabilir")
	return _ok(name)


static func _test_guard_blocks_engine_dirs() -> Dictionary:
	var name := "PathGuard motor klasörlerini korur"
	if AIPathGuard.can_write("res://.godot/cache.cfg"):
		return _fail(name, ".godot yazılabilir")
	if AIPathGuard.can_write("res://.import/x.md5"):
		return _fail(name, ".import yazılabilir")
	return _ok(name)


static func _test_generated_write_clamp() -> Dictionary:
	var name := "PathGuard üretilen-yazımı res://game/ altına sıkıştırır"
	# İzinli: üretilen kök altı
	if not AIPathGuard.can_generate_write("res://game/scripts/p.gd"):
		return _fail(name, "res://game/scripts/ reddedildi")
	if not AIPathGuard.can_generate_write("res://game/scenes/m.tscn"):
		return _fail(name, "res://game/scenes/ reddedildi")
	# Reddedilmeli: kök dışı (genel check_write geçse bile)
	if AIPathGuard.can_generate_write("res://core/engine.gd"):
		return _fail(name, "kök dışı res:// üretime izin verildi")
	if AIPathGuard.can_generate_write("user://x/y.gd"):
		return _fail(name, "user:// üretime izin verildi")
	# Reddedilmeli: traversal + addons + project.godot (devralınan)
	if AIPathGuard.can_generate_write("res://game/../addons/x.gd"):
		return _fail(name, "traversal üretime izin verildi")
	if AIPathGuard.can_generate_write(
		"res://addons/ai_assistant/plugin.gd"
	):
		return _fail(name, "addons üretime izin verildi")
	return _ok(name)


# ============================================================
# OPERATION JOURNAL
# ============================================================

static func _test_journal_lifecycle() -> Dictionary:
	var name := "Journal işlem yaşam döngüsü"
	var j := AIOperationJournal.new()
	var rec: AIOperationJournal.OperationRecord = j.begin_operation(
		AIOperationJournal.OpType.WRITE, "res://test.gd"
	)
	if rec.status != AIOperationJournal.OpStatus.PENDING:
		return _fail(name, "yeni kayıt PENDING olmalı")
	j.mark_done(rec.id, "undo_x")
	if j.get_record(rec.id).status != AIOperationJournal.OpStatus.DONE:
		return _fail(name, "mark_done çalışmadı")
	if j.get_record(rec.id).undo_token != "undo_x":
		return _fail(name, "undo_token kaydedilmedi")
	return _ok(name)


static func _test_journal_pending() -> Dictionary:
	var name := "Journal yarım kalan işlem tespiti"
	var j := AIOperationJournal.new()
	var r1: AIOperationJournal.OperationRecord = j.begin_operation(
		AIOperationJournal.OpType.WRITE, "res://a.gd"
	)
	j.begin_operation(AIOperationJournal.OpType.WRITE, "res://b.gd")
	j.mark_done(r1.id)
	# 1 PENDING kalmalı (b.gd)
	var pending: Array = j.pending_operations()
	if pending.size() != 1:
		return _fail(name, "1 pending beklenir, %d bulundu" % pending.size())
	return _ok(name)


static func _test_journal_last_done() -> Dictionary:
	var name := "Journal son tamamlanan işlem"
	var j := AIOperationJournal.new()
	var r1: AIOperationJournal.OperationRecord = j.begin_operation(
		AIOperationJournal.OpType.WRITE, "res://first.gd"
	)
	var r2: AIOperationJournal.OperationRecord = j.begin_operation(
		AIOperationJournal.OpType.WRITE, "res://second.gd"
	)
	j.mark_done(r1.id)
	j.mark_done(r2.id)
	var last: AIOperationJournal.OperationRecord = j.last_done()
	if last == null or last.target_path != "res://second.gd":
		return _fail(name, "son tamamlanan 'second.gd' olmalı")
	return _ok(name)


static func _test_journal_roundtrip() -> Dictionary:
	var name := "Journal kayıt round-trip"
	var j := AIOperationJournal.new()
	var rec: AIOperationJournal.OperationRecord = j.begin_operation(
		AIOperationJournal.OpType.CREATE, "res://rt.gd"
	)
	j.mark_done(rec.id, "tok")
	# to_dict / from_dict tutarlılığı
	var d: Dictionary = rec.to_dict()
	var rec2 := AIOperationJournal.OperationRecord.new()
	rec2.from_dict(d)
	if rec2.id != rec.id or rec2.target_path != rec.target_path:
		return _fail(name, "round-trip veri kaybı")
	if rec2.status != AIOperationJournal.OpStatus.DONE:
		return _fail(name, "status round-trip bozuk")
	return _ok(name)


# ============================================================
# UNDO STACK
# ============================================================

static func _test_undo_snapshot_content() -> Dictionary:
	var name := "UndoStack içerik snapshot'lar"
	var u := AIUndoStack.new()
	var token: String = u.snapshot_existing("res://x.gd", "eski içerik")
	if token.is_empty():
		return _fail(name, "token üretilmedi")
	var inst: Dictionary = u.get_undo_instruction(token)
	if not inst["found"]:
		return _fail(name, "snapshot bulunamadı")
	if inst["restore_content"] != "eski içerik":
		return _fail(name, "içerik yanlış geri geldi")
	return _ok(name)


static func _test_undo_snapshot_absent() -> Dictionary:
	var name := "UndoStack yokluk snapshot'lar"
	var u := AIUndoStack.new()
	var token: String = u.snapshot_absent("res://yeni.gd")
	var inst: Dictionary = u.get_undo_instruction(token)
	if inst["kind"] != AIUndoStack.SnapshotKind.FILE_ABSENT:
		return _fail(name, "FILE_ABSENT olmalı (geri-al = sil)")
	return _ok(name)


static func _test_undo_dedup() -> Dictionary:
	var name := "UndoStack aynı içeriği deduplike eder"
	var u := AIUndoStack.new()
	u.snapshot_existing("res://a.gd", "aynı içerik")
	u.snapshot_existing("res://b.gd", "aynı içerik")
	# 2 snapshot ama 1 benzersiz içerik
	if u.pool_size() != 1:
		return _fail(name, "aynı içerik 1 kez saklanmalı, havuz: %d" % u.pool_size())
	if u.count() != 2:
		return _fail(name, "2 snapshot olmalı")
	return _ok(name)


static func _test_undo_lifo() -> Dictionary:
	var name := "UndoStack LIFO sırası"
	var u := AIUndoStack.new()
	u.snapshot_absent("res://1.gd")
	var t2: String = u.snapshot_absent("res://2.gd")
	# Son eklenen tepe olmalı
	if u.peek_last() != t2:
		return _fail(name, "peek_last son snapshot'ı vermeli")
	if u.pop_last() != t2:
		return _fail(name, "pop_last son snapshot'ı çıkarmalı")
	if u.count() != 1:
		return _fail(name, "pop sonrası 1 kalmalı")
	return _ok(name)


# ============================================================
# SANDBOXED FILE OP — gerçek I/O
# ============================================================

static func _make_fileop() -> AISandboxedFileOp:
	return AISandboxedFileOp.new(AIOperationJournal.new(), AIUndoStack.new())


static func _test_fileop_write_read() -> Dictionary:
	var name := "FileOp gerçek yaz ve oku"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/wr.txt"
	var w: Dictionary = fop.write_file(path, "merhaba dünya")
	if not w["ok"]:
		return _fail(name, "yazma başarısız: %s" % w["error"])
	var r: Dictionary = fop.read_file(path)
	if not r["ok"]:
		return _fail(name, "okuma başarısız: %s" % r["error"])
	if r["content"] != "merhaba dünya":
		return _fail(name, "içerik yanlış: '%s'" % r["content"])
	return _ok(name)


static func _test_fileop_overwrite() -> Dictionary:
	var name := "FileOp üzerine yazma"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/ow.txt"
	fop.write_file(path, "ilk")
	var w2: Dictionary = fop.write_file(path, "ikinci")
	if not w2["ok"]:
		return _fail(name, "üzerine yazma başarısız")
	# Üzerine yazma undo token üretmeli (eski hâl snapshot'landı)
	if (w2["undo_token"] as String).is_empty():
		return _fail(name, "üzerine yazma undo token üretmeli")
	var r: Dictionary = fop.read_file(path)
	if r["content"] != "ikinci":
		return _fail(name, "içerik güncellenmedi")
	return _ok(name)


static func _test_fileop_delete() -> Dictionary:
	var name := "FileOp gerçek silme"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/del.txt"
	fop.write_file(path, "silinecek")
	var d: Dictionary = fop.delete_file(path)
	if not d["ok"]:
		return _fail(name, "silme başarısız: %s" % d["error"])
	if fop.file_exists(path):
		return _fail(name, "dosya hâlâ var")
	# Silme undo token üretmeli
	if (d["undo_token"] as String).is_empty():
		return _fail(name, "silme undo token üretmeli")
	return _ok(name)


static func _test_fileop_blocked_path() -> Dictionary:
	var name := "FileOp yasaklı yolu reddeder"
	var fop: AISandboxedFileOp = _make_fileop()
	# Sistem yoluna yazma denemeleri başarısız olmalı
	var w: Dictionary = fop.write_file("/etc/passwd", "kötü")
	if w["ok"]:
		return _fail(name, "sistem yoluna yazma geçti")
	var w2: Dictionary = fop.write_file("res://project.godot", "kötü")
	if w2["ok"]:
		return _fail(name, "project.godot yazma geçti")
	return _ok(name)


static func _test_fileop_undo_create() -> Dictionary:
	var name := "FileOp oluşturma geri-alma"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/uc.txt"
	var w: Dictionary = fop.write_file(path, "yeni dosya")
	if not w["ok"]:
		return _fail(name, "oluşturma başarısız")
	# Geri al — dosya silinmeli (önceden yoktu)
	var u: Dictionary = fop.undo(w["undo_token"])
	if not u["ok"]:
		return _fail(name, "undo başarısız: %s" % u["error"])
	if fop.file_exists(path):
		return _fail(name, "geri-alma sonrası dosya hâlâ var")
	return _ok(name)


static func _test_fileop_undo_modify() -> Dictionary:
	var name := "FileOp değiştirme geri-alma"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/um.txt"
	fop.write_file(path, "orijinal")
	var w2: Dictionary = fop.write_file(path, "değiştirilmiş")
	# Geri al — eski içerik dönmeli
	var u: Dictionary = fop.undo(w2["undo_token"])
	if not u["ok"]:
		return _fail(name, "undo başarısız")
	var r: Dictionary = fop.read_file(path)
	if r["content"] != "orijinal":
		return _fail(name, "eski içerik geri gelmedi: '%s'" % r["content"])
	return _ok(name)


static func _test_fileop_atomic() -> Dictionary:
	var name := "FileOp atomik yazım (.tmp kalmaz)"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/at.txt"
	fop.write_file(path, "atomik")
	# .tmp dosyası kalmamalı
	if fop.file_exists(path + ".tmp"):
		return _fail(name, ".tmp dosyası temizlenmedi")
	return _ok(name)


# ============================================================
# EXECUTOR ENGINE
# ============================================================

static func _make_spec(action_type: int, params: Dictionary) -> AIActionSpec:
	var spec := AIActionSpec.create(action_type, "res://x", "TestRole")
	spec.params = params
	return spec


static func _make_action_node() -> AIPlanNode:
	return AIPlanNode.create(AIPlanNode.Level.ACTION, "Test action")


static func _test_engine_write_action() -> Dictionary:
	var name := "Engine write action çalıştırır"
	var engine := AIExecutorEngine.new()
	var node: AIPlanNode = _make_action_node()
	var spec: AIActionSpec = _make_spec(
		AIActionSpec.ActionType.FILE_WRITE,
		{"path": TEST_DIR + "/eng.txt", "content": "engine yazdı"}
	)
	var result: AIVerificationResult = engine.execute_action(node, spec)
	if result.outcome != AIVerificationResult.Outcome.PASS:
		return _fail(name, "action PASS olmalı: %s" % result.message)
	# Dosya gerçekten yazıldı mı
	if not FileAccess.file_exists(TEST_DIR + "/eng.txt"):
		return _fail(name, "dosya gerçekten yazılmadı")
	return _ok(name)


static func _test_engine_high_risk_gate() -> Dictionary:
	var name := "Engine yıkıcı işlemi onaysız durdurur"
	var engine := AIExecutorEngine.new()
	# Önce bir dosya oluştur
	var setup: AISandboxedFileOp = _make_fileop()
	setup.write_file(TEST_DIR + "/risk.txt", "silinecek")
	var node: AIPlanNode = _make_action_node()
	var spec: AIActionSpec = _make_spec(
		AIActionSpec.ActionType.FILE_DELETE, {"path": TEST_DIR + "/risk.txt"}
	)
	# allow_high_risk = false (varsayılan) — SKIP olmalı
	var result: AIVerificationResult = engine.execute_action(node, spec)
	if result.outcome != AIVerificationResult.Outcome.SKIP:
		return _fail(name, "yıkıcı işlem onaysız SKIP olmalı")
	# Dosya hâlâ durmalı (silinmedi)
	if not FileAccess.file_exists(TEST_DIR + "/risk.txt"):
		return _fail(name, "onaysız işlem dosyayı silmiş")
	return _ok(name)


static func _test_engine_unsupported() -> Dictionary:
	var name := "Engine desteklenmeyen tipi SKIP eder"
	var engine := AIExecutorEngine.new()
	var node: AIPlanNode = _make_action_node()
	# NODE_REPARENT Layer 4'te hâlâ desteklenmiyor (NODE_ADD/REMOVE/
	# PROPERTY_SET/SCRIPT_ATTACH/PROJECT_SETTING artık editör işlemi)
	var spec: AIActionSpec = _make_spec(
		AIActionSpec.ActionType.NODE_REPARENT, {}
	)
	var result: AIVerificationResult = engine.execute_action(node, spec)
	if result.outcome != AIVerificationResult.Outcome.SKIP:
		return _fail(name, "desteklenmeyen tip SKIP olmalı (sahte başarı yok)")
	return _ok(name)


static func _test_engine_null_safety() -> Dictionary:
	var name := "Engine null girdi güvenliği"
	var engine := AIExecutorEngine.new()
	# Null node
	var r1: AIVerificationResult = engine.execute_action(null, null)
	if r1.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "null girdi PASS olmamalı")
	# Null spec
	var node: AIPlanNode = _make_action_node()
	var r2: AIVerificationResult = engine.execute_action(node, null)
	if r2.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "null spec PASS olmamalı")
	return _ok(name)


static func _test_engine_undo_last() -> Dictionary:
	var name := "Engine son işlemi geri alır"
	var engine := AIExecutorEngine.new()
	var node: AIPlanNode = _make_action_node()
	var path: String = TEST_DIR + "/eundo.txt"
	var spec: AIActionSpec = _make_spec(
		AIActionSpec.ActionType.FILE_WRITE, {"path": path, "content": "x"}
	)
	engine.execute_action(node, spec)
	if not FileAccess.file_exists(path):
		return _fail(name, "dosya yazılmadı")
	# Son işlemi geri al
	var u: Dictionary = engine.undo_last()
	if not u["ok"]:
		return _fail(name, "undo_last başarısız: %s" % u["error"])
	if FileAccess.file_exists(path):
		return _fail(name, "geri-alma sonrası dosya hâlâ var")
	return _ok(name)


# ============================================================
# RESOURCE QUOTA
# ============================================================

static func _test_quota_allows_normal() -> Dictionary:
	var name := "Quota normal yazmaya izin verir"
	var q := AIResourceQuota.new()
	var check: Dictionary = q.check_write_allowed(1000, true)
	if not check["allowed"]:
		return _fail(name, "normal yazma reddedildi")
	return _ok(name)


static func _test_quota_single_file_limit() -> Dictionary:
	var name := "Quota tek dosya limiti"
	var q := AIResourceQuota.new()
	q.max_single_file_bytes = 500
	# 600 bayt — limiti aşar
	if q.check_write_allowed(600, true)["allowed"]:
		return _fail(name, "tek dosya limiti aşıldı ama izin verildi")
	# 400 bayt — limit içinde
	if not q.check_write_allowed(400, true)["allowed"]:
		return _fail(name, "limit içi yazma reddedildi")
	return _ok(name)


static func _test_quota_file_count_limit() -> Dictionary:
	var name := "Quota dosya sayısı limiti"
	var q := AIResourceQuota.new()
	q.max_file_count = 2
	q.record_write(100, true)
	q.record_write(100, true)
	# 2 dosya doldu — 3. yeni dosya reddedilmeli
	if q.check_write_allowed(100, true)["allowed"]:
		return _fail(name, "dosya sayısı limiti aşıldı ama izin verildi")
	return _ok(name)


static func _test_quota_total_bytes() -> Dictionary:
	var name := "Quota toplam bayt limiti"
	var q := AIResourceQuota.new()
	q.max_total_bytes = 1000
	q.record_write(800, true)
	# 800 kullanıldı, 300 daha = 1100 > 1000 — reddedilmeli
	if q.check_write_allowed(300, true)["allowed"]:
		return _fail(name, "toplam kota aşıldı ama izin verildi")
	# 200 daha = 1000 — tam sınır, kabul
	if not q.check_write_allowed(200, true)["allowed"]:
		return _fail(name, "tam sınır yazma reddedildi")
	return _ok(name)


# ============================================================
# RATE LIMITER
# ============================================================

static func _test_rate_allows_within() -> Dictionary:
	var name := "RateLimiter limit içinde izin verir"
	var rl := AIRateLimiter.new()
	rl.max_ops_in_window = 5
	# 5 işlem — hepsi izinli
	for i in range(5):
		if not rl.try_acquire(100)["allowed"]:
			return _fail(name, "limit içi işlem %d reddedildi" % i)
	return _ok(name)


static func _test_rate_blocks_over() -> Dictionary:
	var name := "RateLimiter limit aşımını engeller"
	var rl := AIRateLimiter.new()
	rl.max_ops_in_window = 3
	for i in range(3):
		rl.try_acquire(100)
	# 4. işlem aynı anda — reddedilmeli
	if rl.try_acquire(100)["allowed"]:
		return _fail(name, "limit aşıldı ama izin verildi")
	return _ok(name)


static func _test_rate_window_slides() -> Dictionary:
	var name := "RateLimiter pencere kayması"
	var rl := AIRateLimiter.new()
	rl.max_ops_in_window = 2
	rl.window_seconds = 10
	rl.try_acquire(100)
	rl.try_acquire(100)
	# Pencere dolu — 3. red
	if rl.try_acquire(100)["allowed"]:
		return _fail(name, "pencere dolu ama izin verildi")
	# 11 saniye sonra — eski işlemler düştü, tekrar açık
	if not rl.try_acquire(111)["allowed"]:
		return _fail(name, "pencere kaydı ama hâlâ kapalı")
	return _ok(name)


# ============================================================
# INTEGRITY VERIFIER
# ============================================================

static func _test_integrity_verifies_ok() -> Dictionary:
	var name := "IntegrityVerifier doğru yazımı onaylar"
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/integ.txt"
	fop.write_file(path, "doğru içerik")
	var v: Dictionary = AIIntegrityVerifier.verify_written(path, "doğru içerik")
	if not v["ok"]:
		return _fail(name, "doğru yazım onaylanmadı: %s" % v["reason"])
	return _ok(name)


static func _test_integrity_catches_missing() -> Dictionary:
	var name := "IntegrityVerifier eksik/bozuk yakalar"
	# Var olmayan dosya — doğrulama başarısız olmalı
	var v: Dictionary = AIIntegrityVerifier.verify_written(
		TEST_DIR + "/yok_boyle.txt", "bir şey"
	)
	if v["ok"]:
		return _fail(name, "var olmayan dosya doğrulamadan geçti")
	# Yanlış içerik beklentisi — hash uyuşmamalı
	var fop: AISandboxedFileOp = _make_fileop()
	var path: String = TEST_DIR + "/integ2.txt"
	fop.write_file(path, "gerçek içerik")
	var v2: Dictionary = AIIntegrityVerifier.verify_written(path, "farklı içerik")
	if v2["ok"]:
		return _fail(name, "yanlış içerik doğrulamadan geçti")
	return _ok(name)


# ============================================================
# TRANSACTION BATCH
# ============================================================

static func _test_batch_all_success() -> Dictionary:
	var name := "Batch hepsi başarılı commit"
	var fop: AISandboxedFileOp = _make_fileop()
	var batch := AITransactionBatch.new(fop)
	batch.add_write(TEST_DIR + "/b1.txt", "bir")
	batch.add_write(TEST_DIR + "/b2.txt", "iki")
	batch.add_write(TEST_DIR + "/b3.txt", "üç")
	var result: Dictionary = batch.commit()
	if not result["ok"]:
		return _fail(name, "commit başarısız: %s" % result["error"])
	if result["applied"] != 3:
		return _fail(name, "3 işlem uygulanmalı")
	# Üç dosya da gerçekten var
	if not (fop.file_exists(TEST_DIR + "/b1.txt")
			and fop.file_exists(TEST_DIR + "/b2.txt")
			and fop.file_exists(TEST_DIR + "/b3.txt")):
		return _fail(name, "dosyalar gerçekten yazılmadı")
	return _ok(name)


static func _test_batch_rollback() -> Dictionary:
	var name := "Batch hata olunca rollback"
	var fop: AISandboxedFileOp = _make_fileop()
	var batch := AITransactionBatch.new(fop)
	# İlk iki geçerli, üçüncü yasaklı yol — hata verecek
	batch.add_write(TEST_DIR + "/rb1.txt", "bir")
	batch.add_write(TEST_DIR + "/rb2.txt", "iki")
	batch.add_write("res://project.godot", "kötü")  # PathGuard reddeder
	var result: Dictionary = batch.commit()
	if result["ok"]:
		return _fail(name, "hatalı batch commit başarılı görünüyor")
	if result["failed_at"] != 2:
		return _fail(name, "hata indeksi 2 olmalı: %d" % result["failed_at"])
	# İlk iki dosya geri alınmış olmalı — rollback
	if fop.file_exists(TEST_DIR + "/rb1.txt") or fop.file_exists(TEST_DIR + "/rb2.txt"):
		return _fail(name, "rollback çalışmadı — dosyalar hâlâ var")
	return _ok(name)


static func _test_batch_empty() -> Dictionary:
	var name := "Batch boş batch güvenli"
	var fop: AISandboxedFileOp = _make_fileop()
	var batch := AITransactionBatch.new(fop)
	var result: Dictionary = batch.commit()
	if not result["ok"]:
		return _fail(name, "boş batch ok olmalı")
	if result["applied"] != 0:
		return _fail(name, "boş batch 0 işlem uygulamalı")
	return _ok(name)
