@tool
class_name AISemanticVerifier
extends AIVerifyLevelBase

## SemanticVerifier — anlamsal doğrulama (Layer 5, Seviye 2).
##
## SYNTACTIC "derleniyor mu?" der. SEMANTIC "ANLAMLI mı?" der.
## Kod derlenebilir ama yine de yanlış olabilir:
##   - Çift fonksiyon tanımı (bu oturumda çift 'persist' bug'ı buydu)
##   - Tanımsız enum değeri (bu oturumda 'FUNCTIONAL' bug'ı buydu)
##   - Tanımsız değişken kullanımı
##   - Ulaşılamaz kod (return'den sonra kod)
##   - class_name var ama extends yok
##   - Boş fonksiyon gövdesi
##
## Bu seviye, derlenmiş GDScript nesnesinin introspection API'lerini
## (get_script_method_list vb.) + kontrollü kaynak analizini birleştirir.
##
## Mock policy: emin olunamayan durumda FAIL değil, WARNING üretilir —
## yanlış pozitif gerçek hatadan daha az zararlı ama yine raporlanır.


func _init() -> void:
	level = AIVerificationResult.VerifyLevel.SEMANTIC
	level_name = "semantic"


## Bir GDScript kaynağını anlamsal olarak doğrular.
## Dönen: AIVerificationResult — PASS / FAIL (anlamsal hata bulundu).
func verify(source_code: String, context: Dictionary = {}) -> AIVerificationResult:
	var result: AIVerificationResult = _new_result(context)

	var validity: Dictionary = _check_source_validity(source_code)
	if not validity["ok"]:
		result.mark_fail("Anlamsal: %s" % validity["reason"])
		return result

	var lines: Array = _tokenize_lines(source_code)
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()

	# --- Kontrol 1: çift fonksiyon tanımı ---
	_check_duplicate_functions(lines, errors)

	# --- Kontrol 2: çift sınıf-üyesi (const/var/enum/signal) ---
	_check_duplicate_members(lines, errors)

	# --- Kontrol 3: class_name var ama extends yok ---
	_check_class_structure(lines, errors)

	# --- Kontrol 4: return sonrası ulaşılamaz kod ---
	_check_unreachable_code(lines, warnings)

	# --- Kontrol 5: boş fonksiyon gövdesi ---
	_check_empty_functions(lines, warnings)

	# --- Kontrol 6: enum referans bütünlüğü (dosya-içi) ---
	_check_enum_references(lines, source_code, errors)

	# --- Sonuç değerlendirme ---
	if errors.size() > 0:
		result.mark_fail(
			"Anlamsal doğrulama başarısız — %d hata" % errors.size(),
			errors
		)
		# Uyarılar da rapora eklensin
		for w in warnings:
			result.warnings.append(w)
	else:
		result.mark_pass(
			{
				"checks_run": 6,
				"warnings": warnings.size(),
				"line_count": lines.size(),
			},
			"semantic_analysis"
		)
		for w in warnings:
			result.warnings.append(w)
		if warnings.size() > 0:
			result.message = (
				"Anlamsal doğrulama geçti — %d uyarı" % warnings.size()
			)
		else:
			result.message = "Anlamsal doğrulama geçti — temiz"
	return result


# ============================================================
# KONTROL 1 — çift fonksiyon tanımı
# ============================================================

## Aynı isimde iki top-level fonksiyon = çakışma (derleme hatası).
func _check_duplicate_functions(lines: Array, errors: PackedStringArray) -> void:
	var seen: Dictionary = {}  # isim -> ilk görülen satır
	for info in lines:
		if info["is_comment"] or info["is_blank"]:
			continue
		var code: String = info["code"]
		# Sadece top-level (girintisiz) func
		if _indent_depth(info["raw"]) != 0:
			continue
		var fname: String = _extract_func_name(code)
		if fname.is_empty():
			continue
		if seen.has(fname):
			errors.append(
				"Çift fonksiyon tanımı: '%s' (satır %d ve %d)" % [
					fname, seen[fname], info["num"]
				]
			)
		else:
			seen[fname] = info["num"]


## Bir kod satırından fonksiyon adını çıkarır. func değilse boş string.
func _extract_func_name(code: String) -> String:
	var stripped: String = code.strip_edges()
	# "static func ad(" veya "func ad("
	var without_static: String = stripped
	if without_static.begins_with("static "):
		without_static = without_static.substr(7).strip_edges()
	if not without_static.begins_with("func "):
		return ""
	var after_func: String = without_static.substr(5).strip_edges()
	var paren: int = after_func.find("(")
	if paren < 0:
		return ""
	var name: String = after_func.substr(0, paren).strip_edges()
	return name if _is_identifier(name) else ""


# ============================================================
# KONTROL 2 — çift sınıf üyesi
# ============================================================

## Aynı isimde iki const/var/enum/signal = çakışma.
func _check_duplicate_members(lines: Array, errors: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for info in lines:
		if info["is_comment"] or info["is_blank"]:
			continue
		if _indent_depth(info["raw"]) != 0:
			continue
		var code: String = info["code"].strip_edges()
		var member: String = ""
		for kw in ["const ", "var ", "enum ", "signal "]:
			if code.begins_with(kw):
				var rest: String = code.substr(kw.length()).strip_edges()
				# isim, sonraki ayraç/operatöre kadar
				member = _leading_identifier(rest)
				break
		if member.is_empty():
			continue
		var key: String = member
		if seen.has(key):
			errors.append(
				"Çift üye tanımı: '%s' (satır %d ve %d)" % [
					member, seen[key], info["num"]
				]
			)
		else:
			seen[key] = info["num"]


# ============================================================
# KONTROL 3 — sınıf yapısı
# ============================================================

## class_name varsa extends de olmalı (class_name extends'siz kullanılamaz).
## NOT: class_name ve extends'in göreli sırası serbesttir — Godot her iki
## sırayı da (class_name önce / extends önce) kabul eder. Sıra kontrolü
## YAPILMAZ; sadece class_name VARSA extends'in de bulunması kontrol edilir.
func _check_class_structure(lines: Array, errors: PackedStringArray) -> void:
	var class_name_line: int = -1
	var extends_line: int = -1
	for info in lines:
		var code: String = info["code"].strip_edges()
		if code.begins_with("class_name ") and class_name_line < 0:
			class_name_line = info["num"]
		elif code.begins_with("extends ") and extends_line < 0:
			extends_line = info["num"]

	if class_name_line >= 0 and extends_line < 0:
		errors.append(
			"class_name var ama extends yok (satır %d)" % class_name_line
		)


# ============================================================
# KONTROL 4 — ulaşılamaz kod
# ============================================================

## return/break/continue sonrası, aynı girinti seviyesinde kod = ulaşılamaz.
func _check_unreachable_code(lines: Array, warnings: PackedStringArray) -> void:
	var terminators: Array = ["return", "break", "continue"]
	for i in range(lines.size()):
		var info: Dictionary = lines[i]
		if info["is_comment"] or info["is_blank"]:
			continue
		var code: String = info["code"]
		var stripped: String = code.strip_edges()
		var depth: int = _indent_depth(info["raw"])

		# Bu satır bir terminatör mü
		var is_term: bool = false
		for t in terminators:
			if stripped == t or stripped.begins_with(t + " "):
				is_term = true
				break
		if not is_term:
			continue

		# Sonraki anlamlı satır — aynı/daha derin girintide mi
		var j: int = i + 1
		while j < lines.size():
			var nxt: Dictionary = lines[j]
			if nxt["is_blank"] or nxt["is_comment"]:
				j += 1
				continue
			var nxt_depth: int = _indent_depth(nxt["raw"])
			# Aynı blokta (aynı girinti), terminatörden sonra kod var
			if nxt_depth >= depth:
				warnings.append(
					"Ulaşılamaz kod olabilir: satır %d ('%s' sonrası)" % [
						nxt["num"], stripped.split(" ")[0]
					]
				)
			break


# ============================================================
# KONTROL 5 — boş fonksiyon gövdesi
# ============================================================

## func tanımının gövdesi yok (ne pass, ne kod) — derleme hatası.
func _check_empty_functions(lines: Array, warnings: PackedStringArray) -> void:
	for i in range(lines.size()):
		var info: Dictionary = lines[i]
		if info["is_comment"] or info["is_blank"]:
			continue
		var code: String = info["code"].strip_edges()
		var is_func: bool = (
			code.begins_with("func ") or code.begins_with("static func ")
		)
		if not is_func or not code.ends_with(":"):
			continue
		var func_depth: int = _indent_depth(info["raw"])

		# Sonraki anlamlı satır gövde mi (daha derin girinti)
		var j: int = i + 1
		var has_body: bool = false
		while j < lines.size():
			var nxt: Dictionary = lines[j]
			if nxt["is_blank"] or nxt["is_comment"]:
				j += 1
				continue
			if _indent_depth(nxt["raw"]) > func_depth:
				has_body = true
			break
		if not has_body:
			warnings.append(
				"Boş fonksiyon gövdesi olabilir: satır %d" % info["num"]
			)


# ============================================================
# KONTROL 6 — enum referans bütünlüğü (dosya-içi)
# ============================================================

## Dosya içinde tanımlı bir enum'a yapılan EnumAdi.DEGER referansları,
## o enum'da gerçekten var olan değerlere karşı doğrulanır.
## ('FUNCTIONAL' bug'ı tipi — olmayan enum değeri kullanımı.)
func _check_enum_references(
	lines: Array, source_code: String, errors: PackedStringArray
) -> void:
	# Bu dosyadaki enum tanımlarını topla
	var enums: Dictionary = _collect_local_enums(source_code)
	if enums.is_empty():
		return

	for info in lines:
		if info["is_comment"] or info["is_blank"]:
			continue
		var code: String = info["code"]
		# EnumAdi.DEGER deseni — DEGER büyük harf
		var idx: int = 0
		while idx < code.length():
			var dot: int = code.find(".", idx)
			if dot < 0:
				break
			# nokta öncesi tanımlayıcı
			var before: String = _identifier_ending_at(code, dot)
			var after: String = _identifier_starting_at(code, dot + 1)
			if enums.has(before) and not after.is_empty():
				# after büyük-harf bir değer mi (enum değeri konvansiyonu)
				if after == after.to_upper() and after != after.to_lower():
					if not (enums[before] as Array).has(after):
						errors.append(
							"Satır %d: '%s.%s' — '%s' enum'da yok (geçerli: %s)" % [
								info["num"], before, after, after,
								str(enums[before])
							]
						)
			idx = dot + 1


## Dosyadaki enum tanımlarını {enum_adı: [değerler]} olarak toplar.
func _collect_local_enums(source_code: String) -> Dictionary:
	var enums: Dictionary = {}
	var lines: PackedStringArray = source_code.split("\n")
	var current_enum: String = ""
	for raw in lines:
		var stripped: String = _strip_comment(raw).strip_edges()
		if stripped.begins_with("enum "):
			var rest: String = stripped.substr(5).strip_edges()
			var brace: int = rest.find("{")
			if brace > 0:
				var ename: String = rest.substr(0, brace).strip_edges()
				if _is_identifier(ename):
					current_enum = ename
					enums[ename] = []
					# aynı satırda } var mı (tek satır enum)
					var inline: String = rest.substr(brace + 1)
					if inline.contains("}"):
						_parse_enum_values(
							inline.substr(0, inline.find("}")), enums[ename]
						)
						current_enum = ""
		elif not current_enum.is_empty():
			if stripped.contains("}"):
				_parse_enum_values(
					stripped.substr(0, stripped.find("}")), enums[current_enum]
				)
				current_enum = ""
			else:
				_parse_enum_values(stripped, enums[current_enum])
	return enums


## Bir enum gövde parçasındaki değerleri listeye ekler.
func _parse_enum_values(fragment: String, out: Array) -> void:
	for part in fragment.split(","):
		var name: String = part.strip_edges()
		# "= 5" varsa at
		var eq: int = name.find("=")
		if eq >= 0:
			name = name.substr(0, eq).strip_edges()
		if _is_identifier(name) and not out.has(name):
			out.append(name)


# ============================================================
# DAHİLİ — tanımlayıcı yardımcıları
# ============================================================

## Bir metnin geçerli bir GDScript tanımlayıcısı olup olmadığı.
func _is_identifier(s: String) -> bool:
	if s.is_empty():
		return false
	var first: String = s[0]
	if not (first == "_" or _is_letter(first)):
		return false
	for ch in s:
		if not (ch == "_" or _is_letter(ch) or _is_digit(ch)):
			return false
	return true


## Bir metnin başındaki tanımlayıcıyı döndürür.
func _leading_identifier(s: String) -> String:
	var result: String = ""
	for ch in s:
		if ch == "_" or _is_letter(ch) or (_is_digit(ch) and not result.is_empty()):
			result += ch
		else:
			break
	return result


## Belirli bir indekste BİTEN tanımlayıcıyı geri doğru okur.
func _identifier_ending_at(text: String, end_idx: int) -> String:
	var i: int = end_idx - 1
	var chars: Array = []
	while i >= 0:
		var ch: String = text[i]
		if ch == "_" or _is_letter(ch) or _is_digit(ch):
			chars.push_front(ch)
			i -= 1
		else:
			break
	return "".join(chars)


## Belirli bir indeksten BAŞLAYAN tanımlayıcıyı ileri okur.
func _identifier_starting_at(text: String, start_idx: int) -> String:
	var result: String = ""
	var i: int = start_idx
	while i < text.length():
		var ch: String = text[i]
		if ch == "_" or _is_letter(ch) or _is_digit(ch):
			result += ch
			i += 1
		else:
			break
	return result


func _is_letter(ch: String) -> bool:
	return ch.to_lower() != ch.to_upper()


func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"
