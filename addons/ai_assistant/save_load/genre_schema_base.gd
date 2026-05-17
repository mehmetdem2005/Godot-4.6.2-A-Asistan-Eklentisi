@tool
class_name AISaveGenreSchemaBase
extends RefCounted

## GenreSchemaBase — tür şeması temeli (Madde 09 / genre_schemas).
##
## Her oyun türü farklı veri kaydeder. Ama hepsinin paylaştığı bir
## yapı var: bir şema = ALAN TANIMLARI listesi. Her alan: adı, tipi,
## varsayılan değeri, zorunlu mu.
##
## Bu temel sınıf o ortak yapıyı + ortak işlemleri tutar:
##   - şemaya göre bir kayıt sözlüğü DOĞRULA
##   - eksik alanları varsayılanla TAMAMLA
##   - boş bir kayıt iskeleti ÜRET
##
## Somut şemalar (fps_3d, rpg_topdown...) bunu genişletir, sadece
## kendi alanlarını tanımlar — doğrulama mantığı buradan gelir.
##
## "Mock yasak": doğrulama gerçek şema kurallarından; geçersiz
## kayıt açıkça reddedilir, sessizce kabul edilmez.

## Desteklenen alan tipleri.
enum FieldType { INT, FLOAT, STRING, BOOL, ARRAY, DICT }

const TYPE_NAMES: Dictionary = {
	FieldType.INT: "int",
	FieldType.FLOAT: "float",
	FieldType.STRING: "string",
	FieldType.BOOL: "bool",
	FieldType.ARRAY: "array",
	FieldType.DICT: "dict",
}

## FieldType -> GDScript TYPE_* karşılığı.
const GDTYPE_MAP: Dictionary = {
	FieldType.INT: TYPE_INT,
	FieldType.FLOAT: TYPE_FLOAT,
	FieldType.STRING: TYPE_STRING,
	FieldType.BOOL: TYPE_BOOL,
	FieldType.ARRAY: TYPE_ARRAY,
	FieldType.DICT: TYPE_DICTIONARY,
}


## Bir şema alanı.
class SchemaField extends RefCounted:
	var field_name: String = ""
	var field_type: int = AISaveGenreSchemaBase.FieldType.INT
	var default_value: Variant = null
	var required: bool = true

	func _init(
		p_name: String, p_type: int, p_default: Variant,
		p_required: bool = true
	) -> void:
		field_name = p_name
		field_type = p_type
		default_value = p_default
		required = p_required


## Şemanın tür adı — alt sınıf set eder.
var genre_name: String = "base"

## Alan tanımları — field_name -> SchemaField.
var _fields: Dictionary = {}


# ============================================================
# ALAN TANIMLAMA — alt sınıflar kullanır
# ============================================================

## Şemaya bir alan ekler.
func define_field(
	field_name: String, field_type: int, default_value: Variant,
	required: bool = true
) -> void:
	if field_name.is_empty():
		return
	_fields[field_name] = SchemaField.new(
		field_name, field_type, default_value, required
	)


## Tanımlı alan sayısı.
func field_count() -> int:
	return _fields.size()


## Bir alan tanımlı mı?
func has_field(field_name: String) -> bool:
	return _fields.has(field_name)


## Tüm alan adları.
func field_names() -> Array:
	return _fields.keys()


# ============================================================
# İSKELET ÜRETİMİ
# ============================================================

## Şemaya göre varsayılan değerlerle boş bir kayıt iskeleti üretir.
func make_skeleton() -> Dictionary:
	var skeleton: Dictionary = {"__genre__": genre_name}
	for field_name in _fields:
		var field: SchemaField = _fields[field_name]
		skeleton[field_name] = field.default_value
	return skeleton


# ============================================================
# DOĞRULAMA
# ============================================================

## Bir kayıt sözlüğünü şemaya göre doğrular.
## data: doğrulanacak kayıt.
## Dönen: {valid: bool, errors: PackedStringArray, missing: PackedStringArray}
func validate(data: Dictionary) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var missing: PackedStringArray = PackedStringArray()

	for field_name in _fields:
		var field: SchemaField = _fields[field_name]

		# Alan var mı
		if not data.has(field_name):
			if field.required:
				missing.append(field_name)
			continue

		# Tip doğru mu
		var expected_gdtype: int = GDTYPE_MAP[field.field_type]
		var actual_value: Variant = data[field_name]
		if not _type_matches(actual_value, expected_gdtype):
			errors.append("'%s' tip hatası — beklenen: %s" % [
				field_name, TYPE_NAMES[field.field_type]
			])

	var valid: bool = errors.is_empty() and missing.is_empty()
	return {"valid": valid, "errors": errors, "missing": missing}


## Bir değerin beklenen GDScript tipinde olup olmadığını kontrol eder.
## int alanları float değer de kabul eder (JSON sayı belirsizliği).
func _type_matches(value: Variant, expected_gdtype: int) -> bool:
	var actual: int = typeof(value)
	if actual == expected_gdtype:
		return true
	# JSON int/float esnekliği — int beklenen yere float gelebilir
	if expected_gdtype == TYPE_INT and actual == TYPE_FLOAT:
		return true
	if expected_gdtype == TYPE_FLOAT and actual == TYPE_INT:
		return true
	return false


# ============================================================
# TAMAMLAMA
# ============================================================

## Eksik alanları varsayılan değerlerle tamamlanmış bir kopya döndürür.
## data: kısmi kayıt.
## Dönen: tüm zorunlu alanları olan tam kayıt.
func fill_defaults(data: Dictionary) -> Dictionary:
	var filled: Dictionary = data.duplicate(true)
	filled["__genre__"] = genre_name
	for field_name in _fields:
		if not filled.has(field_name):
			var field: SchemaField = _fields[field_name]
			filled[field_name] = field.default_value
	return filled


## Bir kayıt bu şemaya göre tamamlanabilir mi?
## (tip hatası yoksa — sadece eksik alanlar tamamlanabilir)
func is_repairable(data: Dictionary) -> bool:
	var result: Dictionary = validate(data)
	# Tip hatası tamir edilemez; sadece eksik alan tamamlanabilir
	return (result["errors"] as PackedStringArray).is_empty()
