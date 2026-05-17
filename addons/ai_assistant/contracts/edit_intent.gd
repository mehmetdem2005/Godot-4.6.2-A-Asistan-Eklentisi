@tool
class_name AIEditIntent
extends AIContractBase

## EditIntent — kod düzenleme niyeti (Madde 19 Surgical Code Editing).
##
## Her kod değişikliği task'ı önce sınıflandırılır: ne tür bir düzenleme?
## Bu sınıflandırma, hangi düzenleme protokolünün kullanılacağını belirler ve
## LLM'in tüm dosyayı baştan yazmasını ENGELLER.
##
## Çekirdek prensip: LLM'e asla full file verme — sadece ilgili scope penceresi.

## Düzenleme niyetleri (9 tip).
enum IntentType {
	ADD_NEW_FILE,            ## Yeni dosya oluştur
	ADD_TO_EXISTING,         ## Mevcut dosyaya ekle
	MODIFY_EXISTING_FUNCTION,## Fonksiyon gövdesini değiştir
	MODIFY_FUNCTION_SIGNATURE,## Fonksiyon imzasını değiştir
	DELETE_CODE,             ## Kod sil
	RENAME_SYMBOL,           ## Sembol yeniden adlandır
	REFACTOR,                ## Yapısal değişiklik (çok adımlı)
	FIX_BUG_AT_LINE,         ## Belirli satırda bug düzelt
	REPLACE_FILE,            ## Dosyayı tamamen değiştir (HITL onayı zorunlu)
}

const INTENT_NAMES: Dictionary = {
	IntentType.ADD_NEW_FILE: "add_new_file",
	IntentType.ADD_TO_EXISTING: "add_to_existing",
	IntentType.MODIFY_EXISTING_FUNCTION: "modify_existing_function",
	IntentType.MODIFY_FUNCTION_SIGNATURE: "modify_function_signature",
	IntentType.DELETE_CODE: "delete_code",
	IntentType.RENAME_SYMBOL: "rename_symbol",
	IntentType.REFACTOR: "refactor",
	IntentType.FIX_BUG_AT_LINE: "fix_bug_at_line",
	IntentType.REPLACE_FILE: "replace_file",
}

## Her niyet için kullanılacak düzenleme protokolü.
const INTENT_PROTOCOL: Dictionary = {
	IntentType.ADD_NEW_FILE: "direct_write",
	IntentType.ADD_TO_EXISTING: "insert_at_anchor",
	IntentType.MODIFY_EXISTING_FUNCTION: "search_replace_block",
	IntentType.MODIFY_FUNCTION_SIGNATURE: "search_replace_with_reference_update",
	IntentType.DELETE_CODE: "delete_block",
	IntentType.RENAME_SYMBOL: "project_wide_rename",
	IntentType.REFACTOR: "multi_step_edit",
	IntentType.FIX_BUG_AT_LINE: "search_replace_block",
	IntentType.REPLACE_FILE: "explicit_replace",
}

## HITL onayı zorunlu olan niyetler.
const REQUIRES_APPROVAL: Array = [
	IntentType.REPLACE_FILE,
]

## Maksimum cerrahi düzenleme satır sayısı — bunun üstü REFACTOR'a bölünmeli.
const MAX_SURGICAL_LINES: int = 50

# --- Kimlik ---
var id: String = ""
var task_ref: String = ""

# --- Niyet ---
var intent_type: int = IntentType.MODIFY_EXISTING_FUNCTION
var target_file: String = ""
var target_symbol: String = ""       ## Fonksiyon/sınıf/değişken adı (varsa)

# --- Scope penceresi (LLM'e verilecek bağlam) ---
var scope_start_line: int = -1       ## -1 = belirsiz
var scope_end_line: int = -1
var scope_context_lines: int = 20    ## Hedef etrafında verilecek bağlam satırı

# --- Beklenti ---
var expected_change_size: int = 0    ## Tahmini değişen satır sayısı
var description: String = ""         ## Ne yapılacak (insan-okunabilir)

# --- Sahiplik ---
var owner_role: String = ""


func contract_type() -> String:
	return "EditIntent"


## Yeni bir düzenleme niyeti oluşturur (factory).
static func create(p_intent_type: int, p_target_file: String, p_owner_role: String) -> AIEditIntent:
	var e := AIEditIntent.new()
	e.id = AIContractBase.generate_id("edit")
	e.intent_type = p_intent_type
	e.target_file = p_target_file
	e.owner_role = p_owner_role
	return e


## Niyet tipinin string adı.
func intent_name() -> String:
	return INTENT_NAMES.get(intent_type, "modify_existing_function")


## Bu niyet için kullanılacak düzenleme protokolü.
func protocol() -> String:
	return INTENT_PROTOCOL.get(intent_type, "search_replace_block")


## Bu niyet HITL onayı gerektiriyor mu?
func requires_approval() -> bool:
	return REQUIRES_APPROVAL.has(intent_type)


## Bu niyet cerrahi sınırı aşıyor mu (REFACTOR'a bölünmeli)?
func exceeds_surgical_limit() -> bool:
	return expected_change_size > MAX_SURGICAL_LINES


## Bu niyet mevcut bir dosyayı değiştiriyor mu (yeni dosya değil)?
func modifies_existing() -> bool:
	return intent_type != IntentType.ADD_NEW_FILE


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"task_ref": task_ref,
		"intent_type": INTENT_NAMES.get(intent_type, "modify_existing_function"),
		"target_file": target_file,
		"target_symbol": target_symbol,
		"scope_start_line": scope_start_line,
		"scope_end_line": scope_end_line,
		"scope_context_lines": scope_context_lines,
		"expected_change_size": expected_change_size,
		"description": description,
		"owner_role": owner_role,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	task_ref = data.get("task_ref", "")
	intent_type = _parse_intent(data.get("intent_type", "modify_existing_function"))
	target_file = data.get("target_file", "")
	target_symbol = data.get("target_symbol", "")
	scope_start_line = int(data.get("scope_start_line", -1))
	scope_end_line = int(data.get("scope_end_line", -1))
	scope_context_lines = int(data.get("scope_context_lines", 20))
	expected_change_size = int(data.get("expected_change_size", 0))
	description = data.get("description", "")
	owner_role = data.get("owner_role", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, target_file, "target_file")
	require_non_empty_string(result, owner_role, "owner_role")
	# Mevcut dosyayı değiştiren niyetler için hedef dosya .gd/.tscn/.gdshader olmalı — bilgi amaçlı
	if expected_change_size < 0:
		result.add_error("expected_change_size negatif olamaz")
	# Cerrahi sınır aşımı — REFACTOR dışı niyetlerde uyarı
	if exceeds_surgical_limit() and intent_type != IntentType.REFACTOR \
			and intent_type != IntentType.REPLACE_FILE \
			and intent_type != IntentType.ADD_NEW_FILE:
		result.add_warning(
			"Değişiklik cerrahi sınırı (%d satır) aşıyor (%d) — REFACTOR'a bölünmeli"
			% [MAX_SURGICAL_LINES, expected_change_size]
		)
	# Fonksiyon değiştiren niyetler hedef sembol bekler
	if (intent_type == IntentType.MODIFY_EXISTING_FUNCTION \
			or intent_type == IntentType.MODIFY_FUNCTION_SIGNATURE) \
			and target_symbol.is_empty():
		result.add_warning("Fonksiyon düzenleme niyeti hedef sembol içermiyor")


static func _parse_intent(s: String) -> int:
	for key in INTENT_NAMES:
		if INTENT_NAMES[key] == s:
			return key
	return IntentType.MODIFY_EXISTING_FUNCTION
