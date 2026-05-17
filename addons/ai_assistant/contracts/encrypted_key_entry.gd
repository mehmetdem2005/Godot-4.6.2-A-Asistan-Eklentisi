@tool
class_name AIEncryptedKeyEntry
extends AIContractBase

## EncryptedKeyEntry — şifrelenmiş API anahtarı kaydı (Madde 6 API Key Security).
##
## API anahtarları asla düz metin saklanmaz. Her anahtar AES-256-CBC ile
## şifrelenir, HMAC-SHA256 ile bütünlük korunur.
##
## ÖNEMLİ: Bu contract sadece ŞİFRELENMİŞ veriyi tutar. Düz metin anahtar
## hiçbir zaman bu nesnede bulunmaz, serialize edilmez, loglanmaz.

# --- Kimlik ---
var provider: String = ""            ## deepseek | openai | anthropic | gemini

# --- Şifreli veri (asla düz metin!) ---
var ciphertext: String = ""          ## Base64 şifrelenmiş anahtar
var iv: String = ""                  ## Base64 initialization vector (16 byte)
var hmac: String = ""                ## Base64 HMAC-SHA256 bütünlük imzası

# --- Doğrulama durumu ---
var validation_status: String = "unverified"
## unverified | valid | invalid | stale

var last_validated_at: String = ""

# --- Zaman ---
var encrypted_at: String = ""


func contract_type() -> String:
	return "EncryptedKeyEntry"


## Yeni bir şifreli anahtar kaydı oluşturur (factory).
## NOT: Şifreleme işlemi bu contract'ın sorumluluğu değil — sadece sonucu tutar.
static func create(p_provider: String) -> AIEncryptedKeyEntry:
	var e := AIEncryptedKeyEntry.new()
	e.provider = p_provider
	e.encrypted_at = AIContractBase.now_iso()
	e.validation_status = "unverified"
	return e


## Şifreli veriyi set eder (şifreleme dışarıda yapılır).
func set_encrypted_payload(p_ciphertext: String, p_iv: String, p_hmac: String) -> void:
	ciphertext = p_ciphertext
	iv = p_iv
	hmac = p_hmac


## Anahtar doğrulama durumunu günceller.
func mark_validated(is_valid: bool) -> void:
	validation_status = "valid" if is_valid else "invalid"
	last_validated_at = AIContractBase.now_iso()


## Doğrulama eski mi (24 saatten fazla)?
## elapsed_hours: son doğrulamadan bu yana geçen saat.
func is_validation_stale(elapsed_hours: float) -> bool:
	return validation_status == "valid" and elapsed_hours > 24.0


## Bu kayıt kullanılabilir mi (şifreli veri tam mı)?
func has_payload() -> bool:
	return not ciphertext.is_empty() and not iv.is_empty() and not hmac.is_empty()


func _to_dict_impl() -> Dictionary:
	# DİKKAT: Burada sadece şifreli veri var — düz metin anahtar ASLA yok.
	return {
		"provider": provider,
		"ciphertext": ciphertext,
		"iv": iv,
		"hmac": hmac,
		"validation_status": validation_status,
		"last_validated_at": last_validated_at,
		"encrypted_at": encrypted_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	provider = data.get("provider", "")
	ciphertext = data.get("ciphertext", "")
	iv = data.get("iv", "")
	hmac = data.get("hmac", "")
	validation_status = data.get("validation_status", "unverified")
	last_validated_at = data.get("last_validated_at", "")
	encrypted_at = data.get("encrypted_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, provider, "provider")
	require_in_set(
		result,
		validation_status,
		["unverified", "valid", "invalid", "stale"],
		"validation_status"
	)
	# Payload varsa üç parça da tam olmalı (encrypt-then-MAC bütünlüğü)
	if not ciphertext.is_empty():
		if iv.is_empty():
			result.add_error("ciphertext var ama iv eksik — şifreleme bütünlüğü bozuk")
		if hmac.is_empty():
			result.add_error("ciphertext var ama hmac eksik — bütünlük imzası yok")
