@tool
class_name AIAgentScopedMemory
extends RefCounted

## Ajan/department/private bellek sınırları. Bu katman kalıcı global
## AIMemoryManager'ın yerine geçmez; onun üzerine erişim scope'u üretir.

const VALID_VISIBILITY: PackedStringArray = [
	"private", "department", "organization",
]
const MAX_RECORDS_PER_SCOPE: int = 128
const MAX_CONTENT_CHARS: int = 12000

var _chart: AIAgentOrgChart = null
var _records: Dictionary = {}
var _sequence: int = 0
var _evicted_count: int = 0


func _init(chart: AIAgentOrgChart = null) -> void:
	_chart = chart if chart != null else AIAgentOrgChart.new()


func remember(
	owner_role_id: String,
	content: String,
	visibility: String = "private",
	tags: Array = [],
	correlation_id: String = "",
	confidence: float = 1.0
) -> Dictionary:
	var owner: String = owner_role_id.strip_edges()
	var text: String = content.strip_edges()
	if not _chart.has_role(owner):
		return {"ok": false, "reason": "owner rolü yok"}
	if text.is_empty() or text.length() > MAX_CONTENT_CHARS:
		return {"ok": false, "reason": "içerik boş veya sınırı aşıyor"}
	if not VALID_VISIBILITY.has(visibility):
		return {"ok": false, "reason": "geçersiz visibility"}
	_sequence += 1
	var profile := _chart.role(owner)
	var record: Dictionary = {
		"record_id": "agent-memory-%06d" % _sequence,
		"owner_role_id": owner,
		"department": profile.department,
		"visibility": visibility,
		"content": text,
		"tags": _clean_tags(tags),
		"correlation_id": correlation_id.strip_edges(),
		"confidence": clampf(confidence, 0.0, 1.0),
		"created_at_ms": Time.get_ticks_msec(),
		"access_count": 0,
	}
	var bucket: Array = _records.get(owner, [])
	bucket.append(record)
	while bucket.size() > MAX_RECORDS_PER_SCOPE:
		bucket.pop_front()
		_evicted_count += 1
	_records[owner] = bucket
	return {"ok": true, "record": record.duplicate(true)}


func recall(
	requester_role_id: String,
	query: String = "",
	limit: int = 32
) -> Array:
	var requester: String = requester_role_id.strip_edges()
	if not _chart.has_role(requester):
		return []
	var requester_profile := _chart.role(requester)
	var needle: String = query.strip_edges().to_lower()
	var visible: Array = []
	for owner_value in _records.keys():
		var owner: String = str(owner_value)
		for record_value in (_records[owner] as Array):
			var record: Dictionary = record_value
			if not _can_read(
				requester, requester_profile.department, record
			):
				continue
			if not needle.is_empty():
				var haystack: String = (
					str(record["content"]) + " "
					+ " ".join(record["tags"] as Array)
				).to_lower()
				if not haystack.contains(needle):
					continue
			var copy: Dictionary = record.duplicate(true)
			copy["access_count"] = int(copy["access_count"]) + 1
			record["access_count"] = int(record["access_count"]) + 1
			visible.append(copy)
	visible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["created_at_ms"]) > int(b["created_at_ms"])
	)
	if visible.size() > clampi(limit, 1, 256):
		visible.resize(clampi(limit, 1, 256))
	return visible


func forget_owner(owner_role_id: String) -> int:
	if not _records.has(owner_role_id):
		return 0
	var count: int = (_records[owner_role_id] as Array).size()
	_records.erase(owner_role_id)
	return count


func stats() -> Dictionary:
	var total: int = 0
	for bucket in _records.values():
		total += (bucket as Array).size()
	return {
		"owners": _records.size(),
		"records": total,
		"evicted": _evicted_count,
	}


func _can_read(
	requester_role_id: String,
	requester_department: String,
	record: Dictionary
) -> bool:
	var visibility: String = str(record["visibility"])
	if visibility == "organization":
		return true
	if visibility == "department":
		return requester_department == str(record["department"])
	return requester_role_id == str(record["owner_role_id"])


func _clean_tags(tags: Array) -> Array:
	var out: Array = []
	for tag_value in tags:
		var tag: String = str(tag_value).strip_edges().to_lower()
		if not tag.is_empty() and not out.has(tag):
			out.append(tag)
	return out
