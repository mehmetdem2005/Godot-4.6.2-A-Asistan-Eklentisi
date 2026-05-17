@tool
class_name AILiveConnectionTest
extends Node

## LiveConnectionTest — canlı bağlantı testi (Layer 7 / entegrasyon).
##
## Sistemin İLK KEZ gerçekten ağa çıkıp bir LLM'den yanıt aldığı an.
## Tüm zinciri uçtan uca koşturur:
##   APIKeyStore (anahtar çöz) -> Router (istek hazırla)
##   -> HTTPTransport (gerçek POST) -> Router (yanıt çöz)
##
## NEDEN AYRI BİR ARAÇ (712'lik panele girmez):
##   712 birim testi SENKRON — çağır, anında sonuç al, kontrol et.
##   Bu test ASENKRON — gerçek ağ çağrısı 1-2 saniye sürer, sonuç bir
##   sinyalle gelir. Senkron panele sokulamaz; ayrı durur, elle
##   tetiklenir. Birim testi ile canlı entegrasyon testi ayrı
##   dünyalardır — profesyonel ayrım.
##
## KULLANIM:
##   1. Bir sahneye/autoload'a bu Node eklenir.
##   2. run_test() çağrılır.
##   3. Sonuç 'test_finished' sinyali ile gelir:
##      {ok: bool, message: String, latency_ms: int, reply: String}
##
## "Mock yasak": anahtar yoksa, ağ yoksa, sağlayıcı hata dönerse —
## açık hata mesajı verir. Sahte "bağlandı" demez.

## Test tamamlandığında yayılan sinyal.
## result: {ok, message, latency_ms, reply}
signal test_finished(result: Dictionary)

## Test ilerleme bildirimi — UI'da adım göstermek için.
signal test_progress(step: String)


## Test edilecek sağlayıcı (şimdilik DeepSeek).
const TEST_PROVIDER_NAME: String = "deepseek"

## Bağlantı testi için gönderilecek basit mesaj.
const TEST_PROMPT: String = "Merhaba. Sadece 'BAGLANTI_TAMAM' yaz."


## Anahtar deposu.
var _key_store: AIAPIKeyStore = null

## Sağlayıcı router'ı.
var _router: AIProviderRouter = null

## HTTP taşıyıcısı (Node — çocuk olarak eklenir).
var _transport: AIHTTPTransport = null

## Test sürüyor mu.
var _running: bool = false

## Aktif test isteğinin referansı (yanıt eşleştirme için).
var _active_request: AIProviderRequest = null


# ============================================================
# KURULUM
# ============================================================

func _ready() -> void:
	# HTTP taşıyıcısını çocuk Node olarak kur — ağaca girmesi şart
	_transport = AIHTTPTransport.new()
	_transport.name = "LiveTestTransport"
	_transport.live_mode = true  # GERÇEK ağ çağrısı
	add_child(_transport)

	# Router'ı kur
	_router = AIProviderRouter.new()
	_router.attach_transport(_transport)

	# Anahtar deposunu kur ve diskten yükle
	_key_store = AIAPIKeyStore.new()
	_key_store.load_from_disk()


# ============================================================
# TEST ÇALIŞTIRMA
# ============================================================

## Canlı bağlantı testini başlatır.
## Sonuç 'test_finished' sinyali ile gelir — bu fonksiyon beklemez.
## Dönen: test başlatılabildi mi (false = ön koşul hatası).
func run_test() -> bool:
	if _running:
		test_progress.emit("Test zaten sürüyor")
		return false

	# --- 1. Anahtar var mı ve çözülebiliyor mu? ---
	test_progress.emit("API anahtarı kontrol ediliyor...")
	var key_result: Dictionary = _key_store.retrieve_key(
		TEST_PROVIDER_NAME
	)
	if not bool(key_result["ok"]):
		_emit_failure(
			"API anahtarı alınamadı: " + str(key_result["reason"])
		)
		return false
	var api_key: String = str(key_result["key"])

	# --- 2. Router'a anahtarı ver ---
	_router.set_api_key(
		AIProviderRequest.Provider.DEEPSEEK, api_key
	)

	# --- 3. Test isteği oluştur ---
	test_progress.emit("İstek hazırlanıyor...")
	_active_request = AIProviderRequest.create(
		AIProviderRequest.Purpose.REASONING, "live_connection_test"
	)
	_active_request.provider = AIProviderRequest.Provider.DEEPSEEK
	_active_request.add_message("user", TEST_PROMPT)
	_active_request.max_tokens = 64
	_active_request.temperature = 0.0

	# --- 4. Router ile yönlendir ---
	var routed: Dictionary = _router.route(_active_request)

	# Router cache'ten veya hata ile anında cevap verdiyse
	if bool(routed["resolved"]):
		var response: AIProviderResponse = routed["response"]
		if response != null and response.is_usable():
			_emit_success(response.content, 0)
		else:
			_emit_failure("Router isteği hazırlayamadı")
		return true

	# --- 5. Ağ çağrısı gerekiyor — gerçek POST ---
	if not bool(routed["needs_network"]):
		_emit_failure("Beklenmeyen router durumu")
		return false

	var prepared: Dictionary = routed["prepared"]
	_running = true
	test_progress.emit("DeepSeek'e bağlanılıyor...")

	var started: bool = _transport.send_post(
		str(prepared["url"]),
		prepared["headers"],
		prepared["body"],
		_on_transport_result
	)
	if not started:
		_running = false
		_emit_failure("HTTP isteği başlatılamadı (taşıyıcı meşgul?)")
		return false

	return true


# ============================================================
# YANIT İŞLEME
# ============================================================

## HTTPTransport çağrıyı bitirince çağrılır.
## raw_result: {ok, status, json, error, latency_ms, dry_run}
func _on_transport_result(raw_result: Dictionary) -> void:
	_running = false
	var latency: int = int(raw_result.get("latency_ms", 0))

	# Ağ seviyesi hata mı?
	if not bool(raw_result.get("ok", false)):
		var net_error: String = str(raw_result.get("error", "?"))
		# HTTP status varsa daha açıklayıcı mesaj
		var status: int = int(raw_result.get("status", 0))
		if status == 401:
			net_error = "API anahtarı reddedildi (401) — anahtar geçersiz"
		elif status == 429:
			net_error = "İstek limiti aşıldı (429) — biraz bekleyin"
		_emit_failure(net_error, latency)
		return

	# Router'a yanıtı çözdür
	var handled: Dictionary = _router.handle_response(
		raw_result, _active_request,
		AIProviderRequest.Provider.DEEPSEEK
	)
	var response: AIProviderResponse = handled["response"]

	if response == null or not response.is_usable():
		var reason: String = "Sağlayıcı yanıtı kullanılamadı"
		if response != null and not response.error_message.is_empty():
			reason = response.error_message
		_emit_failure(reason, latency)
		return

	# BAŞARI — gerçek bir LLM yanıtı geldi
	_emit_success(response.content, latency)


# ============================================================
# SONUÇ YAYMA
# ============================================================

## Başarılı sonuç yayar.
func _emit_success(reply: String, latency_ms: int) -> void:
	test_finished.emit({
		"ok": true,
		"message": "Bağlantı başarılı — DeepSeek yanıt verdi",
		"latency_ms": latency_ms,
		"reply": reply,
	})


## Başarısız sonuç yayar.
func _emit_failure(reason: String, latency_ms: int = 0) -> void:
	test_finished.emit({
		"ok": false,
		"message": reason,
		"latency_ms": latency_ms,
		"reply": "",
	})


# ============================================================
# ANAHTAR YÖNETİMİ — test öncesi anahtar kurmak için
# ============================================================

## Bir API anahtarını şifreleyip kaydeder (test öncesi bir kez).
## Anahtar girişi için kalıcı yol — UI ayar ekranı da bunu çağırır.
## Dönen: {saved: bool, reason: String}
func save_api_key(plaintext_key: String) -> Dictionary:
	return _key_store.store_key(TEST_PROVIDER_NAME, plaintext_key)


## Kayıtlı bir anahtar var mı?
func has_api_key() -> bool:
	return _key_store.has_key(TEST_PROVIDER_NAME)


## Test şu an çalışıyor mu?
func is_running() -> bool:
	return _running
