@tool
class_name AIAgentTaskRouter
extends RefCounted

## Görevi deterministik olarak uzman ajana ve bağımsız kalite rollerine
## yönlendirir. LLM bu kararı genişletebilir fakat güvenlik denetçisini
## kaldıramaz ve birincil ajanı kendi denetçisi yapamaz.

var _chart: AIAgentOrgChart = null
var _sequence: int = 0


func _init(chart: AIAgentOrgChart = null) -> void:
	_chart = chart if chart != null else AIAgentOrgChart.new()


func route(task: Dictionary) -> AIAgentWorkOrder:
	_sequence += 1
	var order := AIAgentWorkOrder.new()
	order.task_id = str(task.get("id", "org-%04d" % _sequence))
	order.title = str(task.get("title", "Görev")).strip_edges()
	order.description = str(task.get("description", task.get("instruction", ""))).strip_edges()
	order.target_path = str(task.get("target_file", task.get("target_path", ""))).strip_edges()
	var text: String = (
		order.title + " " + order.description + " " + order.target_path
	).to_lower()

	var assignment: Dictionary = _classify(text, order.target_path)
	order.primary_role_id = str(assignment["primary"])
	var primary := _chart.role(order.primary_role_id)
	order.department = primary.department if primary != null else "implementation"
	order.reviewer_ids = _unique_reviewers(assignment.get("reviewers", []), order.primary_role_id)
	order.escalation_role_id = str(assignment.get("escalation", ""))
	order.required_capabilities = _to_unique_strings(assignment.get("capabilities", []))
	order.confidence = float(assignment.get("confidence", 0.60))
	order.rationale = str(assignment.get("rationale", "Genel uygulama yönlendirmesi"))
	order.high_risk = _is_high_risk(text)

	# Güvenlik invariant'ları routing sonucundan sonra zorlanır.
	if order.high_risk:
		if order.primary_role_id != "security_reviewer":
			_append_unique(order.reviewer_ids, "security_reviewer")
		if order.escalation_role_id.is_empty():
			order.escalation_role_id = "technical_director"
	var selected := _chart.role(order.primary_role_id)
	if selected != null and selected.can_execute and order.reviewer_ids.is_empty():
		order.reviewer_ids.append("code_reviewer")
	if selected != null and not selected.can_execute and order.high_risk:
		order.status = "escalation_required"

	return order


func _classify(text: String, target_path: String) -> Dictionary:
	if _contains_any(text, ["api key", "secret", "authorization", "permission", "yetki", "güvenlik", "security", "credential"]):
		return _a("security_reviewer", ["test_engineer"], ["security"],
			"Güvenlik/kimlik bilgisi görevi", 0.98, "quality_director")
	if _contains_any(text, ["release", "ci", "workflow", "github actions", "export", "apk", "sürüm", "version", "rollback"]):
		var primary: String = "ci_engineer"
		if _contains_any(text, ["android", "apk", "export"]):
			primary = "android_release_engineer"
		elif _contains_any(text, ["version", "sürüm", "changelog", "manifest"]):
			primary = "versioning_engineer"
		elif text.contains("rollback"):
			primary = "rollback_engineer"
		return _a(primary, ["test_engineer"], ["release"],
			"Release/CI uzmanlık alanı", 0.95, "release_director")
	if _contains_any(text, ["multiplayer", "network", "replication", "rpc", "server", "client", "matchmaking", "latency", "ping"]):
		return _a("multiplayer_engineer", ["security_reviewer", "code_reviewer", "test_engineer"],
			["networking", "authority"], "Ağ ve sunucu otoritesi görevi", 0.96, "technical_director")
	if _contains_any(text, ["performance", "optimiz", "fps", "profil", "memory", "bellek", "lag", "stutter", "mobil performans"]):
		return _a("performance_engineer", ["mobile_performance_reviewer", "code_reviewer"],
			["performance", "profiling"], "Performans/profiling görevi", 0.94, "technical_director")
	if _contains_any(text, ["ui", "ux", "control", "responsive", "buton", "button", "panel", "menü", "menu", "hud"]):
		return _a("ui_ux_engineer", ["code_reviewer", "mobile_performance_reviewer"],
			["ui", "responsive"], "UI/UX ve responsive düzen görevi", 0.93, "technical_director")
	if target_path.ends_with(".tscn") or _contains_any(text, ["scene", "sahne", "node", "düğüm", "inspector", "child"]):
		return _a("scene_implementer", ["code_reviewer", "test_engineer"],
			["scenes", "nodes"], "Sahne/node ağacı görevi", 0.91, "implementation_director")
	if _contains_any(text, ["asset", "texture", "mesh", "resource", "import", "shader", "audio", "animasyon", "animation"]):
		return _a("asset_integration_engineer", ["test_engineer"],
			["assets", "imports"], "Asset/resource entegrasyonu", 0.90, "technical_director")
	if _contains_any(text, ["gereksinim", "requirement", "kabul kriter", "acceptance", "scope", "kapsam", "tasarım belgesi"]):
		return _a("requirements_analyst", ["acceptance_analyst"],
			["requirements", "acceptance"], "Ürün gereksinimi ve kapsam görevi", 0.90, "product_director")
	if _contains_any(text, ["architecture", "mimari", "dependency", "bağımlılık", "system design"]):
		return _a("system_architect", ["code_reviewer", "security_reviewer"],
			["architecture"], "Sistem mimarisi görevi", 0.92, "technical_director")
	if target_path.ends_with(".gd") or _contains_any(text, ["gameplay", "script", "kod", "code", "state machine", "combat", "inventory", "karakter"]):
		return _a("gameplay_engineer", ["code_reviewer", "test_engineer"],
			["gameplay", "gdscript"], "Godot gameplay/kod görevi", 0.88, "technical_director")
	return _a("code_implementer", ["code_reviewer", "test_engineer"],
		["code_changes"], "Genel uygulama görevi", 0.65, "implementation_director")


func _a(
	primary: String,
	reviewers: Array,
	capabilities: Array,
	rationale: String,
	confidence: float,
	escalation: String
) -> Dictionary:
	return {
		"primary": primary,
		"reviewers": reviewers,
		"capabilities": capabilities,
		"rationale": rationale,
		"confidence": confidence,
		"escalation": escalation,
	}


func _is_high_risk(text: String) -> bool:
	return _contains_any(text, [
		"sil", "delete", "remove", "taşı", "move", "rename",
		"project settings", "project.godot", "plugin", "autoload",
		"api key", "secret", "authorization", "download", "indir",
		"internet", "shell", "command", "exec",
	])


func _contains_any(text: String, terms: Array) -> bool:
	for term in terms:
		if text.contains(str(term)):
			return true
	return false


func _unique_reviewers(values: Array, primary: String) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		var reviewer: String = str(value)
		if reviewer != primary and _chart.has_role(reviewer):
			var profile := _chart.role(reviewer)
			if profile.can_approve and not out.has(reviewer):
				out.append(reviewer)
	return out


func _to_unique_strings(values: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		_append_unique(out, str(value))
	return out


func _append_unique(values: PackedStringArray, value: String) -> void:
	if not value.is_empty() and not values.has(value):
		values.append(value)
