@tool
class_name AILiveAgentEvent
extends RefCounted

## Canlı paralel ajanların UI'ya taşıdığı yapılandırılmış olay sözleşmesi.
## Ham HTTP başlıkları veya sınırsız model çıktısı bu sözleşmeye giremez.

const TYPE_STARTED: String = "started"
const TYPE_PROGRESS: String = "progress"
const TYPE_COMPLETED: String = "completed"
const TYPE_FAILED: String = "failed"
const VALID_TYPES: Array[String] = [
	TYPE_STARTED,
	TYPE_PROGRESS,
	TYPE_COMPLETED,
	TYPE_FAILED,
]

const MAX_TEXT_CHARS: int = 1200


static func create(
	event_type: String,
	node_id: String,
	layer: int,
	role_name: String,
	title: String,
	text: String = "",
	confidence: float = 0.0,
	worker_index: int = -1,
	metadata: Dictionary = {}
) -> Dictionary:
	return {
		"type": event_type,
		"node_id": node_id.strip_edges(),
		"layer": maxi(0, layer),
		"role_name": _sanitize_label(role_name),
		"title": _sanitize_label(title),
		"text": safe_excerpt(text),
		"confidence": clampf(confidence, 0.0, 1.0),
		"worker_index": worker_index,
		"timestamp_msec": Time.get_ticks_msec(),
		"metadata": _safe_metadata(metadata),
	}


static func validate(event: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var event_type: String = str(event.get("type", ""))
	if not VALID_TYPES.has(event_type):
		errors.append("geçersiz event type")
	if str(event.get("node_id", "")).strip_edges().is_empty():
		errors.append("node_id boş")
	if str(event.get("role_name", "")).strip_edges().is_empty():
		errors.append("role_name boş")
	if str(event.get("title", "")).strip_edges().is_empty():
		errors.append("title boş")
	var confidence: float = float(event.get("confidence", -1.0))
	if confidence < 0.0 or confidence > 1.0:
		errors.append("confidence 0-1 dışında")
	if str(event.get("text", "")).length() > MAX_TEXT_CHARS + 32:
		errors.append("event metni sınırı aşıyor")
	return {"ok": errors.is_empty(), "errors": errors}


static func safe_excerpt(raw_text: String) -> String:
	var text: String = raw_text.replace("\r\n", "\n").replace("\r", "\n")
	text = _redact_secrets(text).strip_edges()
	if text.length() <= MAX_TEXT_CHARS:
		return text
	return text.left(MAX_TEXT_CHARS) + "\n… [çıktı mobil akış için kırpıldı]"


static func _sanitize_label(raw: String) -> String:
	var clean: String = _redact_secrets(raw).strip_edges()
	clean = clean.replace("\n", " ").replace("\r", " ")
	return clean.left(120)


static func _redact_secrets(raw: String) -> String:
	var output: String = raw
	var key_regex := RegEx.new()
	if key_regex.compile("(?i)\\bsk-[A-Za-z0-9_-]{8,}\\b") == OK:
		output = key_regex.sub(output, "[REDACTED_KEY]", true)
	var auth_regex := RegEx.new()
	if auth_regex.compile("(?i)authorization\\s*:\\s*bearer\\s+[^\\s]+") == OK:
		output = auth_regex.sub(
			output, "Authorization: Bearer [REDACTED]", true
		)
	return output


static func _safe_metadata(metadata: Dictionary) -> Dictionary:
	var safe: Dictionary = {}
	for key in metadata:
		var name: String = str(key)
		var lower: String = name.to_lower()
		if lower.contains("key") or lower.contains("secret") or lower.contains("authorization"):
			continue
		var value: Variant = metadata[key]
		if typeof(value) == TYPE_STRING:
			safe[name] = safe_excerpt(str(value)).left(240)
		elif typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			safe[name] = value
	return safe
