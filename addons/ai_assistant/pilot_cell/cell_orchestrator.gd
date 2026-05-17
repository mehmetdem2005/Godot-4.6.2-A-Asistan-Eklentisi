@tool
class_name AICellOrchestrator
extends RefCounted

## CellOrchestrator — pilot hücre orkestratörü (Layer 9).
##
## Layer 9'un ana motoru. 14 ajanı bir "yazılım şirketi" gibi
## çalıştırır: bir oyun-geliştirme isteği gelir, pipeline boyunca
## rolden role akar, her aşamada reflection'dan geçer, sonunda
## tamamlanmış bir çıktı çıkar.
##
## Birleştirdiği bileşenler:
##   cell_roles      — 14 rol tanımı + pipeline sırası
##   cell_agent      — her rol bir ajan
##   message_bus     — ajanlar arası mesajlaşma
##   reflection_loop — öz-eleştiri turları
##
## Pipeline (Hierarchical): PM -> Architect -> DeliveryManager ->
##   Engineers -> QA -> Debug -> Test -> Performance -> Reviewer ->
##   Commit -> TechWriter
##
## ÖNEMLİ: Bu iskelet sürüm pipeline AKIŞINI, mesajlaşmayı, reflection
## tur yönetimini tam kurar. Ajanların gerçek ZEKÂSI (LLM çağrıları,
## Layer 7 Router üzerinden) sonraki Pilot Cell oturumlarında her role
## özel prompt'la eklenecek. Şimdilik ajanlar NEEDS_LLM döndürür —
## orkestrasyon iskeleti çalışır, sahte tamamlama yoktur.
##
## Mock policy: orkestratör sahte "oyun üretildi" demez — ajanlar
## LLM gerektiriyorsa bunu açıkça raporlar.

## Bir pipeline çalıştırmasının sonucu.
class PipelineRun extends RefCounted:
	var conversation_ref: String = ""
	var task: String = ""
	var stages_completed: int = 0      ## Kaç rol tamamladı
	var stages_total: int = 0
	var needs_llm: bool = false        ## LLM gerektiren aşama var mı
	var escalations: int = 0           ## Kaç escalation oldu
	var stage_results: Array = []      ## Her aşamanın WorkResult'ı
	var relay: AIContextRelay = null   ## Bağlam aktarıcı — rol çıktıları
	var finished: bool = false

	## Pipeline tamamlanma oranı.
	func progress() -> float:
		if stages_total == 0:
			return 0.0
		return float(stages_completed) / float(stages_total)

	func to_dict() -> Dictionary:
		return {
			"conversation_ref": conversation_ref,
			"task": task,
			"stages_completed": stages_completed,
			"stages_total": stages_total,
			"progress": progress(),
			"needs_llm": needs_llm,
			"escalations": escalations,
			"finished": finished,
		}


## Bileşenler.
var bus: AICellMessageBus
var reflection: AIReflectionLoop

## Tüm ajanlara bağlanacak Router (LLM çağrıları için).
var _router: AIProviderRouter = null

## Tüm ajanların canlı modu (true = gerçek LLM çağrısı).
var _live_mode: bool = false


func _init() -> void:
	bus = AICellMessageBus.new()
	reflection = AIReflectionLoop.new()
	_create_all_agents()


## 14 rolün ajanını oluşturur ve veri yoluna kaydeder.
## Router/canlı mod ayarlıysa yeni ajanlara da uygular.
func _create_all_agents() -> void:
	for role in AICellRoles.PIPELINE_ORDER:
		var agent := AICellAgent.new(role)
		if _router != null:
			agent.attach_router(_router)
		agent.set_live_mode(_live_mode)
		bus.register(agent)


## Tüm ajanlara bir Router bağlar — Pilot Cell'in LLM'e erişimi.
func attach_router(router: AIProviderRouter) -> void:
	_router = router
	for role in AICellRoles.PIPELINE_ORDER:
		var agent: AICellAgent = bus.get_agent(role)
		if agent != null:
			agent.attach_router(router)


## Tüm ajanların canlı modunu ayarlar.
## true: gerçek LLM çağrısı (Router + API anahtarı gerekli).
## false (varsayılan): istek hazırlanır, çağrılmaz.
func set_live_mode(value: bool) -> void:
	_live_mode = value
	for role in AICellRoles.PIPELINE_ORDER:
		var agent: AICellAgent = bus.get_agent(role)
		if agent != null:
			agent.set_live_mode(value)


# ============================================================
# PIPELINE YÜRÜTME
# ============================================================

## Bir oyun-geliştirme isteğini pipeline boyunca yürütür.
##
## task: ne yapılacak (örn. "ana menü sahnesi oluştur").
## Dönen: PipelineRun — her aşamanın sonucu.
##
## Akış: her rol sırayla görevi işler, çıktısı bir sonraki role
## HANDOFF mesajıyla geçer. Kod üreten roller reflection'dan geçer.
func run_pipeline(task: String) -> PipelineRun:
	var run := PipelineRun.new()
	run.task = task
	run.conversation_ref = bus.new_conversation()
	run.stages_total = AICellRoles.PIPELINE_ORDER.size()

	if task.strip_edges().is_empty():
		run.finished = true
		return run

	# Önceki rolün çıktısı sonraki role bağlam olur
	# Bağlam aktarıcı — rol çıktılarını yapılandırılmış taşır
	var relay := AIContextRelay.new(task)
	run.relay = relay

	for stage_index in range(AICellRoles.PIPELINE_ORDER.size()):
		var role: int = AICellRoles.PIPELINE_ORDER[stage_index]
		var agent: AICellAgent = bus.get_agent(role)
		if agent == null:
			run.escalations += 1
			continue

		# Ajan görevi işler — bağlamı relay'den al (yapılandırılmış)
		var stage_context: Dictionary = relay.build_context_for(role)
		var result: AICellAgent.WorkResult = agent.process_task(
			task, stage_context
		)
		run.stage_results.append(result)

		# LLM gereken aşama — işaretle (sahte tamamlama yok)
		if result.status == AICellAgent.WorkStatus.NEEDS_LLM:
			run.needs_llm = true
		elif result.status == AICellAgent.WorkStatus.ESCALATED:
			run.escalations += 1

		# Kod üreten rol — reflection turundan geçmeli
		if agent.should_reflect(result):
			_run_reflection_for(agent, result)

		# Çıktıyı relay'e kaydet — yapılandırılmış, sonraki roller için
		relay.record(role, result)

		# Bir sonraki role HANDOFF mesajı
		var next_role: int = AICellRoles.next_in_pipeline(role)
		if next_role >= 0:
			bus.send_between(
				role, next_role, AICellMessage.MessageType.HANDOFF,
				"Aşama teslimi: " + agent.role_name(),
				result.summary, run.conversation_ref
			)

		run.stages_completed += 1

	run.finished = true
	return run


## Bir ajanın çıktısı için reflection oturumu yürütür.
## İskelet sürüm: tur mekanizmasını çalıştırır. Gerçek eleştiri
## (QA/Reviewer LLM) sonraki sürümde derinleşir.
func _run_reflection_for(
	agent: AICellAgent, result: AICellAgent.WorkResult
) -> void:
	reflection.begin()
	# İskelet: ilk turda "LLM gerekli" olduğu için eleştiri belirsiz —
	# boş eleştiriyle yakınsat (gerçek eleştiri LLM ister).
	# Bu, reflection tur mekanizmasının çalıştığını gösterir.
	var critique: AIReflectionLoop.Critique = reflection.make_critique(
		PackedStringArray(), AICellRoles.Role.QA_ENGINEER
	)
	reflection.submit_critique(critique)


# ============================================================
# SORGULAMA
# ============================================================

## Bir rolün ajanını döndürür.
func agent_for(role: int) -> AICellAgent:
	return bus.get_agent(role)


## Kaç ajan kayıtlı (14 olmalı).
func agent_count() -> int:
	return bus.agent_count()


## Orkestratör durum özeti.
func status() -> Dictionary:
	return {
		"agents": bus.agent_count(),
		"expected_agents": AICellRoles.role_count(),
		"bus": bus.status(),
	}


## Tüm ajanları ve veri yolunu sıfırlar.
func reset() -> void:
	bus.reset()
	reflection = AIReflectionLoop.new()
	_create_all_agents()
