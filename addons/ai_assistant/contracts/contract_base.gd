@tool
class_name AIContractBase
extends RefCounted

## Tüm sözleşme (contract) sınıflarının ortak temel sınıfı.
##
## Bu sınıf, sistemdeki tüm veri sözleşmelerinin aynı disipline uymasını sağlar:
## serileştirme (to_dict / from_dict), doğrulama (validate), ve kimlik (contract_type).
##
## Kullanım: Her yeni contract bu sınıftan türer, _validate_impl() ve
## _to_dict_impl() / _from_dict_impl() metodlarını override eder.
##
## Mock policy: Hiçbir contract sahte/yarım veri kabul etmez. validate() başarısız
## olursa AIValidationResult.ok = false döner ve sebep raporlanır.


## Contract tipini döndürür (alt sınıflar override eder).
## Örn: "TaskSpec", "ActionSpec". Serileştirmede tip güvenliği için kullanılır.
func contract_type() -> String:
	push_error("AIContractBase.contract_type() override edilmeli")
	return "AIContractBase"


## Contract şema versiyonu — migration ve uyumluluk için.
func contract_version() -> int:
	return 1


## Contract'ı Dictionary'ye çevirir. Alt sınıflar _to_dict_impl() override eder.
## Sonuç her zaman "_contract_type" ve "_contract_version" meta alanlarını içerir.
func to_dict() -> Dictionary:
	var data: Dictionary = _to_dict_impl()
	data["_contract_type"] = contract_type()
	data["_contract_version"] = contract_version()
	return data


## Contract'ı JSON string'e çevirir.
func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")


## Dictionary'den contract alanlarını yükler. Alt sınıflar _from_dict_impl() override eder.
## Geçersiz/eksik veriyi sessizce kabul etmez — validate() ile kontrol edilmeli.
func from_dict(data: Dictionary) -> void:
	if data.has("_contract_type"):
		var stored_type: String = data["_contract_type"]
		if stored_type != contract_type():
			push_warning(
				"Contract tipi uyuşmazlığı: beklenen '%s', gelen '%s'"
				% [contract_type(), stored_type]
			)
	_from_dict_impl(data)


## JSON string'den contract yükler. Parse hatası durumunda false döner.
func from_json(json_text: String) -> bool:
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_error("Contract JSON parse hatası: geçersiz JSON")
		return false
	from_dict(parsed as Dictionary)
	return true


## Contract'ın geçerliliğini kontrol eder.
## Alt sınıflar _validate_impl() override ederek kendi kurallarını ekler.
func validate() -> AIValidationResult:
	var result := AIValidationResult.new()
	_validate_impl(result)
	return result


## Contract geçerli mi? (kısa yol)
func is_valid() -> bool:
	return validate().ok


# --- Alt sınıfların override edeceği metodlar ---

## Alt sınıf: alanları Dictionary'ye yazar.
func _to_dict_impl() -> Dictionary:
	push_error("%s._to_dict_impl() override edilmeli" % contract_type())
	return {}


## Alt sınıf: Dictionary'den alanları okur.
func _from_dict_impl(_data: Dictionary) -> void:
	push_error("%s._from_dict_impl() override edilmeli" % contract_type())


## Alt sınıf: doğrulama kurallarını result'a ekler.
func _validate_impl(_result: AIValidationResult) -> void:
	push_error("%s._validate_impl() override edilmeli" % contract_type())


# --- Ortak yardımcı doğrulama metodları (alt sınıflar kullanır) ---

## Bir string alanın boş olmadığını doğrular.
static func require_non_empty_string(
	result: AIValidationResult, value: String, field_name: String
) -> void:
	if value.strip_edges().is_empty():
		result.add_error("'%s' alanı boş olamaz" % field_name)


## Bir değerin izin verilen bir enum değeri olduğunu doğrular.
static func require_in_set(
	result: AIValidationResult, value: Variant, allowed: Array, field_name: String
) -> void:
	if not allowed.has(value):
		result.add_error(
			"'%s' alanı geçersiz: '%s' (izin verilenler: %s)"
			% [field_name, str(value), str(allowed)]
		)


## Bir sayısal alanın belirtilen aralıkta olduğunu doğrular.
static func require_in_range(
	result: AIValidationResult, value: float, min_v: float, max_v: float, field_name: String
) -> void:
	if value < min_v or value > max_v:
		result.add_error(
			"'%s' alanı aralık dışı: %s (beklenen: %s - %s)"
			% [field_name, str(value), str(min_v), str(max_v)]
		)


## Pozitif olması gereken bir sayıyı doğrular.
static func require_positive(
	result: AIValidationResult, value: float, field_name: String
) -> void:
	if value <= 0:
		result.add_error("'%s' alanı pozitif olmalı: %s" % [field_name, str(value)])


## Yeni bir benzersiz kimlik üretir (UUID benzeri, çakışma riski ihmal edilebilir).
static func generate_id(prefix: String = "") -> String:
	var rng_part: String = "%08x%08x" % [randi(), randi()]
	var time_part: String = "%x" % Time.get_ticks_usec()
	if prefix.is_empty():
		return "%s%s" % [time_part, rng_part]
	return "%s_%s%s" % [prefix, time_part, rng_part]


## Şu anki UTC zaman damgasını ISO 8601 formatında döndürür.
static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## ISO 8601 string'i Unix timestamp'e çevirir (karşılaştırma için).
static func iso_to_unix(iso: String) -> int:
	var clean: String = iso.rstrip("Z")
	return int(Time.get_unix_time_from_datetime_string(clean))
