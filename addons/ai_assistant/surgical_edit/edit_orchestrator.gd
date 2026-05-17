@tool
class_name AIEditOrchestrator
extends RefCounted

## EditOrchestrator — düzenleme orkestratörü (Surgical Edit middleware).
##
## Surgical Edit'in tek giriş noktası. Master plan: "her code-generating
## cell role'ün çağrısının üstüne middleware olarak girer".
##
## Bir kod düzenleme isteği geldiğinde tam akış:
##   1. IntentClassifier  — bu ne tür bir düzenleme?
##   2. ScopeExtractor    — LLM'e tüm dosya yerine sadece ilgili kısım
##   3. (LLM çağrısı)     — Layer 7 Router; SEARCH/REPLACE formatı zorlanır
##   4. SearchReplaceHandler — LLM çıktısını ayrıştır + uygula
##   5. FormatDriftDetector  — format bozulmuş mu doğrula
##   6. Sonuç: kabul / ret + retry
##
## Bu sınıf 3. adımı (asıl LLM çağrısı) DOĞRUDAN yapmaz — onu çağırana
## bırakır (Pilot Cell'ler yapacak). Orchestrator hazırlık + işleme +
## doğrulama yapar; LLM çağrısı arada bir "callback" gibi düşünülür.
##
## Mock policy: protokol/doğrulama ihlali sahte başarıya dönüşmez — ret.

## Bir düzenleme oturumunun azami deneme sayısı.
const MAX_ATTEMPTS: int = 3


## Bir düzenleme hazırlığının sonucu — LLM'e gönderilmeye hazır.
class EditPreparation extends RefCounted:
	var ok: bool = false
	var intent_type: int = 0
	var intent_name: String = ""
	var needs_hitl: bool = false       ## Tehlikeli intent — HITL şart
	var scope_content: String = ""     ## LLM'e verilecek kapsam (tüm dosya değil)
	var scope_is_full_file: bool = false
	var protocol_instructions: String = ""
	var error: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"intent_name": intent_name,
			"needs_hitl": needs_hitl,
			"scope_is_full_file": scope_is_full_file,
			"error": error,
		}


## Bir düzenleme uygulamasının sonucu.
class EditOutcome extends RefCounted:
	var ok: bool = false
	var new_content: String = ""
	var attempts_used: int = 0
	var rejected: bool = false
	var rejection_reason: String = ""
	var drift_severity: String = "none"
	var drift_findings: Array = []

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"attempts_used": attempts_used,
			"rejected": rejected,
			"rejection_reason": rejection_reason,
			"drift_severity": drift_severity,
		}


## Bileşenler.
var _classifier: AIIntentClassifier
var _scope: AIScopeExtractor
var _protocol: AISearchReplaceHandler
var _drift: AIFormatDriftDetector


func _init() -> void:
	_classifier = AIIntentClassifier.new()
	_scope = AIScopeExtractor.new()
	_protocol = AISearchReplaceHandler.new()
	_drift = AIFormatDriftDetector.new()


# ============================================================
# ADIM 1-2: HAZIRLIK — LLM'e gitmeden önce
# ============================================================

## Bir düzenleme isteğini LLM'e gönderilmeye hazırlar.
## task_text: ne yapılacak. source: hedef dosya içeriği.
## target_symbol: düzenlenecek fonksiyon/sınıf (varsa).
## target_line: belirli satır (bug-fix tipi, varsa -1).
##
## Dönen: EditPreparation — LLM'e verilecek minimal kapsam + protokol.
func prepare(
	task_text: String, source: String,
	target_symbol: String = "", target_line: int = -1
) -> EditPreparation:
	var prep := EditPreparation.new()

	# --- Adım 1: Intent sınıflandır ---
	var has_line: bool = target_line > 0
	var intent: AIIntentClassifier.IntentResult = _classifier.classify(
		task_text, has_line
	)
	prep.intent_type = intent.intent_type
	prep.intent_name = AIIntentClassifier.intent_name(intent.intent_type)

	# Tehlikeli intent (REPLACE_FILE) — HITL şart
	if AIIntentClassifier.is_dangerous(intent.intent_type):
		prep.needs_hitl = true

	# Yeni dosya — kapsam çıkarmaya gerek yok
	if AIIntentClassifier.creates_new_file(intent.intent_type):
		prep.ok = true
		prep.scope_content = ""
		prep.protocol_instructions = (
			"Yeni dosya oluşturuluyor — tam içeriği üret."
		)
		return prep

	# --- Adım 2: Kapsam çıkar — TÜM DOSYA DEĞİL ---
	var window: AIScopeExtractor.ScopeWindow
	if has_line:
		window = _scope.extract_line_scope(source, target_line)
	elif not target_symbol.is_empty():
		window = _scope.extract_function_scope(source, target_symbol)
	else:
		# Hedef belirsiz — sınıflandırma yeterli değil
		prep.ok = false
		prep.error = (
			"Düzenleme hedefi belirsiz — fonksiyon adı veya satır gerekli"
		)
		return prep

	if not window.found:
		prep.ok = false
		prep.error = "Kapsam çıkarılamadı: " + window.reason
		return prep

	prep.ok = true
	prep.scope_content = window.content
	prep.scope_is_full_file = window.is_full_file
	prep.protocol_instructions = AISearchReplaceHandler.protocol_instructions()
	return prep


# ============================================================
# ADIM 4-5: İŞLEME — LLM çıktısı geldikten sonra
# ============================================================

## LLM'in ürettiği SEARCH/REPLACE çıktısını işler ve doğrular.
## source: orijinal tam dosya. llm_output: LLM'in ürettiği düzenleme.
## attempt_number: kaçıncı deneme (1-3).
##
## Dönen: EditOutcome — kabul/ret + doğrulama.
func process_edit(
	source: String, llm_output: String, attempt_number: int = 1
) -> EditOutcome:
	var outcome := EditOutcome.new()
	outcome.attempts_used = attempt_number

	# --- Adım 4: Protokolü ayrıştır + uygula ---
	var apply: AISearchReplaceHandler.ApplyResult = _protocol.process(
		source, llm_output
	)
	if not apply.ok:
		outcome.ok = false
		outcome.rejected = true
		outcome.rejection_reason = (
			apply.rejected_reason if not apply.rejected_reason.is_empty()
			else apply.error
		)
		return outcome

	# --- Adım 5: Format kayması doğrula ---
	var drift: AIFormatDriftDetector.DriftReport = _drift.detect(
		source, apply.new_content
	)
	outcome.drift_severity = drift.max_severity()
	outcome.drift_findings = drift.findings

	# Girinti kayması gibi ERROR seviyesi kayma -> ret
	if drift.max_severity() == "error":
		outcome.ok = false
		outcome.rejected = true
		outcome.rejection_reason = (
			"Format kayması (error): düzenleme dosya stilini bozdu"
		)
		return outcome

	# WARNING seviyesi kayma -> kabul ama işaretli
	outcome.ok = true
	outcome.new_content = apply.new_content
	return outcome


## Bir reddedilen denemeden sonra LLM'e verilecek geri bildirimi üretir.
## Retry akışında kullanılır — LLM neyi yanlış yaptığını öğrenir.
func build_retry_feedback(outcome: EditOutcome) -> String:
	if not outcome.rejected:
		return ""
	var feedback: String = "Önceki düzenleme reddedildi: "
	feedback += outcome.rejection_reason
	feedback += "\nLütfen düzelt: SEARCH metni dosyada birebir ve benzersiz "
	feedback += "olmalı, dosya stilini (tab girinti, yorumlar) koru."
	return feedback


# ============================================================
# DURUM
# ============================================================

## Maksimum deneme sayısına ulaşıldı mı?
func is_attempts_exhausted(attempt_number: int) -> bool:
	return attempt_number >= MAX_ATTEMPTS


## Orchestrator durum özeti.
func status() -> Dictionary:
	return {
		"max_attempts": MAX_ATTEMPTS,
		"components": ["intent_classifier", "scope_extractor",
			"search_replace_handler", "format_drift_detector"],
		"protocols_available": ["search_replace"],
	}
