@tool
class_name AIPilotBrainTest
extends RefCounted

## Pilot Cell — Ajan Zekâsı Self-Test
##
## Sıkı testler: RolePrompts (14 rol promptu), AgentBrain (düşünme
## mekanizması), CellAgent zekâ entegrasyonu, Orchestrator router
## yayılımı.
##
## ÖNEMLİ: Gerçek LLM çağrısı container'da yapılamaz (ağ/anahtar yok).
## Testler "canlı mod kapalı" davranışını doğrular: istek hazırlanır,
## sahte cevap ÜRETİLMEZ, NEEDS_LLM döner. Canlı-mod gerektiren
## senaryolar Layer 7'deki gibi anahtar gelince çalışır.


static func run_all() -> Array:
	var results: Array = []

	# RolePrompts
	results.append(_b("Brain: Prompts", _test_prompts_all_roles()))
	results.append(_b("Brain: Prompts", _test_prompts_system()))
	results.append(_b("Brain: Prompts", _test_prompts_undefined()))
	results.append(_b("Brain: Prompts", _test_prompts_purpose()))
	results.append(_b("Brain: Prompts", _test_prompts_task_message()))
	results.append(_b("Brain: Prompts", _test_prompts_context()))

	# AgentBrain
	results.append(_b("Brain: Think", _test_brain_offline()))
	results.append(_b("Brain: Think", _test_brain_no_router()))
	results.append(_b("Brain: Think", _test_brain_ready_state()))
	results.append(_b("Brain: Think", _test_brain_request_built()))
	results.append(_b("Brain: Think", _test_brain_undefined_role()))

	# CellAgent zekâ entegrasyonu
	results.append(_b("Brain: Agent", _test_agent_offline_needs_llm()))
	results.append(_b("Brain: Agent", _test_agent_empty_task()))
	results.append(_b("Brain: Agent", _test_agent_has_brain()))

	# Orchestrator
	results.append(_b("Brain: Orch", _test_orch_router_propagation()))
	results.append(_b("Brain: Orch", _test_orch_live_mode_propagation()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# ROLE PROMPTS
# ============================================================

static func _test_prompts_all_roles() -> Dictionary:
	var name := "Prompts 14 rol tanımlı"
	# Pipeline'daki her rol için prompt olmalı
	for role in AICellRoles.PIPELINE_ORDER:
		if not AIRolePrompts.has_prompt(role):
			return _fail(name, "rol promptsuz: %s" % AICellRoles.role_name(role))
	return _ok(name)


static func _test_prompts_system() -> Dictionary:
	var name := "Prompts sistem promptu + ortak kısıt"
	var prompt: String = AIRolePrompts.system_prompt(
		AICellRoles.Role.PRODUCT_MANAGER
	)
	if prompt.is_empty():
		return _fail(name, "PM sistem promptu boş")
	# Ortak kısıt eklenmeli — Godot/Forward Mobile geçmeli
	if not prompt.contains("Godot"):
		return _fail(name, "sistem promptu ortak kısıt içermeli")
	return _ok(name)


static func _test_prompts_undefined() -> Dictionary:
	var name := "Prompts tanımsız rol boş döner"
	# 999 geçersiz rol
	if not AIRolePrompts.system_prompt(999).is_empty():
		return _fail(name, "tanımsız rol boş string dönmeli")
	if AIRolePrompts.has_prompt(999):
		return _fail(name, "tanımsız rol has_prompt false olmalı")
	return _ok(name)


static func _test_prompts_purpose() -> Dictionary:
	var name := "Prompts amaç (Purpose) eşlemesi"
	# Kod üreten rol -> CODE
	if AIRolePrompts.purpose_for(AICellRoles.Role.CODE_ENGINEER) != \
			AIProviderRequest.Purpose.CODE:
		return _fail(name, "CodeEngineer CODE purpose olmalı")
	# PM -> REASONING
	if AIRolePrompts.purpose_for(AICellRoles.Role.PRODUCT_MANAGER) != \
			AIProviderRequest.Purpose.REASONING:
		return _fail(name, "ProductManager REASONING purpose olmalı")
	# QA -> VALIDATION
	if AIRolePrompts.purpose_for(AICellRoles.Role.QA_ENGINEER) != \
			AIProviderRequest.Purpose.VALIDATION:
		return _fail(name, "QAEngineer VALIDATION purpose olmalı")
	return _ok(name)


static func _test_prompts_task_message() -> Dictionary:
	var name := "Prompts görev mesajı çerçeveleme"
	var msg: String = AIRolePrompts.build_task_message(
		AICellRoles.Role.PRODUCT_MANAGER, "ana menü oluştur"
	)
	if not msg.contains("ana menü oluştur"):
		return _fail(name, "görev mesajı görev metnini içermeli")
	if not msg.contains("ÇIKTI"):
		return _fail(name, "görev mesajı çıktı yönergesi içermeli")
	return _ok(name)


static func _test_prompts_context() -> Dictionary:
	var name := "Prompts bağlam çerçeveleme"
	# Bağlamsız — bağlam bölümü olmamalı
	var no_ctx: String = AIRolePrompts.build_task_message(
		AICellRoles.Role.ARCHITECT, "tasarla"
	)
	if no_ctx.contains("BAĞLAM"):
		return _fail(name, "bağlamsız mesajda bağlam bölümü olmamalı")
	# Bağlamlı — bağlam görünmeli
	var with_ctx: String = AIRolePrompts.build_task_message(
		AICellRoles.Role.ARCHITECT, "tasarla",
		{"ProductManager": "hedef: hızlı menü"}
	)
	if not with_ctx.contains("BAĞLAM"):
		return _fail(name, "bağlamlı mesajda bağlam bölümü olmalı")
	if not with_ctx.contains("hedef: hızlı menü"):
		return _fail(name, "bağlam içeriği mesajda görünmeli")
	return _ok(name)


# ============================================================
# AGENT BRAIN
# ============================================================

static func _test_brain_offline() -> Dictionary:
	var name := "Brain canlı mod kapalı — sahte cevap yok"
	var brain := AIAgentBrain.new()
	# Varsayılan: live_mode false
	var thought: AIAgentBrain.ThoughtResult = brain.think(
		AICellRoles.Role.PRODUCT_MANAGER, "görev"
	)
	# LLM çağrılmamalı, başarı olmamalı (sahte cevap üretmemeli)
	if thought.llm_called:
		return _fail(name, "canlı mod kapalıyken LLM çağrılmamalı")
	if thought.success:
		return _fail(name, "canlı mod kapalıyken sahte başarı olmamalı")
	return _ok(name)


static func _test_brain_no_router() -> Dictionary:
	var name := "Brain canlı ama router yok"
	var brain := AIAgentBrain.new()
	brain.set_live_mode(true)
	# Router bağlı değil — çağrı yapılamamalı
	var thought: AIAgentBrain.ThoughtResult = brain.think(
		AICellRoles.Role.ARCHITECT, "görev"
	)
	if thought.llm_called:
		return _fail(name, "router yokken çağrı yapılmamalı")
	return _ok(name)


static func _test_brain_ready_state() -> Dictionary:
	var name := "Brain hazır durumu"
	var brain := AIAgentBrain.new()
	# Başlangıçta hazır değil
	if brain.is_ready_to_think():
		return _fail(name, "router+canlı yokken hazır olmamalı")
	# Canlı mod + router -> hazır
	brain.set_live_mode(true)
	brain.attach_router(AIProviderRouter.new())
	if not brain.is_ready_to_think():
		return _fail(name, "router+canlı varken hazır olmalı")
	return _ok(name)


static func _test_brain_request_built() -> Dictionary:
	var name := "Brain istek hazırlama (canlı kapalı)"
	var brain := AIAgentBrain.new()
	var thought: AIAgentBrain.ThoughtResult = brain.think(
		AICellRoles.Role.PRODUCT_MANAGER, "ana menü"
	)
	# Canlı kapalı olsa da istek kurulmuş olmalı
	if thought.prepared_request == null:
		return _fail(name, "istek hazırlanmalı (canlı kapalı olsa da)")
	# İstekte sistem + kullanıcı mesajı olmalı
	if thought.prepared_request.messages.size() < 2:
		return _fail(name, "istek system + user mesajı içermeli")
	return _ok(name)


static func _test_brain_undefined_role() -> Dictionary:
	var name := "Brain promptsuz rol"
	var brain := AIAgentBrain.new()
	var thought: AIAgentBrain.ThoughtResult = brain.think(999, "görev")
	if thought.success:
		return _fail(name, "promptsuz rol başarılı olmamalı")
	return _ok(name)


# ============================================================
# CELL AGENT ZEKÂ ENTEGRASYONU
# ============================================================

static func _test_agent_offline_needs_llm() -> Dictionary:
	var name := "Agent canlı kapalı — NEEDS_LLM"
	var agent := AICellAgent.new(AICellRoles.Role.PRODUCT_MANAGER)
	# Canlı mod kapalı (varsayılan) — gerçek cevap yok
	var result: AICellAgent.WorkResult = agent.process_task("ana menü yap")
	if result.status != AICellAgent.WorkStatus.NEEDS_LLM:
		return _fail(name, "canlı kapalıyken NEEDS_LLM olmalı (sahte yok)")
	# İstek hazırlanmış olmalı — artifacts bunu söylüyor
	if not result.artifacts.get("request_prepared", false):
		return _fail(name, "istek hazırlandığı raporlanmalı")
	return _ok(name)


static func _test_agent_empty_task() -> Dictionary:
	var name := "Agent boş görev FAILED"
	var agent := AICellAgent.new(AICellRoles.Role.ARCHITECT)
	var result: AICellAgent.WorkResult = agent.process_task("")
	if result.status != AICellAgent.WorkStatus.FAILED:
		return _fail(name, "boş görev FAILED olmalı")
	return _ok(name)


static func _test_agent_has_brain() -> Dictionary:
	var name := "Agent beyne sahip"
	var agent := AICellAgent.new(AICellRoles.Role.CODE_ENGINEER)
	if agent.brain == null:
		return _fail(name, "ajan brain'e sahip olmalı")
	# Router bağlama ajan üzerinden çalışmalı
	agent.attach_router(AIProviderRouter.new())
	agent.set_live_mode(true)
	if not agent.brain.is_ready_to_think():
		return _fail(name, "ajan router+canlı sonrası hazır olmalı")
	return _ok(name)


# ============================================================
# ORCHESTRATOR
# ============================================================

static func _test_orch_router_propagation() -> Dictionary:
	var name := "Orchestrator router tüm ajanlara yayar"
	var orch := AICellOrchestrator.new()
	var router := AIProviderRouter.new()
	orch.attach_router(router)
	# Her ajanın beyni router'a sahip olmalı
	for role in AICellRoles.PIPELINE_ORDER:
		var agent: AICellAgent = orch.agent_for(role)
		if agent == null:
			return _fail(name, "ajan eksik: %s" % AICellRoles.role_name(role))
		# Canlı mod açılınca hazır olabilmeli (router var demektir)
		agent.set_live_mode(true)
		if not agent.brain.is_ready_to_think():
			return _fail(name, "router yayılmadı: %s" % \
				AICellRoles.role_name(role))
	return _ok(name)


static func _test_orch_live_mode_propagation() -> Dictionary:
	var name := "Orchestrator canlı mod tüm ajanlara yayar"
	var orch := AICellOrchestrator.new()
	orch.attach_router(AIProviderRouter.new())
	orch.set_live_mode(true)
	# Her ajan canlı modda olmalı
	for role in AICellRoles.PIPELINE_ORDER:
		var agent: AICellAgent = orch.agent_for(role)
		if not agent.brain.live_mode:
			return _fail(name, "canlı mod yayılmadı: %s" % \
				AICellRoles.role_name(role))
	return _ok(name)
