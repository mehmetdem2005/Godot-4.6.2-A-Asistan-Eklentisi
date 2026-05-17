@tool
class_name AIProviderResponse
extends RefCounted

## ProviderResponse — LLM yanıt taşıyıcısı (Layer 7).
##
## Bir AIProviderRequest gönderildi; sağlayıcı (DeepSeek/OpenAI/...) cevap
## verdi. Her sağlayıcının ham yanıt formatı FARKLI. Adapter o ham JSON'u
## bu ortak yapıya çevirir — sistemin geri kalanı tek format görür.
##
## Mock policy: başarısız çağrı sahte içerik üretmez — ok=false +
## hata sebebi taşır.

## İstek başarılı mı (sağlayıcı geçerli yanıt verdi mi).
var ok: bool = false

## Üretilen metin içeriği (asıl LLM çıktısı).
var content: String = ""

## Hangi sağlayıcı yanıtladı (AIProviderRequest.Provider enum değeri).
var provider: int = AIProviderRequest.Provider.DEEPSEEK

## Kullanılan model adı.
var model: String = ""

## Token kullanımı — maliyet hesabı için.
var input_tokens: int = 0
var output_tokens: int = 0

## Yanıt cache'ten mi geldi (true = API'ye gidilmedi, maliyet 0).
var from_cache: bool = false

## Sağlayıcının bitirme sebebi — "stop", "length", "content_filter"...
var finish_reason: String = ""

## Hata durumunda: HTTP kodu (0 = ağ hatası, çağrı hiç ulaşmadı).
var http_status: int = 0

## Hata durumunda: insan-okunur sebep.
var error_message: String = ""

## Çağrı süresi (ms).
var latency_ms: int = 0

## Hangi isteğe ait (AIProviderRequest.id).
var request_ref: String = ""

## Yanıt zamanı (ISO 8601).
var received_at: String = ""


## Başarılı bir yanıt oluşturur.
static func create_success(
	p_content: String, p_provider: int, p_model: String
) -> AIProviderResponse:
	var r := AIProviderResponse.new()
	r.ok = true
	r.content = p_content
	r.provider = p_provider
	r.model = p_model
	r.received_at = AIContractBase.now_iso()
	return r


## Başarısız bir yanıt oluşturur.
## http_status 0 = çağrı sağlayıcıya hiç ulaşmadı (ağ/yapılandırma hatası).
static func create_failure(
	p_error: String, p_http_status: int = 0
) -> AIProviderResponse:
	var r := AIProviderResponse.new()
	r.ok = false
	r.error_message = p_error
	r.http_status = p_http_status
	r.received_at = AIContractBase.now_iso()
	return r


## Cache'ten gelen bir yanıt oluşturur — maliyet 0.
static func create_from_cache(
	p_content: String, p_provider: int, p_model: String
) -> AIProviderResponse:
	var r := create_success(p_content, p_provider, p_model)
	r.from_cache = true
	return r


## Toplam token (input + output).
func total_tokens() -> int:
	return input_tokens + output_tokens


## Bu yanıt kullanılabilir mi — başarılı VE içerik dolu.
func is_usable() -> bool:
	return ok and not content.strip_edges().is_empty()


## Sözlük temsili — serileştirme / log için.
func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"content": content,
		"provider": provider,
		"model": model,
		"input_tokens": input_tokens,
		"output_tokens": output_tokens,
		"from_cache": from_cache,
		"finish_reason": finish_reason,
		"http_status": http_status,
		"error_message": error_message,
		"latency_ms": latency_ms,
		"request_ref": request_ref,
		"received_at": received_at,
	}
