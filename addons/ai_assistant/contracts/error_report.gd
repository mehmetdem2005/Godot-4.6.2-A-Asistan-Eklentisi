@tool
class_name AIErrorReport
extends AIContractBase

## ErrorReport — hata raporu (Madde 2 Debug Loop).
##
## Bir runtime/parse/davranış hatası tespit edildiğinde sınıflandırılır ve
## bu rapora kaydedilir. DebugEngineer bu rapordan teşhis + fix planı üretir.
##
## Hata sınıflandırması deterministiktir (LLM gerektirmez) — kategori bilgisi
## fix stratejisini yönlendirir.

## Hata kategorileri.
enum Category {
	SYNTAX,           ## Parse/sözdizimi hatası
	MISSING_METHOD,   ## Var olmayan metod çağrısı (Godot 3->4 sık)
	MISSING_NODE,     ## Bulunamayan node yolu
	TYPE_MISMATCH,    ## Tip uyuşmazlığı
	NULL_REFERENCE,   ## Null/freed nesne erişimi
	SIGNAL_ERROR,     ## Signal bağlantı hatası
	RESOURCE_ERROR,   ## Resource yükleme hatası
	SHADER_ERROR,     ## Shader derleme hatası
	API_DEPRECATED,   ## Godot 3 API kullanımı (4'te değişmiş)
	RUNTIME_LOGIC,    ## Mantık hatası (crash değil ama yanlış)
	PERFORMANCE,      ## Performans bütçesi aşımı
	UNKNOWN,          ## Sınıflandırılamadı
}

const CATEGORY_NAMES: Dictionary = {
	Category.SYNTAX: "syntax",
	Category.MISSING_METHOD: "missing_method",
	Category.MISSING_NODE: "missing_node",
	Category.TYPE_MISMATCH: "type_mismatch",
	Category.NULL_REFERENCE: "null_reference",
	Category.SIGNAL_ERROR: "signal_error",
	Category.RESOURCE_ERROR: "resource_error",
	Category.SHADER_ERROR: "shader_error",
	Category.API_DEPRECATED: "api_deprecated",
	Category.RUNTIME_LOGIC: "runtime_logic",
	Category.PERFORMANCE: "performance",
	Category.UNKNOWN: "unknown",
}

## Deterministik (LLM gerektirmeyen) çözüm yolu olan kategoriler.
const DETERMINISTIC_FIXABLE: Array = [
	Category.MISSING_METHOD,
	Category.API_DEPRECATED,
]

## Hata önem seviyesi.
enum Severity {
	LOW,       ## Uyarı seviyesi
	MEDIUM,    ## Düzeltilmeli
	HIGH,      ## Çalışmayı engelliyor
	CRITICAL,  ## Crash / veri kaybı riski
}

const SEVERITY_NAMES: Dictionary = {
	Severity.LOW: "low",
	Severity.MEDIUM: "medium",
	Severity.HIGH: "high",
	Severity.CRITICAL: "critical",
}

# --- Kimlik ---
var id: String = ""
var task_ref: String = ""

# --- Hata bilgisi ---
var category: int = Category.UNKNOWN
var severity: int = Severity.MEDIUM
var raw_message: String = ""         ## Godot'un ürettiği ham hata metni
var classified_summary: String = ""  ## Sınıflandırılmış kısa özet

# --- Konum ---
var file_path: String = ""
var line_number: int = -1            ## -1 = bilinmiyor
var node_path: String = ""           ## Sahne hatası ise

# --- Teşhis ---
var stack_trace: PackedStringArray = PackedStringArray()
var probable_cause: String = ""      ## DebugEngineer teşhisi
var suggested_fix: String = ""       ## Önerilen düzeltme

# --- Çözüm takibi ---
var retry_count: int = 0
var is_resolved: bool = false

# --- Zaman ---
var detected_at: String = ""


func contract_type() -> String:
	return "ErrorReport"


## Yeni bir hata raporu oluşturur (factory).
static func create(p_category: int, p_raw_message: String) -> AIErrorReport:
	var e := AIErrorReport.new()
	e.id = AIContractBase.generate_id("err")
	e.category = p_category
	e.raw_message = p_raw_message
	e.detected_at = AIContractBase.now_iso()
	return e


## Kategori string adı.
func category_name() -> String:
	return CATEGORY_NAMES.get(category, "unknown")


## Önem string adı.
func severity_name() -> String:
	return SEVERITY_NAMES.get(severity, "medium")


## Bu hata deterministik olarak (LLM'siz) çözülebilir mi?
func is_deterministic_fixable() -> bool:
	return DETERMINISTIC_FIXABLE.has(category)


## Bu hata için yeniden deneme yapılabilir mi (max 3)?
func can_retry() -> bool:
	return retry_count < 3 and not is_resolved


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"task_ref": task_ref,
		"category": CATEGORY_NAMES.get(category, "unknown"),
		"severity": SEVERITY_NAMES.get(severity, "medium"),
		"raw_message": raw_message,
		"classified_summary": classified_summary,
		"file_path": file_path,
		"line_number": line_number,
		"node_path": node_path,
		"stack_trace": stack_trace,
		"probable_cause": probable_cause,
		"suggested_fix": suggested_fix,
		"retry_count": retry_count,
		"is_resolved": is_resolved,
		"detected_at": detected_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	task_ref = data.get("task_ref", "")
	category = _parse_category(data.get("category", "unknown"))
	severity = _parse_severity(data.get("severity", "medium"))
	raw_message = data.get("raw_message", "")
	classified_summary = data.get("classified_summary", "")
	file_path = data.get("file_path", "")
	line_number = int(data.get("line_number", -1))
	node_path = data.get("node_path", "")
	stack_trace = PackedStringArray(data.get("stack_trace", []))
	probable_cause = data.get("probable_cause", "")
	suggested_fix = data.get("suggested_fix", "")
	retry_count = int(data.get("retry_count", 0))
	is_resolved = bool(data.get("is_resolved", false))
	detected_at = data.get("detected_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, raw_message, "raw_message")
	if retry_count < 0:
		result.add_error("retry_count negatif olamaz")
	if retry_count > 3:
		result.add_warning("retry_count 3'ü aştı — debug loop limiti")


static func _parse_category(s: String) -> int:
	for key in CATEGORY_NAMES:
		if CATEGORY_NAMES[key] == s:
			return key
	return Category.UNKNOWN


static func _parse_severity(s: String) -> int:
	for key in SEVERITY_NAMES:
		if SEVERITY_NAMES[key] == s:
			return key
	return Severity.MEDIUM
