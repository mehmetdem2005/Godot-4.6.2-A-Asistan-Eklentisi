@tool
class_name AIOpenAIAdapter
extends AIProviderAdapterBase

## OpenAIAdapter — OpenAI sağlayıcı adapter'ı (Layer 7).
##
## OpenAI Chat Completions API: /v1/chat/completions, messages dizisi,
## Authorization: Bearer başlığı. DeepSeek bu şemayı taklit ettiği için
## yapı çok benzer — ama ayrı adapter (endpoint, model, gelecekteki
## farklılıklar için bağımsız).


func _init() -> void:
	provider_id = AIProviderRequest.Provider.OPENAI
	provider_name = "openai"
	endpoint_url = "https://api.openai.com/v1/chat/completions"
	default_model = "gpt-4o-mini"


func build_request_body(request: AIProviderRequest) -> Dictionary:
	var model: String = request.model
	if model.strip_edges().is_empty():
		model = default_model
	return {
		"model": model,
		"messages": _messages_openai_format(request),
		"temperature": request.temperature,
		"max_tokens": request.max_tokens,
		"stream": false,
	}


func build_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])


func parse_response(raw_json: Dictionary, http_status: int) -> AIProviderResponse:
	if not _is_http_ok(http_status):
		var api_msg: Variant = _dig(raw_json, ["error", "message"], "")
		var reason: String = _http_error_text(http_status)
		if api_msg is String and not (api_msg as String).is_empty():
			reason += " — " + api_msg
		return AIProviderResponse.create_failure(reason, http_status)

	var content: Variant = _dig(raw_json, ["choices", 0, "message", "content"], null)
	if content == null or not (content is String):
		return AIProviderResponse.create_failure(
			"OpenAI yanıtında içerik bulunamadı", http_status
		)

	var response := AIProviderResponse.create_success(
		content, provider_id, default_model
	)
	response.input_tokens = int(_dig(raw_json, ["usage", "prompt_tokens"], 0))
	response.output_tokens = int(_dig(raw_json, ["usage", "completion_tokens"], 0))
	response.finish_reason = str(_dig(raw_json, ["choices", 0, "finish_reason"], ""))
	response.http_status = http_status
	return response
