@tool
class_name AIFeedEvent
extends AIContractBase

## FeedEvent — Canlı Akış (Live Feed) için tek bir olay kaydı.
##
## Sistemde olan biten her şey (plan üretildi, kod yazıldı, test başarısız oldu,
## commit yapıldı...) bir FeedEvent olarak yayınlanır. Task Workspace'in
## "📡 Canlı Akış" sekmesi bu event'leri gerçek zamanlı gösterir.
##
## Her event bir sahibe (owner_role) aittir — kullanıcı kim ne yapıyor görür.

## Olayın önem seviyesi.
enum Severity {
	DEBUG,    ## Detaylı iz (genelde gizli)
	INFO,     ## Normal akış
	SUCCESS,  ## Başarı
	WARNING,  ## Dikkat
	ERROR,    ## Hata
	CRITICAL, ## Kritik — kullanıcı müdahalesi gerekebilir
}

const SEVERITY_NAMES: Dictionary = {
	Severity.DEBUG: "debug",
	Severity.INFO: "info",
	Severity.SUCCESS: "success",
	Severity.WARNING: "warning",
	Severity.ERROR: "error",
	Severity.CRITICAL: "critical",
}

## Severity -> UI renk (hex).
const SEVERITY_COLOR: Dictionary = {
	Severity.DEBUG: "#6B7280",
	Severity.INFO: "#3B82F6",
	Severity.SUCCESS: "#22C55E",
	Severity.WARNING: "#F59E0B",
	Severity.ERROR: "#EF4444",
	Severity.CRITICAL: "#DC2626",
}

# --- Kimlik ---
var id: String = ""
var timestamp: String = ""           ## ISO 8601 (milisaniye hassasiyetinde)
var sequence: int = 0                ## Monoton artan sıra no (aynı ms'de sıralama için)

# --- İçerik ---
var event_type: String = ""          ## Örn: "TASK_STARTED", "COMMIT_CREATED"
var message: String = ""             ## İnsan-okunabilir açıklama
var severity: int = Severity.INFO

# --- Sahiplik ---
var owner_role: String = ""          ## Hangi cell role / aktör (AICellRoles)

# --- Bağlam ---
var task_ref: String = ""            ## İlgili task id (varsa)
var iteration_ref: String = ""       ## İlgili iteration id (varsa)
var metadata: Dictionary = {}        ## Event tipine özel ekstra veri


func contract_type() -> String:
	return "FeedEvent"


## Yeni bir feed event oluşturur (factory).
static func create(
	p_event_type: String,
	p_message: String,
	p_owner_role: String,
	p_severity: int = Severity.INFO
) -> AIFeedEvent:
	var e := AIFeedEvent.new()
	e.id = AIContractBase.generate_id("evt")
	e.timestamp = _now_iso_ms()
	e.event_type = p_event_type
	e.message = p_message
	e.owner_role = p_owner_role
	e.severity = p_severity
	return e


## Severity'nin string adı.
func severity_name() -> String:
	return SEVERITY_NAMES.get(severity, "info")


## Severity'nin UI rengi.
func severity_color() -> String:
	return SEVERITY_COLOR.get(severity, "#3B82F6")


## Live Feed satırı olarak biçimlenmiş metin döndürür.
## Örn: "[12:34:56.789] [CodeEngineer] TASK_STARTED  player.gd düzenleniyor"
func format_line() -> String:
	var time_part: String = timestamp
	var t_idx: int = timestamp.find("T")
	if t_idx >= 0:
		time_part = timestamp.substr(t_idx + 1).rstrip("Z")
	return "[%s] [%s] %s  %s" % [time_part, owner_role, event_type, message]


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"timestamp": timestamp,
		"sequence": sequence,
		"event_type": event_type,
		"message": message,
		"severity": SEVERITY_NAMES.get(severity, "info"),
		"owner_role": owner_role,
		"task_ref": task_ref,
		"iteration_ref": iteration_ref,
		"metadata": metadata,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	timestamp = data.get("timestamp", "")
	sequence = int(data.get("sequence", 0))
	event_type = data.get("event_type", "")
	message = data.get("message", "")
	severity = _parse_severity(data.get("severity", "info"))
	owner_role = data.get("owner_role", "")
	task_ref = data.get("task_ref", "")
	iteration_ref = data.get("iteration_ref", "")
	metadata = data.get("metadata", {})


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, event_type, "event_type")
	require_non_empty_string(result, owner_role, "owner_role")
	if timestamp.is_empty():
		result.add_warning("timestamp boş — sıralama bozuk olabilir")


static func _parse_severity(s: String) -> int:
	for key in SEVERITY_NAMES:
		if SEVERITY_NAMES[key] == s:
			return key
	return Severity.INFO


## Milisaniye hassasiyetli ISO 8601 zaman damgası.
static func _now_iso_ms() -> String:
	var base: String = Time.get_datetime_string_from_system(true)
	var ms: int = Time.get_ticks_msec() % 1000
	return "%s.%03dZ" % [base, ms]
