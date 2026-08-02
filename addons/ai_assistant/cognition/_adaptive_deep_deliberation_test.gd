@tool
class_name AIAdaptiveDeepDeliberationTest
extends RefCounted

## Faz 12–13 — adaptif düşünme grafiği ile tek ekran canlı ajan ve
## gerçek Godot artefakt sözleşmeleri için 52 deterministik test.


static func run_all() -> Array:
	var results: Array = []
	results.append_array(_policy_tests())
	results.append_array(_graph_tests())
	results.append_array(_execution_and_deepening_tests())
	results.append_array(_consensus_tests())
	results.append_array(_runner_contract_tests())
	results.append_array(AIPhase13LiveWorkspaceTest.run_all())
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray(["=== Adaptive Deep Deliberation Test Sonuçları ==="])
	var batch: String = ""
	for result in results:
		if str(result["batch"]) != batch:
			batch = str(result["batch"])
			lines.append("--- %s ---" % batch)
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append("--- %d geçti, %d başarısız (toplam %d) ---" % [
		passed, failed, results.size()
	])
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _policy_tests() -> Array:
	var policy := AIAdaptiveReasoningPolicy.new()
	var layers: Array[AICognitiveLayerProfile] = policy.canonical_layers()
	var simple: Dictionary = policy.assess("Basit player kodu", "res://game/player.gd")
	var hard: Dictionary = policy.assess(
		"Multiplayer server authority, parallel performance ve security architecture refactor",
		"res://game/network.gd", true
	)
	var sequential_indices: bool = true
	for index in layers.size():
		if layers[index].index != index:
			sequential_indices = false
			break
	return [
		_b("Politika", _check("21 bilişsel katman tanımlı", layers.size() == 21)),
		_b("Politika", _check("Katman indeksleri kesintisiz", sequential_indices)),
		_b("Politika", _check("Başlangıç derinliği 13", int(simple["depth"]) == 13)),
		_b("Politika", _check("Yüksek risk potansiyel derinliği 21", int(hard["potential_depth"]) == 21)),
		_b("Politika", _check("Paralellik 3–6 arasında", int(hard["parallelism"]) >= 3 and int(hard["parallelism"]) <= 6)),
		_b("Politika", _check("Düşük güven derinleşmeyi tetikler", policy.should_deepen(0.60, 0.10, 0, 0))),
		_b("Politika", _check("Yüksek anlaşmazlık derinleşmeyi tetikler", policy.should_deepen(0.90, 0.50, 0, 0))),
		_b("Politika", _check("İki turdan sonra derinleşme durur", not policy.should_deepen(0.10, 1.0, 2, 2, true))),
	]


static func _graph_tests() -> Array:
	var graph := AIAdaptiveDeliberationGraph.new()
	var built: Dictionary = graph.build(
		"Akıllı paralel ajan sistemi kur",
		"res://game/agent_system.gd",
		"full",
		true
	)
	var initial: Array[AIDeliberationNode] = graph.ready_nodes(16)
	var initial_ok: bool = (
		initial.size() == 1
		and initial[0].role == AICellRoles.Role.PRODUCT_MANAGER
		and initial[0].layer_index == 0
	)
	_complete_nodes(graph, initial)
	var context_ready: Array[AIDeliberationNode] = graph.ready_nodes(16)
	var context_ok: bool = context_ready.size() == 3 and _all_layer(context_ready, 1)
	_complete_nodes(graph, context_ready)
	var council_ready: Array[AIDeliberationNode] = graph.ready_nodes(16)
	var council_ok: bool = council_ready.size() == 5 and _all_layer(council_ready, 2)
	var candidate_count: int = _count_kind(graph, "solution_candidate")
	var verify_count: int = _count_kind(graph, "final_verification")
	var final_kind: String = str(graph.node(graph.final_node_id()).node_kind)
	return [
		_b("Grafik", _check("Grafik başarıyla kurulur", bool(built["ok"]))),
		_b("Grafik", _check("Başlangıç grafiği 35 düğüm", int(built["nodes"]) == 35)),
		_b("Grafik", _check("Grafik cycle/dependency doğrulamasından geçer", bool(graph.validate()["ok"]), str(graph.validate()["errors"]))),
		_b("Grafik", _check("İlk dalga yalnız niyet kalibrasyonu", initial_ok)),
		_b("Grafik", _check("Niyet sonrası üç context ajanı paralel hazır", context_ok)),
		_b("Grafik", _check("Context sonrası beş uzman konseyi paralel hazır", council_ok)),
		_b("Grafik", _check("Üç bağımsız çözüm adayı vardır", candidate_count == 3)),
		_b("Grafik", _check("Dört bağımsız final doğrulayıcı vardır", verify_count == 4)),
		_b("Grafik", _check("Nihai düğüm final_generation türündedir", final_kind == "final_generation")),
		_b("Grafik", _check("Hedef paralellik en az beş genişliğe ulaşır", int(graph.metrics()["peak_parallel_ready"]) >= 5)),
	]


static func _execution_and_deepening_tests() -> Array:
	var graph := AIAdaptiveDeliberationGraph.new()
	graph.build("Derin sistem üret", "res://game/deep.gd", "full", true)
	var progressed: bool = _complete_graph(graph)
	var base_metrics: Dictionary = graph.metrics()
	var base_output: String = graph.final_output()
	var base_verifications: int = graph.verification_outputs().size()
	var round_one: Dictionary = graph.append_deepening_round("uzman anlaşmazlığı")
	var round_one_valid: bool = bool(round_one["ok"]) and bool(graph.validate()["ok"])
	var round_one_progressed: bool = _complete_graph(graph)
	var round_one_metrics: Dictionary = graph.metrics()
	var round_two: Dictionary = graph.append_deepening_round("security veto")
	var round_two_valid: bool = bool(round_two["ok"]) and bool(graph.validate()["ok"])
	var round_two_progressed: bool = _complete_graph(graph)
	var round_two_metrics: Dictionary = graph.metrics()
	var round_three: Dictionary = graph.append_deepening_round("sonsuz olmasın")
	return [
		_b("Derinleşme", _check("Dependency dalgaları terminale kadar ilerler", progressed and graph.all_terminal())),
		_b("Derinleşme", _check("Temel final çıktı üretilir", not base_output.is_empty())),
		_b("Derinleşme", _check("Temel doğrulama konseyi dört çıktı verir", base_verifications == 4)),
		_b("Derinleşme", _check("Temel metrik derinliği 13", int(base_metrics["depth"]) == 13)),
		_b("Derinleşme", _check("Birinci meta tur geçerli eklenir", round_one_valid and round_one_progressed)),
		_b("Derinleşme", _check("Birinci meta tur derinliği 17", int(round_one_metrics["depth"]) == 17)),
		_b("Derinleşme", _check("İkinci meta tur geçerli eklenir", round_two_valid and round_two_progressed)),
		_b("Derinleşme", _check("İkinci meta tur derinliği 21", int(round_two_metrics["depth"]) == 21)),
		_b("Derinleşme", _check("Üçüncü meta tur reddedilir", not bool(round_three.get("ok", true)))),
		_b("Derinleşme", _check("Toplam düğüm bütçesi 64'ü aşmaz", int(round_two_metrics["nodes"]) <= 64)),
	]


static func _consensus_tests() -> Array:
	var engine := AIEvidenceConsensusEngine.new()
	var empty: Dictionary = engine.evaluate([])
	var reviewer_conf: float = engine.confidence_from_output(
		"PASS. Test kanıtı ve risk trade-off analizi doğrulandı. " + "kanıt ".repeat(60),
		"Reviewer"
	)
	var code_conf: float = engine.confidence_from_output(
		"PASS. Test kanıtı ve risk trade-off analizi doğrulandı. " + "kanıt ".repeat(60),
		"CodeEngineer"
	)
	var good_nodes: Array[AIDeliberationNode] = [
		_completed_review("r1", AICellRoles.Role.REVIEWER, "PASS: güvenlik ve API testleri geçti", 0.92),
		_completed_review("r2", AICellRoles.Role.TEST_ENGINEER, "PASS: contract ve concurrency testleri geçti", 0.90),
		_completed_review("r3", AICellRoles.Role.QA_ENGINEER, "PASS: kabul kriterleri karşılandı", 0.91),
	]
	var good: Dictionary = engine.evaluate(good_nodes)
	var veto_nodes: Array[AIDeliberationNode] = good_nodes.duplicate()
	veto_nodes.append(_completed_review(
		"rv", AICellRoles.Role.REVIEWER,
		"FAIL: kritik security permission ve secret sızıntısı", 0.95
	))
	var veto: Dictionary = engine.evaluate(veto_nodes)
	var disagreement_nodes: Array[AIDeliberationNode] = [
		_completed_review("d1", AICellRoles.Role.REVIEWER, "PASS", 0.95),
		_completed_review("d2", AICellRoles.Role.TEST_ENGINEER, "FAIL", 0.20),
	]
	var disagreement: Dictionary = engine.evaluate(disagreement_nodes)
	return [
		_b("Uzlaşma", _check("Boş konsey güven üretmez", float(empty["confidence"]) == 0.0)),
		_b("Uzlaşma", _check("Reviewer kanıtı CodeEngineer'dan daha ağırdır", reviewer_conf > code_conf)),
		_b("Uzlaşma", _check("Üç PASS yüksek pass_ratio üretir", float(good["pass_ratio"]) == 1.0)),
		_b("Uzlaşma", _check("Yüksek güvenli konsey kabul edilir", engine.should_accept(good))),
		_b("Uzlaşma", _check("Security FAIL veto üretir", bool(veto["security_veto"]))),
		_b("Uzlaşma", _check("Security veto kabul edilmez", not engine.should_accept(veto))),
		_b("Uzlaşma", _check("Zıt uzman görüşleri anlaşmazlık üretir", float(disagreement["disagreement"]) > 0.25)),
		_b("Uzlaşma", _check("FAIL sayısı raporlanır", int(veto["failed_reviews"]) == 1)),
	]


static func _runner_contract_tests() -> Array:
	var runner := AIAdaptiveRoleGraphRunner.new()
	var path_ok: bool = runner._extract_target_path(
		"ALT GÖREV\nHEDEF DOSYA: res://game/player.gd\n"
	) == "res://game/player.gd"
	var risk_ok: bool = runner._is_high_risk(
		"Multiplayer server permission ve secret sistemi"
	)
	var snapshot: Dictionary = runner.graph_snapshot()
	runner.free()
	return [
		_b("Runner", _check("Worker havuzu üst sınırı 6", AIAdaptiveRoleGraphRunner.MAX_WORKERS == 6)),
		_b("Runner", _check("Bütün roller V4 Pro modeline zorlanır", AIAdaptiveRoleGraphRunner.MAX_MODEL == "deepseek-v4-pro")),
		_b("Runner", _check("Hedef dosya talimattan çıkarılır", path_ok)),
		_b("Runner", _check("Yüksek riskli görev algılanır", risk_ok)),
	]


static func _complete_graph(graph: AIAdaptiveDeliberationGraph) -> bool:
	var guard: int = 0
	while not graph.all_terminal() and guard < 100:
		guard += 1
		var ready: Array[AIDeliberationNode] = graph.ready_nodes(64)
		if ready.is_empty():
			return false
		_complete_nodes(graph, ready)
	return graph.all_terminal()


static func _complete_nodes(
	graph: AIAdaptiveDeliberationGraph,
	nodes: Array[AIDeliberationNode]
) -> void:
	for current in nodes:
		graph.mark_running(current.node_id)
		var output: String = "Kanıt ve trade-off içeren tamamlanmış analiz."
		if current.node_kind == "final_generation":
			output = "extends Node\n\nfunc _ready() -> void:\n\tpass\n"
		elif current.node_kind == "final_verification":
			output = "PASS: contract, security ve performans kanıtı doğrulandı."
		graph.mark_completed(current.node_id, output, 0.90)


static func _count_kind(graph: AIAdaptiveDeliberationGraph, kind: String) -> int:
	var count: int = 0
	for item in graph.all_nodes():
		if str(item["node_kind"]) == kind:
			count += 1
	return count


static func _all_layer(nodes: Array[AIDeliberationNode], layer: int) -> bool:
	for current in nodes:
		if current.layer_index != layer:
			return false
	return true


static func _completed_review(
	id: String, role: int, output: String, confidence: float
) -> AIDeliberationNode:
	var layer := AICognitiveLayerProfile.create(
		12, "verification", "Verification", "test", true, true,
		0.8, 4, [role]
	)
	var current := AIDeliberationNode.create(
		id, layer, "final_verification", role, "Review", "Review prompt"
	)
	current.mark_running()
	current.mark_completed(output, confidence)
	return current


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _check(name: String, ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "name": name, "reason": reason if not ok else ""}
