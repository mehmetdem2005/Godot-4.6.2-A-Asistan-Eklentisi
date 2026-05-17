@tool
class_name AITraceCollector
extends RefCounted

## TraceCollector — yapılandırılmış iz toplayıcı (Layer 6).
##
## Sistem 6 katmanlı ama "kör" çalışıyor — bir plan yürütülürken ne olduğu
## dışarıdan görünmüyor. Bu sınıf her önemli olayı zaman damgalı, bağlamlı
## bir "iz" (trace) olarak kaydeder.
##
## Her iz bir AITraceEntry'dir. İzler:
##   - Monoton sıra numarası taşır (aynı ms'de bile deterministik sıra)
##   - Bir "span" hiyerarşisi oluşturabilir (task içinde action içinde...)
##   - ReplayEngine tarafından geri sarılabilir
##
## Mock policy: iz kaydı gerçek — sahte/atlanmış olay yok.

## İz seviyesi — önem derecesi.
enum TraceLevel { DEBUG, INFO, WARN, ERROR }

const TRACE_LEVEL_NAMES: Dictionary = {
	TraceLevel.DEBUG: "debug",
	TraceLevel.INFO: "info",
	TraceLevel.WARN: "warn",
	TraceLevel.ERROR: "error",
}


## Tek bir iz kaydı.
class TraceEntry extends RefCounted:
	var id: String = ""
	var sequence: int = 0              ## Monoton artan — deterministik sıra
	var timestamp: String = ""         ## ISO 8601
	var level: int = AITraceCollector.TraceLevel.INFO
	var category: String = ""          ## "executor", "verifier", "planner"...
	var event: String = ""             ## "task_started", "action_executed"...
	var message: String = ""
	var span_id: String = ""           ## Bu iz hangi span'e ait
	var parent_span_id: String = ""    ## Span hiyerarşisi
	var data: Dictionary = {}          ## Olaya özel ek veri

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"sequence": sequence,
			"timestamp": timestamp,
			"level": AITraceCollector.TRACE_LEVEL_NAMES.get(level, "info"),
			"category": category,
			"event": event,
			"message": message,
			"span_id": span_id,
			"parent_span_id": parent_span_id,
			"data": data,
		}

	func from_dict(d: Dictionary) -> void:
		id = d.get("id", "")
		sequence = int(d.get("sequence", 0))
		timestamp = d.get("timestamp", "")
		level = AITraceCollector._parse_level(d.get("level", "info"))
		category = d.get("category", "")
		event = d.get("event", "")
		message = d.get("message", "")
		span_id = d.get("span_id", "")
		parent_span_id = d.get("parent_span_id", "")
		data = d.get("data", {})


## Disk yolu.
const TRACE_PATH: String = "user://ai_assistant/observability/trace.json"

## Bellekteki tutulacak maksimum iz sayısı (ring buffer — eskiler atılır).
const MAX_TRACES: int = 5000

## Tüm izler — sıra korunur.
var _traces: Array = []

## Monoton sıra sayacı.
var _sequence: int = 0

## Aktif span yığını — iç içe span'ler için.
var _span_stack: PackedStringArray = PackedStringArray()


## Toplam iz sayısı.
func count() -> int:
	return _traces.size()


## İz koleksiyonu boş mu?
func is_empty() -> bool:
	return _traces.is_empty()


# ============================================================
# İZ KAYDI
# ============================================================

## Bir iz kaydeder. En temel API.
## Dönen: oluşturulan TraceEntry.
func record(
	level: int, category: String, event: String,
	message: String = "", data: Dictionary = {}
) -> TraceEntry:
	var entry := TraceEntry.new()
	entry.id = AIContractBase.generate_id("trace")
	entry.sequence = _sequence
	_sequence += 1
	entry.timestamp = AIContractBase.now_iso()
	entry.level = level
	entry.category = category
	entry.event = event
	entry.message = message
	entry.data = data
	# Aktif span varsa bağla
	if not _span_stack.is_empty():
		entry.span_id = _span_stack[_span_stack.size() - 1]
		if _span_stack.size() >= 2:
			entry.parent_span_id = _span_stack[_span_stack.size() - 2]

	_traces.append(entry)
	# Ring buffer — kapasiteyi aşınca en eskiyi at
	if _traces.size() > MAX_TRACES:
		_traces.pop_front()
	return entry


## Kısa yol — INFO seviyesi iz.
func info(category: String, event: String, message: String = "") -> TraceEntry:
	return record(TraceLevel.INFO, category, event, message)


## Kısa yol — WARN seviyesi iz.
func warn(category: String, event: String, message: String = "") -> TraceEntry:
	return record(TraceLevel.WARN, category, event, message)


## Kısa yol — ERROR seviyesi iz.
func error(category: String, event: String, message: String = "") -> TraceEntry:
	return record(TraceLevel.ERROR, category, event, message)


# ============================================================
# SPAN — iz hiyerarşisi
# ============================================================

## Bir span başlatır — sonraki izler bu span'e ait olur.
## Span'ler iç içe olabilir: task span'i > action span'i > ...
## Dönen: span id (later end_span'e geçilir).
func begin_span(span_name: String) -> String:
	var span_id: String = AIContractBase.generate_id("span")
	_span_stack.append(span_id)
	record(
		TraceLevel.DEBUG, "span", "span_begin", span_name,
		{"span_id": span_id, "span_name": span_name}
	)
	return span_id


## Bir span'i sonlandırır. Yığının tepesindeki span kapatılır.
func end_span(span_name: String = "") -> void:
	if _span_stack.is_empty():
		push_warning("TraceCollector.end_span: açık span yok")
		return
	var span_id: String = _span_stack[_span_stack.size() - 1]
	_span_stack.remove_at(_span_stack.size() - 1)
	record(
		TraceLevel.DEBUG, "span", "span_end", span_name,
		{"span_id": span_id}
	)


## Şu an aktif span var mı?
func has_active_span() -> bool:
	return not _span_stack.is_empty()


# ============================================================
# SORGULAMA
# ============================================================

## Tüm izleri sıra numarasına göre döndürür.
func all_traces() -> Array:
	return _traces


## Belirli kategorideki izleri döndürür.
func traces_by_category(category: String) -> Array:
	var result: Array = []
	for t in _traces:
		if t.category == category:
			result.append(t)
	return result


## Belirli seviye ve üstündeki izleri döndürür (örn. WARN+ERROR).
func traces_at_least(min_level: int) -> Array:
	var result: Array = []
	for t in _traces:
		if t.level >= min_level:
			result.append(t)
	return result


## Belirli bir span'e ait izleri döndürür.
func traces_in_span(span_id: String) -> Array:
	var result: Array = []
	for t in _traces:
		if t.span_id == span_id:
			result.append(t)
	return result


## Sadece hata izlerini döndürür — hızlı tanı için.
func errors() -> Array:
	return traces_at_least(TraceLevel.ERROR)


# ============================================================
# DİSK KALICILIĞI
# ============================================================

## İzleri diske yazar — atomik (.tmp + rename).
func save_to_disk() -> bool:
	var data: Dictionary = {
		"saved_at": AIContractBase.now_iso(),
		"sequence": _sequence,
		"traces": [],
	}
	for t in _traces:
		(data["traces"] as Array).append(t.to_dict())

	var dir_path: String = TRACE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp: String = TRACE_PATH + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("TraceCollector.save: dosya açılamadı")
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, TRACE_PATH) == OK


## İzleri diskten yükler.
func load_from_disk() -> bool:
	if not FileAccess.file_exists(TRACE_PATH):
		return true  # ilk çalıştırma
	var f: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("TraceCollector.load: bozuk JSON")
		return false

	_traces.clear()
	_sequence = int((parsed as Dictionary).get("sequence", 0))
	for td in (parsed as Dictionary).get("traces", []):
		var entry := TraceEntry.new()
		entry.from_dict(td)
		_traces.append(entry)
	return true


## Tüm izleri temizler.
func clear() -> void:
	_traces.clear()
	_sequence = 0
	_span_stack.clear()


static func _parse_level(s: String) -> int:
	for key in TRACE_LEVEL_NAMES:
		if TRACE_LEVEL_NAMES[key] == s:
			return key
	return TraceLevel.INFO
