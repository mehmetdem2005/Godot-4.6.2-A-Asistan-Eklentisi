@tool
class_name AIDeliberationNode
extends RefCounted

## Adaptif bilişsel grafikte tek düşünme/eleştiri/sentez düğümü.

const STATE_PENDING: String = "pending"
const STATE_RUNNING: String = "running"
const STATE_COMPLETED: String = "completed"
const STATE_FAILED: String = "failed"
const STATE_CANCELLED: String = "cancelled"

var node_id: String = ""
var layer_index: int = 0
var layer_id: String = ""
var title: String = ""
var node_kind: String = "analysis"
var role: int = -1
var prompt: String = ""
var dependencies: PackedStringArray = PackedStringArray()
var state: String = STATE_PENDING
var output: String = ""
var confidence: float = 0.0
var uncertainty: float = 1.0
var risk_score: float = 0.0
var candidate_group: String = ""
var resource_scope: String = ""
var attempt: int = 0
var started_at_ms: int = 0
var finished_at_ms: int = 0
var failure_reason: String = ""
var metadata: Dictionary = {}


static func create(
	id: String,
	layer: AICognitiveLayerProfile,
	kind: String,
	assigned_role: int,
	node_title: String,
	node_prompt: String,
	deps: Array = [],
	group: String = ""
) -> AIDeliberationNode:
	var node := AIDeliberationNode.new()
	node.node_id = id.strip_edges()
	node.layer_index = layer.index
	node.layer_id = layer.layer_id
	node.title = node_title.strip_edges()
	node.node_kind = kind.strip_edges()
	node.role = assigned_role
	node.prompt = node_prompt.strip_edges()
	node.candidate_group = group.strip_edges()
	for dep_value in deps:
		var dep: String = str(dep_value).strip_edges()
		if not dep.is_empty() and not node.dependencies.has(dep):
			node.dependencies.append(dep)
	return node


func is_terminal() -> bool:
	return state in [STATE_COMPLETED, STATE_FAILED, STATE_CANCELLED]


func mark_running() -> bool:
	if state != STATE_PENDING:
		return false
	state = STATE_RUNNING
	started_at_ms = Time.get_ticks_msec()
	attempt += 1
	return true


func mark_completed(text: String, score: float = 0.75) -> bool:
	if state != STATE_RUNNING:
		return false
	output = text
	confidence = clampf(score, 0.0, 1.0)
	uncertainty = 1.0 - confidence
	state = STATE_COMPLETED
	finished_at_ms = Time.get_ticks_msec()
	return true


func mark_failed(reason: String) -> bool:
	if state != STATE_RUNNING and state != STATE_PENDING:
		return false
	failure_reason = reason.strip_edges()
	state = STATE_FAILED
	confidence = 0.0
	uncertainty = 1.0
	finished_at_ms = Time.get_ticks_msec()
	return true


func validate() -> Dictionary:
	var errors := PackedStringArray()
	if node_id.is_empty():
		errors.append("node_id boş")
	if layer_id.is_empty() or layer_index < 0:
		errors.append("katman kimliği geçersiz")
	if title.is_empty() or prompt.is_empty():
		errors.append("başlık/prompt boş")
	if not AICellRoles.is_valid_role(role):
		errors.append("geçersiz cell rolü")
	if dependencies.has(node_id):
		errors.append("düğüm kendine bağımlı olamaz")
	return {"ok": errors.is_empty(), "errors": Array(errors)}


func to_dict(include_output: bool = true) -> Dictionary:
	var out: Dictionary = {
		"node_id": node_id,
		"layer_index": layer_index,
		"layer_id": layer_id,
		"title": title,
		"node_kind": node_kind,
		"role": role,
		"role_name": AICellRoles.role_name(role),
		"dependencies": Array(dependencies),
		"state": state,
		"confidence": confidence,
		"uncertainty": uncertainty,
		"risk_score": risk_score,
		"candidate_group": candidate_group,
		"resource_scope": resource_scope,
		"attempt": attempt,
		"failure_reason": failure_reason,
		"metadata": metadata.duplicate(true),
	}
	if include_output:
		out["output"] = output
	return out
