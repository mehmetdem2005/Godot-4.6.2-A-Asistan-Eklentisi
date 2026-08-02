@tool
class_name AIDeepSeekV4Adapter
extends AIDeepSeekAdapter

## DeepSeek V4 adapter.
##
## Eski adapter geriye uyumlu contract yüzeyi olarak korunur. Canlı router
## bu adapter'ı kullanır; ağ gövdesine yalnız kanonik V4 model kimliği ve
## açık düşünme modu çıkar.


func _init() -> void:
	provider_id = AIProviderRequest.Provider.DEEPSEEK
	provider_name = "deepseek"
	endpoint_url = "https://api.deepseek.com/chat/completions"
	default_model = AIDeepSeekModelPolicy.DEFAULT_MODEL


func build_request_body(request: AIProviderRequest) -> Dictionary:
	var requested_model: String = request.model.strip_edges()
	var thinking: bool = AIDeepSeekModelPolicy.thinking_enabled(
		requested_model, request.purpose
	)
	var body: Dictionary = {
		"model": AIDeepSeekModelPolicy.canonical_model(requested_model),
		"messages": _messages_openai_format(request),
		"max_tokens": mini(
			request.max_tokens, AIDeepSeekModelPolicy.MAX_OUTPUT_TOKENS
		),
		"stream": true,
		"stream_options": {"include_usage": true},
		"thinking": {
			"type": "enabled" if thinking else "disabled",
		},
	}

	# DeepSeek V4 düşünme modunda temperature etkisizdir. İstek gövdesini
	# dürüst ve kararlı tutmak için yalnız düşünmesiz üretimde gönderilir.
	if thinking:
		body["reasoning_effort"] = AIDeepSeekModelPolicy.reasoning_effort(
			request.purpose
		)
	else:
		body["temperature"] = request.temperature
	return body


func parse_response(raw_json: Dictionary, http_status: int) -> AIProviderResponse:
	var response: AIProviderResponse = super.parse_response(raw_json, http_status)
	if response.ok:
		var actual_model: String = str(raw_json.get("model", "")).strip_edges()
		response.model = (
			AIDeepSeekModelPolicy.canonical_model(actual_model)
			if not actual_model.is_empty()
			else default_model
		)
	return response
