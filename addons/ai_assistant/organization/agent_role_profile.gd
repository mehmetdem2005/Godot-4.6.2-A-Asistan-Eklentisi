@tool
class_name AIAgentRoleProfile
extends RefCounted

## Bir şirket ajanının değişmez yetki ve sorumluluk sözleşmesi.
## Bu nesne araç çalıştırmaz; yalnız organizasyon/routing katmanına
## güvenilir metadata sağlar. Gerçek mutasyon mevcut Executor'da kalır.

var role_id: String = ""
var title: String = ""
var department: String = ""
var parent_role_id: String = ""
var role_kind: String = "specialist"
var capabilities: PackedStringArray = PackedStringArray()
var allowed_tools: PackedStringArray = PackedStringArray()
var review_domains: PackedStringArray = PackedStringArray()
var memory_scope: String = ""
var can_execute: bool = false
var can_approve: bool = false


static func create(
	id: String,
	role_title: String,
	dept: String,
	parent_id: String,
	kind: String,
	caps: Array,
	tools: Array,
	reviews: Array,
	scope: String,
	execute: bool,
	approve: bool
) -> AIAgentRoleProfile:
	var profile := AIAgentRoleProfile.new()
	profile.role_id = id.strip_edges()
	profile.title = role_title.strip_edges()
	profile.department = dept.strip_edges()
	profile.parent_role_id = parent_id.strip_edges()
	profile.role_kind = kind.strip_edges()
	profile.capabilities = _to_unique_strings(caps)
	profile.allowed_tools = _to_unique_strings(tools)
	profile.review_domains = _to_unique_strings(reviews)
	profile.memory_scope = scope.strip_edges()
	profile.can_execute = execute
	profile.can_approve = approve
	return profile


func has_capability(capability: String) -> bool:
	return capabilities.has(capability)


func allows_tool(tool_id: String) -> bool:
	return allowed_tools.has(tool_id)


func is_manager() -> bool:
	return role_kind == "executive" or role_kind == "director"


func to_dict() -> Dictionary:
	return {
		"role_id": role_id,
		"title": title,
		"department": department,
		"parent_role_id": parent_role_id,
		"role_kind": role_kind,
		"capabilities": Array(capabilities),
		"allowed_tools": Array(allowed_tools),
		"review_domains": Array(review_domains),
		"memory_scope": memory_scope,
		"can_execute": can_execute,
		"can_approve": can_approve,
	}


static func _to_unique_strings(values: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for value in values:
		var text: String = str(value).strip_edges()
		if not text.is_empty() and not out.has(text):
			out.append(text)
	return out
