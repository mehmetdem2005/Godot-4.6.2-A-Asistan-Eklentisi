@tool
class_name AISurgicalValidationTest
extends RefCounted

## Surgical Edit — Doğrulamalar Self-Test
##
## Sıkı testler: 4 düzenleme-sonrası doğrulama.
## CommentLossDetector (yorum kaybı), NamingDriftDetector (sembol
## kayması), ScopeCreepDetector (kapsam taşması), IntentAlignmentChecker
## (niyet uyumu).
##
## NOT scope_creep: bir satırı DEĞİŞTİRMEK satır-tabanlı diff'te
## 2 işlemdir (1 silme + 1 ekleme). Testler expected_change_lines'ı
## bu gerçeğe göre verir.


static func run_all() -> Array:
	var results: Array = []

	# CommentLossDetector
	results.append(_b("Surgical: CommentLoss", _test_comment_docstring_loss()))
	results.append(_b("Surgical: CommentLoss", _test_comment_todo_loss()))
	results.append(_b("Surgical: CommentLoss", _test_comment_preserved()))
	results.append(_b("Surgical: CommentLoss", _test_comment_acceptable()))

	# NamingDriftDetector
	results.append(_b("Surgical: NamingDrift", _test_naming_symbol_removed()))
	results.append(_b("Surgical: NamingDrift", _test_naming_symbol_added()))
	results.append(_b("Surgical: NamingDrift", _test_naming_preserved()))
	results.append(_b("Surgical: NamingDrift", _test_naming_acceptable()))

	# ScopeCreepDetector
	results.append(_b("Surgical: ScopeCreep", _test_creep_within_scope()))
	results.append(_b("Surgical: ScopeCreep", _test_creep_major()))
	results.append(_b("Surgical: ScopeCreep", _test_creep_outside_range()))
	results.append(_b("Surgical: ScopeCreep", _test_creep_range_clean()))

	# IntentAlignmentChecker
	results.append(_b("Surgical: IntentAlign", _test_align_delete()))
	results.append(_b("Surgical: IntentAlign", _test_align_delete_suspicious()))
	results.append(_b("Surgical: IntentAlign", _test_align_add()))
	results.append(_b("Surgical: IntentAlign", _test_align_modify()))
	results.append(_b("Surgical: IntentAlign", _test_align_rename()))
	results.append(_b("Surgical: IntentAlign", _test_align_no_change()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# COMMENT LOSS
# ============================================================

static func _test_comment_docstring_loss() -> Dictionary:
	var name := "CommentLoss docstring kaybı HIGH"
	var d := AICommentLossDetector.new()
	var report: AICommentLossDetector.CommentLossReport = d.detect(
		"## API belgesi\nfunc f():\n\tpass", "func f():\n\tpass"
	)
	if not report.has_loss:
		return _fail(name, "docstring kaybı tespit edilmeli")
	if report.max_severity() != "high":
		return _fail(name, "docstring kaybı HIGH önemde olmalı")
	return _ok(name)


static func _test_comment_todo_loss() -> Dictionary:
	var name := "CommentLoss TODO kaybı MEDIUM"
	var d := AICommentLossDetector.new()
	var report: AICommentLossDetector.CommentLossReport = d.detect(
		"# TODO: bunu düzelt\nvar x = 1", "var x = 1"
	)
	if not report.has_loss:
		return _fail(name, "TODO kaybı tespit edilmeli")
	if report.max_severity() != "medium":
		return _fail(name, "TODO kaybı MEDIUM önemde olmalı")
	return _ok(name)


static func _test_comment_preserved() -> Dictionary:
	var name := "CommentLoss korunan yorum"
	var d := AICommentLossDetector.new()
	var report: AICommentLossDetector.CommentLossReport = d.detect(
		"# önemli yorum\nvar x = 1", "# önemli yorum\nvar x = 2"
	)
	if report.has_loss:
		return _fail(name, "korunan yorumda kayıp olmamalı")
	return _ok(name)


static func _test_comment_acceptable() -> Dictionary:
	var name := "CommentLoss kabul edilebilirlik"
	var d := AICommentLossDetector.new()
	# Docstring kaybı — kabul edilemez
	var high: AICommentLossDetector.CommentLossReport = d.detect(
		"## belge\nkod", "kod"
	)
	if d.is_loss_acceptable(high):
		return _fail(name, "docstring kaybı kabul edilemez olmalı")
	# Normal yorum kaybı — kabul edilebilir
	var low: AICommentLossDetector.CommentLossReport = d.detect(
		"# sıradan\nkod", "kod"
	)
	if not d.is_loss_acceptable(low):
		return _fail(name, "normal yorum kaybı kabul edilebilir olmalı")
	return _ok(name)


# ============================================================
# NAMING DRIFT
# ============================================================

static func _test_naming_symbol_removed() -> Dictionary:
	var name := "NamingDrift sembol kaybı"
	var d := AINamingDriftDetector.new()
	var report: AINamingDriftDetector.NamingDriftReport = d.detect(
		"var health = 1\nvar score = 2", "var score = 2"
	)
	if not report.has_removed():
		return _fail(name, "kaybolan sembol tespit edilmeli")
	return _ok(name)


static func _test_naming_symbol_added() -> Dictionary:
	var name := "NamingDrift sembol ekleme"
	var d := AINamingDriftDetector.new()
	var report: AINamingDriftDetector.NamingDriftReport = d.detect(
		"var a = 1", "var a = 1\nvar b = 2"
	)
	if report.added_symbols.size() != 1:
		return _fail(name, "eklenen sembol tespit edilmeli")
	if report.has_removed():
		return _fail(name, "ekleme kayıp sayılmamalı")
	return _ok(name)


static func _test_naming_preserved() -> Dictionary:
	var name := "NamingDrift korunan semboller"
	var d := AINamingDriftDetector.new()
	var report: AINamingDriftDetector.NamingDriftReport = d.detect(
		"func calc():\n\treturn 1", "func calc():\n\treturn 2"
	)
	# Gövde değişti ama sembol (func calc) korundu
	if report.has_drift:
		return _fail(name, "sembol korunduğunda drift olmamalı")
	return _ok(name)


static func _test_naming_acceptable() -> Dictionary:
	var name := "NamingDrift kabul edilebilirlik"
	var d := AINamingDriftDetector.new()
	# Sembol kaybı — kabul edilemez
	var removed: AINamingDriftDetector.NamingDriftReport = d.detect(
		"var hp = 1", "var health = 1"
	)
	if d.is_drift_acceptable(removed):
		return _fail(name, "sembol kaybı kabul edilemez olmalı")
	# Sadece ekleme — kabul edilebilir
	var added: AINamingDriftDetector.NamingDriftReport = d.detect(
		"var a = 1", "var a = 1\nvar b = 2"
	)
	if not d.is_drift_acceptable(added):
		return _fail(name, "sadece ekleme kabul edilebilir olmalı")
	return _ok(name)


# ============================================================
# SCOPE CREEP
# ============================================================

static func _test_creep_within_scope() -> Dictionary:
	var name := "ScopeCreep kapsam içinde"
	var d := AIScopeCreepDetector.new()
	# 1 satır değişimi = 2 satır-işlemi (b silindi, X eklendi).
	# Gerçekçi beklenti: expected_change_lines = 2
	var report: AIScopeCreepDetector.ScopeCreepReport = d.detect(
		"a\nb\nc", "a\nX\nc", 2
	)
	if report.level != AIScopeCreepDetector.CreepLevel.NONE:
		return _fail(name, "beklenen kapsamdaki değişim NONE olmalı")
	if not report.is_within_scope():
		return _fail(name, "kapsam içi kabul edilmeli")
	return _ok(name)


static func _test_creep_major() -> Dictionary:
	var name := "ScopeCreep büyük taşma"
	var d := AIScopeCreepDetector.new()
	# 20 satırlık tam değişim ama beklenen sadece 3 satırdı
	var old_lines: PackedStringArray = PackedStringArray()
	var new_lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		old_lines.append("eski_%d" % i)
		new_lines.append("yeni_%d" % i)
	var report: AIScopeCreepDetector.ScopeCreepReport = d.detect(
		"\n".join(old_lines), "\n".join(new_lines), 3
	)
	if report.level != AIScopeCreepDetector.CreepLevel.MAJOR:
		return _fail(name, "beklenenin çok üstü değişim MAJOR olmalı")
	if report.is_within_scope():
		return _fail(name, "MAJOR taşma kapsam dışı olmalı")
	return _ok(name)


static func _test_creep_outside_range() -> Dictionary:
	var name := "ScopeCreep izin verilen aralık dışı"
	var d := AIScopeCreepDetector.new()
	# İzin verilen aralık 2-3, ama her yer değişti
	var report: AIScopeCreepDetector.ScopeCreepReport = d.detect_outside_range(
		"a\nb\nc\nd\ne", "X\nY\nZ\nW\nV", 2, 3
	)
	if report.level != AIScopeCreepDetector.CreepLevel.MAJOR:
		return _fail(name, "aralık dışı çok değişim MAJOR olmalı")
	return _ok(name)


static func _test_creep_range_clean() -> Dictionary:
	var name := "ScopeCreep aralık içi temiz"
	var d := AIScopeCreepDetector.new()
	# Sadece izin verilen aralıkta (2-3) değişim
	var report: AIScopeCreepDetector.ScopeCreepReport = d.detect_outside_range(
		"a\nb\nc\nd\ne", "a\nX\nY\nd\ne", 2, 3
	)
	if report.level != AIScopeCreepDetector.CreepLevel.NONE:
		return _fail(name, "aralık içi değişim NONE olmalı")
	return _ok(name)


# ============================================================
# INTENT ALIGNMENT
# ============================================================

static func _test_align_delete() -> Dictionary:
	var name := "IntentAlign DELETE küçülme uyumlu"
	var c := AIIntentAlignmentChecker.new()
	var report: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.DELETE_CODE, "a\nb\nc\nd", "a\nd"
	)
	if not report.is_aligned():
		return _fail(name, "silme niyeti + küçülme uyumlu olmalı")
	return _ok(name)


static func _test_align_delete_suspicious() -> Dictionary:
	var name := "IntentAlign DELETE büyüme şüpheli"
	var c := AIIntentAlignmentChecker.new()
	var report: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.DELETE_CODE, "a", "a\nb\nc\nd"
	)
	# Silme niyetiyle büyüme — uyumlu OLMAMALI
	if report.is_aligned():
		return _fail(name, "silme niyeti + büyüme uyumlu olmamalı")
	return _ok(name)


static func _test_align_add() -> Dictionary:
	var name := "IntentAlign ADD büyüme uyumlu"
	var c := AIIntentAlignmentChecker.new()
	var report: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.ADD_TO_EXISTING, "a\nb", "a\nb\nc\nd"
	)
	if not report.is_aligned():
		return _fail(name, "ekleme niyeti + büyüme uyumlu olmalı")
	# Ters: ekleme niyeti + küçülme — uyumsuz
	var shrink: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.ADD_TO_EXISTING, "a\nb\nc\nd", "a"
	)
	if shrink.is_aligned():
		return _fail(name, "ekleme niyeti + küçülme uyumlu olmamalı")
	return _ok(name)


static func _test_align_modify() -> Dictionary:
	var name := "IntentAlign MODIFY ölçülü değişim"
	var c := AIIntentAlignmentChecker.new()
	# Ölçülü değişim — uyumlu
	var ok_report: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION,
		"a\nb\nc", "a\nX\nc"
	)
	if not ok_report.is_aligned():
		return _fail(name, "ölçülü değişiklik uyumlu olmalı")
	# Aşırı büyüme — şüpheli
	var big: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION,
		"a\nb", "a\nb\nc\nd\ne\nf\ng\nh"
	)
	if big.is_aligned():
		return _fail(name, "aşırı büyüme şüpheli olmalı")
	return _ok(name)


static func _test_align_rename() -> Dictionary:
	var name := "IntentAlign RENAME boyut korunur"
	var c := AIIntentAlignmentChecker.new()
	# Sadece ad değişti, boyut aynı — uyumlu
	var ok_report: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.RENAME_SYMBOL, "var hp = 1", "var health = 1"
	)
	if not ok_report.is_aligned():
		return _fail(name, "ad değişimi + sabit boyut uyumlu olmalı")
	# Satır eklendi — şüpheli (rename satır eklememeli)
	var grew: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.RENAME_SYMBOL,
		"var hp = 1", "var health = 1\nx\ny\nz\nw"
	)
	if grew.is_aligned():
		return _fail(name, "rename + satır ekleme şüpheli olmalı")
	return _ok(name)


static func _test_align_no_change() -> Dictionary:
	var name := "IntentAlign değişiklik yok — misaligned"
	var c := AIIntentAlignmentChecker.new()
	# Değiştirme niyeti ama hiç değişiklik yok
	var report: AIIntentAlignmentChecker.AlignmentReport = c.check(
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION,
		"aynı kod", "aynı kod"
	)
	if report.is_aligned():
		return _fail(name, "değişiklik yokken uyumlu olmamalı")
	return _ok(name)
