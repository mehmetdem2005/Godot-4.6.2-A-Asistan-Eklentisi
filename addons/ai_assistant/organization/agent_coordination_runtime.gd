@tool
class_name AIAgentCoordinationRuntime
extends RefCounted

## Mailbox, event bus, scoped memory ve resource lock'ları tek güvenli
## koordinasyon yüzeyinde birleştirir. Görevleri çalıştırmaz; yalnız
## rezervasyon/iletişim sağlar. Gerçek mutasyon yine Executor'dadır.

const DEFAULT_DEPARTMENT_LIMIT: int = 2
const MAX_DEPARTMENT_LIMIT: int = 8

var chart: AIAgentOrgChart = null
var event_bus: AIAgentEventBus = null
var memory: AIAgentScopedMemory = null
var locks: AIAgentResourceLockManager = null

var _mailboxes: Dictionary = {}
var _department_limits: Dictionary = {}
var _active_work: Dictionary = {}
var _message_sequence: int = 0


func _init(org_chart: AIAgentOrgChart = null) -> void:
	chart = org_chart if org_chart != null else AIAgentOrgChart.new()
	event_bus = AIAgentEventBus.new()
	memory = AIAgentScopedMemory.new(chart)
	locks = AIAgentResourceLockManager.new()
	for role_data in chart.all_roles():
		var role_id: String = str(role_data["role_id"])
		_mailboxes[role_id] = AIAgentMailbox.new(role_id)
		var department: String = str(role_data["department"])
		if not _department_limits.has(department):
			_department_limits[department] = DEFAULT_DEPARTMENT_LIMIT
			_active_work[department] = {}


func mailbox(role_id: String) -> AIAgentMailbox:
	return _mailboxes.get(role_id) as AIAgentMailbox


func set_department_limit(department: String, limit: int) -> bool:
	if not _department_limits.has(department):
		return false
	_department_limits[department] = clampi(limit, 1, MAX_DEPARTMENT_LIMIT)
	return true


func send_message(
	sender_role_id: String,
	recipient_role_id: String,
	kind: String,
	subject: String,
	body: String,
	payload: Dictionary = {},
	priority: String = "normal",
	correlation_id: String = "",
	requires_ack: bool = false
) -> Dictionary:
	if not chart.has_role(sender_role_id) or not chart.has_role(recipient_role_id):
		return {"ok": false, "reason": "sender/recipient rolü yok"}
	_message_sequence += 1
	var message := AIAgentMessage.create(
		"agent-msg-%06d" % _message_sequence,
		sender_role_id,
		recipient_role_id,
		kind,
		subject,
		body,
		payload,
		priority,
		correlation_id,
		requires_ack
	)
	message.department = chart.role(recipient_role_id).department
	var validation: Dictionary = message.validate(chart)
	if not bool(validation["ok"]):
		return {"ok": false, "reason": str(validation["errors"])}
	var target := mailbox(recipient_role_id)
	var queued: Dictionary = target.enqueue(message)
	if not bool(queued.get("ok", false)):
		return queued
	event_bus.publish(
		"message.%s" % kind,
		sender_role_id,
		{
			"message_id": message.message_id,
			"recipient_role_id": recipient_role_id,
			"priority": priority,
		},
		correlation_id
	)
	return {"ok": true, "message": message.to_dict()}


func dispatch_work_order(order: AIAgentWorkOrder) -> Dictionary:
	if order == null:
		return {"ok": false, "reason": "WorkOrder null"}
	var validation: Dictionary = order.validate(chart)
	if not bool(validation["ok"]):
		return {"ok": false, "reason": str(validation["errors"])}
	var sent: Array = []
	var assignment: Dictionary = send_message(
		AIAgentOrgChart.ROOT_ID,
		order.primary_role_id,
		"assignment",
		order.title,
		order.description,
		order.to_dict(),
		"high" if order.high_risk else "normal",
		order.task_id,
		true
	)
	if not bool(assignment.get("ok", false)):
		return assignment
	sent.append(str((assignment["message"] as Dictionary)["message_id"]))
	for reviewer_id in order.reviewer_ids:
		var review_message: Dictionary = send_message(
			order.primary_role_id,
			reviewer_id,
			"review_request",
			"İnceleme: " + order.title,
			order.rationale,
			order.to_dict(),
			"critical" if order.high_risk else "high",
			order.task_id,
			true
		)
		if not bool(review_message.get("ok", false)):
			return {
				"ok": false,
				"reason": "review mesajı kuyruğa alınamadı",
				"sent_message_ids": sent,
			}
		sent.append(str((review_message["message"] as Dictionary)["message_id"]))
	event_bus.publish(
		"work_order.dispatched",
		AIAgentOrgChart.ROOT_ID,
		order.to_dict(),
		order.task_id
	)
	return {"ok": true, "sent_message_ids": sent}


func reserve_work(
	order: AIAgentWorkOrder,
	resource_path: String = ""
) -> Dictionary:
	if order == null:
		return {"ok": false, "reason": "WorkOrder null"}
	var validation: Dictionary = order.validate(chart)
	if not bool(validation["ok"]):
		return {"ok": false, "reason": str(validation["errors"])}
	var department: String = order.department
	var active: Dictionary = _active_work.get(department, {})
	var limit: int = int(_department_limits.get(department, DEFAULT_DEPARTMENT_LIMIT))
	if active.size() >= limit and not active.has(order.task_id):
		return {
			"ok": false,
			"reason": "departman concurrency sınırı dolu",
			"limit": limit,
		}
	if not resource_path.strip_edges().is_empty():
		var lock_result: Dictionary = locks.acquire_write(
			resource_path, order.primary_role_id
		)
		if not bool(lock_result.get("ok", false)):
			return lock_result
	active[order.task_id] = {
		"primary_role_id": order.primary_role_id,
		"resource_path": resource_path,
		"started_at_ms": Time.get_ticks_msec(),
	}
	_active_work[department] = active
	event_bus.publish(
		"work.started", order.primary_role_id, order.to_dict(), order.task_id
	)
	return {"ok": true, "active": active.size(), "limit": limit}


func complete_work(order: AIAgentWorkOrder, summary: String = "") -> bool:
	if order == null or not _active_work.has(order.department):
		return false
	var active: Dictionary = _active_work[order.department]
	if not active.has(order.task_id):
		return false
	var reservation: Dictionary = active[order.task_id]
	var resource_path: String = str(reservation.get("resource_path", ""))
	if not resource_path.is_empty():
		locks.release(resource_path, order.primary_role_id)
	active.erase(order.task_id)
	_active_work[order.department] = active
	if not summary.strip_edges().is_empty():
		memory.remember(
			order.primary_role_id,
			summary,
			"department",
			["task-result", order.department],
			order.task_id,
			1.0
		)
	event_bus.publish(
		"work.completed",
		order.primary_role_id,
		{"task_id": order.task_id, "summary": summary},
		order.task_id
	)
	return true


func active_work_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for department_value in _active_work.keys():
		var department: String = str(department_value)
		out[department] = (_active_work[department] as Dictionary).duplicate(true)
	return out


func stats() -> Dictionary:
	var queued: int = 0
	for mailbox_value in _mailboxes.values():
		queued += (mailbox_value as AIAgentMailbox).size()
	var active_count: int = 0
	for active in _active_work.values():
		active_count += (active as Dictionary).size()
	return {
		"roles": _mailboxes.size(),
		"queued_messages": queued,
		"active_work": active_count,
		"event_bus": event_bus.stats(),
		"memory": memory.stats(),
		"locks": locks.stats(),
	}
