@tool
class_name AIHTTPTransportTest
extends RefCounted

## Router — HTTPTransport Self-Test
##
## HTTPTransport sistemin gerçekten ağa çıktığı tek nokta. Container'da
## ve test ortamında gerçek HTTP yapılamaz — bu testler taşıma
## katmanının AĞ GEREKTİRMEYEN kısımlarını doğrular:
##   - dry-run davranışı (live_mode=false)
##   - boş URL reddi
##   - last_dry_run kaydı (istek hazırlama doğru mu)
##   - is_busy durumu
##   - hata kodu -> mesaj eşlemesi
##
## Gerçek ağ çağrısı (live_mode=true) bu testlerin kapsamı dışında;
## o, API anahtarı + gerçek cihazla doğrulanır.
##
## NOT: HTTPTransport bir Node'dur. Testte .new() ile oluşturulur;
## dry-run yolu _http node'una dokunmadığı için sahne ağacı gerekmez.


static func run_all() -> Array:
	var results: Array = []

	results.append(_b("Transport: DryRun", _test_dry_run_no_send()))
	results.append(_b("Transport: DryRun", _test_dry_run_records_request()))
	results.append(_b("Transport: DryRun", _test_dry_run_callback()))
	results.append(_b("Transport: Reject", _test_empty_url_rejected()))
	results.append(_b("Transport: State", _test_not_busy_initially()))
	results.append(_b("Transport: State", _test_default_live_mode()))
	results.append(_b("Transport: Errors", _test_error_text_mapping()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# DRY-RUN
# ============================================================

static func _test_dry_run_no_send() -> Dictionary:
	var name := "DryRun gerçek çağrı yapmaz"
	var transport := AIHTTPTransport.new()
	# live_mode varsayılan false — dry-run
	var captured: Dictionary = {}
	var cb := func(response: Dictionary) -> void:
		captured.merge(response, true)
	var sent: bool = transport.send_post(
		"https://api.example.com/v1/chat",
		PackedStringArray(["Content-Type: application/json"]),
		{"model": "test"}, cb
	)
	transport.free()
	# Dry-run da "başarıyla işlendi" (true) döner ama gerçek çağrı yok
	if not sent:
		return _fail(name, "dry-run isteği işlenmeli")
	if not captured.get("dry_run", false):
		return _fail(name, "dry_run bayrağı işaretlenmeli")
	# Dry-run sahte başarı vermemeli — ok=false
	if captured.get("ok", true):
		return _fail(name, "dry-run sahte başarı vermemeli (ok=false)")
	return _ok(name)


static func _test_dry_run_records_request() -> Dictionary:
	var name := "DryRun istek detaylarını kaydeder"
	var transport := AIHTTPTransport.new()
	var cb := func(_response: Dictionary) -> void:
		pass
	transport.send_post(
		"https://api.test.com/endpoint",
		PackedStringArray(["Authorization: Bearer xyz"]),
		{"prompt": "merhaba"}, cb
	)
	var recorded: Dictionary = transport.last_dry_run
	transport.free()
	# last_dry_run istek bilgilerini taşımalı
	if recorded.get("url", "") != "https://api.test.com/endpoint":
		return _fail(name, "dry-run URL'i kaydetmeli")
	if not recorded.has("body_json"):
		return _fail(name, "dry-run gövde JSON'ını kaydetmeli")
	return _ok(name)


static func _test_dry_run_callback() -> Dictionary:
	var name := "DryRun callback çağrılır"
	var transport := AIHTTPTransport.new()
	var called: Array = [false]
	var cb := func(_response: Dictionary) -> void:
		called[0] = true
	transport.send_post(
		"https://x.com/y", PackedStringArray(), {}, cb
	)
	transport.free()
	if not called[0]:
		return _fail(name, "dry-run callback'i çağırmalı")
	return _ok(name)


# ============================================================
# RET
# ============================================================

static func _test_empty_url_rejected() -> Dictionary:
	var name := "Boş URL reddedilir"
	var transport := AIHTTPTransport.new()
	var cb := func(_response: Dictionary) -> void:
		pass
	var sent: bool = transport.send_post("", PackedStringArray(), {}, cb)
	transport.free()
	if sent:
		return _fail(name, "boş URL'li istek reddedilmeli")
	return _ok(name)


# ============================================================
# DURUM
# ============================================================

static func _test_not_busy_initially() -> Dictionary:
	var name := "Başlangıçta meşgul değil"
	var transport := AIHTTPTransport.new()
	var busy: bool = transport.is_busy()
	transport.free()
	if busy:
		return _fail(name, "yeni transport meşgul olmamalı")
	return _ok(name)


static func _test_default_live_mode() -> Dictionary:
	var name := "Varsayılan dry-run modu"
	var transport := AIHTTPTransport.new()
	var live: bool = transport.live_mode
	transport.free()
	# Güvenli varsayılan: live_mode kapalı (kazara ağ çağrısı olmasın)
	if live:
		return _fail(name, "live_mode varsayılan false olmalı")
	return _ok(name)


# ============================================================
# HATA EŞLEMESİ
# ============================================================

static func _test_error_text_mapping() -> Dictionary:
	var name := "Hata kodu -> mesaj eşlemesi"
	var transport := AIHTTPTransport.new()
	# _result_error_text saf fonksiyon — bilinen kodları mesaja çevirir
	var timeout_text: String = transport._result_error_text(
		HTTPRequest.RESULT_TIMEOUT
	)
	var unknown_text: String = transport._result_error_text(9999)
	transport.free()
	if timeout_text.is_empty():
		return _fail(name, "timeout için mesaj olmalı")
	if unknown_text.is_empty():
		return _fail(name, "bilinmeyen kod için de mesaj olmalı")
	# Farklı kodlar farklı mesaj vermeli
	if timeout_text == unknown_text:
		return _fail(name, "farklı hata kodları farklı mesaj vermeli")
	return _ok(name)
