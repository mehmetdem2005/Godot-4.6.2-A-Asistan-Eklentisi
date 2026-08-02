@tool
class_name AIDeepSeekSSEDecoder
extends RefCounted

## DeepSeek/OpenAI data-only SSE akışını ağ chunk sınırlarından bağımsız
## olarak ayrıştırır. UTF-8 satır tamamlanmadan String'e çevrilmez.

var _pending_bytes := PackedByteArray()
var _data_lines := PackedStringArray()
var _done: bool = false


func feed_bytes(chunk: PackedByteArray) -> Array:
	var events: Array = []
	if _done or chunk.is_empty():
		return events
	_pending_bytes.append_array(chunk)
	while true:
		var newline_index: int = _find_newline(_pending_bytes)
		if newline_index < 0:
			break
		var line_bytes: PackedByteArray = _pending_bytes.slice(0, newline_index)
		_pending_bytes = _pending_bytes.slice(newline_index + 1)
		if not line_bytes.is_empty() and line_bytes[-1] == 13:
			line_bytes.resize(line_bytes.size() - 1)
		var line: String = line_bytes.get_string_from_utf8()
		events.append_array(_consume_line(line))
	return events


func finish() -> Array:
	var events: Array = []
	if not _pending_bytes.is_empty():
		var line: String = _pending_bytes.get_string_from_utf8()
		_pending_bytes.clear()
		events.append_array(_consume_line(line))
	if not _data_lines.is_empty():
		events.append(_flush_event())
	return events


func is_done() -> bool:
	return _done


func reset() -> void:
	_pending_bytes.clear()
	_data_lines.clear()
	_done = false


func _consume_line(line: String) -> Array:
	var events: Array = []
	if line.is_empty():
		if not _data_lines.is_empty():
			events.append(_flush_event())
		return events
	if line.begins_with(":"):
		return events
	if line.begins_with("data:"):
		var value: String = line.substr(5)
		if value.begins_with(" "):
			value = value.substr(1)
		_data_lines.append(value)
	return events


func _flush_event() -> Dictionary:
	var payload: String = "\n".join(_data_lines)
	_data_lines.clear()
	if payload == "[DONE]":
		_done = true
		return {"done": true, "json": {}, "error": ""}
	var parser := JSON.new()
	var error_code: int = parser.parse(payload)
	if error_code != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {
			"done": false,
			"json": {},
			"error": "SSE JSON ayrıştırılamadı: " + parser.get_error_message(),
			"raw": payload.left(512),
		}
	return {"done": false, "json": parser.data, "error": ""}


func _find_newline(bytes: PackedByteArray) -> int:
	for index in bytes.size():
		if bytes[index] == 10:
			return index
	return -1
