@tool
class_name AIHTTPTransport
extends Node

## HTTPTransport — gerçek HTTP taşıma katmanı (Layer 7).
##
## Bu sınıf sistemin GERÇEKTEN ağa çıktığı tek nokta. Godot'un
## HTTPRequest node'unu sarmalar.
##
## ÖNEMLİ MİMARİ NOTU:
##   HTTPRequest bir Node'dur (RefCounted değil) — sahne ağacına
##   eklenmesi gerekir. Bu yüzden HTTPTransport da Node'dur. Sistemin
##   geri kalanı RefCounted; bu sınıf köprüdür.
##
##   Kullanım: bir sahne/autoload bu node'u ağaca ekler, sonra
##   send_request() çağrılır. Yanıt 'request_finished' sinyali ile gelir.
##
## API ANAHTARI: Bu sınıf anahtarı SAKLAMAZ. Her çağrıda dışarıdan
## alır (anahtar yönetimi ayrı bir güvenlik katmanının işi). Anahtar
## boşsa istek yine gönderilir ama sağlayıcı 401 döner — bu beklenen
## davranıştır, sahte başarı yok.
##
## DRY-RUN: dry_run=true iken gerçek ağ çağrısı YAPILMAZ; istek
## detayları döndürülür. Test ve anahtarsız geliştirme için.

## Gerçek ağ çağrısı yapılsın mı? false = dry-run (istek hazırlanır,
## gönderilmez). API anahtarı + gerçek ortam hazır olunca true yapılır.
var live_mode: bool = false

## Zaman aşımı (saniye).
var timeout_seconds: float = 30.0

## İç HTTPRequest node'u — _ready'de oluşturulur.
var _http: HTTPRequest = null

## Devam eden bir istek var mı (aynı anda tek istek).
var _busy: bool = false

## Aktif isteğin tamamlanınca çağrılacak callback'i.
var _pending_callback: Callable

## Aktif istek başlangıç zamanı (latency hesabı).
var _request_start_ms: int = 0

## Son dry-run isteğinin detayı (test/inceleme için).
var last_dry_run: Dictionary = {}


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = timeout_seconds
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


# ============================================================
# İSTEK GÖNDERME
# ============================================================

## Bir HTTP POST isteği gönderir.
## url: tam endpoint. headers: HTTP başlıkları. body: JSON gövde (Dictionary).
## callback: tamamlanınca {ok, status, json, error, latency_ms} ile çağrılır.
##
## live_mode=false ise GERÇEK ÇAĞRI YAPILMAZ — istek detayı last_dry_run'a
## yazılır, callback dry-run sonucuyla çağrılır.
##
## Dönen: istek başlatıldı mı (false = meşgul veya hata).
func send_post(
	url: String, headers: PackedStringArray, body: Dictionary, callback: Callable
) -> bool:
	if _busy:
		push_warning("HTTPTransport: önceki istek hâlâ sürüyor")
		return false
	if url.strip_edges().is_empty():
		push_warning("HTTPTransport: URL boş")
		return false

	var body_json: String = JSON.stringify(body)

	# --- DRY-RUN: gerçek çağrı yapma ---
	if not live_mode:
		last_dry_run = {
			"url": url,
			"headers": headers,
			"body": body,
			"body_json": body_json,
		}
		# Dry-run sonucu — açıkça "gönderilmedi" der, sahte başarı yok
		if callback.is_valid():
			callback.call({
				"ok": false,
				"status": 0,
				"json": {},
				"error": "DRY-RUN: istek hazırlandı ama gönderilmedi "
					+ "(live_mode=false)",
				"latency_ms": 0,
				"dry_run": true,
			})
		return true

	# --- LIVE: gerçek ağ çağrısı ---
	if _http == null:
		push_error("HTTPTransport: HTTPRequest hazır değil (node ağaçta mı?)")
		return false

	_busy = true
	_pending_callback = callback
	_request_start_ms = Time.get_ticks_msec()

	var err: int = _http.request(
		url, headers, HTTPClient.METHOD_POST, body_json
	)
	if err != OK:
		_busy = false
		if callback.is_valid():
			callback.call({
				"ok": false,
				"status": 0,
				"json": {},
				"error": "HTTP isteği başlatılamadı (kod %d)" % err,
				"latency_ms": 0,
				"dry_run": false,
			})
		return false
	return true


## İstek tamamlandığında HTTPRequest'in çağırdığı iç handler.
func _on_request_completed(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray
) -> void:
	_busy = false
	var latency: int = Time.get_ticks_msec() - _request_start_ms

	# result — Godot'un HTTPRequest.Result enum'u (ağ seviyesi)
	if result != HTTPRequest.RESULT_SUCCESS:
		if _pending_callback.is_valid():
			_pending_callback.call({
				"ok": false,
				"status": 0,
				"json": {},
				"error": _result_error_text(result),
				"latency_ms": latency,
				"dry_run": false,
			})
		return

	# Gövdeyi JSON olarak ayrıştır
	var text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var json_data: Dictionary = {}
	if parsed is Dictionary:
		json_data = parsed
	elif parsed == null:
		# JSON ayrıştırılamadı — yine de status'u ilet
		if _pending_callback.is_valid():
			_pending_callback.call({
				"ok": false,
				"status": response_code,
				"json": {},
				"error": "Yanıt JSON olarak ayrıştırılamadı",
				"latency_ms": latency,
				"dry_run": false,
			})
		return

	# Başarılı — HTTP status'a göre ok belirlenir
	var is_ok: bool = response_code >= 200 and response_code < 300
	if _pending_callback.is_valid():
		_pending_callback.call({
			"ok": is_ok,
			"status": response_code,
			"json": json_data,
			"error": "" if is_ok else "HTTP %d" % response_code,
			"latency_ms": latency,
			"dry_run": false,
		})


## HTTPRequest.Result kodunu insan-okunur metne çevirir.
func _result_error_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "İstek zaman aşımına uğradı"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Sunucuya bağlanılamadı"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "DNS çözümlenemedi — internet bağlantısı yok olabilir"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Bağlantı hatası"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/SSL el sıkışma hatası"
		_:
			return "Ağ hatası (result kodu %d)" % result


## Şu an bir istek devam ediyor mu?
func is_busy() -> bool:
	return _busy
