@tool
class_name AISaveHMACSigner
extends RefCounted

## HMACSigner — kayıt imzalayıcı (Madde 09 / Save-Load / bütünlük).
##
## Bir kayıt dosyası kurcalanmış olabilir — oyuncu save dosyasını
## elle düzenleyip hile yapmış, ya da dosya bozulmuş olabilir. Bu
## sınıf kayda bir HMAC-SHA256 İMZASI ekler.
##
## HMAC: içerik + gizli anahtar -> tek yönlü imza. İçerik bir bayt
## bile değişirse imza tutmaz. Anahtarı bilmeyen geçerli imza
## üretemez.
##
## Kullanım:
##   - Kaydederken: sign_content(content) -> imza, dosyaya eklenir
##   - Yüklerken: verify(content, imza) -> kurcalanmış mı
##
## NOT: Godot'un HMAC-SHA256'sı kullanılır. Anahtar yönetimi
## ayrı bir konu (Madde 6) — bu sınıf anahtarı dışarıdan alır.
##
## Mock policy: imza gerçek kriptografik fonksiyondan üretilir.

## Varsayılan anahtar — gerçek kullanımda dışarıdan verilmeli.
## Bu sadece anahtar verilmediğinde tutarlılık için.
const FALLBACK_KEY: String = "ai_assistant_save_integrity_v1"


## İmzalama için kullanılan anahtar.
var _key: PackedByteArray


func _init(key: String = "") -> void:
	if key.is_empty():
		_key = FALLBACK_KEY.to_utf8_buffer()
	else:
		_key = key.to_utf8_buffer()


## İmzalama anahtarını ayarlar.
func set_key(key: String) -> void:
	if key.is_empty():
		push_warning("HMACSigner: boş anahtar reddedildi")
		return
	_key = key.to_utf8_buffer()


# ============================================================
# İMZALAMA
# ============================================================

## Bir içerik için HMAC-SHA256 imzası üretir.
## content: imzalanacak metin (genelde kayıt JSON'ı).
## Dönen: Base64 kodlanmış imza string'i. Hata olursa boş string.
##
## NOT: Metot adı 'sign_content' — 'sign' GDScript'in yerleşik
## matematik fonksiyonudur, çakışma olmaması için açık ad kullanılır.
func sign_content(content: String) -> String:
	if content.is_empty():
		return ""
	var ctx := HMACContext.new()
	var start_err: int = ctx.start(HashingContext.HASH_SHA256, _key)
	if start_err != OK:
		push_error("HMACSigner: HMAC başlatılamadı")
		return ""
	var update_err: int = ctx.update(content.to_utf8_buffer())
	if update_err != OK:
		push_error("HMACSigner: HMAC güncellenemedi")
		return ""
	var digest: PackedByteArray = ctx.finish()
	return Marshalls.raw_to_base64(digest)


# ============================================================
# DOĞRULAMA
# ============================================================

## Bir içeriğin imzasını doğrular.
## content: kontrol edilecek metin. signature: beklenen imza.
## Dönen: true = imza geçerli (içerik kurcalanmamış).
##
## Sabit-zamanlı karşılaştırma kullanılır — zamanlama saldırısına
## karşı (imzanın kaçıncı karakterde tutmadığı sızdırılmaz).
func verify(content: String, signature: String) -> bool:
	if signature.is_empty():
		return false
	var expected: String = sign_content(content)
	if expected.is_empty():
		return false
	return _constant_time_equals(expected, signature)


## İçerik + imza zarfını tek seferde doğrular.
## signed_content: {content: String, signature: String} biçiminde.
## Dönen: {ok: bool, content: String, reason: String}
func verify_envelope(signed_content: Dictionary) -> Dictionary:
	if not signed_content.has("content"):
		return {"ok": false, "content": "", "reason": "İçerik alanı yok"}
	if not signed_content.has("signature"):
		return {"ok": false, "content": "", "reason": "İmza alanı yok"}
	var content: String = str(signed_content["content"])
	var signature: String = str(signed_content["signature"])
	if verify(content, signature):
		return {"ok": true, "content": content, "reason": ""}
	return {
		"ok": false,
		"content": "",
		"reason": "İmza tutmuyor — kayıt kurcalanmış veya bozuk",
	}


# ============================================================
# DAHİLİ
# ============================================================

## İki string'i sabit zamanda karşılaştırır.
## Erken çıkış yok — uzunluk farkı dışında her zaman tüm karakterler
## kontrol edilir, böylece zamanlama bilgi sızdırmaz.
func _constant_time_equals(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var diff: int = 0
	for i in range(a.length()):
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0
