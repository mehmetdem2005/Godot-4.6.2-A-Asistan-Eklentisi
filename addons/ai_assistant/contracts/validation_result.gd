@tool
class_name AIValidationResult
extends RefCounted

## Doğrulama sonucu — bir contract'ın veya işlemin geçerli olup olmadığını,
## ve geçersizse sebeplerini taşır.
##
## Sistemin her yerinde ortak doğrulama dili: contract validation,
## verifier sonuçları, edit validation hepsi bunu kullanır.

var ok: bool = true
var errors: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()


## Bir hata ekler ve sonucu geçersiz işaretler.
func add_error(msg: String) -> void:
	errors.append(msg)
	ok = false


## Bir uyarı ekler (geçerliliği etkilemez).
func add_warning(msg: String) -> void:
	warnings.append(msg)


## Başka bir doğrulama sonucunu bunun içine birleştirir.
func merge(other: AIValidationResult) -> void:
	if other == null:
		return
	for e in other.errors:
		errors.append(e)
	for w in other.warnings:
		warnings.append(w)
	if not other.ok:
		ok = false


## Hata var mı?
func has_errors() -> bool:
	return errors.size() > 0


## Uyarı var mı?
func has_warnings() -> bool:
	return warnings.size() > 0


## Tüm hata ve uyarıları tek metin olarak özetler (log/UI için).
func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if ok:
		parts.append("✓ Geçerli")
	else:
		parts.append("✗ Geçersiz (%d hata)" % errors.size())
	for e in errors:
		parts.append("  HATA: " + e)
	for w in warnings:
		parts.append("  UYARI: " + w)
	return "\n".join(parts)


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
	}


## Boş, başarılı bir sonuç oluşturur (factory).
static func create_ok() -> AIValidationResult:
	return AIValidationResult.new()


## Tek hatayla başarısız bir sonuç oluşturur (factory).
static func create_error(msg: String) -> AIValidationResult:
	var r := AIValidationResult.new()
	r.add_error(msg)
	return r
