@tool
class_name AIProviderAdapterBase
extends RefCounted

## ProviderAdapterBase — sağlayıcı adapter temel sınıfı (Layer 7).
##
## Her LLM sağlayıcısının API'si FARKLIDIR:
##   - Farklı endpoint URL'leri
##   - Farklı istek JSON şeması (messages formatı, parametre isimleri)
##   - Farklı yanıt JSON şeması (içerik nerede, token nerede)
##   - Farklı kimlik doğrulama başlığı (Authorization, x-api-key...)
##
## Adapter deseni: her sağlayıcı için bir alt sınıf. Sistemin geri kalanı
## tek arayüz görür: build_request_body() ve parse_response().
##
## Bu temel sınıf ortak yapı + alt sınıfların override edeceği sözleşmeyi
## tanımlar. Gerçek HTTP gönderimi HTTPTransport'ta; adapter sadece
## ÇEVİRİ yapar (istek nesnesi -> sağlayıcı JSON'u, sağlayıcı JSON'u ->
## AIProviderResponse).
##
## Mock policy: adapter sahte yanıt üretmez — sadece format çevirir.

## Bu adapter'ın sağladığı sağlayıcı (AIProviderRequest.Provider).
var provider_id: int = AIProviderRequest.Provider.DEEPSEEK

## Sağlayıcının insan-okunur adı.
var provider_name: String = "base"

## API endpoint URL'si — alt sınıf set eder.
var endpoint_url: String = ""

## Bu sağlayıcının varsayılan modeli.
var default_model: String = ""


# ============================================================
# ALT SINIFLARIN OVERRIDE EDECEĞİ SÖZLEŞME
# ============================================================

## İstek gövdesini (JSON-uyumlu Dictionary) üretir — ALT SINIF OVERRIDE EDER.
## request: AIProviderRequest. Dönen: sağlayıcının beklediği JSON yapısı.
func build_request_body(request: AIProviderRequest) -> Dictionary:
	push_warning("AdapterBase.build_request_body() override edilmemiş")
	return {}


## HTTP başlıklarını üretir — ALT SINIF OVERRIDE EDER.
## api_key: kimlik anahtarı (dışarıdan verilir, adapter saklamaz).
## Dönen: ["Header: value", ...] biçiminde PackedStringArray.
func build_headers(api_key: String) -> PackedStringArray:
	push_warning("AdapterBase.build_headers() override edilmemiş")
	return PackedStringArray()


## Sağlayıcının ham yanıt JSON'unu AIProviderResponse'a çevirir.
## ALT SINIF OVERRIDE EDER.
## raw_json: ayrıştırılmış yanıt (Dictionary). http_status: HTTP kodu.
func parse_response(raw_json: Dictionary, http_status: int) -> AIProviderResponse:
	push_warning("AdapterBase.parse_response() override edilmemiş")
	return AIProviderResponse.create_failure("Adapter parse_response yok")


# ============================================================
# ORTAK YARDIMCILAR (alt sınıflar kullanır)
# ============================================================

## AIProviderRequest'in mesajlarını OpenAI-uyumlu role/content dizisine
## çevirir. DeepSeek ve OpenAI bu formatı paylaşır.
func _messages_openai_format(request: AIProviderRequest) -> Array:
	var msgs: Array = []
	# system prompt varsa ilk mesaj olarak
	if not request.system_prompt.strip_edges().is_empty():
		msgs.append({"role": "system", "content": request.system_prompt})
	for m in request.messages:
		msgs.append({
			"role": m.get("role", "user"),
			"content": m.get("content", ""),
		})
	return msgs


## HTTP durum kodunun başarı aralığında olup olmadığı (2xx).
func _is_http_ok(status: int) -> bool:
	return status >= 200 and status < 300


## Bir yanıt JSON'unda iç içe bir alanı güvenli okur.
## path: ["choices", 0, "message", "content"] gibi.
## Bulunamazsa default döner — çökme yok.
func _dig(data: Variant, path: Array, default_value: Variant = null) -> Variant:
	var current: Variant = data
	for key in path:
		if current is Dictionary:
			if not (current as Dictionary).has(key):
				return default_value
			current = (current as Dictionary)[key]
		elif current is Array:
			var idx: int = int(key)
			if idx < 0 or idx >= (current as Array).size():
				return default_value
			current = (current as Array)[idx]
		else:
			return default_value
	return current


## HTTP hata kodunu insan-okunur sebebe çevirir.
func _http_error_text(status: int) -> String:
	match status:
		400:
			return "Geçersiz istek (400)"
		401:
			return "Kimlik doğrulama başarısız — API anahtarı geçersiz (401)"
		403:
			return "Erişim reddedildi (403)"
		404:
			return "Endpoint bulunamadı (404)"
		429:
			return "Hız limiti aşıldı — çok fazla istek (429)"
		500, 502, 503:
			return "Sağlayıcı sunucu hatası (%d)" % status
		0:
			return "Ağ hatası — sağlayıcıya ulaşılamadı"
		_:
			return "HTTP hatası (%d)" % status
