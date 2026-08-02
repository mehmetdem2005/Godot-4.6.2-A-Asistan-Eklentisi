@tool
class_name AIEvidenceConsensusEngine
extends RefCounted

## Metin çıktılarını kör çoğunlukla değil; rol güvenilirliği, somut kanıt,
## güvenlik veto ve uzman anlaşmazlığıyla değerlendirir.

const ROLE_WEIGHTS: Dictionary = {
	"Reviewer": 1.20,
	"QAEngineer": 1.15,
	"TestEngineer": 1.15,
	"DebugEngineer": 1.10,
	"PerformanceEngineer": 1.05,
	"Architect": 1.10,
	"CodeEngineer": 0.95,
	"ProductManager": 0.90,
	"DeliveryManager": 0.90,
}


func confidence_from_output(output: String, role_name: String = "") -> float:
	var text: String = output.strip_edges()
	if text.is_empty():
		return 0.0
	var lower: String = text.to_lower()
	var score: float = 0.58
	if _contains_any(lower, ["kanıt", "evidence", "test", "çünkü", "because"]):
		score += 0.08
	if _contains_any(lower, ["trade-off", "risk", "risk:", "varsayım", "assumption"]):
		score += 0.06
	if _contains_any(lower, ["pass", "doğrulandı", "uyumlu"]):
		score += 0.05
	if _contains_any(lower, ["fail", "kritik", "critical", "güvenlik açığı"]):
		score -= 0.08
	if _contains_any(lower, ["emin değil", "belirsiz", "unknown", "muhtemelen"]):
		score -= 0.08
	if text.length() > 1200:
		score += 0.04
	elif text.length() < 120:
		score -= 0.10
	var weight: float = float(ROLE_WEIGHTS.get(role_name, 1.0))
	return clampf(score * weight, 0.05, 0.98)


func evaluate(nodes: Array[AIDeliberationNode]) -> Dictionary:
	var completed: Array[AIDeliberationNode] = []
	for current in nodes:
		if current.state == AIDeliberationNode.STATE_COMPLETED:
			completed.append(current)
	if completed.is_empty():
		return {
			"confidence": 0.0,
			"disagreement": 1.0,
			"security_veto": false,
			"pass_ratio": 0.0,
			"failed_reviews": 0,
		}
	var weighted_total: float = 0.0
	var total_weight: float = 0.0
	var pass_count: int = 0
	var fail_count: int = 0
	var security_veto: bool = false
	var opinions: Array[float] = []
	for current in completed:
		var role_name: String = AICellRoles.role_name(current.role)
		var confidence: float = current.confidence
		if confidence <= 0.0:
			confidence = confidence_from_output(current.output, role_name)
		var weight: float = float(ROLE_WEIGHTS.get(role_name, 1.0))
		weighted_total += confidence * weight
		total_weight += weight
		opinions.append(confidence)
		var upper: String = current.output.to_upper()
		var explicit_fail: bool = upper.contains("FAIL") and not upper.contains("PASS")
		var explicit_pass: bool = upper.contains("PASS") and not explicit_fail
		if explicit_fail:
			fail_count += 1
		elif explicit_pass:
			pass_count += 1
		if (
			role_name in ["Reviewer", "QAEngineer"]
			and explicit_fail
			and _contains_any(current.output.to_lower(), [
				"security", "güvenlik", "secret", "permission", "yetki",
			])
		):
			security_veto = true
	var mean: float = weighted_total / maxf(total_weight, 0.001)
	var variance: float = 0.0
	for opinion in opinions:
		variance += pow(float(opinion) - mean, 2.0)
	variance /= maxf(float(opinions.size()), 1.0)
	var disagreement: float = clampf(sqrt(variance) * 2.5, 0.0, 1.0)
	var reviewed: int = pass_count + fail_count
	var pass_ratio: float = (
		float(pass_count) / float(reviewed) if reviewed > 0 else mean
	)
	if security_veto:
		mean = minf(mean, 0.35)
	return {
		"confidence": clampf(mean, 0.0, 1.0),
		"disagreement": disagreement,
		"security_veto": security_veto,
		"pass_ratio": clampf(pass_ratio, 0.0, 1.0),
		"failed_reviews": fail_count,
		"completed": completed.size(),
	}


func should_accept(report: Dictionary) -> bool:
	return (
		not bool(report.get("security_veto", false))
		and float(report.get("confidence", 0.0)) >= 0.82
		and float(report.get("pass_ratio", 0.0)) >= 0.66
		and int(report.get("failed_reviews", 0)) <= 1
	)


func _contains_any(text: String, terms: Array) -> bool:
	for term_value in terms:
		if text.contains(str(term_value)):
			return true
	return false
