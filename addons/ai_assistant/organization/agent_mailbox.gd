@tool
class_name AIAgentMailbox
extends RefCounted

## Tek ajana ait bounded, priority-aware mesaj kutusu.
## Aynı message_id iki kez kabul edilmez; süresi dolan mesajlar temizlenir.

const DEFAULT_CAPACITY: int = 64
const PRIORITY_SCORE: Dictionary = {
	"critical": 4,
	"high": 3,
	"normal": 2,
	"low": 1,
}

var owner_role_id: String = ""
var capacity: int = DEFAULT_CAPACITY
var _messages: Array[AIAgentMessage] = []
var _seen_ids: Dictionary = {}
var _dropped_count: int = 0


func _init(owner: String = "", max_capacity: int = DEFAULT_CAPACITY) -> void:
	owner_role_id = owner.strip_edges()
	capacity = clampi(max_capacity, 1, 1024)


func enqueue(message: AIAgentMessage) -> Dictionary:
	if message == null:
		return {"ok": false, "reason": "mesaj null"}
	if message.recipient_role_id != owner_role_id:
		return {"ok": false, "reason": "mesaj yanlış mailbox alıcısına ait"}
	if message.is_expired():
		return {"ok": false, "reason": "mesaj süresi dolmuş"}
	if _seen_ids.has(message.message_id):
		return {"ok": false, "reason": "tekrarlı message_id"}
	purge_expired()
	if _messages.size() >= capacity:
		var worst_index: int = _lowest_priority_index()
		var incoming_score: int = int(PRIORITY_SCORE.get(message.priority, 0))
		var worst_score: int = int(PRIORITY_SCORE.get(
			(_messages[worst_index] as AIAgentMessage).priority, 0
		))
		if incoming_score <= worst_score:
			_dropped_count += 1
			return {"ok": false, "reason": "mailbox kapasitesi dolu"}
		var removed := _messages.pop_at(worst_index) as AIAgentMessage
		_seen_ids.erase(removed.message_id)
		_dropped_count += 1
	_messages.append(message)
	_seen_ids[message.message_id] = true
	_sort_messages()
	return {"ok": true, "reason": "", "size": _messages.size()}


func peek() -> AIAgentMessage:
	purge_expired()
	if _messages.is_empty():
		return null
	return _messages[0]


func dequeue() -> AIAgentMessage:
	purge_expired()
	if _messages.is_empty():
		return null
	var message := _messages.pop_front() as AIAgentMessage
	_seen_ids.erase(message.message_id)
	return message


func acknowledge(message_id: String) -> bool:
	for message in _messages:
		if message.message_id == message_id:
			return message.acknowledge()
	return false


func purge_expired(now_ms: int = -1) -> int:
	var removed: int = 0
	for index in range(_messages.size() - 1, -1, -1):
		var message := _messages[index] as AIAgentMessage
		if message.is_expired(now_ms):
			_messages.remove_at(index)
			_seen_ids.erase(message.message_id)
			removed += 1
	return removed


func clear() -> void:
	_messages.clear()
	_seen_ids.clear()


func size() -> int:
	purge_expired()
	return _messages.size()


func stats() -> Dictionary:
	var critical: int = 0
	var awaiting_ack: int = 0
	for message in _messages:
		if message.priority == "critical":
			critical += 1
		if message.requires_ack and not message.acknowledged:
			awaiting_ack += 1
	return {
		"owner_role_id": owner_role_id,
		"size": size(),
		"capacity": capacity,
		"critical": critical,
		"awaiting_ack": awaiting_ack,
		"dropped": _dropped_count,
	}


func _sort_messages() -> void:
	_messages.sort_custom(func(a: AIAgentMessage, b: AIAgentMessage) -> bool:
		var a_score: int = int(PRIORITY_SCORE.get(a.priority, 0))
		var b_score: int = int(PRIORITY_SCORE.get(b.priority, 0))
		if a_score == b_score:
			return a.created_at_ms < b.created_at_ms
		return a_score > b_score
	)


func _lowest_priority_index() -> int:
	var lowest_index: int = 0
	var lowest_score: int = 999
	var newest_time: int = -1
	for index in _messages.size():
		var message := _messages[index] as AIAgentMessage
		var score: int = int(PRIORITY_SCORE.get(message.priority, 0))
		if score < lowest_score or (score == lowest_score and message.created_at_ms > newest_time):
			lowest_index = index
			lowest_score = score
			newest_time = message.created_at_ms
	return lowest_index
