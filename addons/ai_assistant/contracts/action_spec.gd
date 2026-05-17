@tool
class_name AIActionSpec
extends AIContractBase

## ActionSpec — atomik işlem birimi.
##
## Bir task, ActionSpec listesine derlenir. Her ActionSpec tek bir atomik
## işlemdir: dosya yaz, node ekle, property set et, sahne kaydet, shader derle...
##
## ActionSpec'ler serileştirilebilir VE yeniden oynatılabilir (replay) —
## bu, debug loop ve time-travel için kritiktir.

## Atomik işlem tipleri.
enum ActionType {
	FILE_WRITE,        ## Dosya oluştur/yaz
	FILE_DELETE,       ## Dosya sil
	NODE_ADD,          ## Sahneye node ekle
	NODE_REMOVE,       ## Node sil
	NODE_REPARENT,     ## Node taşı
	PROPERTY_SET,      ## Node property değiştir
	SCENE_SAVE,        ## Sahne kaydet
	SCENE_CREATE,      ## Yeni sahne oluştur
	RESOURCE_CREATE,   ## Resource (.tres) oluştur
	SHADER_COMPILE,    ## Shader derle/doğrula
	SCRIPT_ATTACH,     ## Script bir node'a bağla
	SIGNAL_CONNECT,    ## Signal bağlantısı kur
	PROJECT_SETTING,   ## project.godot ayarı değiştir
	INPUT_MAP_EDIT,    ## InputMap action ekle/değiştir
	CUSTOM,            ## Tanımlı tiplere uymayan
}

const ACTION_TYPE_NAMES: Dictionary = {
	ActionType.FILE_WRITE: "file_write",
	ActionType.FILE_DELETE: "file_delete",
	ActionType.NODE_ADD: "node_add",
	ActionType.NODE_REMOVE: "node_remove",
	ActionType.NODE_REPARENT: "node_reparent",
	ActionType.PROPERTY_SET: "property_set",
	ActionType.SCENE_SAVE: "scene_save",
	ActionType.SCENE_CREATE: "scene_create",
	ActionType.RESOURCE_CREATE: "resource_create",
	ActionType.SHADER_COMPILE: "shader_compile",
	ActionType.SCRIPT_ATTACH: "script_attach",
	ActionType.SIGNAL_CONNECT: "signal_connect",
	ActionType.PROJECT_SETTING: "project_setting",
	ActionType.INPUT_MAP_EDIT: "input_map_edit",
	ActionType.CUSTOM: "custom",
}

## Yıkıcı (geri alınamaz tehlikeli) işlem tipleri — HITL onayı gerektirir.
const DESTRUCTIVE_TYPES: Array = [
	ActionType.FILE_DELETE,
	ActionType.NODE_REMOVE,
	ActionType.PROJECT_SETTING,
]

# --- Kimlik ---
var id: String = ""
var task_ref: String = ""            ## Hangi task'a ait
var sequence: int = 0                ## Task içindeki sıra no

# --- İşlem ---
var action_type: int = ActionType.CUSTOM
var target_path: String = ""         ## Hedef dosya/node yolu
var params: Dictionary = {}          ## İşleme özel parametreler

# --- Sahiplik ---
var owner_role: String = ""          ## Hangi cell role bu action'ı üretti

# --- Geri alma ---
var idempotency_key: String = ""     ## Aynı action tekrar uygulanırsa tespit için
var is_reversible: bool = true       ## Geri alınabilir mi
var reverse_params: Dictionary = {}  ## Geri alma için gereken veri (snapshot)

# --- Doğrulama ---
var expected_outcome: String = ""    ## Bu action sonrası beklenen durum (verifier için)


func contract_type() -> String:
	return "ActionSpec"


## Yeni bir action oluşturur (factory).
static func create(p_action_type: int, p_target_path: String, p_owner_role: String) -> AIActionSpec:
	var a := AIActionSpec.new()
	a.id = AIContractBase.generate_id("act")
	a.action_type = p_action_type
	a.target_path = p_target_path
	a.owner_role = p_owner_role
	a.idempotency_key = AIContractBase.generate_id("idem")
	return a


## Action tipinin string adı.
func action_type_name() -> String:
	return ACTION_TYPE_NAMES.get(action_type, "custom")


## Bu action yıkıcı mı (HITL onayı gerektirir)?
func is_destructive() -> bool:
	return DESTRUCTIVE_TYPES.has(action_type)


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"task_ref": task_ref,
		"sequence": sequence,
		"action_type": ACTION_TYPE_NAMES.get(action_type, "custom"),
		"target_path": target_path,
		"params": params,
		"owner_role": owner_role,
		"idempotency_key": idempotency_key,
		"is_reversible": is_reversible,
		"reverse_params": reverse_params,
		"expected_outcome": expected_outcome,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	task_ref = data.get("task_ref", "")
	sequence = int(data.get("sequence", 0))
	action_type = _parse_action_type(data.get("action_type", "custom"))
	target_path = data.get("target_path", "")
	params = data.get("params", {})
	owner_role = data.get("owner_role", "")
	idempotency_key = data.get("idempotency_key", "")
	is_reversible = bool(data.get("is_reversible", true))
	reverse_params = data.get("reverse_params", {})
	expected_outcome = data.get("expected_outcome", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, owner_role, "owner_role")
	# CUSTOM dışı tüm action'lar hedef yol gerektirir
	if action_type != ActionType.CUSTOM:
		require_non_empty_string(result, target_path, "target_path")
	# Yıkıcı ama geri alınamaz işlem — kritik uyarı
	if is_destructive() and not is_reversible:
		result.add_warning(
			"Yıkıcı + geri alınamaz action (%s) — HITL onayı zorunlu olmalı"
			% action_type_name()
		)


static func _parse_action_type(s: String) -> int:
	for key in ACTION_TYPE_NAMES:
		if ACTION_TYPE_NAMES[key] == s:
			return key
	return ActionType.CUSTOM
