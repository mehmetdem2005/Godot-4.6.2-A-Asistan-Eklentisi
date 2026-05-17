@tool
class_name AICostRecord
extends AIContractBase

## CostRecord — LLM çağrı maliyet kaydı (Madde 5 Cost Guardrails).
##
## Her LLM çağrısı tamamlandığında gerçek kullanım ve maliyet bu kayda yazılır.
## Append-only ledger oluşturur — audit izi + tahmin kalibrasyonu için.
##
## was_estimated alanı: tahmin mi yoksa gerçek kullanım mı olduğunu belirtir.

# --- Kimlik ---
var id: String = ""
var request_ref: String = ""         ## Hangi ProviderRequest'e ait
var task_ref: String = ""

# --- Sağlayıcı ---
var provider: String = ""            ## deepseek | openai | anthropic | gemini
var model: String = ""

# --- Token kullanımı ---
var input_tokens: int = 0
var output_tokens: int = 0

# --- Maliyet ---
var input_cost_usd: float = 0.0
var output_cost_usd: float = 0.0
var total_cost_usd: float = 0.0

# --- Sahiplik ---
var cell_role: String = ""           ## Hangi cell role maliyeti üretti

# --- Meta ---
var was_estimated: bool = false      ## Tahmin mi gerçek mi
var was_cache_hit: bool = false      ## Cache hit ise maliyet 0
var was_approved: bool = true        ## HITL onayı alındı mı (gerekiyorsa)
var latency_ms: int = 0              ## Çağrı süresi

# --- Zaman ---
var recorded_at: String = ""


func contract_type() -> String:
	return "CostRecord"


## Yeni bir maliyet kaydı oluşturur (factory).
static func create(p_provider: String, p_cell_role: String) -> AICostRecord:
	var c := AICostRecord.new()
	c.id = AIContractBase.generate_id("cost")
	c.provider = p_provider
	c.cell_role = p_cell_role
	c.recorded_at = AIContractBase.now_iso()
	return c


## Token kullanımından toplam maliyeti hesaplar ve set eder.
func compute_total() -> float:
	if was_cache_hit:
		total_cost_usd = 0.0
	else:
		total_cost_usd = input_cost_usd + output_cost_usd
	return total_cost_usd


## Toplam token sayısı.
func total_tokens() -> int:
	return input_tokens + output_tokens


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"request_ref": request_ref,
		"task_ref": task_ref,
		"provider": provider,
		"model": model,
		"input_tokens": input_tokens,
		"output_tokens": output_tokens,
		"input_cost_usd": input_cost_usd,
		"output_cost_usd": output_cost_usd,
		"total_cost_usd": total_cost_usd,
		"cell_role": cell_role,
		"was_estimated": was_estimated,
		"was_cache_hit": was_cache_hit,
		"was_approved": was_approved,
		"latency_ms": latency_ms,
		"recorded_at": recorded_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	request_ref = data.get("request_ref", "")
	task_ref = data.get("task_ref", "")
	provider = data.get("provider", "")
	model = data.get("model", "")
	input_tokens = int(data.get("input_tokens", 0))
	output_tokens = int(data.get("output_tokens", 0))
	input_cost_usd = float(data.get("input_cost_usd", 0.0))
	output_cost_usd = float(data.get("output_cost_usd", 0.0))
	total_cost_usd = float(data.get("total_cost_usd", 0.0))
	cell_role = data.get("cell_role", "")
	was_estimated = bool(data.get("was_estimated", false))
	was_cache_hit = bool(data.get("was_cache_hit", false))
	was_approved = bool(data.get("was_approved", true))
	latency_ms = int(data.get("latency_ms", 0))
	recorded_at = data.get("recorded_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, provider, "provider")
	if input_tokens < 0 or output_tokens < 0:
		result.add_error("token sayıları negatif olamaz")
	if input_cost_usd < 0.0 or output_cost_usd < 0.0 or total_cost_usd < 0.0:
		result.add_error("maliyet negatif olamaz")
	# Cache hit ise maliyet 0 olmalı
	if was_cache_hit and total_cost_usd > 0.0:
		result.add_warning("cache hit ama maliyet 0 değil — kontrol et")
	# Toplam tutarlılığı (cache hit değilse)
	if not was_cache_hit:
		var expected: float = input_cost_usd + output_cost_usd
		if abs(total_cost_usd - expected) > 0.0001:
			result.add_warning("total_cost_usd, input+output toplamıyla uyuşmuyor")
