@tool
class_name AIContextRelayTest
extends RefCounted

## Pilot Cell — ContextRelay Self-Test
##
## Sıkı testler: pipeline'da roller arası yapılandırılmış bağlam
## aktarımı. Kritik senaryo: DeliveryManager'ın task listesi
## CodeEngineer'a ÖZET değil YAPILANDIRILMIŞ ulaşmalı.


static func run_all() -> Array:
	var results: Array = []

	results.append(_b("Relay: Record", _test_record_basic()))
	results.append(_b("Relay: Record", _test_record_structured()))
	results.append(_b("Relay: Context", _test_context_original_task()))
	results.append(_b("Relay: Context", _test_context_summaries()))
	results.append(_b("Relay: Context", _test_context_key_input()))
	results.append(_b("Relay: Context", _test_context_unstructured()))
	results.append(_b("Relay: Context", _test_context_empty_items()))
	results.append(_b("Relay: KeyPred", _test_key_predecessor()))
	results.append(_b("Relay: Verdict", _test_fail_verdict()))
	results.append(_b("Relay: Verdict", _test_pass_verdict()))
	results.append(_b("Relay: Query", _test_structured_count()))
	results.append(_b("Relay: Pipeline", _test_pipeline_integration()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


## Test için bir WorkResult üretir.
static func _make_result(
	role: int, summary: String, items: Array, structured: bool,
	verdict: String = ""
) -> AICellAgent.WorkResult:
	var result := AICellAgent.WorkResult.new()
	result.role = role
	result.summary = summary
	result.output = "ham metin"
	result.artifacts = {
		"structured": structured,
		"items": items,
		"verdict": verdict,
		"parsed_kind": "task_list" if not items.is_empty() else "raw_text",
	}
	return result


# ============================================================
# KAYIT
# ============================================================

static func _test_record_basic() -> Dictionary:
	var name := "Relay temel kayıt"
	var relay := AIContextRelay.new("görev")
	var result := _make_result(
		AICellRoles.Role.PRODUCT_MANAGER, "hedef tanımlandı", [], false
	)
	relay.record(AICellRoles.Role.PRODUCT_MANAGER, result)
	if relay.entry_count() != 1:
		return _fail(name, "kayıt eklenmedi")
	if not relay.has_entry(AICellRoles.Role.PRODUCT_MANAGER):
		return _fail(name, "PM kaydı bulunamadı")
	return _ok(name)


static func _test_record_structured() -> Dictionary:
	var name := "Relay yapılandırılmış kayıt"
	var relay := AIContextRelay.new("görev")
	var items: Array = [{"index": 1, "text": "iş"}]
	var result := _make_result(
		AICellRoles.Role.DELIVERY_MANAGER, "1 task", items, true
	)
	relay.record(AICellRoles.Role.DELIVERY_MANAGER, result)
	var entry: AIContextRelay.RelayEntry = relay.entry_for(
		AICellRoles.Role.DELIVERY_MANAGER
	)
	if entry == null:
		return _fail(name, "kayıt alınamadı")
	if not entry.structured:
		return _fail(name, "structured bayrağı korunmadı")
	if entry.items.size() != 1:
		return _fail(name, "items korunmadı")
	return _ok(name)


# ============================================================
# BAĞLAM ÜRETİMİ
# ============================================================

static func _test_context_original_task() -> Dictionary:
	var name := "Context orijinal görev her zaman var"
	var relay := AIContextRelay.new("ana menü oluştur")
	var context: Dictionary = relay.build_context_for(
		AICellRoles.Role.PRODUCT_MANAGER
	)
	if context.get("original_task", "") != "ana menü oluştur":
		return _fail(name, "orijinal görev bağlamda olmalı")
	return _ok(name)


static func _test_context_summaries() -> Dictionary:
	var name := "Context önceki rol özetleri"
	var relay := AIContextRelay.new("görev")
	relay.record(AICellRoles.Role.PRODUCT_MANAGER, _make_result(
		AICellRoles.Role.PRODUCT_MANAGER, "hedef: hızlı menü", [], false
	))
	var context: Dictionary = relay.build_context_for(
		AICellRoles.Role.ARCHITECT
	)
	# PM'in özeti Architect'in bağlamında olmalı
	if context.get("ProductManager", "") != "hedef: hızlı menü":
		return _fail(name, "önceki rol özeti bağlamda olmalı")
	return _ok(name)


static func _test_context_key_input() -> Dictionary:
	var name := "Context key input — yapılandırılmış aktarım"
	var relay := AIContextRelay.new("görev")
	# DeliveryManager yapılandırılmış task listesi üretir
	var tasks: Array = [
		{"index": 1, "text": "menü scripti yaz"},
		{"index": 2, "text": "buton ekle"},
	]
	relay.record(AICellRoles.Role.DELIVERY_MANAGER, _make_result(
		AICellRoles.Role.DELIVERY_MANAGER, "2 task", tasks, true
	))
	# CodeEngineer'ın bağlamı — DM key predecessor
	var context: Dictionary = relay.build_context_for(
		AICellRoles.Role.CODE_ENGINEER
	)
	# KRİTİK: task'lar özet değil, yapılandırılmış gelmeli
	if not context.has("_key_input_items"):
		return _fail(name, "kod rolü key input items almalı")
	var key_items: Array = context["_key_input_items"]
	if key_items.size() != 2:
		return _fail(name, "task'lar yapılandırılmış geçmeli")
	if str(key_items[0]["text"]) != "menü scripti yaz":
		return _fail(name, "task içeriği korunmalı")
	return _ok(name)


static func _test_context_unstructured() -> Dictionary:
	var name := "Context yapılandırılmamış — key input yok"
	var relay := AIContextRelay.new("görev")
	# DeliveryManager structured=false
	relay.record(AICellRoles.Role.DELIVERY_MANAGER, _make_result(
		AICellRoles.Role.DELIVERY_MANAGER, "özet", [], false
	))
	var context: Dictionary = relay.build_context_for(
		AICellRoles.Role.CODE_ENGINEER
	)
	# Yapılandırılmamışsa key_input verilmemeli
	if context.has("_key_input_items"):
		return _fail(name, "yapılandırılmamış çıktı key input vermemeli")
	return _ok(name)


static func _test_context_empty_items() -> Dictionary:
	var name := "Context structured ama boş items"
	var relay := AIContextRelay.new("görev")
	# structured=true ama items boş
	relay.record(AICellRoles.Role.DELIVERY_MANAGER, _make_result(
		AICellRoles.Role.DELIVERY_MANAGER, "özet", [], true
	))
	var context: Dictionary = relay.build_context_for(
		AICellRoles.Role.CODE_ENGINEER
	)
	# Boş items -> key input verilmemeli
	if context.has("_key_input_items"):
		return _fail(name, "boş items key input vermemeli")
	return _ok(name)


# ============================================================
# KEY PREDECESSOR
# ============================================================

static func _test_key_predecessor() -> Dictionary:
	var name := "KeyPredecessor doğru eşleme"
	var relay := AIContextRelay.new()
	# Kod rolleri -> DeliveryManager (test build_context üzerinden)
	# DeliveryManager structured task verelim, kod rolü almalı
	relay.record(AICellRoles.Role.DELIVERY_MANAGER, _make_result(
		AICellRoles.Role.DELIVERY_MANAGER, "t",
		[{"index": 1, "text": "x"}], true
	))
	var code_ctx: Dictionary = relay.build_context_for(
		AICellRoles.Role.SCENE_ENGINEER
	)
	if code_ctx.get("_key_input_role", "") != "DeliveryManager":
		return _fail(name, "SceneEngineer key predecessor DeliveryManager olmalı")
	return _ok(name)


# ============================================================
# VERDICT
# ============================================================

static func _test_fail_verdict() -> Dictionary:
	var name := "Verdict FAIL tespiti"
	var relay := AIContextRelay.new()
	relay.record(AICellRoles.Role.QA_ENGINEER, _make_result(
		AICellRoles.Role.QA_ENGINEER, "inceleme", [], true, "fail"
	))
	if not relay.has_fail_verdict():
		return _fail(name, "fail verdict tespit edilmeli")
	return _ok(name)


static func _test_pass_verdict() -> Dictionary:
	var name := "Verdict PASS — fail yok"
	var relay := AIContextRelay.new()
	relay.record(AICellRoles.Role.QA_ENGINEER, _make_result(
		AICellRoles.Role.QA_ENGINEER, "inceleme", [], true, "pass"
	))
	if relay.has_fail_verdict():
		return _fail(name, "pass verdict'te fail olmamalı")
	return _ok(name)


# ============================================================
# SORGULAMA
# ============================================================

static func _test_structured_count() -> Dictionary:
	var name := "Query yapılandırılmış sayım"
	var relay := AIContextRelay.new()
	relay.record(AICellRoles.Role.PRODUCT_MANAGER, _make_result(
		AICellRoles.Role.PRODUCT_MANAGER, "a", [], true
	))
	relay.record(AICellRoles.Role.ARCHITECT, _make_result(
		AICellRoles.Role.ARCHITECT, "b", [], false
	))
	if relay.structured_count() != 1:
		return _fail(name, "1 yapılandırılmış kayıt bekleniyordu")
	return _ok(name)


# ============================================================
# PIPELINE ENTEGRASYONU
# ============================================================

static func _test_pipeline_integration() -> Dictionary:
	var name := "Pipeline relay entegrasyonu"
	var orch := AICellOrchestrator.new()
	var run: AICellOrchestrator.PipelineRun = orch.run_pipeline(
		"ana menü oluştur"
	)
	# Pipeline relay'e sahip olmalı
	if run.relay == null:
		return _fail(name, "PipelineRun relay'e sahip olmalı")
	# 14 rol işlendi — relay 14 kayıt taşımalı
	if run.relay.entry_count() != 14:
		return _fail(name, "relay 14 kayıt taşımalı, %d" % \
			run.relay.entry_count())
	return _ok(name)
