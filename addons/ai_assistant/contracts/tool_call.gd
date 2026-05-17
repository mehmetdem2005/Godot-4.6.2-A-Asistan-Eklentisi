@tool
class_name AIToolCall
extends AIContractBase

## ToolCall — bir cell role'ün bir araç (tool) çağrısı.
##
## Cell role'ler işlerini "tool" çağırarak yapar (generate_texture,
## search_assets, run_test...). Her çağrı bir ToolCall olarak kaydedilir.
##
## Idempotency key sayesinde aynı çağrı tekrar yapılırsa tespit edilir
## (cache hit veya tekrar koruması).

# --- Kimlik ---
var id: String = ""
var task_ref: String = ""            ## Hangi task bağlamında çağrıldı

# --- Çağrı ---
var tool_name: String = ""           ## Çağrılan aracın adı
var params: Dictionary = {}          ## Araç parametreleri

# --- Sahiplik ---
var owner_role: String = ""          ## Hangi cell role çağırdı

# --- Maliyet ve onay ---
var cost_estimate: float = 0.0       ## Tahmini maliyet (USD) — Madde 5
var requires_approval: bool = false  ## HITL onayı gerektirir mi
var idempotency_key: String = ""     ## Tekrar tespiti için

# --- Durum ---
var was_approved: bool = false       ## Onaylandı mı (gerekiyorsa)
var was_cache_hit: bool = false      ## Cache'ten mi geldi (maliyet $0)

# --- Zaman ---
var called_at: String = ""


func contract_type() -> String:
	return "ToolCall"


## Yeni bir tool call oluşturur (factory).
static func create(p_tool_name: String, p_owner_role: String) -> AIToolCall:
	var tc := AIToolCall.new()
	tc.id = AIContractBase.generate_id("tool")
	tc.tool_name = p_tool_name
	tc.owner_role = p_owner_role
	tc.idempotency_key = AIContractBase.generate_id("idem")
	tc.called_at = AIContractBase.now_iso()
	return tc


## Bu çağrının gerçek (efektif) maliyetini döndürür.
## Cache hit ise maliyet 0.
func effective_cost() -> float:
	if was_cache_hit:
		return 0.0
	return cost_estimate


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"task_ref": task_ref,
		"tool_name": tool_name,
		"params": params,
		"owner_role": owner_role,
		"cost_estimate": cost_estimate,
		"requires_approval": requires_approval,
		"idempotency_key": idempotency_key,
		"was_approved": was_approved,
		"was_cache_hit": was_cache_hit,
		"called_at": called_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	task_ref = data.get("task_ref", "")
	tool_name = data.get("tool_name", "")
	params = data.get("params", {})
	owner_role = data.get("owner_role", "")
	cost_estimate = float(data.get("cost_estimate", 0.0))
	requires_approval = bool(data.get("requires_approval", false))
	idempotency_key = data.get("idempotency_key", "")
	was_approved = bool(data.get("was_approved", false))
	was_cache_hit = bool(data.get("was_cache_hit", false))
	called_at = data.get("called_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, tool_name, "tool_name")
	require_non_empty_string(result, owner_role, "owner_role")
	if cost_estimate < 0.0:
		result.add_error("cost_estimate negatif olamaz: %s" % str(cost_estimate))
	# Onay gerektiren ama onaylanmamış çağrı çalıştırılmamalı
	if requires_approval and not was_approved:
		result.add_warning(
			"Tool call '%s' onay gerektiriyor ama henüz onaylanmadı" % tool_name
		)
