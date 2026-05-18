@tool
class_name AIAPIKeyStore
extends RefCounted

## APIKeyStore — şifreli API anahtarı deposu (Layer 7 / güvenlik).
##
## API anahtarları kimlik bilgisidir — düz metin saklanmaz. Bu sınıf
## anahtarları AES-256-CBC ile şifreleyip `user://` klasöründe tutar.
##
## NEDEN ŞİFRELEME (user:// zaten cihaza özelken):
##   user:// başka uygulamalardan korunur, ama cihaz yedekleri, dosya
##   senkronizasyonu, ekran paylaşımı gibi sızıntı yolları vardır.
##   Profesyonel standart: kimlik bilgisi her zaman şifreli durur.
##
## MİMARİ:
##   - Şifreleme anahtarı cihaza özel bir tohumdan türetilir
##     (OS.get_unique_id()). Yani bir cihazda şifrelenen dosya başka
##     cihaza kopyalansa çözülemez — ekstra koruma katmanı.
##   - Her kayıt AIEncryptedKeyEntry olarak saklanır: ciphertext + iv
##     + hmac. HMAC bütünlük sağlar — dosya kurcalanırsa yakalanır.
##
## "Mock yasak": şifre çözme HMAC doğrulamasından geçmezse anahtar
## DÖNDÜRÜLMEZ — sahte/bozuk anahtarla sessizce devam edilmez.

## Anahtar dosyasının yolu.
const STORE_PATH: String = "user://ai_assistant_keys.dat"

## AES blok boyutu (CBC için 16 bayt).
const BLOCK_SIZE: int = 16


## Şifrelenmiş anahtar girdileri — provider_name -> AIEncryptedKeyEntry.
var _entries: Dictionary = {}

## Cihaza özel türetilmiş şifreleme anahtarı (32 bayt — AES-256).
var _crypto_key: PackedByteArray = PackedByteArray()

## Son işlem hatası (varsa).
var last_error: String = ""


func _init() -> void:
	_derive_crypto_key()


# ============================================================
# ŞİFRELEME ANAHTARI TÜRETME
# ============================================================

## Cihaza özel kimlikten 32 baytlık AES anahtarı türetir.
## OS.get_unique_id() cihaz başına sabittir — aynı cihazda hep aynı
## anahtar üretilir, başka cihazda farklı.
func _derive_crypto_key() -> void:
	var device_seed: String = OS.get_unique_id()
	# Boş gelirse (bazı platformlar) sabit bir yedek tohum kullan
	if device_seed.is_empty():
		device_seed = "ai_assistant_fallback_seed_v1"
	# SHA-256 ile 32 baytlık anahtar — AES-256 için tam boy
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("ai_asistann::" + device_seed).to_utf8_buffer())
	_crypto_key = ctx.finish()


# ============================================================
# ANAHTAR KAYDETME
# ============================================================

## Bir sağlayıcı için API anahtarını şifreleyip saklar.
## provider_name: "deepseek" | "openai" | "anthropic" | "gemini".
## plaintext_key: düz metin API anahtarı.
## Dönen: {saved: bool, reason: String}
func store_key(provider_name: String, plaintext_key: String) -> Dictionary:
	if provider_name.strip_edges().is_empty():
		return {"saved": false, "reason": "Sağlayıcı adı boş"}
	if plaintext_key.strip_edges().is_empty():
		return {"saved": false, "reason": "API anahtarı boş"}

	# Baş/son boşluk ve satır sonu temizle. Mobilde yapıştırınca
	# anahtara eklenen "\n"/boşluk "Bearer sk-...\n" yapıp 401 üretir.
	# API anahtarları asla baş/son boşluk içermez — güvenle kırpılır.
	var clean_key: String = plaintext_key.strip_edges()

	# Rastgele IV üret (her şifreleme için benzersiz)
	var iv: PackedByteArray = _random_bytes(BLOCK_SIZE)

	# Düz metni blok boyutuna pad'le (PKCS7)
	var plain_bytes: PackedByteArray = clean_key.to_utf8_buffer()
	var padded: PackedByteArray = _pkcs7_pad(plain_bytes)

	# AES-256-CBC şifrele
	var aes := AESContext.new()
	var err: int = aes.start(
		AESContext.MODE_CBC_ENCRYPT, _crypto_key, iv
	)
	if err != OK:
		return {"saved": false, "reason": "AES başlatılamadı"}
	var ciphertext: PackedByteArray = aes.update(padded)
	aes.finish()

	# HMAC-SHA256 bütünlük imzası — ciphertext üzerinden
	var hmac: PackedByteArray = _compute_hmac(ciphertext, iv)

	# AIEncryptedKeyEntry olarak sakla
	var entry: AIEncryptedKeyEntry = AIEncryptedKeyEntry.create(
		provider_name
	)
	entry.set_encrypted_payload(
		Marshalls.raw_to_base64(ciphertext),
		Marshalls.raw_to_base64(iv),
		Marshalls.raw_to_base64(hmac)
	)
	_entries[provider_name] = entry

	# Diske yaz
	if not _save_to_disk():
		return {"saved": false, "reason": last_error}

	return {"saved": true, "reason": "Anahtar şifrelendi ve kaydedildi"}


# ============================================================
# ANAHTAR OKUMA
# ============================================================

## Bir sağlayıcının API anahtarını çözüp döndürür.
## provider_name: sağlayıcı adı.
## Dönen: {ok: bool, key: String, reason: String}
##   ok=false ise key BOŞ — sahte anahtar asla döndürülmez.
func retrieve_key(provider_name: String) -> Dictionary:
	if not _entries.has(provider_name):
		return {
			"ok": false, "key": "",
			"reason": "Bu sağlayıcı için kayıtlı anahtar yok",
		}

	var entry: AIEncryptedKeyEntry = _entries[provider_name]
	if not entry.has_payload():
		return {"ok": false, "key": "", "reason": "Şifreli yük eksik"}

	# Base64'ten ham bayta çevir
	var ciphertext: PackedByteArray = Marshalls.base64_to_raw(
		entry.ciphertext
	)
	var iv: PackedByteArray = Marshalls.base64_to_raw(entry.iv)
	var stored_hmac: PackedByteArray = Marshalls.base64_to_raw(
		entry.hmac
	)

	# HMAC doğrula — dosya kurcalanmış mı?
	var expected_hmac: PackedByteArray = _compute_hmac(ciphertext, iv)
	if not _constant_time_equal(stored_hmac, expected_hmac):
		return {
			"ok": false, "key": "",
			"reason": "HMAC doğrulaması başarısız — anahtar kurcalanmış "
				+ "olabilir, kullanılmadı",
		}

	# AES-256-CBC çöz
	var aes := AESContext.new()
	var err: int = aes.start(
		AESContext.MODE_CBC_DECRYPT, _crypto_key, iv
	)
	if err != OK:
		return {"ok": false, "key": "", "reason": "AES çözme başlatılamadı"}
	var padded: PackedByteArray = aes.update(ciphertext)
	aes.finish()

	# PKCS7 pad'i kaldır
	var plain_bytes: PackedByteArray = _pkcs7_unpad(padded)
	if plain_bytes.is_empty():
		return {
			"ok": false, "key": "",
			"reason": "Çözme sonrası geçersiz dolgu — anahtar bozuk",
		}

	return {
		"ok": true,
		"key": plain_bytes.get_string_from_utf8(),
		"reason": "Anahtar çözüldü",
	}


# ============================================================
# SORGULAMA
# ============================================================

## Bir sağlayıcı için kayıtlı anahtar var mı?
func has_key(provider_name: String) -> bool:
	return _entries.has(provider_name)


## Kayıtlı sağlayıcı adları.
func stored_providers() -> Array:
	return _entries.keys()


## Bir sağlayıcının anahtarını siler.
func delete_key(provider_name: String) -> bool:
	if not _entries.has(provider_name):
		return false
	_entries.erase(provider_name)
	_save_to_disk()
	return true


# ============================================================
# DİSK
# ============================================================

## Anahtar deposunu diskten yükler. Eklenti açılışında çağrılır.
## Dönen: {loaded: bool, count: int, reason: String}
func load_from_disk() -> Dictionary:
	if not FileAccess.file_exists(STORE_PATH):
		# Dosya yok — ilk çalıştırma, hata değil
		return {
			"loaded": true, "count": 0,
			"reason": "Henüz kayıtlı anahtar yok",
		}

	var file: FileAccess = FileAccess.open(
		STORE_PATH, FileAccess.READ
	)
	if file == null:
		last_error = "Anahtar dosyası açılamadı"
		return {"loaded": false, "count": 0, "reason": last_error}

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_error = "Anahtar dosyası bozuk (JSON değil)"
		return {"loaded": false, "count": 0, "reason": last_error}

	_entries.clear()
	var data: Dictionary = parsed
	var provider_map: Dictionary = data.get("providers", {})
	for provider_name in provider_map:
		var entry: AIEncryptedKeyEntry = AIEncryptedKeyEntry.create(
			str(provider_name)
		)
		entry.from_dict(provider_map[provider_name])
		_entries[provider_name] = entry

	return {
		"loaded": true, "count": _entries.size(),
		"reason": "%d anahtar yüklendi" % _entries.size(),
	}


## Anahtar deposunu diske yazar.
func _save_to_disk() -> bool:
	var provider_map: Dictionary = {}
	for provider_name in _entries:
		provider_map[provider_name] = (
			_entries[provider_name] as AIEncryptedKeyEntry
		).to_dict()

	var data: Dictionary = {
		"version": 1,
		"providers": provider_map,
	}

	var file: FileAccess = FileAccess.open(
		STORE_PATH, FileAccess.WRITE
	)
	if file == null:
		last_error = "Anahtar dosyası yazılamadı"
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


# ============================================================
# KRİPTO YARDIMCILARI
# ============================================================

## Belirtilen sayıda kriptografik rastgele bayt üretir.
func _random_bytes(count: int) -> PackedByteArray:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(count)


## HMAC-SHA256 hesaplar — ciphertext + iv üzerinden.
func _compute_hmac(
	ciphertext: PackedByteArray, iv: PackedByteArray
) -> PackedByteArray:
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, _crypto_key)
	ctx.update(iv)
	ctx.update(ciphertext)
	return ctx.finish()


## PKCS7 dolgu ekler — veriyi blok boyutunun katına tamamlar.
func _pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var pad_len: int = BLOCK_SIZE - (data.size() % BLOCK_SIZE)
	# Tam blok ise yine bir tam blok dolgu eklenir (PKCS7 kuralı)
	if pad_len == 0:
		pad_len = BLOCK_SIZE
	var padded: PackedByteArray = data.duplicate()
	for i in range(pad_len):
		padded.append(pad_len)
	return padded


## PKCS7 dolgusunu kaldırır. Geçersizse boş dizi döner.
func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty() or data.size() % BLOCK_SIZE != 0:
		return PackedByteArray()
	var pad_len: int = data[data.size() - 1]
	# Dolgu uzunluğu geçerli aralıkta mı?
	if pad_len <= 0 or pad_len > BLOCK_SIZE or pad_len > data.size():
		return PackedByteArray()
	# Tüm dolgu baytları aynı değerde mi (PKCS7 doğrulaması)?
	for i in range(data.size() - pad_len, data.size()):
		if data[i] != pad_len:
			return PackedByteArray()
	return data.slice(0, data.size() - pad_len)


## İki bayt dizisini sabit zamanda karşılaştırır.
## Zamanlama saldırılarına karşı — erken çıkış yapmaz.
func _constant_time_equal(
	a: PackedByteArray, b: PackedByteArray
) -> bool:
	if a.size() != b.size():
		return false
	var diff: int = 0
	for i in range(a.size()):
		diff |= a[i] ^ b[i]
	return diff == 0
