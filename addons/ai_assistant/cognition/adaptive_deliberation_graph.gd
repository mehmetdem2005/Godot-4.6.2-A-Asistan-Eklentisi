@tool
class_name AIAdaptiveDeliberationGraph
extends RefCounted

## 13 temel + iki meta turla 21 katmana derinleşebilen, bağımlılık tabanlı
## düşünme DAG'ı. Global sıra yoktur; yalnız gerçek dependency'ler beklenir.

var policy: AIAdaptiveReasoningPolicy = null
var task: String = ""
var target_path: String = ""
var mode: String = "full"
var high_risk: bool = false
var assessment: Dictionary = {}
var layers: Array[AICognitiveLayerProfile] = []

var _nodes: Dictionary = {}
var _node_order: PackedStringArray = PackedStringArray()
var _sequence: int = 0
var _deepen_round: int = 0
var _final_node_id: String = ""
var _peak_parallel_ready: int = 0


func _init(reasoning_policy: AIAdaptiveReasoningPolicy = null) -> void:
	policy = reasoning_policy if reasoning_policy != null else AIAdaptiveReasoningPolicy.new()
	layers = policy.canonical_layers()


func build(
	root_task: String,
	path: String = "",
	run_mode: String = "full",
	is_high_risk: bool = false
) -> Dictionary:
	reset()
	task = root_task.strip_edges()
	target_path = path.strip_edges()
	mode = run_mode.strip_edges()
	high_risk = is_high_risk
	assessment = policy.assess(task, target_path, high_risk)
	if task.is_empty():
		return {"ok": false, "reason": "görev boş"}

	var intent := _add(
		0, "intent", "intent_calibration", AICellRoles.Role.PRODUCT_MANAGER,
		"Niyeti ve başarı ölçütlerini kalibre et",
		"Kullanıcının gerçek hedefini, açık ve örtük kısıtları, kabul kriterlerini, başarısızlık koşullarını ve belirsiz noktaları çıkar. Çözüm üretme; problemi kesinleştir.",
		[]
	)
	var context_ids: Array = []
	context_ids.append(_add(
		1, "context_arch", "grounding", AICellRoles.Role.ARCHITECT,
		"Mevcut mimari ve API zemini",
		"Gerçek Godot 4.6.3 mimari sözleşmelerini, bağımlılıkları ve entegrasyon sınırlarını çıkar. Uydurma API kullanma.",
		[intent.node_id]
	).node_id)
	context_ids.append(_add(
		1, "context_debug", "grounding", AICellRoles.Role.DEBUG_ENGINEER,
		"Hata ve kırılganlık zemini",
		"Muhtemel hata yüzeylerini, mevcut davranışla çakışmaları ve teşhis için gerekli kanıtları çıkar.",
		[intent.node_id]
	).node_id)
	context_ids.append(_add(
		1, "context_qa", "grounding", AICellRoles.Role.QA_ENGINEER,
		"Kalite ve kabul zemini",
		"Test edilebilir kabul kriterleri, regresyon sınırları ve kanıt gereksinimlerini çıkar.",
		[intent.node_id]
	).node_id)

	var council_ids: Array = []
	council_ids.append(_add(
		2, "council_arch", "council", AICellRoles.Role.ARCHITECT,
		"Mimari konsey görüşü",
		"Uzun vadeli mimari, modülerlik, ölçeklenebilirlik ve Godot entegrasyonu açısından çözüm ilkelerini öner.",
		context_ids
	).node_id)
	council_ids.append(_add(
		2, "council_review", "council", AICellRoles.Role.REVIEWER,
		"Bağımsız eleştiri görüşü",
		"Yanlış varsayım, aşırı karmaşıklık, yetki ihlali ve bakım riski açısından yaklaşımı sorgula.",
		context_ids
	).node_id)
	council_ids.append(_add(
		2, "council_test", "council", AICellRoles.Role.TEST_ENGINEER,
		"Test stratejisi görüşü",
		"Unit, contract, integration, concurrency ve failure-injection test stratejisini öner.",
		context_ids
	).node_id)
	council_ids.append(_add(
		2, "council_perf", "council", AICellRoles.Role.PERFORMANCE_ENGINEER,
		"Performans görüşü",
		"Mobil CPU, bellek, ağ, token maliyeti ve bounded concurrency açısından darboğazları çıkar.",
		context_ids
	).node_id)
	council_ids.append(_add(
		2, "council_qa", "council", AICellRoles.Role.QA_ENGINEER,
		"Risk ve kabul görüşü",
		"Release bloklayıcı riskleri, güvenlik veto koşullarını ve ölçülebilir kalite eşiğini tanımla.",
		context_ids
	).node_id)

	var decomposition := _add(
		3, "decomposition", "decomposition", AICellRoles.Role.DELIVERY_MANAGER,
		"Çok ölçekli görev ayrıştırması",
		"Problemi sistem → alt sistem → bileşen → değişiklik → test → kanıt seviyelerinde bağımlılık DAG'ına ayır. Sadece gerçek bağımlılıkları belirt.",
		council_ids
	)

	var hypothesis_ids: Array = []
	hypothesis_ids.append(_add(
		4, "hypothesis_arch", "hypothesis", AICellRoles.Role.ARCHITECT,
		"Hipotez A — mimari sadelik",
		"Minimum coupling ve net sınırlarla bir çözüm hipotezi üret. Trade-off ve başarısızlık koşullarını açıkla.",
		[decomposition.node_id], "solution_hypotheses"
	).node_id)
	hypothesis_ids.append(_add(
		4, "hypothesis_engineering", "hypothesis", AICellRoles.Role.CODE_ENGINEER,
		"Hipotez B — uygulama verimliliği",
		"En az kod riskiyle uygulanabilir alternatif çözüm üret. API, state ve veri akışını belirt.",
		[decomposition.node_id], "solution_hypotheses"
	).node_id)
	hypothesis_ids.append(_add(
		4, "hypothesis_failure", "hypothesis", AICellRoles.Role.DEBUG_ENGINEER,
		"Hipotez C — failure-first tasarım",
		"Önce hata senaryolarını modelleyerek dayanıklı bir alternatif çözüm üret.",
		[decomposition.node_id], "solution_hypotheses"
	).node_id)

	var counter_ids: Array = []
	counter_ids.append(_add(
		5, "counter_reviewer", "counterfactual", AICellRoles.Role.REVIEWER,
		"Şeytanın avukatı",
		"Üç hipotezin gizli varsayımlarını çürüt; hangi koşulda her biri başarısız olur açıkla.",
		hypothesis_ids
	).node_id)
	counter_ids.append(_add(
		5, "counter_qa", "counterfactual", AICellRoles.Role.QA_ENGINEER,
		"Kabul kriteri karşı testi",
		"Hipotezleri kabul kriterlerine karşı saldırgan biçimde test et; kanıtsız iddiaları işaretle.",
		hypothesis_ids
	).node_id)
	counter_ids.append(_add(
		5, "counter_perf", "counterfactual", AICellRoles.Role.PERFORMANCE_ENGINEER,
		"Ölçek ve maliyet karşı testi",
		"Hipotezlerin mobil performans, paralellik, token ve bellek maliyetlerinde nerede çökeceğini ara.",
		hypothesis_ids
	).node_id)

	var synthesis := _add(
		6, "architecture_synthesis", "synthesis", AICellRoles.Role.ARCHITECT,
		"Kanıt ağırlıklı mimari sentez",
		"Hipotezler ve karşı testleri birleştir. Tek bir yaklaşımı kör seçme; güçlü parçaları sentezle, reddedilen seçenekleri ve gerekçeyi yaz.",
		counter_ids
	)

	var candidate_ids: Array = []
	for index in 3:
		candidate_ids.append(_add(
			7,
			"candidate_%d" % (index + 1),
			"solution_candidate",
			AICellRoles.Role.CODE_ENGINEER,
			"Bağımsız çözüm adayı %d" % (index + 1),
			"Mimari senteze uyan bağımsız, eksiksiz ve uygulanabilir çözüm üret. Diğer adayları görmeden kendi yaklaşımını kur. Hedef artefaktı tam ver.",
			[synthesis.node_id],
			"implementation_candidates"
		).node_id)

	var adversarial_ids: Array = []
	var adversarial_roles: Array[int] = [
		AICellRoles.Role.REVIEWER,
		AICellRoles.Role.DEBUG_ENGINEER,
		AICellRoles.Role.TEST_ENGINEER,
		AICellRoles.Role.PERFORMANCE_ENGINEER,
		AICellRoles.Role.QA_ENGINEER,
	]
	var adversarial_titles: Array[String] = [
		"Kod ve mimari red team",
		"Failure injection incelemesi",
		"Test kapsama saldırısı",
		"Mobil performans saldırısı",
		"Kabul ve güvenlik veto incelemesi",
	]
	for index in adversarial_roles.size():
		adversarial_ids.append(_add(
			8,
			"adversarial_%d" % (index + 1),
			"adversarial_review",
			adversarial_roles[index],
			adversarial_titles[index],
			"Bütün çözüm adaylarını karşılaştır. Somut kusur, kanıt, önem derecesi ve düzeltme önerisi ver. Kolay PASS verme.",
			candidate_ids
		).node_id)

	var simulation_ids: Array = []
	var simulation_roles: Array[int] = [
		AICellRoles.Role.TEST_ENGINEER,
		AICellRoles.Role.DEBUG_ENGINEER,
		AICellRoles.Role.PERFORMANCE_ENGINEER,
		AICellRoles.Role.QA_ENGINEER,
	]
	var simulation_prompts: Array[String] = [
		"Mutlu yol, sınır değer ve regresyon senaryolarını zihinsel olarak çalıştır; beklenen sonuçları yaz.",
		"Timeout, null, eksik dosya, yarış durumu ve kısmi başarısızlık senaryolarını simüle et.",
		"Düşük seviye Android cihaz, uzun LLM yanıtı ve yoğun görev grafiği altında kaynak davranışını simüle et.",
		"Kullanıcı kabul kriterleri ve güvenlik sınırlarına göre release kararı simüle et.",
	]
	for index in simulation_roles.size():
		simulation_ids.append(_add(
			9,
			"simulation_%d" % (index + 1),
			"simulation",
			simulation_roles[index],
			"Simülasyon %d" % (index + 1),
			simulation_prompts[index],
			candidate_ids + adversarial_ids
		).node_id)

	var consensus := _add(
		10, "consensus", "consensus", AICellRoles.Role.REVIEWER,
		"Kanıt ağırlıklı uzlaşma",
		"Adayları güvenlik veto, test kanıtı, performans, doğruluk ve bakım maliyetine göre puanla. Kazananı, alınacak parçaları ve zorunlu düzeltmeleri açıkça seç.",
		adversarial_ids + simulation_ids
	)
	var final_node := _add(
		11, "final_construction", "final_generation", AICellRoles.Role.CODE_ENGINEER,
		"Nihai artefakt üretimi",
		"Uzlaşma kararına ve bütün zorunlu düzeltmelere göre tek, tam, Godot 4.6.3 uyumlu nihai artefakt üret. Açıklama yerine doğrudan uygulanabilir çıktı ver.",
		[consensus.node_id] + candidate_ids
	)
	_final_node_id = final_node.node_id

	var verification_ids: Array = []
	var verify_roles: Array[int] = [
		AICellRoles.Role.REVIEWER,
		AICellRoles.Role.TEST_ENGINEER,
		AICellRoles.Role.QA_ENGINEER,
		AICellRoles.Role.PERFORMANCE_ENGINEER,
	]
	for index in verify_roles.size():
		verification_ids.append(_add(
			12,
			"verification_%d" % (index + 1),
			"final_verification",
			verify_roles[index],
			"Nihai bağımsız doğrulama %d" % (index + 1),
			"Nihai artefaktı bağımsız doğrula. PASS veya FAIL ile başla; somut hata, kanıt ve zorunlu düzeltmeleri yaz.",
			[final_node.node_id]
		).node_id)

	var validation: Dictionary = validate()
	return {
		"ok": bool(validation["ok"]),
		"reason": str(validation.get("errors", [])),
		"nodes": _nodes.size(),
		"depth": 13,
		"parallelism": int(assessment.get("parallelism", 4)),
		"verification_nodes": verification_ids,
	}


func reset() -> void:
	_nodes.clear()
	_node_order.clear()
	_sequence = 0
	_deepen_round = 0
	_final_node_id = ""
	_peak_parallel_ready = 0


func node(node_id: String) -> AIDeliberationNode:
	return _nodes.get(node_id) as AIDeliberationNode


func all_nodes() -> Array:
	var out: Array = []
	for node_id in _node_order:
		out.append((node(node_id) as AIDeliberationNode).to_dict())
	return out


func ready_nodes(limit: int = 6) -> Array[AIDeliberationNode]:
	var ready: Array[AIDeliberationNode] = []
	for node_id in _node_order:
		var current := node(node_id)
		if current.state != AIDeliberationNode.STATE_PENDING:
			continue
		if _dependencies_terminal(current):
			ready.append(current)
	_peak_parallel_ready = maxi(_peak_parallel_ready, ready.size())
	if ready.size() > clampi(limit, 1, 16):
		ready.resize(clampi(limit, 1, 16))
	return ready


func context_for(node_id: String, max_chars: int = 180000) -> Dictionary:
	var current := node(node_id)
	if current == null:
		return {}
	var context: Dictionary = {
		"bilişsel_katman": current.layer_id,
		"katman_indeksi": current.layer_index,
		"ana_görev": task,
		"hedef_dosya": target_path,
		"çalışma_modu": mode,
		"öncül_çıktılar": [],
	}
	var used: int = 0
	var dependency_outputs: Array = []
	for dependency_id in current.dependencies:
		var dependency := node(dependency_id)
		if dependency == null:
			continue
		var output: String = dependency.output
		var remaining: int = maxi(0, max_chars - used)
		if remaining == 0:
			break
		if output.length() > remaining:
			output = output.left(remaining)
		dependency_outputs.append({
			"node_id": dependency.node_id,
			"layer": dependency.layer_id,
			"role": AICellRoles.role_name(dependency.role),
			"state": dependency.state,
			"confidence": dependency.confidence,
			"output": output,
			"failure_reason": dependency.failure_reason,
		})
		used += output.length()
	context["öncül_çıktılar"] = dependency_outputs
	return context


func mark_running(node_id: String) -> bool:
	var current := node(node_id)
	return current != null and current.mark_running()


func mark_completed(node_id: String, output: String, confidence: float) -> bool:
	var current := node(node_id)
	return current != null and current.mark_completed(output, confidence)


func mark_failed(node_id: String, reason: String) -> bool:
	var current := node(node_id)
	return current != null and current.mark_failed(reason)


func all_terminal() -> bool:
	if _nodes.is_empty():
		return false
	for value in _nodes.values():
		if not (value as AIDeliberationNode).is_terminal():
			return false
	return true


func has_running() -> bool:
	for value in _nodes.values():
		if (value as AIDeliberationNode).state == AIDeliberationNode.STATE_RUNNING:
			return true
	return false


func final_output() -> String:
	var final_node := node(_final_node_id)
	return "" if final_node == null else final_node.output


func final_node_id() -> String:
	return _final_node_id


func failed_count() -> int:
	var count: int = 0
	for value in _nodes.values():
		if (value as AIDeliberationNode).state == AIDeliberationNode.STATE_FAILED:
			count += 1
	return count


func completed_nodes() -> Array[AIDeliberationNode]:
	var out: Array[AIDeliberationNode] = []
	for node_id in _node_order:
		var current := node(node_id)
		if current.state == AIDeliberationNode.STATE_COMPLETED:
			out.append(current)
	return out


func average_confidence() -> float:
	var completed: Array[AIDeliberationNode] = completed_nodes()
	if completed.is_empty():
		return 0.0
	var total: float = 0.0
	for current in completed:
		total += current.confidence
	return total / float(completed.size())


func verification_outputs() -> Array:
	var out: Array = []
	for node_id in _node_order:
		var current := node(node_id)
		if current.node_kind == "final_verification" and current.state == AIDeliberationNode.STATE_COMPLETED:
			out.append(current.to_dict())
	return out


func append_deepening_round(reason: String) -> Dictionary:
	if _deepen_round >= AIAdaptiveReasoningPolicy.MAX_DEEPEN_ROUNDS:
		return {"ok": false, "reason": "derinleşme sınırı"}
	if _nodes.size() + 8 > AIAdaptiveReasoningPolicy.MAX_NODES:
		return {"ok": false, "reason": "düğüm bütçesi"}
	_deepen_round += 1
	var round: int = _deepen_round
	var base_layer: int = 13 + (round - 1) * 4
	var previous_final: String = _final_node_id
	var probe_ids: Array = []
	probe_ids.append(_add(
		base_layer,
		"deep_skeptic_%d" % round,
		"meta_skeptic",
		AICellRoles.Role.REVIEWER,
		"Derin skeptic turu %d" % round,
		"Önceki nihai çözümün yanlış olabileceğini varsay. En güçlü karşı kanıtı, model hatasını ve kaçırılan varsayımları bul. Derinleşme nedeni: " + reason,
		[previous_final]
	).node_id)
	probe_ids.append(_add(
		base_layer,
		"deep_alternative_%d" % round,
		"meta_alternative",
		AICellRoles.Role.ARCHITECT,
		"Alternatif paradigma turu %d" % round,
		"Önceki çözümden yapısal olarak farklı, daha güvenli bir paradigma üret ve hangi kanıtla üstün olduğunu açıkla.",
		[previous_final]
	).node_id)
	probe_ids.append(_add(
		base_layer,
		"deep_test_%d" % round,
		"meta_test",
		AICellRoles.Role.TEST_ENGINEER,
		"Derin test turu %d" % round,
		"Önceki çözümü çürütecek property-based, concurrency ve failure-injection senaryoları üret.",
		[previous_final]
	).node_id)
	var synth := _add(
		base_layer + 1,
		"deep_synthesis_%d" % round,
		"meta_synthesis",
		AICellRoles.Role.ARCHITECT,
		"Paradigma-üstü yeniden sentez %d" % round,
		"Skeptic, alternatif ve test kanıtlarını birleştirerek önceki çözümden daha güçlü ve gerekçeli bir karar üret.",
		probe_ids
	)
	var revised := _add(
		base_layer + 2,
		"deep_final_%d" % round,
		"final_generation",
		AICellRoles.Role.CODE_ENGINEER,
		"Derinleştirilmiş nihai artefakt %d" % round,
		"Yeniden senteze göre nihai artefaktı baştan değerlendir ve tam, uygulanabilir çıktıyı üret.",
		[synth.node_id, previous_final]
	)
	_final_node_id = revised.node_id
	var roles: Array[int] = [
		AICellRoles.Role.REVIEWER,
		AICellRoles.Role.TEST_ENGINEER,
		AICellRoles.Role.QA_ENGINEER,
	]
	for index in roles.size():
		_add(
			base_layer + 3,
			"deep_verify_%d_%d" % [round, index + 1],
			"final_verification",
			roles[index],
			"Derin final doğrulama %d.%d" % [round, index + 1],
			"Revize artefaktı bağımsız doğrula. PASS/FAIL, kanıt ve kalan riskleri ver.",
			[revised.node_id]
		)
	return {
		"ok": true,
		"round": round,
		"depth": 13 + round * 4,
		"final_node_id": revised.node_id,
	}


func metrics() -> Dictionary:
	var states: Dictionary = {}
	for value in _nodes.values():
		var state: String = (value as AIDeliberationNode).state
		states[state] = int(states.get(state, 0)) + 1
	return {
		"nodes": _nodes.size(),
		"depth": 13 + _deepen_round * 4,
		"deepen_rounds": _deepen_round,
		"peak_parallel_ready": _peak_parallel_ready,
		"average_confidence": average_confidence(),
		"failed": failed_count(),
		"states": states,
		"final_node_id": _final_node_id,
	}


func validate() -> Dictionary:
	var errors := PackedStringArray()
	if _nodes.is_empty():
		errors.append("grafik boş")
	for node_id in _node_order:
		var current := node(node_id)
		var node_validation: Dictionary = current.validate()
		if not bool(node_validation["ok"]):
			errors.append("%s: %s" % [node_id, str(node_validation["errors"])])
		for dependency_id in current.dependencies:
			if not _nodes.has(dependency_id):
				errors.append("eksik dependency: %s -> %s" % [node_id, dependency_id])
			elif node(dependency_id).layer_index > current.layer_index:
				errors.append("gelecek katmana bağımlılık: %s -> %s" % [node_id, dependency_id])
		if _has_cycle_from(node_id, {}, {}):
			errors.append("cycle: " + node_id)
	return {"ok": errors.is_empty(), "errors": Array(errors)}


func _add(
	layer_index: int,
	id_suffix: String,
	kind: String,
	role: int,
	title: String,
	prompt: String,
	deps: Array = [],
	group: String = ""
) -> AIDeliberationNode:
	_sequence += 1
	var layer: AICognitiveLayerProfile = layers[layer_index]
	var id: String = "d%02d-%03d-%s" % [layer_index, _sequence, id_suffix]
	var current := AIDeliberationNode.create(
		id, layer, kind, role, title, prompt, deps, group
	)
	_nodes[id] = current
	_node_order.append(id)
	return current


func _dependencies_terminal(current: AIDeliberationNode) -> bool:
	for dependency_id in current.dependencies:
		var dependency := node(dependency_id)
		if dependency == null or not dependency.is_terminal():
			return false
	return true


func _has_cycle_from(
	node_id: String,
	visiting: Dictionary,
	visited: Dictionary
) -> bool:
	if visiting.has(node_id):
		return true
	if visited.has(node_id):
		return false
	visiting[node_id] = true
	var current := node(node_id)
	if current != null:
		for dependency_id in current.dependencies:
			if _has_cycle_from(dependency_id, visiting, visited):
				return true
	visiting.erase(node_id)
	visited[node_id] = true
	return false
