@tool
class_name AISurgicalEditTest
extends RefCounted

## Phase 10 / Surgical Edit — Self-Test
##
## Sıkı testler: IntentClassifier (9 intent sınıflandırma), ScopeExtractor
## (kapsam penceresi), SearchReplaceHandler (SEARCH/REPLACE protokolü),
## FormatDriftDetector (format kayması), EditOrchestrator (middleware akışı).
##
## Bu modül full-rewrite önlemenin çekirdeği — testler özellikle
## "tüm dosya verilmedi", "belirsiz eşleşme reddedildi", "format korundu"
## güvencelerini doğrular.


static func run_all() -> Array:
	var results: Array = []

	# IntentClassifier
	results.append(_b("Surgical: Intent", _test_intent_new_file()))
	results.append(_b("Surgical: Intent", _test_intent_delete()))
	results.append(_b("Surgical: Intent", _test_intent_replace_file()))
	results.append(_b("Surgical: Intent", _test_intent_no_match_llm()))
	results.append(_b("Surgical: Intent", _test_intent_empty()))
	results.append(_b("Surgical: Intent", _test_intent_line_hint()))
	results.append(_b("Surgical: Intent", _test_intent_dangerous_flag()))

	# ScopeExtractor
	results.append(_b("Surgical: Scope", _test_scope_function()))
	results.append(_b("Surgical: Scope", _test_scope_not_found()))
	results.append(_b("Surgical: Scope", _test_scope_line()))
	results.append(_b("Surgical: Scope", _test_scope_block_end()))
	results.append(_b("Surgical: Scope", _test_scope_not_full_file()))

	# SearchReplaceHandler
	results.append(_b("Surgical: SR", _test_sr_parse()))
	results.append(_b("Surgical: SR", _test_sr_apply_unique()))
	results.append(_b("Surgical: SR", _test_sr_reject_ambiguous()))
	results.append(_b("Surgical: SR", _test_sr_reject_not_found()))
	results.append(_b("Surgical: SR", _test_sr_unclosed_block()))
	results.append(_b("Surgical: SR", _test_sr_no_blocks()))

	# FormatDriftDetector
	results.append(_b("Surgical: Drift", _test_drift_indent()))
	results.append(_b("Surgical: Drift", _test_drift_comment_loss()))
	results.append(_b("Surgical: Drift", _test_drift_clean()))

	# EditOrchestrator
	results.append(_b("Surgical: Orch", _test_orch_prepare_scope()))
	results.append(_b("Surgical: Orch", _test_orch_process_valid()))
	results.append(_b("Surgical: Orch", _test_orch_process_reject()))
	results.append(_b("Surgical: Orch", _test_orch_new_file()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


## Test için örnek GDScript kaynağı.
static func _sample_source() -> String:
	return (
		"@tool\n"
		+ "extends RefCounted\n"
		+ "# Oyuncu davranışı\n"
		+ "func jump() -> void:\n"
		+ "\tvelocity_y = -10.0\n"
		+ "func move() -> void:\n"
		+ "\tposition_x += 5.0\n"
	)


# ============================================================
# INTENT CLASSIFIER
# ============================================================

static func _test_intent_new_file() -> Dictionary:
	var name := "Intent yeni dosya sınıflandırma"
	var c := AIIntentClassifier.new()
	var r: AIIntentClassifier.IntentResult = c.classify(
		"yeni dosya oluştur enemy.gd"
	)
	if r.intent_type != AIEditIntent.IntentType.ADD_NEW_FILE:
		return _fail(name, "ADD_NEW_FILE bekleniyordu")
	return _ok(name)


static func _test_intent_delete() -> Dictionary:
	var name := "Intent silme sınıflandırma"
	var c := AIIntentClassifier.new()
	var r: AIIntentClassifier.IntentResult = c.classify("şu fonksiyonu sil")
	if r.intent_type != AIEditIntent.IntentType.DELETE_CODE:
		return _fail(name, "DELETE_CODE bekleniyordu")
	return _ok(name)


static func _test_intent_replace_file() -> Dictionary:
	var name := "Intent tam dosya değişimi (spesifik kelime)"
	var c := AIIntentClassifier.new()
	# 'tamamen değiştir' (spesifik) 'değiştir' (genel) bastırmalı
	var r: AIIntentClassifier.IntentResult = c.classify(
		"tamamen değiştir bu dosyayı"
	)
	if r.intent_type != AIEditIntent.IntentType.REPLACE_FILE:
		return _fail(name, "REPLACE_FILE bekleniyordu — spesifik kelime kazanmalı")
	return _ok(name)


static func _test_intent_no_match_llm() -> Dictionary:
	var name := "Intent eşleşme yok -> LLM fallback"
	var c := AIIntentClassifier.new()
	var r: AIIntentClassifier.IntentResult = c.classify("blah rastgele metin")
	if not r.needs_llm:
		return _fail(name, "eşleşme yoksa LLM fallback işaretlenmeli")
	return _ok(name)


static func _test_intent_empty() -> Dictionary:
	var name := "Intent boş metin -> LLM"
	var c := AIIntentClassifier.new()
	var r: AIIntentClassifier.IntentResult = c.classify("")
	if not r.needs_llm:
		return _fail(name, "boş metin LLM gerektirmeli")
	return _ok(name)


static func _test_intent_line_hint() -> Dictionary:
	var name := "Intent satır ipucu bug-fix güçlendirir"
	var c := AIIntentClassifier.new()
	# Satır ipucu ile — FIX_BUG_AT_LINE öne çıkmalı
	var r: AIIntentClassifier.IntentResult = c.classify("şunu çöz", true)
	if r.intent_type != AIEditIntent.IntentType.FIX_BUG_AT_LINE:
		return _fail(name, "satır ipucu FIX_BUG_AT_LINE'a yönlendirmeli")
	return _ok(name)


static func _test_intent_dangerous_flag() -> Dictionary:
	var name := "Intent tehlikeli/proje-geneli bayrakları"
	# REPLACE_FILE tehlikeli olmalı
	if not AIIntentClassifier.is_dangerous(AIEditIntent.IntentType.REPLACE_FILE):
		return _fail(name, "REPLACE_FILE tehlikeli işaretlenmeli")
	# RENAME proje-geneli olmalı
	if not AIIntentClassifier.is_project_wide(
		AIEditIntent.IntentType.RENAME_SYMBOL
	):
		return _fail(name, "RENAME_SYMBOL proje-geneli işaretlenmeli")
	# Normal modify tehlikeli OLMAMALI
	if AIIntentClassifier.is_dangerous(
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION
	):
		return _fail(name, "normal modify tehlikeli olmamalı")
	return _ok(name)


# ============================================================
# SCOPE EXTRACTOR
# ============================================================

static func _test_scope_function() -> Dictionary:
	var name := "Scope fonksiyon kapsamı"
	var s := AIScopeExtractor.new()
	var window: AIScopeExtractor.ScopeWindow = s.extract_function_scope(
		_sample_source(), "jump", 0
	)
	if not window.found:
		return _fail(name, "jump fonksiyonu bulunamadı")
	# İçerik jump'ı içermeli ama move'u değil (context 0)
	if not window.content.contains("velocity_y"):
		return _fail(name, "kapsam jump gövdesini içermeli")
	return _ok(name)


static func _test_scope_not_found() -> Dictionary:
	var name := "Scope olmayan fonksiyon"
	var s := AIScopeExtractor.new()
	var window: AIScopeExtractor.ScopeWindow = s.extract_function_scope(
		_sample_source(), "yokFonksiyon", 0
	)
	if window.found:
		return _fail(name, "olmayan fonksiyon found=true olmamalı")
	return _ok(name)


static func _test_scope_line() -> Dictionary:
	var name := "Scope satır kapsamı"
	var s := AIScopeExtractor.new()
	var window: AIScopeExtractor.ScopeWindow = s.extract_line_scope(
		_sample_source(), 5, 1
	)
	if not window.found:
		return _fail(name, "satır kapsamı bulunamadı")
	if window.target_start_line != 5:
		return _fail(name, "hedef satır 5 olmalı")
	return _ok(name)


static func _test_scope_block_end() -> Dictionary:
	var name := "Scope blok sonu (girinti analizi)"
	var s := AIScopeExtractor.new()
	# jump fonksiyonu satır 4, gövdesi satır 5 — sonraki func 6'da
	var window: AIScopeExtractor.ScopeWindow = s.extract_function_scope(
		_sample_source(), "jump", 0
	)
	# Hedef bitiş satırı move()'dan önce olmalı (satır 5)
	if window.target_end_line >= 6:
		return _fail(name, "jump kapsamı move'a taşmamalı")
	return _ok(name)


static func _test_scope_not_full_file() -> Dictionary:
	var name := "Scope büyük dosyada tüm dosyayı vermez"
	var s := AIScopeExtractor.new()
	# 100 satırlık yapay dosya
	var big_lines: PackedStringArray = PackedStringArray()
	big_lines.append("@tool")
	big_lines.append("extends RefCounted")
	for i in range(50):
		big_lines.append("var dummy_%d: int = %d" % [i, i])
	big_lines.append("func target() -> void:")
	big_lines.append("\tpass")
	for i in range(50):
		big_lines.append("var more_%d: int = %d" % [i, i])
	var big_source: String = "\n".join(big_lines)
	var window: AIScopeExtractor.ScopeWindow = s.extract_function_scope(
		big_source, "target", 5
	)
	if not window.found:
		return _fail(name, "target bulunamadı")
	# Büyük dosyada kapsam tüm dosya OLMAMALI
	if window.is_full_file:
		return _fail(name, "büyük dosyada kapsam tüm dosyayı kapsamamalı")
	return _ok(name)


# ============================================================
# SEARCH/REPLACE HANDLER
# ============================================================

static func _make_sr_output(search: String, replace: String) -> String:
	return (
		AISearchReplaceHandler.SEARCH_MARKER + "\n"
		+ search + "\n"
		+ AISearchReplaceHandler.SEPARATOR + "\n"
		+ replace + "\n"
		+ AISearchReplaceHandler.REPLACE_MARKER
	)


static func _test_sr_parse() -> Dictionary:
	var name := "SR blok ayrıştırma"
	var h := AISearchReplaceHandler.new()
	var output: String = _make_sr_output("eski kod", "yeni kod")
	var parsed: Dictionary = h.parse_blocks(output)
	if not parsed["ok"]:
		return _fail(name, "geçerli blok ayrıştırılamadı: %s" % parsed["error"])
	var blocks: Array = parsed["blocks"]
	if blocks.size() != 1:
		return _fail(name, "1 blok bekleniyordu")
	return _ok(name)


static func _test_sr_apply_unique() -> Dictionary:
	var name := "SR benzersiz eşleşme uygular"
	var h := AISearchReplaceHandler.new()
	var source: String = "func f():\n\treturn 1\n"
	var output: String = _make_sr_output("\treturn 1", "\treturn 42")
	var result: AISearchReplaceHandler.ApplyResult = h.process(source, output)
	if not result.ok:
		return _fail(name, "geçerli düzenleme uygulanamadı")
	if not result.new_content.contains("return 42"):
		return _fail(name, "değişiklik içeriğe yansımadı")
	return _ok(name)


static func _test_sr_reject_ambiguous() -> Dictionary:
	var name := "SR belirsiz eşleşmeyi reddeder"
	var h := AISearchReplaceHandler.new()
	# 'return 1' iki kez geçiyor — belirsiz
	var source: String = "\treturn 1\n\treturn 1\n"
	var output: String = _make_sr_output("\treturn 1", "\treturn 2")
	var result: AISearchReplaceHandler.ApplyResult = h.process(source, output)
	if result.ok:
		return _fail(name, "belirsiz eşleşme uygulanmamalı (sahte başarı)")
	if not result.rejected_reason.contains("belirsiz"):
		return _fail(name, "ret nedeni belirsizliği söylemeli")
	return _ok(name)


static func _test_sr_reject_not_found() -> Dictionary:
	var name := "SR bulunamayan SEARCH'ü reddeder"
	var h := AISearchReplaceHandler.new()
	var source: String = "tamamen farklı içerik"
	var output: String = _make_sr_output("var olmayan metin", "yeni")
	var result: AISearchReplaceHandler.ApplyResult = h.process(source, output)
	if result.ok:
		return _fail(name, "bulunamayan SEARCH uygulanmamalı")
	return _ok(name)


static func _test_sr_unclosed_block() -> Dictionary:
	var name := "SR kapatılmamış blok hatası"
	var h := AISearchReplaceHandler.new()
	# SEPARATOR yok
	var bad: String = AISearchReplaceHandler.SEARCH_MARKER + "\nmetin\n"
	var parsed: Dictionary = h.parse_blocks(bad)
	if parsed["ok"]:
		return _fail(name, "kapatılmamış blok ok=true olmamalı")
	return _ok(name)


static func _test_sr_no_blocks() -> Dictionary:
	var name := "SR blok içermeyen çıktı"
	var h := AISearchReplaceHandler.new()
	var parsed: Dictionary = h.parse_blocks("sadece düz metin, blok yok")
	if parsed["ok"]:
		return _fail(name, "bloksuz çıktı ok=true olmamalı")
	return _ok(name)


# ============================================================
# FORMAT DRIFT DETECTOR
# ============================================================

static func _test_drift_indent() -> Dictionary:
	var name := "Drift girinti stili kayması"
	var d := AIFormatDriftDetector.new()
	# Öncesi tab, sonrası boşluk
	var before: String = "func f():\n\treturn 1"
	var after: String = "func f():\n    return 1"
	var report: AIFormatDriftDetector.DriftReport = d.detect(before, after)
	if not report.has_drift:
		return _fail(name, "tab->boşluk kayması tespit edilmeli")
	if report.max_severity() != "error":
		return _fail(name, "girinti kayması error seviyesi olmalı")
	return _ok(name)


static func _test_drift_comment_loss() -> Dictionary:
	var name := "Drift yorum kaybı"
	var d := AIFormatDriftDetector.new()
	var before: String = "# yorum 1\n# yorum 2\nvar x = 1"
	var after: String = "var x = 1"
	var report: AIFormatDriftDetector.DriftReport = d.detect(before, after)
	if not report.has_drift:
		return _fail(name, "yorum kaybı tespit edilmeli")
	if report.comment_count_before <= report.comment_count_after:
		return _fail(name, "yorum sayısı azalmalıydı")
	return _ok(name)


static func _test_drift_clean() -> Dictionary:
	var name := "Drift temiz düzenleme"
	var d := AIFormatDriftDetector.new()
	# Yorum korundu, tab korundu — sadece değer değişti
	var before: String = "# açıklama\nfunc f():\n\treturn 1"
	var after: String = "# açıklama\nfunc f():\n\treturn 99"
	var report: AIFormatDriftDetector.DriftReport = d.detect(before, after)
	if report.max_severity() == "error":
		return _fail(name, "temiz düzenleme error vermemeli")
	return _ok(name)


# ============================================================
# EDIT ORCHESTRATOR
# ============================================================

static func _test_orch_prepare_scope() -> Dictionary:
	var name := "Orchestrator hazırlık kapsam çıkarır"
	var orch := AIEditOrchestrator.new()
	var prep: AIEditOrchestrator.EditPreparation = orch.prepare(
		"jump fonksiyonunu değiştir", _sample_source(), "jump"
	)
	if not prep.ok:
		return _fail(name, "hazırlık başarısız: %s" % prep.error)
	# Kapsam dolu olmalı (LLM'e verilecek)
	if prep.scope_content.is_empty():
		return _fail(name, "kapsam içeriği boş")
	# Protokol talimatı eklenmiş olmalı
	if prep.protocol_instructions.is_empty():
		return _fail(name, "protokol talimatı eksik")
	return _ok(name)


static func _test_orch_process_valid() -> Dictionary:
	var name := "Orchestrator geçerli düzenlemeyi işler"
	var orch := AIEditOrchestrator.new()
	var source: String = "func f():\n\treturn 1\n"
	var llm_output: String = (
		AISearchReplaceHandler.SEARCH_MARKER + "\n"
		+ "\treturn 1\n"
		+ AISearchReplaceHandler.SEPARATOR + "\n"
		+ "\treturn 42\n"
		+ AISearchReplaceHandler.REPLACE_MARKER
	)
	var outcome: AIEditOrchestrator.EditOutcome = orch.process_edit(
		source, llm_output, 1
	)
	if not outcome.ok:
		return _fail(name, "geçerli düzenleme reddedildi: %s" % outcome.rejection_reason)
	if not outcome.new_content.contains("return 42"):
		return _fail(name, "düzenleme içeriğe yansımadı")
	return _ok(name)


static func _test_orch_process_reject() -> Dictionary:
	var name := "Orchestrator bozuk düzenlemeyi reddeder"
	var orch := AIEditOrchestrator.new()
	var source: String = "func f():\n\treturn 1\n"
	# Bulunamayan SEARCH
	var bad_output: String = (
		AISearchReplaceHandler.SEARCH_MARKER + "\n"
		+ "var olmayan kod\n"
		+ AISearchReplaceHandler.SEPARATOR + "\n"
		+ "yeni\n"
		+ AISearchReplaceHandler.REPLACE_MARKER
	)
	var outcome: AIEditOrchestrator.EditOutcome = orch.process_edit(
		source, bad_output, 1
	)
	if outcome.ok:
		return _fail(name, "bozuk düzenleme kabul edilmemeli (sahte başarı)")
	if not outcome.rejected:
		return _fail(name, "rejected bayrağı işaretlenmeli")
	# Retry geri bildirimi üretilmeli
	var feedback: String = orch.build_retry_feedback(outcome)
	if feedback.is_empty():
		return _fail(name, "retry geri bildirimi boş")
	return _ok(name)


static func _test_orch_new_file() -> Dictionary:
	var name := "Orchestrator yeni dosya kapsam istemez"
	var orch := AIEditOrchestrator.new()
	var prep: AIEditOrchestrator.EditPreparation = orch.prepare(
		"yeni dosya oluştur item.gd", ""
	)
	if not prep.ok:
		return _fail(name, "yeni dosya hazırlığı başarısız")
	# Yeni dosya — kapsam boş olmalı (çıkarılacak bir şey yok)
	if not prep.scope_content.is_empty():
		return _fail(name, "yeni dosyada kapsam içeriği olmamalı")
	return _ok(name)
