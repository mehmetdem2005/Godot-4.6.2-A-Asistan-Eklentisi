@tool
class_name AIRouterTest
extends RefCounted

## Phase 7 / Layer 7 — Multi-Provider Router Self-Test
##
## Sıkı testler: 4 adapter (format çevirisi), PromptCache (LRU + hit/miss),
## ModeController (Eco/Quality, Single/Pro), FallbackChain (zincir + karar),
## ProviderRouter (cache + mod + hazırlık).
##
## NOT: HTTPTransport bir Node ve gerçek ağ çağrısı yapar — onun GERÇEK
## ağ davranışı ancak sahnede, API anahtarıyla test edilir. Burada
## router'ın transport'suz/anahtarsız davranışı (dry-run, açık hata)
## sınanır — sahte başarı olmadığı doğrulanır.


static func run_all() -> Array:
	var results: Array = []

	# Adapter — format çevirisi
	results.append(_b("Router: Adapter", _test_deepseek_body()))
	results.append(_b("Router: Adapter", _test_deepseek_max_tokens_clamp()))
	results.append(_b("Router: Adapter", _test_openai_headers()))
	results.append(_b("Router: Adapter", _test_anthropic_system()))
	results.append(_b("Router: Adapter", _test_gemini_contents()))
	results.append(_b("Router: Adapter", _test_adapter_parse_success()))
	results.append(_b("Router: Adapter", _test_adapter_parse_error()))
	results.append(_b("Router: Adapter", _test_gemini_endpoint_url()))

	# PromptCache
	results.append(_b("Router: Cache", _test_cache_store_lookup()))
	results.append(_b("Router: Cache", _test_cache_miss()))
	results.append(_b("Router: Cache", _test_cache_no_store_failure()))
	results.append(_b("Router: Cache", _test_cache_hit_rate()))

	# ModeController
	results.append(_b("Router: Mode", _test_mode_eco_tokens()))
	results.append(_b("Router: Mode", _test_mode_quality_tokens()))
	results.append(_b("Router: Mode", _test_mode_single_providers()))
	results.append(_b("Router: Mode", _test_mode_pro_providers()))
	results.append(_b("Router: Mode", _test_mode_preferred()))

	# FallbackChain
	results.append(_b("Router: Fallback", _test_fallback_advance()))
	results.append(_b("Router: Fallback", _test_fallback_exhaust()))
	results.append(_b("Router: Fallback", _test_fallback_decision()))

	# ProviderRouter
	results.append(_b("Router: Engine", _test_router_no_key()))
	results.append(_b("Router: Engine", _test_router_cache_hit()))
	results.append(_b("Router: Engine", _test_router_single_mode()))
	results.append(_b("Router: Engine", _test_router_status()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


## Test için örnek istek üretir.
static func _make_request(purpose: int = AIProviderRequest.Purpose.REASONING) -> AIProviderRequest:
	var req := AIProviderRequest.create(purpose, "TestRole")
	req.system_prompt = "Sen bir test asistanısın"
	req.add_message("user", "Merhaba")
	req.max_tokens = 1000
	req.temperature = 0.7
	return req


# ============================================================
# ADAPTER
# ============================================================

static func _test_deepseek_body() -> Dictionary:
	var name := "DeepSeek istek gövdesi (OpenAI fmt)"
	var adapter := AIDeepSeekAdapter.new()
	var body: Dictionary = adapter.build_request_body(_make_request())
	if not body.has("messages"):
		return _fail(name, "messages alanı yok")
	# system prompt ilk mesaj olmalı
	var msgs: Array = body["messages"]
	if msgs.size() < 2 or msgs[0]["role"] != "system":
		return _fail(name, "system prompt ilk mesaj değil")
	if body["model"] != "deepseek-chat":
		return _fail(name, "varsayılan model yanlış")
	return _ok(name)


static func _test_deepseek_max_tokens_clamp() -> Dictionary:
	var name := "DeepSeek max_tokens API tavanına (8192) güvenle kırpılır"
	var adapter := AIDeepSeekAdapter.new()
	var req := _make_request()
	req.max_tokens = 100000
	var body: Dictionary = adapter.build_request_body(req)
	if int(body["max_tokens"]) != AIDeepSeekAdapter.MAX_OUTPUT_TOKENS:
		return _fail(name, "8192'e kırpılmalı: %d" % int(body["max_tokens"]))
	# Tavan altı değer aynen korunur (kırpma yalnız aşımda).
	req.max_tokens = 1000
	if int(adapter.build_request_body(req)["max_tokens"]) != 1000:
		return _fail(name, "tavan altı değer korunmalı")
	return _ok(name)


static func _test_openai_headers() -> Dictionary:
	var name := "OpenAI başlıkları (Bearer)"
	var adapter := AIOpenAIAdapter.new()
	var headers: PackedStringArray = adapter.build_headers("test_key_123")
	var found: bool = false
	for h in headers:
		if h.begins_with("Authorization: Bearer test_key_123"):
			found = true
	if not found:
		return _fail(name, "Authorization Bearer başlığı yok")
	return _ok(name)


static func _test_anthropic_system() -> Dictionary:
	var name := "Anthropic system ayrı alan"
	var adapter := AIAnthropicAdapter.new()
	var body: Dictionary = adapter.build_request_body(_make_request())
	# system üst-seviye alan olmalı, messages içinde DEĞİL
	if not body.has("system"):
		return _fail(name, "system üst-seviye alan değil")
	for m in body["messages"]:
		if m["role"] == "system":
			return _fail(name, "system messages içinde olmamalı")
	# x-api-key başlığı
	var headers: PackedStringArray = adapter.build_headers("ant_key")
	var has_xkey: bool = false
	for h in headers:
		if h.begins_with("x-api-key:"):
			has_xkey = true
	if not has_xkey:
		return _fail(name, "x-api-key başlığı yok")
	return _ok(name)


static func _test_gemini_contents() -> Dictionary:
	var name := "Gemini contents/parts + role çevirisi"
	var adapter := AIGeminiAdapter.new()
	var req := _make_request()
	req.add_message("assistant", "önceki yanıt")
	var body: Dictionary = adapter.build_request_body(req)
	if not body.has("contents"):
		return _fail(name, "contents alanı yok")
	# assistant -> model çevrilmeli
	var found_model: bool = false
	for c in body["contents"]:
		if c["role"] == "model":
			found_model = true
		if c["role"] == "assistant":
			return _fail(name, "assistant rolü model'e çevrilmedi")
	if not found_model:
		return _fail(name, "model rolü bulunamadı")
	return _ok(name)


static func _test_adapter_parse_success() -> Dictionary:
	var name := "Adapter başarılı yanıt çözümleme"
	var adapter := AIDeepSeekAdapter.new()
	var raw: Dictionary = {
		"choices": [{"message": {"content": "Test yanıtı"}, "finish_reason": "stop"}],
		"usage": {"prompt_tokens": 12, "completion_tokens": 8},
	}
	var response: AIProviderResponse = adapter.parse_response(raw, 200)
	if not response.ok:
		return _fail(name, "başarılı yanıt ok=false")
	if response.content != "Test yanıtı":
		return _fail(name, "içerik yanlış çözüldü")
	if response.input_tokens != 12 or response.output_tokens != 8:
		return _fail(name, "token sayıları yanlış")
	return _ok(name)


static func _test_adapter_parse_error() -> Dictionary:
	var name := "Adapter hata yanıtı çözümleme"
	var adapter := AIDeepSeekAdapter.new()
	# 401 — kimlik hatası
	var raw: Dictionary = {"error": {"message": "Invalid API key"}}
	var response: AIProviderResponse = adapter.parse_response(raw, 401)
	if response.ok:
		return _fail(name, "401 yanıtı ok=true olmamalı")
	if response.http_status != 401:
		return _fail(name, "http_status korunmadı")
	# Sahte içerik üretmemeli
	if not response.content.is_empty():
		return _fail(name, "hata yanıtında içerik olmamalı (sahte başarı)")
	return _ok(name)


static func _test_gemini_endpoint_url() -> Dictionary:
	var name := "Gemini endpoint URL (model + key)"
	var adapter := AIGeminiAdapter.new()
	var url: String = adapter.build_endpoint_url(_make_request(), "gem_key")
	# URL model adını VE anahtarı içermeli
	if not url.contains("gemini-1.5-flash"):
		return _fail(name, "URL model adı içermiyor")
	if not url.contains("key=gem_key"):
		return _fail(name, "URL anahtar query'si içermiyor")
	return _ok(name)


# ============================================================
# PROMPT CACHE
# ============================================================

static func _test_cache_store_lookup() -> Dictionary:
	var name := "Cache yaz ve bul"
	var cache := AIPromptCache.new()
	var req := _make_request()
	var resp := AIProviderResponse.create_success(
		"cache içeriği", AIProviderRequest.Provider.DEEPSEEK, "deepseek-chat"
	)
	cache.store(req, resp)
	var found: AIProviderResponse = cache.lookup(req)
	if found == null:
		return _fail(name, "cache'e yazılan bulunamadı")
	if found.content != "cache içeriği":
		return _fail(name, "cache içeriği yanlış")
	if not found.from_cache:
		return _fail(name, "cache yanıtı from_cache=true olmalı")
	return _ok(name)


static func _test_cache_miss() -> Dictionary:
	var name := "Cache miss — olmayan istek"
	var cache := AIPromptCache.new()
	var found: AIProviderResponse = cache.lookup(_make_request())
	if found != null:
		return _fail(name, "boş cache'te sonuç bulundu")
	return _ok(name)


static func _test_cache_no_store_failure() -> Dictionary:
	var name := "Cache başarısız yanıtı saklamaz"
	var cache := AIPromptCache.new()
	var req := _make_request()
	var fail_resp := AIProviderResponse.create_failure("hata", 500)
	var stored: bool = cache.store(req, fail_resp)
	if stored:
		return _fail(name, "başarısız yanıt cache'lendi")
	if cache.count() != 0:
		return _fail(name, "cache boş olmalı")
	return _ok(name)


static func _test_cache_hit_rate() -> Dictionary:
	var name := "Cache hit oranı hesabı"
	var cache := AIPromptCache.new()
	var req := _make_request()
	var resp := AIProviderResponse.create_success(
		"x", AIProviderRequest.Provider.DEEPSEEK, "m"
	)
	cache.store(req, resp)
	cache.lookup(req)   # hit
	cache.lookup(_make_request_other())  # miss
	# 1 hit, 1 miss -> 0.5
	if abs(cache.hit_rate() - 0.5) > 0.01:
		return _fail(name, "hit oranı yanlış: %f" % cache.hit_rate())
	return _ok(name)


## Farklı içerikli istek — cache miss üretmek için.
static func _make_request_other() -> AIProviderRequest:
	var req := AIProviderRequest.create(
		AIProviderRequest.Purpose.CODE, "OtherRole"
	)
	req.add_message("user", "Tamamen farklı içerik")
	return req


# ============================================================
# MODE CONTROLLER
# ============================================================

static func _test_mode_eco_tokens() -> Dictionary:
	var name := "Mode ECO token kırpar"
	var mode := AIModeController.new()
	mode.set_operation_mode(AIModeController.OperationMode.ECO)
	# ECO: 2000 -> 1000
	if mode.resolve_max_tokens(2000) != 1000:
		return _fail(name, "ECO token yarıya inmeli")
	# ECO min 256
	if mode.resolve_max_tokens(100) != 256:
		return _fail(name, "ECO min 256 olmalı")
	return _ok(name)


static func _test_mode_quality_tokens() -> Dictionary:
	var name := "Mode QUALITY token artırır"
	var mode := AIModeController.new()
	mode.set_operation_mode(AIModeController.OperationMode.QUALITY)
	if mode.resolve_max_tokens(1000) != 2000:
		return _fail(name, "QUALITY token iki katına çıkmalı")
	return _ok(name)


static func _test_mode_single_providers() -> Dictionary:
	var name := "Mode SINGLE sadece DeepSeek"
	var mode := AIModeController.new()
	mode.set_access_mode(AIModeController.AccessMode.SINGLE)
	var allowed: Array = mode.allowed_providers()
	if allowed.size() != 1:
		return _fail(name, "SINGLE modda 1 sağlayıcı olmalı")
	if allowed[0] != AIProviderRequest.Provider.DEEPSEEK:
		return _fail(name, "SINGLE modda DeepSeek olmalı")
	return _ok(name)


static func _test_mode_pro_providers() -> Dictionary:
	var name := "Mode PROFESSIONAL 4 sağlayıcı"
	var mode := AIModeController.new()
	mode.set_access_mode(AIModeController.AccessMode.PROFESSIONAL)
	if mode.allowed_providers().size() != 4:
		return _fail(name, "PRO modda 4 sağlayıcı olmalı")
	return _ok(name)


static func _test_mode_preferred() -> Dictionary:
	var name := "Mode tercih edilen sağlayıcı"
	var mode := AIModeController.new()
	# SINGLE — her zaman DeepSeek
	mode.set_access_mode(AIModeController.AccessMode.SINGLE)
	var pref: int = mode.preferred_provider(AIProviderRequest.Purpose.CODE)
	if pref != AIProviderRequest.Provider.DEEPSEEK:
		return _fail(name, "SINGLE modda tercih DeepSeek olmalı")
	return _ok(name)


# ============================================================
# FALLBACK CHAIN
# ============================================================

static func _test_fallback_advance() -> Dictionary:
	var name := "Fallback zincir ilerleme"
	var chain := AIFallbackChain.new()
	chain.configure([
		AIProviderRequest.Provider.DEEPSEEK,
		AIProviderRequest.Provider.OPENAI,
	])
	if chain.current() != AIProviderRequest.Provider.DEEPSEEK:
		return _fail(name, "ilk sağlayıcı DeepSeek olmalı")
	var next_p: int = chain.advance()
	if next_p != AIProviderRequest.Provider.OPENAI:
		return _fail(name, "advance OpenAI'a geçmeli")
	return _ok(name)


static func _test_fallback_exhaust() -> Dictionary:
	var name := "Fallback zincir tükenmesi"
	var chain := AIFallbackChain.new()
	chain.configure([AIProviderRequest.Provider.DEEPSEEK])
	# Tek elemanlı zincir — advance sonrası tükenmiş
	var next_p: int = chain.advance()
	if next_p != -1:
		return _fail(name, "tek elemanlı zincir advance -1 dönmeli")
	return _ok(name)


static func _test_fallback_decision() -> Dictionary:
	var name := "Fallback karar mantığı"
	# 500 -> fallback evet
	var r500 := AIProviderResponse.create_failure("sunucu hatası", 500)
	if not AIFallbackChain.should_fallback(r500):
		return _fail(name, "500 hatası fallback tetiklemeli")
	# 401 -> fallback HAYIR (anahtar sorunu, sağlayıcı değiştirmek çözmez)
	var r401 := AIProviderResponse.create_failure("kötü anahtar", 401)
	if AIFallbackChain.should_fallback(r401):
		return _fail(name, "401 fallback tetiklememeli")
	# başarı -> fallback hayır
	var ok_resp := AIProviderResponse.create_success(
		"ok", AIProviderRequest.Provider.DEEPSEEK, "m"
	)
	if AIFallbackChain.should_fallback(ok_resp):
		return _fail(name, "başarılı yanıt fallback tetiklememeli")
	return _ok(name)


# ============================================================
# PROVIDER ROUTER
# ============================================================

static func _test_router_no_key() -> Dictionary:
	var name := "Router anahtarsız açık hata verir"
	var router := AIProviderRouter.new()
	# Hiç API anahtarı ayarlanmadı
	var result: Dictionary = router.route(_make_request())
	# Anahtar yok — çözülmüş (resolved) ve başarısız olmalı, sahte başarı YOK
	if not result["resolved"]:
		return _fail(name, "anahtarsız istek çözülmüş olmalı")
	var response: AIProviderResponse = result["response"]
	if response.ok:
		return _fail(name, "anahtarsız istek ok=true olmamalı (sahte başarı)")
	if not response.error_message.contains("anahtar"):
		return _fail(name, "hata mesajı anahtar eksikliğini söylemeli")
	return _ok(name)


static func _test_router_cache_hit() -> Dictionary:
	var name := "Router cache hit ağ çağrısı atlar"
	var router := AIProviderRouter.new()
	var req := _make_request()
	# Cache'e elle bir yanıt koy
	var cached := AIProviderResponse.create_success(
		"önbellekli", AIProviderRequest.Provider.DEEPSEEK, "deepseek-chat"
	)
	router.cache.store(req, cached)
	# Aynı isteği route et — cache'ten dönmeli
	var result: Dictionary = router.route(req)
	if result["needs_network"]:
		return _fail(name, "cache hit'te ağ çağrısı gerekmemeli")
	if not result["resolved"]:
		return _fail(name, "cache hit çözülmüş olmalı")
	var response: AIProviderResponse = result["response"]
	if not response.from_cache:
		return _fail(name, "yanıt cache'ten gelmeli")
	return _ok(name)


static func _test_router_single_mode() -> Dictionary:
	var name := "Router SINGLE mod DeepSeek'e zorlar"
	var router := AIProviderRouter.new()
	router.mode.set_access_mode(AIModeController.AccessMode.SINGLE)
	var req := _make_request()
	# İstek OpenAI istiyor ama SINGLE mod DeepSeek'e zorlamalı
	req.provider = AIProviderRequest.Provider.OPENAI
	router.route(req)
	# _apply_mode sonrası provider DeepSeek olmuş olmalı
	if req.provider != AIProviderRequest.Provider.DEEPSEEK:
		return _fail(name, "SINGLE mod sağlayıcıyı DeepSeek'e zorlamadı")
	return _ok(name)


static func _test_router_status() -> Dictionary:
	var name := "Router durum raporu"
	var router := AIProviderRouter.new()
	var status: Dictionary = router.status()
	if status["adapters_registered"] != 4:
		return _fail(name, "4 adapter kayıtlı olmalı")
	if status["transport_attached"]:
		return _fail(name, "transport henüz bağlı olmamalı")
	return _ok(name)
