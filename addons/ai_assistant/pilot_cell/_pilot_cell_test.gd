@tool
class_name AIPilotCellTest
extends RefCounted

## Phase 12 / Layer 9 — Pilot Cell Self-Test
##
## Sıkı testler: CellRoles (14 rol + pipeline), CellAgent (mesajlaşma +
## görev), MessageBus (yönlendirme), ReflectionLoop (tur mantığı),
## CellOrchestrator (pipeline akışı).
##
## NOT: Ajan ZEKÂSI (LLM çağrıları) bu iskelet sürümde yok — ajanlar
## NEEDS_LLM döndürür. Testler ORKESTRASYONUN doğruluğunu sınar:
## roller doğru sırada, mesaj doğru yere, reflection doğru sayar.
## Sahte "oyun üretildi" yok — testler bunu da doğrular.


static func run_all() -> Array:
	var results: Array = []

	# CellRoles
	results.append(_b("Pilot: Roles", _test_roles_count()))
	results.append(_b("Pilot: Roles", _test_roles_pipeline_order()))
	results.append(_b("Pilot: Roles", _test_roles_code_generating()))
	results.append(_b("Pilot: Roles", _test_roles_name_lookup()))

	# CellAgent
	results.append(_b("Pilot: Agent", _test_agent_inbox()))
	results.append(_b("Pilot: Agent", _test_agent_process()))
	results.append(_b("Pilot: Agent", _test_agent_empty_task()))
	results.append(_b("Pilot: Agent", _test_agent_reflection_decision()))

	# MessageBus
	results.append(_b("Pilot: Bus", _test_bus_register()))
	results.append(_b("Pilot: Bus", _test_bus_send()))
	results.append(_b("Pilot: Bus", _test_bus_invalid_recipient()))
	results.append(_b("Pilot: Bus", _test_bus_type_filter()))

	# ReflectionLoop
	results.append(_b("Pilot: Reflect", _test_reflect_converge()))
	results.append(_b("Pilot: Reflect", _test_reflect_iterate()))
	results.append(_b("Pilot: Reflect", _test_reflect_exhaust()))
	results.append(_b("Pilot: Reflect", _test_reflect_can_continue()))

	# CellOrchestrator
	results.append(_b("Pilot: Orch", _test_orch_agent_count()))
	results.append(_b("Pilot: Orch", _test_orch_pipeline_run()))
	results.append(_b("Pilot: Orch", _test_orch_needs_llm()))
	results.append(_b("Pilot: Orch", _test_orch_empty_task()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# CELL ROLES
# ============================================================

static func _test_roles_count() -> Dictionary:
	var name := "Roles 14 rol tanımlı"
	if AICellRoles.role_count() != 14:
		return _fail(name, "14 rol bekleniyordu, %d var" % AICellRoles.role_count())
	if AICellRoles.PIPELINE_ORDER.size() != 14:
		return _fail(name, "pipeline 14 rol içermeli")
	return _ok(name)


static func _test_roles_pipeline_order() -> Dictionary:
	var name := "Roles pipeline sırası"
	# PM ilk, TechWriter son
	if AICellRoles.PIPELINE_ORDER[0] != AICellRoles.Role.PRODUCT_MANAGER:
		return _fail(name, "pipeline PM ile başlamalı")
	# PM'in sonrası Architect
	if AICellRoles.next_in_pipeline(AICellRoles.Role.PRODUCT_MANAGER) != \
			AICellRoles.Role.ARCHITECT:
		return _fail(name, "PM sonrası Architect olmalı")
	# Son rolün sonrası -1
	if AICellRoles.next_in_pipeline(AICellRoles.Role.TECH_WRITER) != -1:
		return _fail(name, "son rol sonrası -1 dönmeli")
	# İlk rolün öncesi -1
	if AICellRoles.prev_in_pipeline(AICellRoles.Role.PRODUCT_MANAGER) != -1:
		return _fail(name, "ilk rol öncesi -1 dönmeli")
	return _ok(name)


static func _test_roles_code_generating() -> Dictionary:
	var name := "Roles kod üreten rol tespiti"
	# CodeEngineer kod üretir
	if not AICellRoles.is_code_generating(AICellRoles.Role.CODE_ENGINEER):
		return _fail(name, "CodeEngineer kod üreten olmalı")
	# ProductManager kod üretmez
	if AICellRoles.is_code_generating(AICellRoles.Role.PRODUCT_MANAGER):
		return _fail(name, "ProductManager kod üreten olmamalı")
	# CodeEngineer engineer grubunda
	if not AICellRoles.is_engineer(AICellRoles.Role.CODE_ENGINEER):
		return _fail(name, "CodeEngineer engineer olmalı")
	return _ok(name)


static func _test_roles_name_lookup() -> Dictionary:
	var name := "Roles ad ile arama"
	var role: int = AICellRoles.role_from_name("Architect")
	if role != AICellRoles.Role.ARCHITECT:
		return _fail(name, "isim->rol araması yanlış")
	# Olmayan isim
	if AICellRoles.role_from_name("OlmayanRol") != -1:
		return _fail(name, "olmayan isim -1 dönmeli")
	return _ok(name)


# ============================================================
# CELL AGENT
# ============================================================

static func _test_agent_inbox() -> Dictionary:
	var name := "Agent gelen kutusu"
	var agent := AICellAgent.new(AICellRoles.Role.CODE_ENGINEER)
	var msg := AICellMessage.create("PM", "CodeEngineer",
		AICellMessage.MessageType.HANDOFF)
	agent.receive(msg)
	if agent.inbox_count() != 1:
		return _fail(name, "mesaj gelen kutusuna eklenmedi")
	var pulled: AICellMessage = agent.pull_message()
	if pulled == null:
		return _fail(name, "mesaj çekilemedi")
	if agent.inbox_count() != 0:
		return _fail(name, "çekilen mesaj kutudan çıkmadı")
	return _ok(name)


static func _test_agent_process() -> Dictionary:
	var name := "Agent görev işleme"
	var agent := AICellAgent.new(AICellRoles.Role.ARCHITECT)
	var result: AICellAgent.WorkResult = agent.process_task(
		"sistem mimarisi tasarla"
	)
	# İskelet sürüm — LLM gerekli, sahte tamamlama yok
	if result.status != AICellAgent.WorkStatus.NEEDS_LLM:
		return _fail(name, "iskelet ajan NEEDS_LLM döndürmeli (sahte başarı yok)")
	if result.role != AICellRoles.Role.ARCHITECT:
		return _fail(name, "sonuç rolü yanlış")
	return _ok(name)


static func _test_agent_empty_task() -> Dictionary:
	var name := "Agent boş görev reddi"
	var agent := AICellAgent.new(AICellRoles.Role.CODE_ENGINEER)
	var result: AICellAgent.WorkResult = agent.process_task("")
	if result.status != AICellAgent.WorkStatus.FAILED:
		return _fail(name, "boş görev FAILED olmalı")
	return _ok(name)


static func _test_agent_reflection_decision() -> Dictionary:
	var name := "Agent reflection kararı"
	# Kod üreten rol her zaman reflection ister
	var coder := AICellAgent.new(AICellRoles.Role.CODE_ENGINEER)
	var coder_result: AICellAgent.WorkResult = coder.process_task("kod yaz")
	if not coder.should_reflect(coder_result):
		return _fail(name, "kod üreten rol reflection istemeli")
	# PM başarılı işte reflection istemez — ama iskelet NEEDS_LLM döndürür,
	# o yüzden başarısız sayılır, reflection ister. DONE olsaydı istemezdi.
	var pm := AICellAgent.new(AICellRoles.Role.PRODUCT_MANAGER)
	var done_result := AICellAgent.WorkResult.new()
	done_result.status = AICellAgent.WorkStatus.DONE
	if pm.should_reflect(done_result):
		return _fail(name, "PM tamamlanmış işte reflection istememeli")
	return _ok(name)


# ============================================================
# MESSAGE BUS
# ============================================================

static func _test_bus_register() -> Dictionary:
	var name := "Bus ajan kaydı"
	var bus := AICellMessageBus.new()
	var agent := AICellAgent.new(AICellRoles.Role.PRODUCT_MANAGER)
	bus.register(agent)
	if not bus.has_agent(AICellRoles.Role.PRODUCT_MANAGER):
		return _fail(name, "ajan kaydedilmedi")
	if bus.agent_count() != 1:
		return _fail(name, "ajan sayısı yanlış")
	return _ok(name)


static func _test_bus_send() -> Dictionary:
	var name := "Bus mesaj yönlendirme"
	var bus := AICellMessageBus.new()
	bus.register(AICellAgent.new(AICellRoles.Role.PRODUCT_MANAGER))
	var arch := AICellAgent.new(AICellRoles.Role.ARCHITECT)
	bus.register(arch)
	var result: Dictionary = bus.send_between(
		AICellRoles.Role.PRODUCT_MANAGER, AICellRoles.Role.ARCHITECT,
		AICellMessage.MessageType.HANDOFF, "Teslim", "İçerik"
	)
	if not result["ok"]:
		return _fail(name, "mesaj gönderimi başarısız")
	# Architect'in gelen kutusunda olmalı
	if arch.inbox_count() != 1:
		return _fail(name, "mesaj alıcının kutusuna ulaşmadı")
	return _ok(name)


static func _test_bus_invalid_recipient() -> Dictionary:
	var name := "Bus geçersiz alıcı reddi"
	var bus := AICellMessageBus.new()
	bus.register(AICellAgent.new(AICellRoles.Role.PRODUCT_MANAGER))
	# Architect kayıtlı değil — gönderim başarısız olmalı
	var result: Dictionary = bus.send_between(
		AICellRoles.Role.PRODUCT_MANAGER, AICellRoles.Role.ARCHITECT,
		AICellMessage.MessageType.HANDOFF, "Teslim", "İçerik"
	)
	if result["ok"]:
		return _fail(name, "kayıtsız alıcıya gönderim başarısız olmalı")
	return _ok(name)


static func _test_bus_type_filter() -> Dictionary:
	var name := "Bus mesaj tipi filtresi"
	var bus := AICellMessageBus.new()
	bus.register(AICellAgent.new(AICellRoles.Role.PRODUCT_MANAGER))
	bus.register(AICellAgent.new(AICellRoles.Role.ARCHITECT))
	bus.send_between(
		AICellRoles.Role.PRODUCT_MANAGER, AICellRoles.Role.ARCHITECT,
		AICellMessage.MessageType.HANDOFF, "h", "h"
	)
	bus.send_between(
		AICellRoles.Role.PRODUCT_MANAGER, AICellRoles.Role.ARCHITECT,
		AICellMessage.MessageType.ESCALATION, "e", "e"
	)
	var escalations: Array = bus.messages_of_type(
		AICellMessage.MessageType.ESCALATION
	)
	if escalations.size() != 1:
		return _fail(name, "tip filtresi yanlış sayı döndü")
	return _ok(name)


# ============================================================
# REFLECTION LOOP
# ============================================================

static func _test_reflect_converge() -> Dictionary:
	var name := "Reflection eleştiri yoksa yakınsar"
	var loop := AIReflectionLoop.new()
	loop.begin()
	var critique: AIReflectionLoop.Critique = loop.make_critique(
		PackedStringArray(), AICellRoles.Role.QA_ENGINEER
	)
	var result: Dictionary = loop.submit_critique(critique)
	if not result["converged"]:
		return _fail(name, "eleştiri yoksa yakınsamalı")
	if result["continue"]:
		return _fail(name, "yakınsayınca devam etmemeli")
	return _ok(name)


static func _test_reflect_iterate() -> Dictionary:
	var name := "Reflection eleştiri varsa tur ilerler"
	var loop := AIReflectionLoop.new()
	loop.begin()
	var critique: AIReflectionLoop.Critique = loop.make_critique(
		PackedStringArray(["sorun var"]), AICellRoles.Role.QA_ENGINEER
	)
	var result: Dictionary = loop.submit_critique(critique)
	if not result["continue"]:
		return _fail(name, "eleştiri varsa devam etmeli")
	if loop.current_round() != 1:
		return _fail(name, "tur 1'e ilerlemiş olmalı")
	return _ok(name)


static func _test_reflect_exhaust() -> Dictionary:
	var name := "Reflection max tur tükenmesi"
	var loop := AIReflectionLoop.new()
	loop.begin()
	# Her turda eleştiri ver — max tur'a ulaşana kadar
	var last: Dictionary = {}
	for i in range(AIReflectionLoop.MAX_ROUNDS):
		var critique: AIReflectionLoop.Critique = loop.make_critique(
			PackedStringArray(["hâlâ sorun"]), AICellRoles.Role.QA_ENGINEER
		)
		last = loop.submit_critique(critique)
	# Max tur sonunda exhausted olmalı, converged değil
	if not last["exhausted"]:
		return _fail(name, "max tur sonunda exhausted olmalı")
	if last["converged"]:
		return _fail(name, "exhausted converged olmamalı")
	return _ok(name)


static func _test_reflect_can_continue() -> Dictionary:
	var name := "Reflection yakınsama sonrası durur"
	var loop := AIReflectionLoop.new()
	loop.begin()
	var critique: AIReflectionLoop.Critique = loop.make_critique(
		PackedStringArray(), AICellRoles.Role.QA_ENGINEER
	)
	loop.submit_critique(critique)
	# Yakınsadıktan sonra devam edememe
	if loop.can_continue():
		return _fail(name, "yakınsama sonrası can_continue false olmalı")
	if not loop.did_converge():
		return _fail(name, "did_converge true olmalı")
	return _ok(name)


# ============================================================
# CELL ORCHESTRATOR
# ============================================================

static func _test_orch_agent_count() -> Dictionary:
	var name := "Orchestrator 14 ajan oluşturur"
	var orch := AICellOrchestrator.new()
	if orch.agent_count() != 14:
		return _fail(name, "14 ajan bekleniyordu, %d var" % orch.agent_count())
	return _ok(name)


static func _test_orch_pipeline_run() -> Dictionary:
	var name := "Orchestrator pipeline akışı"
	var orch := AICellOrchestrator.new()
	var run: AICellOrchestrator.PipelineRun = orch.run_pipeline(
		"ana menü sahnesi oluştur"
	)
	if not run.finished:
		return _fail(name, "pipeline tamamlanmalı")
	# 14 aşama tamamlanmalı
	if run.stages_completed != 14:
		return _fail(name, "14 aşama tamamlanmalı, %d" % run.stages_completed)
	if run.stages_total != 14:
		return _fail(name, "toplam aşama 14 olmalı")
	return _ok(name)


static func _test_orch_needs_llm() -> Dictionary:
	var name := "Orchestrator LLM ihtiyacını işaretler"
	var orch := AICellOrchestrator.new()
	var run: AICellOrchestrator.PipelineRun = orch.run_pipeline(
		"oyun mekaniği yap"
	)
	# İskelet ajanlar NEEDS_LLM döndürür — pipeline bunu işaretlemeli
	# (sahte "oyun üretildi" yok)
	if not run.needs_llm:
		return _fail(name, "iskelet pipeline LLM ihtiyacını işaretlemeli")
	return _ok(name)


static func _test_orch_empty_task() -> Dictionary:
	var name := "Orchestrator boş görev güvenliği"
	var orch := AICellOrchestrator.new()
	var run: AICellOrchestrator.PipelineRun = orch.run_pipeline("")
	if not run.finished:
		return _fail(name, "boş görev de finished olmalı")
	if run.stages_completed != 0:
		return _fail(name, "boş görevde aşama tamamlanmamalı")
	return _ok(name)
