@tool
class_name AIAgentEventBus
extends RefCounted

## Ajan/departman olaylarını bounded journal içinde taşır.
## Callback çalıştırmaz; tüketiciler cursor ile poll eder. Böylece bir
## subscriber'ın hatası organizasyon çekirdeğini re-entrant yapamaz.

const DEFAULT_CAPACITY: int = 256

var capacity: int = DEFAULT_CAPACITY
var _sequence: int = 0
var _events: Array[Dictionary] = []
var _subscriptions: Dictionary = {}
var _dropped_count: int = 0


func _init(max_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = clampi(max_capacity, 8, 4096)


func subscribe(subscriber_id: String, topics: Array) -> bool:
	var id: String = subscriber_id.strip_edges()
	if id.is_empty():
		return false
	var clean := PackedStringArray()
	for topic_value in topics:
		var topic: String = str(topic_value).strip_edges()
		if not topic.is_empty() and not clean.has(topic):
			clean.append(topic)
	if clean.is_empty():
		return false
	_subscriptions[id] = {"topics": clean, "cursor": _sequence}
	return true


func unsubscribe(subscriber_id: String) -> bool:
	return _subscriptions.erase(subscriber_id)


func publish(
	topic: String,
	sender_role_id: String,
	payload: Dictionary = {},
	correlation_id: String = ""
) -> Dictionary:
	var clean_topic: String = topic.strip_edges()
	var sender: String = sender_role_id.strip_edges()
	if clean_topic.is_empty() or sender.is_empty():
		return {"ok": false, "reason": "topic/sender boş"}
	_sequence += 1
	var event: Dictionary = {
		"sequence": _sequence,
		"topic": clean_topic,
		"sender_role_id": sender,
		"payload": payload.duplicate(true),
		"correlation_id": correlation_id.strip_edges(),
		"created_at_ms": Time.get_ticks_msec(),
	}
	_events.append(event)
	while _events.size() > capacity:
		_events.pop_front()
		_dropped_count += 1
	return {"ok": true, "event": event.duplicate(true)}


func poll(subscriber_id: String, limit: int = 32) -> Array:
	if not _subscriptions.has(subscriber_id):
		return []
	var subscription: Dictionary = _subscriptions[subscriber_id]
	var topics: PackedStringArray = subscription["topics"]
	var cursor: int = int(subscription["cursor"])
	var out: Array = []
	var newest_seen: int = cursor
	for event_value in _events:
		var event: Dictionary = event_value
		var sequence: int = int(event["sequence"])
		if sequence <= cursor:
			continue
		newest_seen = maxi(newest_seen, sequence)
		if _topic_matches(topics, str(event["topic"])):
			out.append(event.duplicate(true))
			if out.size() >= clampi(limit, 1, 256):
				break
	# Cursor yalnız incelenen son olaya ilerler; limit sonrası olaylar kaybolmaz.
	if not out.is_empty():
		newest_seen = int((out[-1] as Dictionary)["sequence"])
	subscription["cursor"] = newest_seen
	_subscriptions[subscriber_id] = subscription
	return out


func latest_sequence() -> int:
	return _sequence


func stats() -> Dictionary:
	return {
		"sequence": _sequence,
		"retained_events": _events.size(),
		"capacity": capacity,
		"subscriptions": _subscriptions.size(),
		"dropped": _dropped_count,
	}


func _topic_matches(topics: PackedStringArray, event_topic: String) -> bool:
	for topic in topics:
		if topic == "*" or topic == event_topic:
			return true
		if topic.ends_with(".*"):
			var prefix: String = topic.left(topic.length() - 1)
			if event_topic.begins_with(prefix):
				return true
	return false
