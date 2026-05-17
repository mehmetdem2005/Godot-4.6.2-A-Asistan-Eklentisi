@tool
class_name AIDebugLoopSession
extends RefCounted

## DebugLoopSession — debug oturumu (Madde 02 / Debug Loop ana API).
##
## Debug Loop'un tek giriş noktası. Devin'in imza döngüsünü yönetir:
##
##   çalıştır -> hata yakala -> sınıflandır -> kök neden -> düzeltme
##   planla -> uygula -> TEKRAR çalıştır ... ta ki düzelene ya da
##   yükseltme gerekene kadar.
##
## Alt parçaları birleştirir:
##   error_classifier   — hatayı kategorize et
##   root_cause_analyzer — neden olduğunu bul
##   fix_planner        — ne yapılacağını planla
##   retry_orchestrator — kaç kez denenecek + circuit breaker
##   escalation_manager — pes etme noktasında insana devret
##
## Bu sınıf bir sandbox çalıştırma SONUCUNU alır ve o turda ne
## yapılacağına karar verir. Gerçek sandbox çalıştırma + düzeltme
## uygulama dış katmanların (sandbox_runner, Surgical Edit) işi —
## bu sınıf KARAR VERİCİDİR, test edilebilir.
##
## Mock policy: her karar gerçek hata + gerçek deneme geçmişinden.

## Oturumun bir turdaki kararı.
enum SessionAction { APPLY_FIX, NEEDS_LLM, ESCALATE, DONE }

const ACTION_NAMES: Dictionary = {
	SessionAction.APPLY_FIX: "apply_fix",
	SessionAction.NEEDS_LLM: "needs_llm",
	SessionAction.ESCALATE: "escalate",
	SessionAction.DONE: "done",
}


## Bir turun karar sonucu.
class TurnDecision extends RefCounted:
	var action: int = AIDebugLoopSession.SessionAction.DONE
	var fix_plan: AIDebugFixPlanner.FixPlan = null
	var escalation: AIDebugEscalationManager.EscalationReport = null
	var message: String = ""

	func action_name() -> String:
		return AIDebugLoopSession.ACTION_NAMES.get(action, "?")

	func to_dict() -> Dictionary:
		return {"action": action_name(), "message": message}


## Alt bileşenler.
var _classifier: AIDebugErrorClassifier
var _analyzer: AIDebugRootCauseAnalyzer
var _planner: AIDebugFixPlanner
var _retry: AIDebugRetryOrchestrator
var _escalation: AIDebugEscalationManager

## Oturum başında yakalanan ilk hata — escalation raporu için.
var _original_error: String = ""

## Denenen düzeltmelerin kaydı.
var _attempted_fixes: PackedStringArray = PackedStringArray()


func _init() -> void:
	var api_mapper := AIDebugGodot4APIMapper.new()
	_classifier = AIDebugErrorClassifier.new()
	_analyzer = AIDebugRootCauseAnalyzer.new(api_mapper)
	_planner = AIDebugFixPlanner.new(api_mapper)
	_retry = AIDebugRetryOrchestrator.new()
	_escalation = AIDebugEscalationManager.new()


# ============================================================
# DEBUG DÖNGÜSÜ — ana karar
# ============================================================

## Bir sandbox çalıştırma sonucunu işler ve sıradaki adıma karar verir.
## run_result: SandboxRunResult.
## Dönen: TurnDecision.
func process_run(
	run_result: AIDebugSandboxResult
) -> TurnDecision:
	var decision := TurnDecision.new()

	# --- Çalıştırma başarılı — döngü bitti ---
	if run_result.is_success():
		decision.action = SessionAction.DONE
		decision.message = "Kod başarıyla çalıştı — debug döngüsü tamam"
		return decision

	# --- Hata var — ilk hatayı kaydet ---
	var error_text: String = run_result.primary_error()
	if _original_error.is_empty():
		_original_error = error_text

	# --- Hatayı sınıflandır ---
	var error_class: AIDebugErrorClassifier.ErrorClass = \
		_classifier.classify(error_text)

	# --- Kök neden analizi ---
	var root_cause: AIDebugRootCauseAnalyzer.RootCause = \
		_analyzer.analyze(error_class)

	# --- Kök neden bulunamadı — LLM gerekli ---
	if not root_cause.is_actionable():
		decision.action = SessionAction.NEEDS_LLM
		decision.message = "Kök neden otomatik bulunamadı — LLM gerekli"
		return decision

	# --- Düzeltme planla ---
	var fix_plan: AIDebugFixPlanner.FixPlan = _planner.plan_fix(
		root_cause, error_class
	)

	# --- Plan LLM gerektiriyor ---
	if fix_plan.strategy == AIDebugFixPlanner.FixStrategy.NEEDS_LLM:
		decision.action = SessionAction.NEEDS_LLM
		decision.message = "Düzeltme için LLM gerekli: " \
			+ fix_plan.description
		return decision

	# --- Retry orchestrator'a danış — deneme hakkı var mı ---
	var attempt: Dictionary = _retry.report_attempt(error_text)
	if bool(attempt["should_retry"]):
		# Düzeltme uygulanabilir — kaydet ve uygula kararı ver
		_attempted_fixes.append(fix_plan.description)
		decision.action = SessionAction.APPLY_FIX
		decision.fix_plan = fix_plan
		decision.message = "Düzeltme uygulanacak: " + fix_plan.description
		return decision

	# --- Deneme hakkı bitti / circuit açıldı — yükselt ---
	var reason: int = AIDebugEscalationManager.EscalationReason.MAX_RETRIES
	if _retry.is_circuit_open():
		reason = AIDebugEscalationManager.EscalationReason.CIRCUIT_OPEN
	decision.escalation = _escalation.escalate(
		reason, _original_error, _retry.attempt_count, _attempted_fixes
	)
	decision.action = SessionAction.ESCALATE
	decision.message = "Otomatik düzeltme tükendi — kullanıcıya devredildi"
	return decision


# ============================================================
# OTURUM YÖNETİMİ
# ============================================================

## Yeni bir debug oturumu için durumu sıfırlar.
func reset() -> void:
	_retry.reset()
	_original_error = ""
	_attempted_fixes.clear()


## Bu oturumda kaç deneme yapıldı?
func attempt_count() -> int:
	return _retry.attempt_count


## Debug döngüsü hâlâ devam edebilir mi?
func can_continue() -> bool:
	return _retry.can_retry()


## Alt bileşenlere erişim — test ve detay için.
func retry_orchestrator() -> AIDebugRetryOrchestrator:
	return _retry


## Oturum durum özeti.
func summary() -> Dictionary:
	return {
		"attempts": _retry.attempt_count,
		"can_continue": can_continue(),
		"fixes_attempted": _attempted_fixes.size(),
		"retry": _retry.summary(),
	}
