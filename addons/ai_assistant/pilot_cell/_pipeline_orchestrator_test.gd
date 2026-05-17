@tool
class_name AIPipelineOrchestratorTest
extends RefCounted

## Uçtan Uca Orkestratör Self-Test (Aşama 4c).
##
## Doğrular: kod çıkarma, Planner entegrasyonu, SENKRON çekirdek
## (verify → HITL kapısı → Executor gerçek yazım), HITL kapısının
## ARTIK gerçekten çağrıldığı ve engelleyebildiği (Executor↔HITL
## bağı), geçersiz kodun yazılmadığı (mock policy).
##
## Gerçek LLM ağ adımı ASENKRON — burada değil; tools/e2e_runner.gd'de
## gerçek anahtarla kanıtlanır (devir §5.4).

const VALID_CODE: String = (
	"extends Node\n\n\nfunc _ready() -> void:\n\tprint(\"merhaba\")\n"
)


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("E2E: Kod", _test_extract_fenced()))
	results.append(_b("E2E: Kod", _test_extract_plain()))
	results.append(_b("E2E: Plan", _test_build_plan()))
	results.append(_b("E2E: Çekirdek", _test_apply_valid_executes()))
	results.append(_b("E2E: Çekirdek", _test_apply_invalid_blocked()))
	results.append(_b("E2E: Çekirdek", _test_apply_empty()))
	results.append(_b("E2E: HITL", _test_hitl_gate_blocks()))
	results.append(_b("E2E: Durum", _test_no_bridge()))
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _new() -> AIPipelineOrchestrator:
	return AIPipelineOrchestrator.new()


# ============================================================
# KOD ÇIKARMA
# ============================================================

static func _test_extract_fenced() -> Dictionary:
	var name := "Markdown çitli koddan kod çıkarılır"
	var o := _new()
	var raw := "İşte kod:\n```gdscript\nextends Node\n```\nbitti"
	var code: String = o.extract_code(raw)
	o.free()
	if code != "extends Node":
		return _fail(name, "çit soyulmadı: '%s'" % code)
	return _ok(name)


static func _test_extract_plain() -> Dictionary:
	var name := "Çitsiz içerik aynen döner"
	var o := _new()
	var code: String = o.extract_code("extends Node")
	o.free()
	if code != "extends Node":
		return _fail(name, "düz metin korunmalı")
	return _ok(name)


# ============================================================
# PLANNER ENTEGRASYONU
# ============================================================

static func _test_build_plan() -> Dictionary:
	var name := "Planner zinciri ACTION düğümü üretir"
	var o := _new()
	var node: AIPlanNode = o.build_plan("Merhaba oyunu", "hello.gd yaz")
	var ok: bool = node != null and node.level == AIPlanNode.Level.ACTION
	o.free()
	if not ok:
		return _fail(name, "ACTION seviyeli düğüm dönmeli")
	return _ok(name)


# ============================================================
# SENKRON ÇEKİRDEK
# ============================================================

static func _test_apply_valid_executes() -> Dictionary:
	var name := "Geçerli kod: verify→gate→GERÇEK yazım"
	var o := _new()
	var r: Dictionary = o.apply_generated_code(
		"user://ai_assistant/e2e_test/hello_ok.gd",
		"```gdscript\n" + VALID_CODE + "```",
		"CodeEngineer"
	)
	o.free()
	if str(r["stage"]) != "executed":
		return _fail(name, "executed aşamasına ulaşmalı: " +
			str(r["stage"]) + " / " + str(r["message"]))
	if not bool(r["ok"]):
		return _fail(name, "gerçek yazım başarılı olmalı: " +
			str(r["message"]))
	return _ok(name)


static func _test_apply_invalid_blocked() -> Dictionary:
	var name := "Geçersiz kod: verify'da durur, YAZILMAZ (mock)"
	var o := _new()
	var r: Dictionary = o.apply_generated_code(
		"user://ai_assistant/e2e_test/bad.gd",
		"func ( bu gecersiz gdscript !!!",
		"CodeEngineer"
	)
	o.free()
	if bool(r["ok"]):
		return _fail(name, "geçersiz kod ok olmamalı")
	if str(r["stage"]) != "verify":
		return _fail(name, "verify aşamasında durmalı: " + str(r["stage"]))
	return _ok(name)


static func _test_apply_empty() -> Dictionary:
	var name := "Boş içerik: extract aşamasında durur"
	var o := _new()
	var r: Dictionary = o.apply_generated_code(
		"user://ai_assistant/e2e_test/empty.gd", "   ```\n```  ",
		"CodeEngineer"
	)
	o.free()
	if bool(r["ok"]) or str(r["stage"]) != "extract":
		return _fail(name, "boş kod extract'ta durmalı: " + str(r["stage"]))
	return _ok(name)


# ============================================================
# HITL KAPISI — Executor↔HITL bağı kanıtı
# ============================================================

static func _test_hitl_gate_blocks() -> Dictionary:
	var name := "HITL kapısı gerçekten çağrılır ve engeller"
	var o := _new()
	# Eşiği LOW yap — normal yazma bile insan onayı istesin
	o.hitl_coordinator().set_approval_threshold(
		AIRiskAssessor.RiskLevel.LOW
	)
	var r: Dictionary = o.apply_generated_code(
		"user://ai_assistant/e2e_test/gated.gd",
		"```gdscript\n" + VALID_CODE + "```",
		"CodeEngineer"
	)
	o.free()
	if str(r["stage"]) != "hitl":
		return _fail(name, "HITL aşamasında durmalı: " + str(r["stage"]))
	if bool(r["ok"]):
		return _fail(name, "onay beklerken yazılmamalı")
	if not bool(r["needs_approval"]):
		return _fail(name, "needs_approval true olmalı")
	return _ok(name)


# ============================================================
# DURUM
# ============================================================

static func _test_no_bridge() -> Dictionary:
	var name := "Köprüsüz run_task dürüst başarısızlık"
	var o := _new()
	var captured: Array = []
	o.pipeline_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	var started: bool = o.run_task(
		"hedef", "user://x.gd", "yap", AICellRoles.Role.CODE_ENGINEER
	)
	o.free()
	if started:
		return _fail(name, "köprü yokken başlamamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "bridge aşamasında dürüst hata dönmeli")
	return _ok(name)
