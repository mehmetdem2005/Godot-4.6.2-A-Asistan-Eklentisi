@tool
class_name AISaveSchemaRegistry
extends RefCounted

## SchemaRegistry — şema kayıt defteri (Madde 09 / genre_schemas).
##
## 9 oyun türü şeması var. Save/Load sistemi hangi şemayı
## kullanacağını bilmeli — oyun "ben bir RPG'yim" der, registry
## doğru şemayı verir.
##
## Bu sınıf tüm tür şemalarını tek yerden erişilebilir kılar:
## tür adıyla şema bul, kayıt verisinden türü tespit et, bir
## kaydı doğru şemaya göre doğrula.
##
## Mock policy: şema seçimi gerçek tür adından; bilinmeyen tür
## açıkça reddedilir.

## Tür adı -> şema örneği.
var _schemas: Dictionary = {}


func _init() -> void:
	_register_builtin_schemas()


## Yerleşik 9 tür şemasını kaydeder.
func _register_builtin_schemas() -> void:
	_register(AISaveFPS3DSchema.new())
	_register(AISavePlatformer2DSchema.new())
	_register(AISaveRPGTopdownSchema.new())
	_register(AISavePuzzleSchema.new())
	_register(AISaveRacing3DSchema.new())
	_register(AISaveSurvival3DSchema.new())
	_register(AISaveVisualNovelSchema.new())
	_register(AISaveStrategyIsometricSchema.new())
	_register(AISaveHorror3DSchema.new())


## Bir şemayı kaydeder.
func _register(schema: AISaveGenreSchemaBase) -> void:
	if schema != null and not schema.genre_name.is_empty():
		_schemas[schema.genre_name] = schema


# ============================================================
# ŞEMA ERİŞİMİ
# ============================================================

## Bir tür için şema kayıtlı mı?
func has_schema(genre_name: String) -> bool:
	return _schemas.has(genre_name)


## Bir tür adı için şemayı döndürür. Yoksa null.
func get_schema(genre_name: String) -> AISaveGenreSchemaBase:
	return _schemas.get(genre_name, null)


## Kayıtlı tüm tür adları.
func genre_names() -> Array:
	var names: Array = _schemas.keys()
	names.sort()
	return names


## Kayıtlı şema sayısı.
func schema_count() -> int:
	return _schemas.size()


# ============================================================
# TÜR TESPİTİ
# ============================================================

## Bir kayıt verisinden oyun türünü tespit eder.
## Şemalar make_skeleton'da "__genre__" alanı koyar.
## Dönen: tür adı, yoksa boş string.
func detect_genre(data: Dictionary) -> String:
	var genre: String = str(data.get("__genre__", ""))
	if genre.is_empty() or not _schemas.has(genre):
		return ""
	return genre


# ============================================================
# DOĞRULAMA
# ============================================================

## Bir kayıt verisini, gömülü türüne göre doğrular.
## data: kayıt verisi (__genre__ alanı içermeli).
## Dönen: {ok: bool, genre: String, validation: Dictionary, reason}
func validate_save(data: Dictionary) -> Dictionary:
	var genre: String = detect_genre(data)
	if genre.is_empty():
		return {
			"ok": false, "genre": "", "validation": {},
			"reason": "Kayıt türü tespit edilemedi",
		}

	var schema: AISaveGenreSchemaBase = _schemas[genre]
	var validation: Dictionary = schema.validate(data)
	return {
		"ok": bool(validation["valid"]),
		"genre": genre,
		"validation": validation,
		"reason": "Doğrulama tamam" if bool(validation["valid"]) \
			else "Şema doğrulaması başarısız",
	}


## Bir tür için boş kayıt iskeleti üretir.
## Dönen: iskelet sözlük, tür yoksa boş sözlük.
func make_skeleton(genre_name: String) -> Dictionary:
	if not _schemas.has(genre_name):
		return {}
	return (_schemas[genre_name] as AISaveGenreSchemaBase).make_skeleton()
