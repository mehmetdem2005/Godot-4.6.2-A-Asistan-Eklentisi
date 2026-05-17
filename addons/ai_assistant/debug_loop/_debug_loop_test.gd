@tool
class_name AIDebugLoopTest
extends RefCounted

## Madde 02 — Debug Loop Çekirdek Self-Test
##
## Sıkı testler: core (ErrorClassifier, Godot4APIMapper, AutoloadGuard,
## SandboxResult), intelligence (RootCauseAnalyzer, FixPlanner),
## orchestration (RetryOrchestrator, EscalationManager,
## DebugLoopSession).
##
## NOT classifier: Godot iki tür tırnak kullanır — "dup" (çift) ve
## 'instance' (tek). Testler ikisini de kapsar.


static func run_all() -> Array:
	var results: Array = []

	# ErrorClassifier
	results.append(_b("Debug: Classifier", _test_classify_parse()))
	results.append(_b("Debug: Classifier", _test_classify_api()))
	results.append(_b("Debug: Classifier", _test_classify_quote_styles()))
	results.append(_b("Debug: Classifier", _test_classify_unknown()))

	# Godot4APIMapper
	results.append(_b("Debug: APIMapper", _test_mapper_method()))
	results.append(_b("Debug: APIMapper", _test_mapper_class()))
	results.append(_b("Debug: APIMapper", _test_mapper_unknown()))

	# AutoloadGuard
	results.append(_b("Debug: Guard", _test_guard_protect()))
	results.append(_b("Debug: Guard", _test_guard_read_allowed()))

	# SandboxResult
	results.append(_b("Debug: Sandbox", _test_sandbox_success()))
	results.append(_b("Debug: Sandbox", _test_sandbox_failure()))

	# RootCauseAnalyzer
	results.append(_b("Debug: RootCause", _test_root_api()))
	results.append(_b("Debug: RootCause", _test_root_unknown()))

	# FixPlanner
	results.append(_b("Debug: FixPlan", _test_fixplan_api()))
	results.append(_b("Debug: FixPlan", _test_fixplan_needs_llm()))

	# RetryOrchestrator
	results.append(_b("Debug: Retry", _test_retry_fixed()))
	results.append(_b("Debug: Retry", _test_retry_max()))
	results.append(_b("Debug: Retry", _test_retry_circuit()))

	# EscalationManager
	results.append(_b("Debug: Escalation", _test_escalation_report()))

	# DebugLoopSession — entegrasyon
	results.append(_b("Debug: Session", _test_session_done()))
	results.append(_b("Debug: Session", _test_session_apply_fix()))
	results.append(_b("Debug: Session", _test_session_needs_llm()))
	results.append(_b("Debug: Session", _test_session_escalate()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# ERROR CLASSIFIER
# ============================================================

static func _test_classify_parse() -> Dictionary:
	var name := "Classifier parse hatası"
	var c := AIDebugErrorClassifier.new()
	var result: AIDebugErrorClassifier.ErrorClass = c.classify(
		"res://x.gd:42 - Parse Error: beklenmeyen token"
	)
	if result.category != AIDebugErrorClassifier.ErrorCategory \
			.PARSE_ERROR:
		return _fail(name, "parse hatası PARSE_ERROR olmalı")
	if result.line != 42:
		return _fail(name, "satır numarası 42 çıkarılmalı")
	return _ok(name)


static func _test_classify_api() -> Dictionary:
	var name := "Classifier API hatası"
	var c := AIDebugErrorClassifier.new()
	var result: AIDebugErrorClassifier.ErrorClass = c.classify(
		"Invalid call to nonexistent function 'instance'"
	)
	if result.category != AIDebugErrorClassifier.ErrorCategory.API_ERROR:
		return _fail(name, "API hatası API_ERROR olmalı")
	return _ok(name)


static func _test_classify_quote_styles() -> Dictionary:
	var name := "Classifier iki tırnak stili"
	var c := AIDebugErrorClassifier.new()
	# Tek tırnak — Godot bazen böyle yazar
	var single: AIDebugErrorClassifier.ErrorClass = c.classify(
		"nonexistent function 'instance'"
	)
	if single.symbol != "instance":
		return _fail(name, "tek tırnaklı sembol çıkarılmalı: 'instance'")
	# Çift tırnak
	var double: AIDebugErrorClassifier.ErrorClass = c.classify(
		"Parse Error: Function \"dup\" has the same name"
	)
	if double.symbol != "dup":
		return _fail(name, "çift tırnaklı sembol çıkarılmalı: \"dup\"")
	return _ok(name)


static func _test_classify_unknown() -> Dictionary:
	var name := "Classifier eşleşmeyen -> LLM"
	var c := AIDebugErrorClassifier.new()
	var result: AIDebugErrorClassifier.ErrorClass = c.classify(
		"tamamen tanınmayan bir mesaj"
	)
	if result.category != AIDebugErrorClassifier.ErrorCategory.UNKNOWN:
		return _fail(name, "eşleşmeyen hata UNKNOWN olmalı")
	if not result.needs_llm:
		return _fail(name, "UNKNOWN hata LLM gerektirmeli")
	return _ok(name)


# ============================================================
# GODOT 4 API MAPPER
# ============================================================

static func _test_mapper_method() -> Dictionary:
	var name := "APIMapper metod eşlemesi"
	var m := AIDebugGodot4APIMapper.new()
	if not m.has_method_mapping("instance"):
		return _fail(name, "'instance' bilinen bir 3→4 değişimi olmalı")
	var mapping: Dictionary = m.map_method("instance")
	if str(mapping["new_name"]) != "instantiate":
		return _fail(name, "instance -> instantiate eşlenmeli")
	return _ok(name)


static func _test_mapper_class() -> Dictionary:
	var name := "APIMapper sınıf eşlemesi"
	var m := AIDebugGodot4APIMapper.new()
	var mapping: Dictionary = m.map_class("KinematicBody2D")
	if not bool(mapping["found"]):
		return _fail(name, "KinematicBody2D bilinen değişim olmalı")
	if str(mapping["new_name"]) != "CharacterBody2D":
		return _fail(name, "KinematicBody2D -> CharacterBody2D")
	return _ok(name)


static func _test_mapper_unknown() -> Dictionary:
	var name := "APIMapper bilinmeyen sembol"
	var m := AIDebugGodot4APIMapper.new()
	var fix: Dictionary = m.suggest_fix("MyCustomThing")
	if bool(fix["fixable"]):
		return _fail(name, "bilinmeyen sembol düzeltilebilir olmamalı")
	return _ok(name)


# ============================================================
# AUTOLOAD GUARD
# ============================================================

static func _test_guard_protect() -> Dictionary:
	var name := "Guard korumalı yazma engeli"
	var g := AIDebugAutoloadGuard.new()
	g.protect("GameState")
	# Korumalıya yazma engellenmeli
	if g.can_write("GameState"):
		return _fail(name, "korumalı autoload'a yazma engellenmeli")
	# Korumasıza yazma serbest
	if not g.can_write("TempData"):
		return _fail(name, "korumasız autoload'a yazma serbest olmalı")
	return _ok(name)


static func _test_guard_read_allowed() -> Dictionary:
	var name := "Guard okuma serbest"
	var g := AIDebugAutoloadGuard.new()
	g.protect("GameState")
	# Korumalı bile olsa okuma serbest
	var read: Dictionary = g.check_access(
		"GameState", AIDebugAutoloadGuard.AccessKind.READ
	)
	if not bool(read["allowed"]):
		return _fail(name, "korumalı autoload okuması serbest olmalı")
	return _ok(name)


# ============================================================
# SANDBOX RESULT
# ============================================================

static func _test_sandbox_success() -> Dictionary:
	var name := "Sandbox başarılı sonuç"
	var result := AIDebugSandboxResult.make_success(120)
	if not result.is_success():
		return _fail(name, "hatasız sonuç başarılı olmalı")
	if result.is_failure():
		return _fail(name, "başarılı sonuç failure olmamalı")
	return _ok(name)


static func _test_sandbox_failure() -> Dictionary:
	var name := "Sandbox başarısız sonuç"
	var result := AIDebugSandboxResult.make_parse_failure(
		"Parse Error: satır 5"
	)
	if result.is_success():
		return _fail(name, "parse hatalı sonuç başarılı olmamalı")
	if not result.failed_at_parse():
		return _fail(name, "parse aşamasında başarısız işaretlenmeli")
	if result.primary_error().is_empty():
		return _fail(name, "birincil hata dönmeli")
	return _ok(name)


# ============================================================
# ROOT CAUSE ANALYZER
# ============================================================

static func _test_root_api() -> Dictionary:
	var name := "RootCause API hatası deterministik"
	var classifier := AIDebugErrorClassifier.new()
	var analyzer := AIDebugRootCauseAnalyzer.new()
	var error_class: AIDebugErrorClassifier.ErrorClass = \
		classifier.classify("Invalid call to nonexistent function 'instance'")
	var root: AIDebugRootCauseAnalyzer.RootCause = analyzer.analyze(
		error_class
	)
	# Bilinen API — deterministik, yüksek güven
	if not root.deterministic:
		return _fail(name, "bilinen API hatası deterministik olmalı")
	if root.confidence != AIDebugRootCauseAnalyzer.Confidence.HIGH:
		return _fail(name, "bilinen API hatası HIGH güven olmalı")
	return _ok(name)


static func _test_root_unknown() -> Dictionary:
	var name := "RootCause bilinmeyen -> LLM"
	var classifier := AIDebugErrorClassifier.new()
	var analyzer := AIDebugRootCauseAnalyzer.new()
	var error_class: AIDebugErrorClassifier.ErrorClass = \
		classifier.classify("tanınmayan garip hata")
	var root: AIDebugRootCauseAnalyzer.RootCause = analyzer.analyze(
		error_class
	)
	if root.is_actionable():
		return _fail(name, "bilinmeyen hata deterministik olmamalı")
	return _ok(name)


# ============================================================
# FIX PLANNER
# ============================================================

static func _test_fixplan_api() -> Dictionary:
	var name := "FixPlan API surgical replace"
	var classifier := AIDebugErrorClassifier.new()
	var analyzer := AIDebugRootCauseAnalyzer.new()
	var planner := AIDebugFixPlanner.new()
	var error_class: AIDebugErrorClassifier.ErrorClass = \
		classifier.classify("Invalid call to nonexistent function 'instance'")
	var root: AIDebugRootCauseAnalyzer.RootCause = analyzer.analyze(
		error_class
	)
	var plan: AIDebugFixPlanner.FixPlan = planner.plan_fix(
		root, error_class
	)
	if plan.strategy != AIDebugFixPlanner.FixStrategy.SURGICAL_REPLACE:
		return _fail(name, "bilinen API hatası surgical replace olmalı")
	if not plan.deterministic:
		return _fail(name, "API düzeltmesi deterministik olmalı")
	return _ok(name)


static func _test_fixplan_needs_llm() -> Dictionary:
	var name := "FixPlan null hatası -> LLM"
	var classifier := AIDebugErrorClassifier.new()
	var analyzer := AIDebugRootCauseAnalyzer.new()
	var planner := AIDebugFixPlanner.new()
	var error_class: AIDebugErrorClassifier.ErrorClass = \
		classifier.classify("call function on a null instance")
	var root: AIDebugRootCauseAnalyzer.RootCause = analyzer.analyze(
		error_class
	)
	var plan: AIDebugFixPlanner.FixPlan = planner.plan_fix(
		root, error_class
	)
	# Null hatası düzeltme için LLM ister
	if plan.strategy != AIDebugFixPlanner.FixStrategy.NEEDS_LLM:
		return _fail(name, "null hatası düzeltmesi LLM gerektirmeli")
	return _ok(name)


# ============================================================
# RETRY ORCHESTRATOR
# ============================================================

static func _test_retry_fixed() -> Dictionary:
	var name := "Retry hata yok -> fixed"
	var r := AIDebugRetryOrchestrator.new()
	# Boş imza = hata yok = düzeltildi
	var attempt: Dictionary = r.report_attempt("")
	if bool(attempt["should_retry"]):
		return _fail(name, "hata yokken tekrar denenmemeli")
	return _ok(name)


static func _test_retry_max() -> Dictionary:
	var name := "Retry max deneme sınırı"
	var r := AIDebugRetryOrchestrator.new()
	# Üç farklı hata — üçüncüde max retry
	r.report_attempt("hataA")
	r.report_attempt("hataB")
	var third: Dictionary = r.report_attempt("hataC")
	if bool(third["should_retry"]):
		return _fail(name, "3. denemede tekrar durmalı")
	return _ok(name)


static func _test_retry_circuit() -> Dictionary:
	var name := "Retry circuit breaker"
	var r := AIDebugRetryOrchestrator.new()
	# Aynı hata iki kez — circuit breaker
	r.report_attempt("ayniHata")
	var second: Dictionary = r.report_attempt("ayniHata")
	if bool(second["should_retry"]):
		return _fail(name, "aynı hata tekrarında devre açılmalı")
	if not r.is_circuit_open():
		return _fail(name, "circuit OPEN olmalı")
	return _ok(name)


# ============================================================
# ESCALATION MANAGER
# ============================================================

static func _test_escalation_report() -> Dictionary:
	var name := "Escalation rapor üretimi"
	var e := AIDebugEscalationManager.new()
	var report: AIDebugEscalationManager.EscalationReport = e.escalate(
		AIDebugEscalationManager.EscalationReason.MAX_RETRIES,
		"null instance hatası", 3,
		PackedStringArray(["fix denemesi 1", "fix denemesi 2"])
	)
	if report.attempts_made != 3:
		return _fail(name, "deneme sayısı korunmalı")
	if report.attempted_fixes.size() != 2:
		return _fail(name, "denenen düzeltmeler korunmalı")
	if report.user_message.is_empty():
		return _fail(name, "kullanıcı mesajı üretilmeli")
	return _ok(name)


# ============================================================
# DEBUG LOOP SESSION — entegrasyon
# ============================================================

static func _test_session_done() -> Dictionary:
	var name := "Session başarılı çalışma -> done"
	var session := AIDebugLoopSession.new()
	var run := AIDebugSandboxResult.make_success(100)
	var decision: AIDebugLoopSession.TurnDecision = session.process_run(run)
	if decision.action != AIDebugLoopSession.SessionAction.DONE:
		return _fail(name, "başarılı çalışma DONE olmalı")
	return _ok(name)


static func _test_session_apply_fix() -> Dictionary:
	var name := "Session bilinen API hatası -> apply_fix"
	var session := AIDebugLoopSession.new()
	# Bilinen API hatası — deterministik düzeltilebilir
	var run := AIDebugSandboxResult.make_parse_failure(
		"Invalid call to nonexistent function 'instance'"
	)
	# make_parse_failure status'u PARSE_FAILED yapıyor — ama içerik
	# API hatası; classifier metne bakar, doğru kategoriyi bulur
	var decision: AIDebugLoopSession.TurnDecision = session.process_run(run)
	if decision.action != AIDebugLoopSession.SessionAction.APPLY_FIX:
		return _fail(name, "bilinen API hatası apply_fix olmalı, ge: " \
			+ decision.action_name())
	return _ok(name)


static func _test_session_needs_llm() -> Dictionary:
	var name := "Session null hatası -> needs_llm"
	var session := AIDebugLoopSession.new()
	var run := AIDebugSandboxResult.new()
	run.set_status(AIDebugSandboxResult.RunStatus.RUNTIME_FAILED)
	run.add_error("call function on a null instance")
	var decision: AIDebugLoopSession.TurnDecision = session.process_run(run)
	if decision.action != AIDebugLoopSession.SessionAction.NEEDS_LLM:
		return _fail(name, "null hatası needs_llm olmalı")
	return _ok(name)


static func _test_session_escalate() -> Dictionary:
	var name := "Session circuit breaker -> escalate"
	var session := AIDebugLoopSession.new()
	# Aynı API hatasını iki kez işle — ikincide circuit breaker
	var run1 := AIDebugSandboxResult.new()
	run1.set_status(AIDebugSandboxResult.RunStatus.RUNTIME_FAILED)
	run1.add_error("Invalid call to nonexistent function 'instance'")
	session.process_run(run1)
	# Aynı hata tekrar
	var run2 := AIDebugSandboxResult.new()
	run2.set_status(AIDebugSandboxResult.RunStatus.RUNTIME_FAILED)
	run2.add_error("Invalid call to nonexistent function 'instance'")
	var decision: AIDebugLoopSession.TurnDecision = session.process_run(run2)
	if decision.action != AIDebugLoopSession.SessionAction.ESCALATE:
		return _fail(name, "aynı hata tekrarı escalate olmalı, ge: " \
			+ decision.action_name())
	if decision.escalation == null:
		return _fail(name, "escalate kararı escalation raporu içermeli")
	return _ok(name)
