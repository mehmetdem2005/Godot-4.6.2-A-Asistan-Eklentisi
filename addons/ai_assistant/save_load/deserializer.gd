@tool
class_name AISaveDeserializer
extends RefCounted

## SaveDeserializer — kayıt çözümleyici (Madde 09 / Save-Load).
##
## Diskteki JSON kayıt dosyasını geri Dictionary'e çevirir. AMA en
## kritik iş bu değil — DOĞRULAMA. Kayıt dosyası bozuk olabilir
## (yarım yazılmış, kurcalanmış, eski sürümden). Bu sınıf SAVUNMACI:
## bozuk veride ÇÖKMEZ, açık hata döndürür.
##
## Kontroller:
##   - JSON geçerli mi (parse edilebiliyor mu)
##   - Zarf yapısı doğru mu (_meta + data var mı)
##   - Şema sürümü okunabiliyor mu
##
## Save/Load invariant'ı: "asla çökme" — bozuk kayıt oyunu
## çökertmemeli, kullanıcıya temiz bir hata göstermeli.
##
## Mock policy: çözümleme gerçek JSON'dan; eksik alan uydurulmaz.

## Bir çözümleme sonucu.
class DeserializeResult extends RefCounted:
	var ok: bool = false
	var data: Dictionary = {}          ## Oyun durumu (data kısmı)
	var schema_version: int = -1       ## Kayıttan okunan şema sürümü
	var envelope_version: int = -1
	var saved_at_unix: int = 0
	var game_id: String = ""
	var error: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"schema_version": schema_version,
			"envelope_version": envelope_version,
			"game_id": game_id,
			"error": error,
		}


# ============================================================
# ÇÖZÜMLEME
# ============================================================

## Bir JSON kayıt metnini çözümler ve doğrular.
## json_text: diskten okunan ham JSON.
## Dönen: DeserializeResult — başarısızsa ok=false + açık hata.
func deserialize(json_text: String) -> DeserializeResult:
	var result := DeserializeResult.new()

	# --- Adım 1: boş kontrolü ---
	if json_text.strip_edges().is_empty():
		result.error = "Kayıt dosyası boş"
		return result

	# --- Adım 2: JSON parse — savunmacı ---
	var json := JSON.new()
	var parse_err: int = json.parse(json_text)
	if parse_err != OK:
		result.error = "Bozuk JSON: satır %d — %s" % [
			json.get_error_line(), json.get_error_message()
		]
		return result

	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		result.error = "Kayıt kök yapısı bir nesne (Dictionary) değil"
		return result

	var envelope: Dictionary = parsed

	# --- Adım 3: zarf yapısı doğrulama ---
	if not envelope.has("_meta"):
		result.error = "Kayıt üst-verisi (_meta) eksik"
		return result
	if not envelope.has("data"):
		result.error = "Kayıt verisi (data) eksik"
		return result

	var meta: Variant = envelope["_meta"]
	if typeof(meta) != TYPE_DICTIONARY:
		result.error = "_meta bir nesne değil"
		return result
	var data: Variant = envelope["data"]
	if typeof(data) != TYPE_DICTIONARY:
		result.error = "data bir nesne değil"
		return result

	# --- Adım 4: üst-veriyi oku ---
	var meta_dict: Dictionary = meta
	result.envelope_version = int(meta_dict.get("envelope_version", -1))
	result.schema_version = int(meta_dict.get("schema_version", -1))
	result.saved_at_unix = int(meta_dict.get("saved_at_unix", 0))
	result.game_id = str(meta_dict.get("game_id", ""))

	# Şema sürümü okunamadıysa — kayıt güvenilmez
	if result.schema_version < 0:
		result.error = "Şema sürümü eksik veya geçersiz"
		return result

	result.data = data
	result.ok = true
	return result


## Bir kayıt metninin SADECE şema sürümünü okur — tam çözümleme
## yapmadan. Migration kararı için hızlı kontrol.
## Dönen: şema sürümü, okunamadıysa -1.
func peek_schema_version(json_text: String) -> int:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return -1
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return -1
	var envelope: Dictionary = parsed
	if not envelope.has("_meta"):
		return -1
	var meta: Variant = envelope["_meta"]
	if typeof(meta) != TYPE_DICTIONARY:
		return -1
	return int((meta as Dictionary).get("schema_version", -1))


## Bir JSON metninin geçerli bir kayıt zarfı olup olmadığını
## hızlıca kontrol eder (tam çözümleme yapmadan).
func is_valid_save(json_text: String) -> bool:
	return deserialize(json_text).ok
