@tool
class_name AIProviderRequest
extends AIContractBase

## ProviderRequest — LLM sağlayıcı isteği (Layer 7).
##
## Bir cell role LLM çağırmak istediğinde bir ProviderRequest oluşturur.
## Router bu isteği uygun provider'a (DeepSeek/OpenAI/Anthropic/Gemini) yönlendirir.
##
## Mock policy: provider devre dışıysa PROVIDER_DISABLED hatası fırlatılır,
## sahte cevap üretilmez.

## Desteklenen sağlayıcılar.
enum Provider {
	DEEPSEEK,   ## Başlangıçta tek aktif (bütçe dostu)
	OPENAI,     ## Phase 2+ (key gelince)
	ANTHROPIC,  ## Phase 2+
	GEMINI,     ## Phase 2+
}

const PROVIDER_NAMES: Dictionary = {
	Provider.DEEPSEEK: "deepseek",
	Provider.OPENAI: "openai",
	Provider.ANTHROPIC: "anthropic",
	Provider.GEMINI: "gemini",
}

## İstek amacı — model seçimini etkiler.
enum Purpose {
	REASONING,    ## Plan, analiz, karar
	CODE,         ## Kod üretimi
	VALIDATION,   ## Doğrulama, inceleme
	EMBEDDING,    ## Vektör gömme
	SUMMARY,      ## Özetleme
}

const PURPOSE_NAMES: Dictionary = {
	Purpose.REASONING: "reasoning",
	Purpose.CODE: "code",
	Purpose.VALIDATION: "validation",
	Purpose.EMBEDDING: "embedding",
	Purpose.SUMMARY: "summary",
}

# --- Kimlik ---
var id: String = ""
var task_ref: String = ""

# --- İstek ---
var provider: int = Provider.DEEPSEEK
var model: String = ""               ## Belirli model adı (boş = router seçer)
var purpose: int = Purpose.REASONING
var system_prompt: String = ""
var messages: Array = []             ## [{role: "user"|"assistant", content: String}]
var temperature: float = 0.7
## İstenen çıktı token tavanı. Gerçek üst sınır sağlayıcı/model adapter'ı
## tarafından uygulanır (DeepSeek V4: 384K); yapay küçük bir ortak tavan yok.
var max_tokens: int = 100000

# --- Sahiplik ---
var owner_role: String = ""          ## Hangi cell role çağırıyor

# --- Maliyet ve önbellek ---
var estimated_input_tokens: int = 0
var estimated_cost_usd: float = 0.0
var cache_key: String = ""           ## Önbellek anahtarı (deterministik)

# --- Zaman ---
var created_at: String = ""


func contract_type() -> String:
	return "ProviderRequest"


## Yeni bir provider isteği oluşturur (factory).
static func create(p_purpose: int, p_owner_role: String) -> AIProviderRequest:
	var r := AIProviderRequest.new()
	r.id = AIContractBase.generate_id("req")
	r.purpose = p_purpose
	r.owner_role = p_owner_role
	r.created_at = AIContractBase.now_iso()
	return r


## Provider'ın string adı.
func provider_name() -> String:
	return PROVIDER_NAMES.get(provider, "deepseek")


## Amaç string adı.
func purpose_name() -> String:
	return PURPOSE_NAMES.get(purpose, "reasoning")


## İsteğe bir mesaj ekler.
func add_message(role: String, content: String) -> void:
	messages.append({"role": role, "content": content})


## Önbellek anahtarını hesaplar — aynı istek aynı anahtar üretir.
## Amaç ve DeepSeek düşünme modu da kimliğe dahildir; aynı V4 modelinin
## düşünmeli/düşünmesiz sonuçları birbirinin cache kaydını kullanamaz.
func compute_cache_key() -> String:
	var model_key: String = model
	if provider == Provider.DEEPSEEK:
		model_key = AIDeepSeekModelPolicy.cache_discriminator(model, purpose)
	var canonical: String = "%s|%s|purpose:%s|%s|temp:%s" % [
		provider_name(), model_key, purpose_name(), system_prompt,
		str(temperature)
	]
	for m in messages:
		canonical += "|%s:%s" % [m.get("role", ""), m.get("content", "")]

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	cache_key = ctx.finish().hex_encode()
	return cache_key


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"task_ref": task_ref,
		"provider": PROVIDER_NAMES.get(provider, "deepseek"),
		"model": model,
		"purpose": PURPOSE_NAMES.get(purpose, "reasoning"),
		"system_prompt": system_prompt,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens,
		"owner_role": owner_role,
		"estimated_input_tokens": estimated_input_tokens,
		"estimated_cost_usd": estimated_cost_usd,
		"cache_key": cache_key,
		"created_at": created_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	task_ref = data.get("task_ref", "")
	provider = _parse_provider(data.get("provider", "deepseek"))
	model = data.get("model", "")
	purpose = _parse_purpose(data.get("purpose", "reasoning"))
	system_prompt = data.get("system_prompt", "")
	messages = data.get("messages", [])
	temperature = float(data.get("temperature", 0.7))
	max_tokens = int(data.get("max_tokens", 100000))
	owner_role = data.get("owner_role", "")
	estimated_input_tokens = int(data.get("estimated_input_tokens", 0))
	estimated_cost_usd = float(data.get("estimated_cost_usd", 0.0))
	cache_key = data.get("cache_key", "")
	created_at = data.get("created_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, owner_role, "owner_role")
	require_in_range(result, temperature, 0.0, 2.0, "temperature")
	if max_tokens <= 0:
		result.add_error("max_tokens pozitif olmalı: %d" % max_tokens)
	if estimated_cost_usd < 0.0:
		result.add_error("estimated_cost_usd negatif olamaz")
	# Embedding dışı istekler mesaj gerektirir
	if purpose != Purpose.EMBEDDING and messages.is_empty():
		result.add_warning("İstek hiç mesaj içermiyor")


static func _parse_provider(s: String) -> int:
	for key in PROVIDER_NAMES:
		if PROVIDER_NAMES[key] == s:
			return key
	return Provider.DEEPSEEK


static func _parse_purpose(s: String) -> int:
	for key in PURPOSE_NAMES:
		if PURPOSE_NAMES[key] == s:
			return key
	return Purpose.REASONING
