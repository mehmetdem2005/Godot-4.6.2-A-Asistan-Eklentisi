@tool
class_name AIGeminiAdapter
extends AIProviderAdapterBase

## GeminiAdapter — Google Gemini sağlayıcı adapter'ı (Layer 7).
##
## Gemini API en farklı olanı:
##   - Endpoint model adını İÇERİR: /models/{model}:generateContent
##   - Kimlik: anahtar URL query parametresi (?key=...) — başlıkta değil
##   - Mesaj yapısı: contents[].parts[].text  (messages değil)
##   - role "assistant" yerine "model"
##   - system: systemInstruction ayrı alan
##   - İçerik: candidates[0].content.parts[0].text
##   - Token: usageMetadata.promptTokenCount / candidatesTokenCount


## Endpoint tabanı — model adı build sırasında eklenir.
const ENDPOINT_BASE: String = "https://generativelanguage.googleapis.com/v1beta/models/"


func _init() -> void:
	provider_id = AIProviderRequest.Provider.GEMINI
	provider_name = "gemini"
	default_model = "gemini-1.5-flash"
	# endpoint_url build_endpoint_url() ile dinamik üretilir
	endpoint_url = ENDPOINT_BASE


## Gemini endpoint'i model adını içerir — bu yardımcı tam URL'yi üretir.
## api_key URL'de query parametresi olarak gider.
func build_endpoint_url(request: AIProviderRequest, api_key: String) -> String:
	var model: String = request.model
	if model.strip_edges().is_empty():
		model = default_model
	return ENDPOINT_BASE + model + ":generateContent?key=" + api_key


## Gemini istek gövdesi — contents/parts yapısı.
func build_request_body(request: AIProviderRequest) -> Dictionary:
	# Gemini: messages -> contents, her content {role, parts:[{text}]}
	# role "assistant" -> "model" çevirisi gerekir
	var contents: Array = []
	for m in request.messages:
		var role: String = m.get("role", "user")
		if role == "assistant":
			role = "model"
		contents.append({
			"role": role,
			"parts": [{"text": m.get("content", "")}],
		})

	var body: Dictionary = {
		"contents": contents,
		"generationConfig": {
			"temperature": request.temperature,
			"maxOutputTokens": request.max_tokens,
		},
	}
	# system -> systemInstruction ayrı alan
	if not request.system_prompt.strip_edges().is_empty():
		body["systemInstruction"] = {
			"parts": [{"text": request.system_prompt}],
		}
	return body


## Gemini başlıkları — anahtar URL'de olduğu için sadece Content-Type.
func build_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
	])


## Gemini yanıtı — candidates[0].content.parts[0].text yapısı.
func parse_response(raw_json: Dictionary, http_status: int) -> AIProviderResponse:
	if not _is_http_ok(http_status):
		var api_msg: Variant = _dig(raw_json, ["error", "message"], "")
		var reason: String = _http_error_text(http_status)
		if api_msg is String and not (api_msg as String).is_empty():
			reason += " — " + api_msg
		return AIProviderResponse.create_failure(reason, http_status)

	var content: Variant = _dig(
		raw_json, ["candidates", 0, "content", "parts", 0, "text"], null
	)
	if content == null or not (content is String):
		return AIProviderResponse.create_failure(
			"Gemini yanıtında içerik bulunamadı", http_status
		)

	var response := AIProviderResponse.create_success(
		content, provider_id, default_model
	)
	response.input_tokens = int(
		_dig(raw_json, ["usageMetadata", "promptTokenCount"], 0)
	)
	response.output_tokens = int(
		_dig(raw_json, ["usageMetadata", "candidatesTokenCount"], 0)
	)
	response.finish_reason = str(
		_dig(raw_json, ["candidates", 0, "finishReason"], "")
	)
	response.http_status = http_status
	return response
