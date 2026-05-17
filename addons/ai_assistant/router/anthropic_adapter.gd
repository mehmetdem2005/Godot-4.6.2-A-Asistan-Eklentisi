@tool
class_name AIAnthropicAdapter
extends AIProviderAdapterBase

## AnthropicAdapter — Anthropic (Claude) sağlayıcı adapter'ı (Layer 7).
##
## Anthropic Messages API, OpenAI'dan FARKLIDIR:
##   - system prompt ayrı bir üst-seviye alan (messages içinde değil)
##   - Kimlik: x-api-key başlığı (Authorization değil)
##   - anthropic-version başlığı zorunlu
##   - İçerik: content[0].text (choices değil)
##   - Token: usage.input_tokens / usage.output_tokens


## Anthropic API sürümü — başlıkta gönderilir.
const ANTHROPIC_VERSION: String = "2023-06-01"


func _init() -> void:
	provider_id = AIProviderRequest.Provider.ANTHROPIC
	provider_name = "anthropic"
	endpoint_url = "https://api.anthropic.com/v1/messages"
	default_model = "claude-3-5-haiku-20241022"


## Anthropic istek gövdesi — system AYRI alan.
func build_request_body(request: AIProviderRequest) -> Dictionary:
	var model: String = request.model
	if model.strip_edges().is_empty():
		model = default_model

	# Anthropic: system messages dizisinde DEĞİL, ayrı alan.
	# messages sadece user/assistant içerir.
	var msgs: Array = []
	for m in request.messages:
		msgs.append({
			"role": m.get("role", "user"),
			"content": m.get("content", ""),
		})

	var body: Dictionary = {
		"model": model,
		"messages": msgs,
		"max_tokens": request.max_tokens,
		"temperature": request.temperature,
	}
	# system varsa üst-seviye alan olarak ekle
	if not request.system_prompt.strip_edges().is_empty():
		body["system"] = request.system_prompt
	return body


## Anthropic başlıkları — x-api-key + anthropic-version.
func build_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: " + ANTHROPIC_VERSION,
	])


## Anthropic yanıtı — content[0].text yapısı.
func parse_response(raw_json: Dictionary, http_status: int) -> AIProviderResponse:
	if not _is_http_ok(http_status):
		var api_msg: Variant = _dig(raw_json, ["error", "message"], "")
		var reason: String = _http_error_text(http_status)
		if api_msg is String and not (api_msg as String).is_empty():
			reason += " — " + api_msg
		return AIProviderResponse.create_failure(reason, http_status)

	# Anthropic: content bir dizi, ilk text bloğunun .text alanı
	var content: Variant = _dig(raw_json, ["content", 0, "text"], null)
	if content == null or not (content is String):
		return AIProviderResponse.create_failure(
			"Anthropic yanıtında içerik bulunamadı", http_status
		)

	var response := AIProviderResponse.create_success(
		content, provider_id, default_model
	)
	response.input_tokens = int(_dig(raw_json, ["usage", "input_tokens"], 0))
	response.output_tokens = int(_dig(raw_json, ["usage", "output_tokens"], 0))
	response.finish_reason = str(_dig(raw_json, ["stop_reason"], ""))
	response.http_status = http_status
	return response
