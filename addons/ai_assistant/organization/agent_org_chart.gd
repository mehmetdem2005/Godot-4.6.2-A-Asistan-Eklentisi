@tool
class_name AIAgentOrgChart
extends RefCounted

## AAA ölçeğine genişleyebilen kanonik ajan ağacı.
## Yönetici ajanlar planlar/yönlendirir; uygulayıcılar iş üretir;
## kalite ajanları bağımsız inceler. Bu katman Executor yetkisi vermez.

const ROOT_ID: String = "chief_orchestrator"
const MAX_DEPTH: int = 4
const PRIVILEGED_TOOLS: Array = [
	"executor.apply", "filesystem.write", "filesystem.delete",
	"editor.mutate", "project_settings.write",
]

var _roles: Dictionary = {}


func _init() -> void:
	_build_canonical_tree()


func role(role_id: String) -> AIAgentRoleProfile:
	return _roles.get(role_id) as AIAgentRoleProfile


func has_role(role_id: String) -> bool:
	return _roles.has(role_id)


func all_roles() -> Array:
	var out: Array = []
	for role_id in _roles.keys():
		out.append((_roles[role_id] as AIAgentRoleProfile).to_dict())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["role_id"]) < str(b["role_id"])
	)
	return out


func role_count() -> int:
	return _roles.size()


func children_of(parent_id: String) -> Array:
	var out: Array = []
	for value in _roles.values():
		var profile := value as AIAgentRoleProfile
		if profile.parent_role_id == parent_id:
			out.append(profile.to_dict())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["role_id"]) < str(b["role_id"])
	)
	return out


func path_to_root(role_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Dictionary = {}
	var current: String = role_id
	while not current.is_empty() and _roles.has(current):
		if seen.has(current):
			out.append("<cycle>")
			break
		seen[current] = true
		out.append(current)
		current = (role(current) as AIAgentRoleProfile).parent_role_id
	return out


func validate() -> Dictionary:
	var errors := PackedStringArray()
	if not _roles.has(ROOT_ID):
		errors.append("Kök Chief Orchestrator bulunamadı")
		return {"ok": false, "errors": Array(errors)}
	var root := role(ROOT_ID)
	if not root.parent_role_id.is_empty():
		errors.append("Kök ajanın parent alanı boş olmalı")

	for key_value in _roles.keys():
		var key: String = str(key_value)
		var profile := role(key)
		if profile == null:
			errors.append("Geçersiz rol kaydı: " + key)
			continue
		if profile.role_id != key:
			errors.append("Rol anahtarı/id uyuşmazlığı: " + key)
		if profile.title.is_empty() or profile.department.is_empty():
			errors.append("Rol başlığı/departmanı boş: " + key)
		if profile.memory_scope.is_empty():
			errors.append("Bellek scope'u boş: " + key)
		if key != ROOT_ID and not _roles.has(profile.parent_role_id):
			errors.append("Eksik parent: %s -> %s" % [key, profile.parent_role_id])
		if profile.can_execute and profile.can_approve:
			errors.append("Uygulayıcı kendi işini onaylayamaz: " + key)
		if profile.is_manager():
			for tool_id in PRIVILEGED_TOOLS:
				if profile.allows_tool(str(tool_id)):
					errors.append("Yönetici ayrıcalıklı araç alamaz: %s/%s" % [key, tool_id])
		if profile.department == "release" and profile.allows_tool("code.write"):
			errors.append("Release rolü oyun kodu yazamaz: " + key)

		var path: PackedStringArray = path_to_root(key)
		if path.has("<cycle>"):
			errors.append("Organizasyon döngüsü: " + key)
		elif path.is_empty() or path[-1] != ROOT_ID:
			errors.append("Rol köke bağlanmıyor: " + key)
		elif path.size() > MAX_DEPTH:
			errors.append("Organizasyon derinliği aşıldı: " + key)

	return {"ok": errors.is_empty(), "errors": Array(errors)}


func _register(profile: AIAgentRoleProfile) -> void:
	if profile == null or profile.role_id.is_empty():
		return
	if _roles.has(profile.role_id):
		push_error("AgentOrgChart: tekrarlı rol " + profile.role_id)
		return
	_roles[profile.role_id] = profile


func _role(
	id: String,
	title: String,
	department: String,
	parent: String,
	kind: String,
	capabilities: Array,
	tools: Array,
	reviews: Array,
	can_execute: bool = false,
	can_approve: bool = false
) -> void:
	_register(AIAgentRoleProfile.create(
		id, title, department, parent, kind, capabilities, tools, reviews,
		"org/%s/%s" % [department, id], can_execute, can_approve
	))


func _build_canonical_tree() -> void:
	# Kök yönetici: doğrudan mutasyon yok.
	_role(ROOT_ID, "Chief Orchestrator", "executive", "", "executive",
		["portfolio_planning", "department_routing", "conflict_resolution"],
		["project.read", "memory.read", "task.delegate"], [], false, false)

	# Departman yöneticileri.
	_role("product_director", "Product Director", "product", ROOT_ID, "director",
		["requirements", "scope", "acceptance"],
		["project.read", "memory.read", "task.delegate"], [], false, false)
	_role("technical_director", "Technical Director", "technical", ROOT_ID, "director",
		["architecture", "technical_strategy", "dependency_governance"],
		["project.read", "memory.read", "task.delegate"], [], false, false)
	_role("implementation_director", "Implementation Director", "implementation", ROOT_ID, "director",
		["delivery_planning", "work_allocation"],
		["project.read", "memory.read", "task.delegate"], [], false, false)
	_role("quality_director", "Quality Director", "quality", ROOT_ID, "director",
		["quality_policy", "independent_review", "release_evidence"],
		["project.read", "memory.read", "task.delegate"], [], false, false)
	_role("release_director", "Release Director", "release", ROOT_ID, "director",
		["release_planning", "rollback", "version_governance"],
		["project.read", "memory.read", "task.delegate"], [], false, false)

	# Product specialists.
	_role("requirements_analyst", "Requirements Analyst", "product", "product_director", "specialist",
		["requirements", "intent_analysis", "scope"],
		["project.read", "memory.read", "document.propose"], ["acceptance"], false, false)
	_role("acceptance_analyst", "Acceptance Criteria Analyst", "product", "product_director", "reviewer",
		["acceptance", "traceability"],
		["project.read", "test.read", "review.comment"], ["requirements"], false, true)

	# Technical specialists — implementation yapabilir ama onaylayamaz.
	_role("system_architect", "Principal System Architect", "technical", "technical_director", "specialist",
		["architecture", "dependency_design", "system_design"],
		["project.read", "code.read", "design.propose"], ["architecture"], false, false)
	_role("gameplay_engineer", "Godot Gameplay Engineer", "technical", "technical_director", "implementer",
		["gameplay", "gdscript", "state_machine"],
		["project.read", "code.read", "code.propose"], ["code", "tests"], true, false)
	_role("ui_ux_engineer", "UI/UX Engineer", "technical", "technical_director", "implementer",
		["ui", "ux", "responsive", "control_nodes"],
		["project.read", "scene.read", "code.propose", "scene.propose"], ["code", "mobile"], true, false)
	_role("multiplayer_engineer", "Multiplayer Engineer", "technical", "technical_director", "implementer",
		["networking", "replication", "authority"],
		["project.read", "code.read", "code.propose"], ["code", "security", "tests"], true, false)
	_role("performance_engineer", "Performance Engineer", "technical", "technical_director", "implementer",
		["performance", "profiling", "mobile_optimization"],
		["project.read", "profile.read", "code.propose"], ["performance", "code"], true, false)
	_role("asset_integration_engineer", "Asset Integration Engineer", "technical", "technical_director", "implementer",
		["assets", "imports", "resources"],
		["project.read", "resource.read", "resource.propose"], ["assets", "tests"], true, false)

	# Generic implementation specialists.
	_role("code_implementer", "Code Implementer", "implementation", "implementation_director", "implementer",
		["gdscript", "refactoring", "code_changes"],
		["project.read", "code.read", "code.propose"], ["code", "tests"], true, false)
	_role("scene_implementer", "Scene Implementer", "implementation", "implementation_director", "implementer",
		["scenes", "nodes", "inspector"],
		["project.read", "scene.read", "scene.propose"], ["architecture", "tests"], true, false)
	_role("resource_implementer", "Resource Implementer", "implementation", "implementation_director", "implementer",
		["resources", "imports", "file_layout"],
		["project.read", "resource.read", "resource.propose"], ["assets", "tests"], true, false)

	# Bağımsız kalite departmanı.
	_role("code_reviewer", "Independent Code Reviewer", "quality", "quality_director", "reviewer",
		["code_review", "architecture_compliance"],
		["project.read", "code.read", "review.comment"], ["code"], false, true)
	_role("test_engineer", "Test Automation Engineer", "quality", "quality_director", "reviewer",
		["tests", "regression", "acceptance"],
		["project.read", "test.read", "test.propose", "review.comment"], ["tests"], false, true)
	_role("security_reviewer", "Security Reviewer", "quality", "quality_director", "reviewer",
		["security", "permissions", "secrets", "supply_chain"],
		["project.read", "security.scan", "review.comment"], ["security"], false, true)
	_role("mobile_performance_reviewer", "Mobile Performance Reviewer", "quality", "quality_director", "reviewer",
		["performance", "android", "responsive"],
		["project.read", "profile.read", "review.comment"], ["performance", "mobile"], false, true)

	# Release specialists: oyun koduna doğrudan yazma yetkileri yok.
	_role("ci_engineer", "CI Engineer", "release", "release_director", "specialist",
		["ci", "quality_gates", "artifacts"],
		["project.read", "ci.propose", "test.read"], ["release"], true, false)
	_role("android_release_engineer", "Android Release Engineer", "release", "release_director", "specialist",
		["android", "export", "device_smoke"],
		["project.read", "export.read", "release.propose"], ["release", "mobile"], true, false)
	_role("versioning_engineer", "Versioning Engineer", "release", "release_director", "specialist",
		["versioning", "changelog", "manifest"],
		["project.read", "release.propose", "document.propose"], ["release"], true, false)
	_role("rollback_engineer", "Rollback Engineer", "release", "release_director", "specialist",
		["rollback", "recovery", "incident_response"],
		["project.read", "history.read", "rollback.propose"], ["release", "security"], true, false)
