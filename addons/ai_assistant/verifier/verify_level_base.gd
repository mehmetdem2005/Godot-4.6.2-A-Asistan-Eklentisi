@tool
class_name AIVerifyLevelBase
extends RefCounted

## VerifyLevelBase — doğrulama seviyesi temel sınıfı (Layer 5).
##
## Verifier 5 seviyeli olacak (şu an 2'si gerçek):
##   SYNTACTIC   — kod derleniyor mu?
##   SEMANTIC    — anlamlı mı? (tanımsız sembol, çift tanım...)
##   RUNTIME     — çalışınca çöküyor mu? (sonraki phase)
##   BEHAVIORAL  — beklendiği gibi mi davranıyor? (sonraki phase)
##   PERFORMANCE — yeterince hızlı mı? (sonraki phase)
##
## Her seviye bu sınıftan türer ve verify() metodunu override eder.
## Ortak akış, sonuç biçimi ve yardımcılar burada toplanır.
##
## Mock policy: bir seviye gerçekten uygulanmamışsa SKIP/NOT_IMPLEMENTED
## döndürür — asla sahte PASS vermez.

## Bu seviyenin VerifyLevel enum karşılığı — alt sınıf set eder.
var level: int = AIVerificationResult.VerifyLevel.SYNTACTIC

## Bu seviyenin insan-okunur adı — alt sınıf set eder.
var level_name: String = "base"


## Bir GDScript kaynağını doğrular — ALT SINIF OVERRIDE EDER.
## source_code: doğrulanacak GDScript metni.
## context: ek bilgi (dosya yolu, bağımlılıklar vb.) — opsiyonel.
## Dönen: AIVerificationResult.
func verify(source_code: String, context: Dictionary = {}) -> AIVerificationResult:
	# Temel sınıf gerçek doğrulama yapmaz — alt sınıf override etmeli.
	var result := AIVerificationResult.create(level, context.get("task_ref", "?"))
	result.outcome = AIVerificationResult.Outcome.SKIP
	result.message = "VerifyLevelBase.verify() override edilmemiş (NOT_IMPLEMENTED)"
	return result


# ============================================================
# ALT SINIFLAR İÇİN ORTAK YARDIMCILAR
# ============================================================

## Yeni bir sonuç nesnesi üretir — bu seviyenin level'ı ile.
func _new_result(context: Dictionary) -> AIVerificationResult:
	return AIVerificationResult.create(level, context.get("task_ref", "?"))


## Girdi kaynağının temel geçerliliğini kontrol eder.
## Boş veya sadece-boşluk kaynak doğrulanamaz.
## Dönen: {ok: bool, reason: String}
func _check_source_validity(source_code: String) -> Dictionary:
	if source_code.strip_edges().is_empty():
		return {"ok": false, "reason": "Doğrulanacak kaynak boş"}
	return {"ok": true, "reason": ""}


## Bir kaynağı satırlara böler — yorumları ve boş satırları işaretler.
## Dönen: her satır için {num, raw, code, is_blank, is_comment}.
## code = yorumdan arındırılmış kısım (string literal'leri kabaca korunur).
func _tokenize_lines(source_code: String) -> Array:
	var result: Array = []
	var lines: PackedStringArray = source_code.split("\n")
	for i in range(lines.size()):
		var raw: String = lines[i]
		var stripped: String = raw.strip_edges()
		var is_blank: bool = stripped.is_empty()
		var is_comment: bool = stripped.begins_with("#")
		result.append({
			"num": i + 1,
			"raw": raw,
			"code": _strip_comment(raw),
			"is_blank": is_blank,
			"is_comment": is_comment,
		})
	return result


## Bir satırdan yorumu ayıklar — string literal içindeki '#' korunur.
## Basit ama güvenli: tırnak içindeyken '#' yok sayılır.
func _strip_comment(line: String) -> String:
	var in_string: bool = false
	var quote_char: String = ""
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if in_string:
			if ch == quote_char:
				in_string = false
		else:
			if ch == "\"" or ch == "'":
				in_string = true
				quote_char = ch
			elif ch == "#":
				return line.substr(0, i)
		i += 1
	return line


## Bir kaynağın girinti seviyesini (tab sayısı) döndürür.
func _indent_depth(line: String) -> int:
	var depth: int = 0
	for ch in line:
		if ch == "\t":
			depth += 1
		else:
			break
	return depth
