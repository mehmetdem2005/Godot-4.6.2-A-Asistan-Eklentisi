@tool
class_name AISaveSerializer
extends RefCounted

## SaveSerializer — kayıt serileştirici (Madde 09 / Save-Load).
##
## Oyun durumunu (Dictionary) diske yazılabilir JSON string'e çevirir.
## Save/Load'ın 5 invariant'ından biri: serileştirme DETERMİNİSTİK
## ve KENDİNİ TANIMLAR olmalı — yani çıktı her zaman bir şema
## sürümü ve üst-veri taşır.
##
## Üretilen yapı:
##   {
##     "_meta": { schema_version, saved_at, game_id, ... },
##     "data": { ...gerçek oyun durumu... }
##   }
##
## _meta sayesinde bir kayıt dosyası kendini açıklar: hangi sürüm,
## ne zaman kaydedildi. Bu, ileride migration (sürüm yükseltme)
## için şarttır.
##
## Mock policy: serileştirme gerçek veriden yapılır; eksik üst-veri
## uydurulmaz, açık varsayılan kullanılır.

## Kayıt formatı sürümü — bu serializer'ın ürettiği zarf sürümü.
const ENVELOPE_VERSION: int = 1


## Bir serileştirme sonucu.
class SerializeResult extends RefCounted:
	var ok: bool = false
	var json_text: String = ""
	var byte_size: int = 0
	var error: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"byte_size": byte_size,
			"error": error,
		}


# ============================================================
# SERİLEŞTİRME
# ============================================================

## Oyun durumunu kendini-tanımlayan JSON'a çevirir.
## game_state: kaydedilecek oyun verisi (Dictionary).
## schema_version: oyunun kendi şema sürümü (migration için).
## game_id: oyun kimliği (opsiyonel üst-veri).
## Dönen: SerializeResult.
func serialize(
	game_state: Dictionary, schema_version: int, game_id: String = ""
) -> SerializeResult:
	var result := SerializeResult.new()

	# JSON'a çevrilemeyen tip kontrolü — savunmacı
	if not _is_json_safe(game_state):
		result.error = "Oyun durumu JSON-uyumsuz tip içeriyor"
		return result

	# Kendini-tanımlayan zarf
	var envelope: Dictionary = {
		"_meta": {
			"envelope_version": ENVELOPE_VERSION,
			"schema_version": schema_version,
			"game_id": game_id,
			"saved_at_unix": int(Time.get_unix_time_from_system()),
		},
		"data": game_state,
	}

	var json_text: String = JSON.stringify(envelope, "\t")
	if json_text.is_empty():
		result.error = "JSON serileştirme başarısız"
		return result

	result.json_text = json_text
	result.byte_size = json_text.to_utf8_buffer().size()
	result.ok = true
	return result


## Sadece veri kısmını serileştirir — zarf olmadan (iç kullanım).
func serialize_raw(data: Dictionary) -> String:
	if not _is_json_safe(data):
		return ""
	return JSON.stringify(data, "\t")


# ============================================================
# DAHİLİ — JSON güvenlik kontrolü
# ============================================================

## Bir değerin JSON'a güvenle çevrilebilir olup olmadığını kontrol eder.
## JSON destekler: null, bool, int, float, String, Array, Dictionary.
## Object/Callable/RID gibi tipler kaydedilemez.
func _is_json_safe(value: Variant) -> bool:
	var t: int = typeof(value)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, \
		TYPE_STRING_NAME:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				# Anahtarlar string olmalı (JSON kuralı)
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				if not _is_json_safe(value[key]):
					return false
			return true
		# Vektör/renk gibi tipler — JSON'da yok, kaydedilemez
		_:
			return false
