@tool
class_name AIAdaptiveReasoningPolicy
extends RefCounted

## Görev karmaşıklığı, risk, belirsizlik ve uzman anlaşmazlığına göre
## bilişsel derinliği ve paralel genişliği belirler.

const MIN_DEPTH: int = 7
const DEFAULT_DEPTH: int = 10
const MAX_DEPTH: int = 13
const MIN_PARALLEL: int = 2
const MAX_PARALLEL: int = 6
const MAX_NODES: int = 36
const MAX_DEEPEN_ROUNDS: int = 2
const MAX_CORRECTION_ROUNDS: int = 2


func canonical_layers() -> Array[AICognitiveLayerProfile]:
	return [
		_layer(0, "intent_calibration", "Niyet Kalibrasyonu",
			"Kullanıcının gerçek hedefini, kısıtlarını ve başarı ölçütlerini kesinleştir.",
			false, true, 0.82, 1, [AICellRoles.Role.PRODUCT_MANAGER]),
		_layer(1, "context_grounding", "Bağlam ve Kanıt Zemini",
			"Gerçek proje bağlamı, mevcut sınıflar, API sözleşmeleri ve riskleri çıkar.",
			true, true, 0.78, 3, [
				AICellRoles.Role.ARCHITECT,
				AICellRoles.Role.DEBUG_ENGINEER,
				AICellRoles.Role.QA_ENGINEER,
			]),
		_layer(2, "strategic_council", "Stratejik Uzman Konseyi",
			"Mimari, güvenlik, test ve performans perspektiflerini paralel üret.",
			true, true, 0.76, 5, [
				AICellRoles.Role.ARCHITECT,
				AICellRoles.Role.REVIEWER,
				AICellRoles.Role.TEST_ENGINEER,
				AICellRoles.Role.PERFORMANCE_ENGINEER,
				AICellRoles.Role.QA_ENGINEER,
			]),
		_layer(3, "problem_decomposition", "Çok Ölçekli Ayrıştırma",
			"Problemi sistem, alt sistem, bileşen ve doğrulama seviyelerine böl.",
			false, true, 0.80, 1, [AICellRoles.Role.DELIVERY_MANAGER]),
		_layer(4, "hypothesis_generation", "Paralel Hipotez Üretimi",
			"Birbirinden belirgin en az üç çözüm yaklaşımı üret ve trade-off yaz.",
			true, true, 0.72, 3, [
				AICellRoles.Role.ARCHITECT,
				AICellRoles.Role.CODE_ENGINEER,
				AICellRoles.Role.DEBUG_ENGINEER,
			]),
		_layer(5, "counterfactual_analysis", "Karşı-Olgusal Analiz",
			"Her yaklaşımın başarısız olacağı koşulları ve gizli varsayımları ara.",
			true, true, 0.74, 3, [
				AICellRoles.Role.REVIEWER,
				AICellRoles.Role.QA_ENGINEER,
				AICellRoles.Role.PERFORMANCE_ENGINEER,
			]),
		_layer(6, "architecture_synthesis", "Mimari Sentez",
			"Kanıt ve eleştirileri birleştirerek uygulanabilir ana tasarımı seç.",
			false, true, 0.84, 1, [AICellRoles.Role.ARCHITECT]),
		_layer(7, "solution_candidates", "Paralel Çözüm Adayları",
			"Aynı sözleşmeye uyan bağımsız çözüm adayları üret.",
			true, true, 0.76, 3, [AICellRoles.Role.CODE_ENGINEER]),
		_layer(8, "adversarial_review", "Karşıt İnceleme ve Red Team",
			"Kod, güvenlik, performans, API ve regresyon açıklarını saldırgan biçimde ara.",
			true, true, 0.82, 5, [
				AICellRoles.Role.REVIEWER,
				AICellRoles.Role.DEBUG_ENGINEER,
				AICellRoles.Role.TEST_ENGINEER,
				AICellRoles.Role.PERFORMANCE_ENGINEER,
				AICellRoles.Role.QA_ENGINEER,
			]),
		_layer(9, "simulation", "Zihinsel Simülasyon",
			"Mutlu yol, sınır durum, hata ve mobil performans senaryolarını simüle et.",
			true, true, 0.80, 4, [
				AICellRoles.Role.TEST_ENGINEER,
				AICellRoles.Role.DEBUG_ENGINEER,
				AICellRoles.Role.PERFORMANCE_ENGINEER,
				AICellRoles.Role.QA_ENGINEER,
			]),
		_layer(10, "consensus", "Kanıt Ağırlıklı Uzlaşma",
			"Adayları güvenlik veto, test kanıtı ve güven skorlarıyla karşılaştır.",
			false, true, 0.86, 1, [AICellRoles.Role.REVIEWER]),
		_layer(11, "final_construction", "Nihai İnşa",
			"Uzlaşma kararına göre tek, eksiksiz ve doğrulanabilir artefakt üret.",
			false, true, 0.88, 1, [AICellRoles.Role.CODE_ENGINEER]),
		_layer(12, "verification_reflection", "Doğrulama ve Meta-Öğrenme",
			"Son artefaktı bağımsız doğrula; kalan belirsizliği ve öğrenilen kuralları çıkar.",
			true, true, 0.88, 4, [
				AICellRoles.Role.REVIEWER,
				AICellRoles.Role.TEST_ENGINEER,
				AICellRoles.Role.QA_ENGINEER,
				AICellRoles.Role.PERFORMANCE_ENGINEER,
			]),
	]


func assess(task: String, target_path: String, high_risk: bool = false) -> Dictionary:
	var text: String = (task + " " + target_path).to_lower()
	var complexity: float = 0.25
	complexity += minf(0.25, float(task.length()) / 4000.0)
	if _contains_any(text, ["multiplayer", "network", "server", "authority", "rpc"]):
		complexity += 0.20
	if _contains_any(text, ["architecture", "mimari", "refactor", "sistem", "framework"]):
		complexity += 0.18
	if _contains_any(text, ["performance", "optimiz", "thread", "concurrent", "parallel"]):
		complexity += 0.15
	if _contains_any(text, ["security", "secret", "permission", "delete", "sil", "project.godot"]):
		complexity += 0.18
	if high_risk:
		complexity += 0.15
	complexity = clampf(complexity, 0.0, 1.0)
	var depth: int = clampi(
		roundi(lerpf(float(MIN_DEPTH), float(MAX_DEPTH), complexity)),
		MIN_DEPTH,
		MAX_DEPTH
	)
	var parallelism: int = clampi(
		roundi(lerpf(float(MIN_PARALLEL), float(MAX_PARALLEL), complexity)),
		MIN_PARALLEL,
		MAX_PARALLEL
	)
	return {
		"complexity": complexity,
		"depth": depth,
		"parallelism": parallelism,
		"max_nodes": MAX_NODES,
		"max_deepen_rounds": MAX_DEEPEN_ROUNDS,
		"max_correction_rounds": MAX_CORRECTION_ROUNDS,
		"force_red_team": high_risk or complexity >= 0.65,
	}


func should_deepen(
	average_confidence: float,
	disagreement: float,
	failed_nodes: int,
	deepen_round: int
) -> bool:
	if deepen_round >= MAX_DEEPEN_ROUNDS:
		return false
	return (
		average_confidence < 0.78
		or disagreement > 0.35
		or failed_nodes > 0
	)


func _layer(
	index: int,
	id: String,
	title: String,
	purpose: String,
	parallel: bool,
	mandatory: bool,
	confidence: float,
	branches: int,
	roles: Array[int]
) -> AICognitiveLayerProfile:
	return AICognitiveLayerProfile.create(
		index, id, title, purpose, parallel, mandatory,
		confidence, branches, roles
	)


func _contains_any(text: String, terms: Array) -> bool:
	for term_value in terms:
		if text.contains(str(term_value)):
			return true
	return false
