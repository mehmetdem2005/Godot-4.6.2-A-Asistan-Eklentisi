@tool
class_name AIVerificationResult
extends AIContractBase

## VerificationResult — doğrulayıcı (Verifier) sonucu (Layer 5).
##
## Verifier 5 seviyede çalışır:
##   L1 Syntactic  — sözdizimi doğru mu (parse)
##   L2 Semantic   — anlamsal tutarlı mı (read-only inceleme)
##   L3 Runtime    — çalışıyor mu (sandbox)
##   L4 Behavioral — beklendiği gibi davranıyor mu
##   L5 Performance — mobil bütçeye uyuyor mu
##
## Evidence-based: hiçbir "başarılı" sonuç KANIT olmadan kabul edilmez.

## Doğrulama seviyeleri.
enum VerifyLevel {
	SYNTACTIC,    ## L1 — sözdizimi
	SEMANTIC,     ## L2 — anlamsal
	RUNTIME,      ## L3 — çalışma zamanı
	BEHAVIORAL,   ## L4 — davranışsal
	PERFORMANCE,  ## L5 — performans
}

const LEVEL_NAMES: Dictionary = {
	VerifyLevel.SYNTACTIC: "syntactic",
	VerifyLevel.SEMANTIC: "semantic",
	VerifyLevel.RUNTIME: "runtime",
	VerifyLevel.BEHAVIORAL: "behavioral",
	VerifyLevel.PERFORMANCE: "performance",
}

## Doğrulama sonucu durumu.
enum Outcome {
	PASS,     ## Geçti
	FAIL,     ## Başarısız
	SKIP,     ## Atlandı (bu seviye uygulanamadı)
	WARNING,  ## Geçti ama dikkat gerektiren noktalar var
}

const OUTCOME_NAMES: Dictionary = {
	Outcome.PASS: "pass",
	Outcome.FAIL: "fail",
	Outcome.SKIP: "skip",
	Outcome.WARNING: "warning",
}

# --- Kimlik ---
var id: String = ""
var task_ref: String = ""            ## Hangi task doğrulandı
var level: int = VerifyLevel.SYNTACTIC

# --- Sonuç ---
var outcome: int = Outcome.SKIP
var message: String = ""             ## İnsan-okunabilir sonuç açıklaması

# --- Kanıt (evidence-based zorunlu) ---
var evidence: Dictionary = {}        ## Sonucu destekleyen kanıt (hash, log, çıktı)
var evidence_type: String = ""       ## "ast_parse" | "test_log" | "diff" | "metrics"

# --- Detaylar ---
var errors: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()

# --- Zaman ---
var verified_at: String = ""
var duration_ms: int = 0             ## Doğrulama ne kadar sürdü


func contract_type() -> String:
	return "VerificationResult"


## Yeni bir doğrulama sonucu oluşturur (factory).
static func create(p_level: int, p_task_ref: String) -> AIVerificationResult:
	var v := AIVerificationResult.new()
	v.id = AIContractBase.generate_id("verify")
	v.level = p_level
	v.task_ref = p_task_ref
	v.verified_at = AIContractBase.now_iso()
	return v


## Seviyenin string adı.
func level_name() -> String:
	return LEVEL_NAMES.get(level, "syntactic")


## Sonucun string adı.
func outcome_name() -> String:
	return OUTCOME_NAMES.get(outcome, "skip")


## Sonucu PASS olarak işaretler — kanıt zorunludur.
## evidence boşsa otomatik WARNING'e düşer (mock policy: kanıtsız başarı yok).
func mark_pass(p_evidence: Dictionary, p_evidence_type: String) -> void:
	evidence = p_evidence
	evidence_type = p_evidence_type
	if p_evidence.is_empty():
		outcome = Outcome.WARNING
		warnings.append("PASS işaretlendi ama kanıt yok — WARNING'e düşürüldü")
	else:
		outcome = Outcome.PASS


## Sonucu FAIL olarak işaretler.
func mark_fail(p_message: String, p_errors: PackedStringArray = PackedStringArray()) -> void:
	outcome = Outcome.FAIL
	message = p_message
	for e in p_errors:
		errors.append(e)


## Bu sonuç başarılı sayılır mı (PASS veya WARNING)?
func is_acceptable() -> bool:
	return outcome == Outcome.PASS or outcome == Outcome.WARNING


## Bu sonuç kanıta dayanıyor mu?
func has_evidence() -> bool:
	return not evidence.is_empty()


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"task_ref": task_ref,
		"level": LEVEL_NAMES.get(level, "syntactic"),
		"outcome": OUTCOME_NAMES.get(outcome, "skip"),
		"message": message,
		"evidence": evidence,
		"evidence_type": evidence_type,
		"errors": errors,
		"warnings": warnings,
		"verified_at": verified_at,
		"duration_ms": duration_ms,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	task_ref = data.get("task_ref", "")
	level = _parse_level(data.get("level", "syntactic"))
	outcome = _parse_outcome(data.get("outcome", "skip"))
	message = data.get("message", "")
	evidence = data.get("evidence", {})
	evidence_type = data.get("evidence_type", "")
	errors = PackedStringArray(data.get("errors", []))
	warnings = PackedStringArray(data.get("warnings", []))
	verified_at = data.get("verified_at", "")
	duration_ms = int(data.get("duration_ms", 0))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, task_ref, "task_ref")
	# Evidence-based kuralı: PASS ama kanıt yok = ihlal
	if outcome == Outcome.PASS and evidence.is_empty():
		result.add_error(
			"PASS sonucu kanıt içermiyor — evidence-based kuralı ihlali"
		)
	# FAIL ama hata mesajı yok
	if outcome == Outcome.FAIL and message.is_empty() and errors.is_empty():
		result.add_warning("FAIL sonucu açıklama içermiyor")
	if duration_ms < 0:
		result.add_error("duration_ms negatif olamaz")


static func _parse_level(s: String) -> int:
	for key in LEVEL_NAMES:
		if LEVEL_NAMES[key] == s:
			return key
	return VerifyLevel.SYNTACTIC


static func _parse_outcome(s: String) -> int:
	for key in OUTCOME_NAMES:
		if OUTCOME_NAMES[key] == s:
			return key
	return Outcome.SKIP
