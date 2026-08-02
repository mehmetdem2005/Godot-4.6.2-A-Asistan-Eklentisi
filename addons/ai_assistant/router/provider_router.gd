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
## İstek akışı:
##   1. Cache'e bak  -> varsa cache yanıtı dön (maliyet 0)
##   2. Mode'a göre sağlayıcı sırası belirle
##   3. Adapter ile istek gövdesini hazırla
##   4. HTTPTransport ile gönder (veya dry-run)
##   5. Yanıtı adapter ile çöz
##   6. Hata + fallback gerekiyorsa -> sıradaki sağlayıcı
##   7. Başarılı yanıtı cache'e yaz
##
## ÖNEMLİ: HTTPTransport bir Node — bu RefCounted sınıf onu DIŞARIDAN
## alır (attach_transport). Transport yoksa router dry-run benzeri
## davranır: isteği hazırlar, "transport yok" hatası döner. Sahte
## başarı YOK.

## Bileşenler.
var mode: AIModeController
var cache: AIPromptCache
var fallback: AIFallbackChain

## Sağlayıcı adapter'ları — provider enum -> adapter.
var _adapters: Dictionary = {}

## API anahtarları — provider enum -> key string.
## Router anahtarı kalıcı saklamaz; çalışma süresince tutar.
## Anahtar yönetimi ayrı bir güvenlik katmanının işi.
var _api_keys: Dictionary = {}

## HTTP taşıma katmanı — Node, dışarıdan enjekte edilir.
var _transport: AIHTTPTransport = null


func _init() -> void:
	mode = AIModeController.new()
	cache = AIPromptCache.new()
	fallback = AIFallbackChain.new()
	_register_adapters()


## 4 sağlayıcı adapter'ını kaydeder.
func _register_adapters() -> void:
	# Canlı DeepSeek trafiği yalnız V4 adapter üzerinden çıkar. Eski
	# AIDeepSeekAdapter sınıfı geriye uyumlu contract yüzeyi olarak kalır.
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

## HTTP taşıma node'unu bağlar — gerçek ağ çağrısı için.
## Bir sahne/autoload AIHTTPTransport'u ağaca ekler, sonra buraya verir.
func attach_transport(transport: AIHTTPTransport) -> void:
	_transport = transport


## Bir sağlayıcı için API anahtarı ayarlar.
## provider: AIProviderRequest.Provider enum. key: anahtar.
func set_api_key(provider: int, key: String) -> void:
	_api_keys[provider] = key


## Bir sağlayıcının anahtarı ayarlanmış mı?
func has_api_key(provider: int) -> bool:
	return _api_keys.has(provider) and not str(_api_keys[provider]).is_empty()


## Bir sağlayıcının adapter'ını döndürür. Yoksa null.
func get_adapter(provider: int) -> AIProviderAdapterBase:
	return _adapters.get(provider, null)


# ============================================================
# İSTEK HAZIRLAMA — sağlayıcıya göndermeden önce
# ============================================================

## Bir isteği moda göre ayarlar — token, sıcaklık, sağlayıcı.
## request üzerinde DEĞİŞİKLİK YAPAR (mod parametrelerini uygular).
func _apply_mode(request: AIProviderRequest) -> void:
	request.max_tokens = mode.resolve_max_tokens(request.max_tokens)
	request.temperature = mode.resolve_temperature(request.temperature)
	# Sağlayıcı belirtilmemişse mod tercih etsin
	# (request.provider zaten bir değer taşır; mod SINGLE ise zorla DeepSeek)
	if mode.is_single_provider():
		request.provider = AIProviderRequest.Provider.DEEPSEEK


## Bu istek için fallback zincirini moda göre kurar.
## Birincil: isteğin/mod'un tercihi. Yedekler: izinli diğer sağlayıcılar.
func _build_fallback_chain(request: AIProviderRequest) -> void:
	var allowed: Array = mode.allowed_providers()
	# Birincil sağlayıcı — isteğinki (izinliyse), değilse mod tercihi
	var primary: int = request.provider
	if not allowed.has(primary):
		primary = mode.preferred_provider(request.purpose)

	var chain: Array = [primary]
	# Kalan izinli sağlayıcılar yedek olarak eklenir
	for p in allowed:
		if p != primary and not chain.has(p):
			chain.append(p)
	fallback.configure(chain)


# ============================================================
# ANA YÖNLENDİRME
# ============================================================

## Bir isteği yönlendirir ve yanıt döndürür.
##
## NOT: Gerçek HTTP çağrısı asenkrondur (HTTPTransport sinyal-tabanlı).
## Bu metod SENKRON karar mantığını yapar: cache, mod, hazırlık. Gerçek
## ağ adımı için route_async kullanılır. Bu metod cache hit'i veya
## hazırlık hatalarını hemen döndürebilir.
##
## Dönen: {
##   resolved: bool,        cache'ten/hatadan hemen sonuç var mı
##   response: AIProviderResponse veya null,
##   needs_network: bool,   ağ çağrısı gerekiyor mu (route_async'e geç)
##   prepared: Dictionary,  ağ çağrısı için hazırlanmış {url, headers, body, provider}
## }
func route(request: AIProviderRequest) -> Dictionary:
	# --- 1. Mod uygula ---
	_apply_mode(request)

	# --- 2. Cache kontrolü ---
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

	# --- 3. Fallback zinciri kur ---
	_build_fallback_chain(request)

	# --- 4. İlk sağlayıcıyı hazırla ---
	var prep: Dictionary = _prepare_for_provider(request, fallback.current())
	if not prep["ok"]:
		# Hazırlık hatası — sahte başarı yok, açık hata
		return {
			"resolved": true,
			"response": AIProviderResponse.create_failure(prep["error"]),
			"needs_network": false,
			"prepared": {},
		}

	# --- 5. Ağ çağrısı gerekiyor ---
	return {
		"resolved": false,
		"response": null,
		"needs_network": true,
		"prepared": prep,
	}


## Belirli bir sağlayıcı için ağ çağrısı malzemesini hazırlar.
## Dönen: {ok, error, url, headers, body, provider, adapter}
func _prepare_for_provider(request: AIProviderRequest, provider: int) -> Dictionary:
	if provider < 0:
		return {"ok": false, "error": "Fallback zinciri tükendi — sağlayıcı yok"}

	var adapter: AIProviderAdapterBase = get_adapter(provider)
	if adapter == null:
		return {"ok": false, "error": "Sağlayıcı adapter'ı bulunamadı"}

	# API anahtarı kontrolü — yoksa açıkça söyle (sahte başarı yok)
	if not has_api_key(provider):
		return {
			"ok": false,
			"error": "'%s' için API anahtarı ayarlanmamış" % adapter.provider_name,
		}
	var api_key: String = _api_keys[provider]

	var body: Dictionary = adapter.build_request_body(request)
	var headers: PackedStringArray = adapter.build_headers(api_key)

	# Gemini özel: endpoint URL'si model + anahtar içerir
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


## Bir HTTP yanıtını işler — adapter ile çözer, cache'e yazar.
## raw_result: HTTPTransport callback'inin verdiği {ok, status, json...}.
## request: orijinal istek. provider: hangi sağlayıcı yanıtladı.
## Dönen: {response: AIProviderResponse, should_fallback: bool}
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

	# Başarılıysa cache'e yaz
	if response.is_usable() and mode.should_use_cache():
		cache.store(request, response)

	# Fallback gerekli mi
	var needs_fallback: bool = AIFallbackChain.should_fallback(response)
	return {"response": response, "should_fallback": needs_fallback}


## Fallback sonrası sıradaki sağlayıcıyı hazırlar.
## Dönen: route() ile aynı yapı.
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
		# Bu sağlayıcı hazırlanamadı — bir sonrakini dene
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

## Router durum özeti.
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
	}
