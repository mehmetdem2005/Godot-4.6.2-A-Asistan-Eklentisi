@tool
class_name AIProviderRouter
extends RefCounted

## ProviderRouter — çoklu sağlayıcı yönlendirici (Layer 7).
##
## Layer 7'nin beyni. Bir AIProviderRequest alır ve onu doğru LLM
## sağlayıcısına ulaştırıp AIProviderResponse döndürür. Birleştirdiği
## bileşenler:
##   - ModeController  — hangi sağlayıcı/parametre (Eco/Quality, Single/Pro)
##   - PromptCache     — aynı istek varsa API'ye gitme
##   - 4 Adapter       — sağlayıcıya özel format çevirisi
##   - FallbackChain   — sağlayıcı çökerse sıradakine
##   - HTTPTransport   — gerçek ağ çağrısı (dışarıdan enjekte edilir)
##
## PRO_MAX üretim profili:
##   DeepSeek'e giden her canlı istek ağdan önce deepseek-v4-pro,
##   thinking=enabled, reasoning_effort=max ve mümkün olan en yüksek
##   güvenli çıktı bütçesine normalize edilir. Eski/Flash ayarları canlı
##   trafiğin kalitesini düşüremez.

var mode: AIModeController
var cache: AIPromptCache
var fallback: AIFallbackChain

var _adapters: Dictionary = {}
var _api_keys: Dictionary = {}
var _transport: AIHTTPTransport = null


func _init() -> void:
	mode = AIModeController.new()
	cache = AIPromptCache.new()
	fallback = AIFallbackChain.new()
	_register_adapters()


func _register_adapters() -> void:
	var deepseek := AIDeepSeekV4Adapter.new()
	var openai := AIOpenAIAdapter.new()
	var anthropic := AIAnthropicAdapter.new()
	var gemini := AIGeminiAdapter.new()
	_adapters[AIProviderRequest.Provider.DEEPSEEK] = deepseek
	_adapters[AIProviderRequest.Provider.OPENAI] = openai
	_adapters[AIProviderRequest.Provider.ANTHROPIC] = anthropic
	_adapters[AIProviderRequest.Provider.GEMINI] = gemini


# ============================================================
# YAPILANDIRMA
# ============================================================

func attach_transport(transport: AIHTTPTransport) -> void:
	_transport = transport


func set_api_key(provider: int, key: String) -> void:
	_api_keys[provider] = key.strip_edges()


func has_api_key(provider: int) -> bool:
	return _api_keys.has(provider) and not str(_api_keys[provider]).is_empty()


func get_adapter(provider: int) -> AIProviderAdapterBase:
	return _adapters.get(provider, null)


# ============================================================
# İSTEK HAZIRLAMA
# ============================================================

func _apply_mode(request: AIProviderRequest) -> void:
	request.max_tokens = mode.resolve_max_tokens(request.max_tokens)
	request.temperature = mode.resolve_temperature(request.temperature)
	if mode.is_single_provider():
		request.provider = AIProviderRequest.Provider.DEEPSEEK
	if request.provider == AIProviderRequest.Provider.DEEPSEEK:
		_apply_deepseek_pro_max_profile(request)


## DeepSeek canlı isteklerini tek üretim profiline sabitler.
func _apply_deepseek_pro_max_profile(request: AIProviderRequest) -> void:
	request.provider = AIProviderRequest.Provider.DEEPSEEK
	request.model = AIDeepSeekModelPolicy.production_model(request.model)
	if request.estimated_input_tokens <= 0:
		request.estimated_input_tokens = _estimate_input_tokens(request)
	request.max_tokens = AIDeepSeekModelPolicy.max_output_for_context(
		request.estimated_input_tokens
	)


## Harici tokenizer gerektirmeyen, bağlam taşmasını önlemeye yönelik
## muhafazakâr tahmin. Türkçe/kod karışımı için yaklaşık 3 karakter/token
## ve mesaj başına protokol payı kullanılır.
func _estimate_input_tokens(request: AIProviderRequest) -> int:
	var chars: int = request.system_prompt.length()
	var message_count: int = 0
	for message in request.messages:
		if typeof(message) != TYPE_DICTIONARY:
			continue
		message_count += 1
		chars += str(message.get("role", "")).length()
		chars += str(message.get("content", "")).length()
	return maxi(1, int(ceil(float(chars) / 3.0)) + message_count * 16 + 128)


func _build_fallback_chain(request: AIProviderRequest) -> void:
	var allowed: Array = mode.allowed_providers()
	var primary: int = request.provider
	if not allowed.has(primary):
		primary = mode.preferred_provider(request.purpose)

	var chain: Array = [primary]
	for p in allowed:
		if p != primary and not chain.has(p):
			chain.append(p)
	fallback.configure(chain)


# ============================================================
# ANA YÖNLENDİRME
# ============================================================

func route(request: AIProviderRequest) -> Dictionary:
	_apply_mode(request)

	if mode.should_use_cache():
		var cached: AIProviderResponse = cache.lookup(request)
		if cached != null:
			cached.request_ref = request.id
			return {
				"resolved": true,
				"response": cached,
				"needs_network": false,
				"prepared": {},
			}

	_build_fallback_chain(request)

	var prep: Dictionary = _prepare_for_provider(request, fallback.current())
	if not prep["ok"]:
		return {
			"resolved": true,
			"response": AIProviderResponse.create_failure(prep["error"]),
			"needs_network": false,
			"prepared": {},
		}

	return {
		"resolved": false,
		"response": null,
		"needs_network": true,
		"prepared": prep,
	}


func _prepare_for_provider(request: AIProviderRequest, provider: int) -> Dictionary:
	if provider < 0:
		return {"ok": false, "error": "Fallback zinciri tükendi — sağlayıcı yok"}

	var adapter: AIProviderAdapterBase = get_adapter(provider)
	if adapter == null:
		return {"ok": false, "error": "Sağlayıcı adapter'ı bulunamadı"}

	if provider == AIProviderRequest.Provider.DEEPSEEK:
		_apply_deepseek_pro_max_profile(request)
		if request.max_tokens <= 0:
			return {
				"ok": false,
				"error": (
					"DeepSeek 1M bağlam bütçesi tükendi; girdi kısaltılmalı"
				),
			}

	if not has_api_key(provider):
		return {
			"ok": false,
			"error": "'%s' için API anahtarı ayarlanmamış" % adapter.provider_name,
		}
	var api_key: String = _api_keys[provider]

	var body: Dictionary = adapter.build_request_body(request)
	var headers: PackedStringArray = adapter.build_headers(api_key)

	var url: String = adapter.endpoint_url
	if adapter is AIGeminiAdapter:
		url = (adapter as AIGeminiAdapter).build_endpoint_url(request, api_key)

	return {
		"ok": true,
		"error": "",
		"url": url,
		"headers": headers,
		"body": body,
		"provider": provider,
		"adapter": adapter,
	}


func handle_response(
	raw_result: Dictionary, request: AIProviderRequest, provider: int
) -> Dictionary:
	var adapter: AIProviderAdapterBase = get_adapter(provider)
	if adapter == null:
		return {
			"response": AIProviderResponse.create_failure("Adapter kayıp"),
			"should_fallback": false,
		}

	var status: int = int(raw_result.get("status", 0))
	var json: Dictionary = raw_result.get("json", {})
	var response: AIProviderResponse = adapter.parse_response(json, status)
	response.request_ref = request.id
	response.latency_ms = int(raw_result.get("latency_ms", 0))

	if response.is_usable() and mode.should_use_cache():
		cache.store(request, response)

	var needs_fallback: bool = AIFallbackChain.should_fallback(response)
	return {"response": response, "should_fallback": needs_fallback}


func route_next(request: AIProviderRequest) -> Dictionary:
	var next_provider: int = fallback.advance()
	if next_provider < 0:
		return {
			"resolved": true,
			"response": AIProviderResponse.create_failure(
				"Tüm sağlayıcılar denendi, hepsi başarısız"
			),
			"needs_network": false,
			"prepared": {},
		}
	var prep: Dictionary = _prepare_for_provider(request, next_provider)
	if not prep["ok"]:
		if fallback.has_next():
			return route_next(request)
		return {
			"resolved": true,
			"response": AIProviderResponse.create_failure(prep["error"]),
			"needs_network": false,
			"prepared": {},
		}
	return {
		"resolved": false,
		"response": null,
		"needs_network": true,
		"prepared": prep,
	}


# ============================================================
# DURUM
# ============================================================

func status() -> Dictionary:
	var keyed: Array = []
	for p in _api_keys:
		if has_api_key(p):
			keyed.append(p)
	return {
		"mode": mode.status(),
		"cache": cache.stats(),
		"adapters_registered": _adapters.size(),
		"providers_with_keys": keyed,
		"transport_attached": _transport != null,
		"transport_live": _transport != null and _transport.live_mode,
		"deepseek_profile": {
			"model": AIDeepSeekModelPolicy.PRODUCTION_MODEL,
			"thinking": "enabled",
			"reasoning_effort": "max",
			"max_output_tokens": AIDeepSeekModelPolicy.MAX_OUTPUT_TOKENS,
			"context_tokens": AIDeepSeekModelPolicy.MAX_CONTEXT_TOKENS,
		},
	}
