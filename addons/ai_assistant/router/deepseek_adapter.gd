@tool
class_name AIDeepSeekAdapter
extends AIProviderAdapterBase

## DeepSeekAdapter — DeepSeek sağlayıcı adapter'ı (Layer 7).
##
## DeepSeek API'si OpenAI-uyumludur: /chat/completions endpoint'i,
## messages dizisi, Authorization: Bearer başlığı.
##
## Master plan'da başlangıç sağlayıcısı — bütçe dostu, "Single Mode".


## DeepSeek API çıktı token sabit tavanı. Üzerinde değer gönderilirse
## API isteği 400 ile reddeder — bu yüzden GÜVENLE kırpılır.
const MAX_OUTPUT_TOKENS: int = 8192


func _init() -> void:
	provider_id = AIProviderRequest.Provider.DEEPSEEK
	provider_name = "deepseek"
	endpoint_url = "https://api.deepseek.com/chat/completions"
	default_model = "deepseek-chat"


## DeepSeek istek gövdesi — OpenAI-uyumlu şema.
func build_request_body(request: AIProviderRequest) -> Dictionary:
	var model: String = request.model
	if model.strip_edges().is_empty():
		model = default_model
	return {
		"model": model,
		"messages": _messages_openai_format(request),
		"temperature": request.temperature,
		"max_tokens": mini(request.max_tokens, MAX_OUTPUT_TOKENS),
		"stream": false,
	}


## DeepSeek başlıkları — Bearer token.
func build_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])


## DeepSeek yanıtı — OpenAI-uyumlu şema.
## İçerik: choices[0].message.content
## Token: usage.prompt_tokens / usage.completion_tokens
func parse_response(raw_json: Dictionary, http_status: int) -> AIProviderResponse:
	if not _is_http_ok(http_status):
		# Hata gövdesinde mesaj olabilir
		var api_msg: Variant = _dig(raw_json, ["error", "message"], "")
		var reason: String = _http_error_text(http_status)
		if api_msg is String and not (api_msg as String).is_empty():
			reason += " — " + api_msg
		return AIProviderResponse.create_failure(reason, http_status)

	var content: Variant = _dig(raw_json, ["choices", 0, "message", "content"], null)
	if content == null or not (content is String):
		return AIProviderResponse.create_failure(
			"DeepSeek yanıtında içerik bulunamadı", http_status
		)

	var response := AIProviderResponse.create_success(
		content, provider_id, default_model
	)
	response.input_tokens = int(_dig(raw_json, ["usage", "prompt_tokens"], 0))
	response.output_tokens = int(_dig(raw_json, ["usage", "completion_tokens"], 0))
	response.finish_reason = str(_dig(raw_json, ["choices", 0, "finish_reason"], ""))
	response.http_status = http_status
	return response
