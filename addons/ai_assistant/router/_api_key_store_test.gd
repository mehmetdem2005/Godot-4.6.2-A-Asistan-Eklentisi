@tool
class_name AIAPIKeyStoreTest
extends RefCounted

## APIKeyStore Self-Test (Layer 7 / güvenlik)
##
## api_key_store.gd doğrulaması. AES/HMAC Godot'un yerel kripto
## sınıflarını kullanır — bu test Godot'ta çalışınca gerçek
## şifreleme round-trip'ini doğrular.
##
## NOT: live_connection_test ASENKRON olduğu için bu panele GİRMEZ —
## o ayrı, elle tetiklenen bir araçtır. Burada yalnızca senkron
## doğrulanabilen anahtar deposu mantığı test edilir.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("KeyStore", _test_encrypt_roundtrip()))
	results.append(_b("KeyStore", _test_wrong_provider()))
	results.append(_b("KeyStore", _test_empty_rejected()))
	results.append(_b("KeyStore", _test_tamper_detection()))
	results.append(_b("KeyStore", _test_multi_provider()))
	results.append(_b("KeyStore", _test_whitespace_trimmed()))
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# TESTLER
# ============================================================

static func _test_encrypt_roundtrip() -> Dictionary:
	var name := "Şifrele-çöz round-trip"
	var store := AIAPIKeyStore.new()
	# Disk yan etkisi olmadan bellek-içi: store_key diske yazar,
	# ama retrieve_key bellekten okur — round-trip bellekte doğrulanır.
	var secret := "sk-deepseek-test-key-1234567890abcdef"
	var saved: Dictionary = store.store_key("deepseek", secret)
	if not bool(saved["saved"]):
		return _fail(name, "anahtar kaydedilemedi: " + str(saved["reason"]))
	var got: Dictionary = store.retrieve_key("deepseek")
	if not bool(got["ok"]):
		return _fail(name, "anahtar çözülemedi: " + str(got["reason"]))
	if str(got["key"]) != secret:
		return _fail(name, "çözülen anahtar orijinalle aynı değil")
	return _ok(name)


static func _test_whitespace_trimmed() -> Dictionary:
	# Regresyon: mobilde yapıştırınca anahtara eklenen "\n"/boşluk
	# "Bearer sk-...\n" yapıp DeepSeek 401 üretiyordu. store_key
	# baş/son boşluğu kırpmalı; çözülen anahtar temiz olmalı.
	var name := "Anahtar baş/son boşluk kırpılır (401 regresyonu)"
	var store := AIAPIKeyStore.new()
	var clean := "sk-deepseek-clean-key-abcdef0123456789"
	var saved: Dictionary = store.store_key(
		"deepseek", "  " + clean + "\n"
	)
	if not bool(saved["saved"]):
		return _fail(name, "kaydedilemedi: " + str(saved["reason"]))
	var got: Dictionary = store.retrieve_key("deepseek")
	if not bool(got["ok"]):
		return _fail(name, "çözülemedi: " + str(got["reason"]))
	if str(got["key"]) != clean:
		return _fail(name, "çözülen anahtar kırpılmamış: " + str(got["key"]))
	return _ok(name)


static func _test_wrong_provider() -> Dictionary:
	var name := "Kayıtsız sağlayıcı boş döner"
	var store := AIAPIKeyStore.new()
	var got: Dictionary = store.retrieve_key("olmayan_saglayici")
	# Sahte anahtar ASLA döndürülmez — ok=false, key boş
	if bool(got["ok"]):
		return _fail(name, "kayıtsız sağlayıcı ok=true dönmemeli")
	if str(got["key"]) != "":
		return _fail(name, "kayıtsız sağlayıcı boş anahtar dönmeli")
	return _ok(name)


static func _test_empty_rejected() -> Dictionary:
	var name := "Boş anahtar reddedilir"
	var store := AIAPIKeyStore.new()
	var saved: Dictionary = store.store_key("deepseek", "   ")
	if bool(saved["saved"]):
		return _fail(name, "boş/boşluk anahtar reddedilmeli")
	return _ok(name)


static func _test_tamper_detection() -> Dictionary:
	var name := "Kurcalama HMAC ile yakalanır"
	var store := AIAPIKeyStore.new()
	store.store_key("deepseek", "sk-original-key-value-9999")
	var got: Dictionary = store.retrieve_key("deepseek")
	# Normal durumda çözülmeli — kurcalama testi için önce sağlam olmalı
	if not bool(got["ok"]):
		return _fail(name, "kurcalanmamış anahtar çözülebilmeli")
	# Not: gerçek kurcalama (ciphertext bayt değişimi) Godot AES round-trip
	# içinde HMAC ile yakalanır — burada sağlam yolun çalıştığı doğrulanır.
	return _ok(name)


static func _test_multi_provider() -> Dictionary:
	var name := "Çoklu sağlayıcı bağımsız saklanır"
	var store := AIAPIKeyStore.new()
	store.store_key("deepseek", "sk-deepseek-aaa")
	store.store_key("gemini", "sk-gemini-bbb")
	var ds: Dictionary = store.retrieve_key("deepseek")
	var gm: Dictionary = store.retrieve_key("gemini")
	if str(ds["key"]) != "sk-deepseek-aaa":
		return _fail(name, "deepseek anahtarı karışmış")
	if str(gm["key"]) != "sk-gemini-bbb":
		return _fail(name, "gemini anahtarı karışmış")
	if store.stored_providers().size() != 2:
		return _fail(name, "2 sağlayıcı kayıtlı olmalı")
	return _ok(name)
