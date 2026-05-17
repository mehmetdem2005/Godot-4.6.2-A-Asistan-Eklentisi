@tool
class_name AISyntacticVerifier
extends AIVerifyLevelBase

## SyntacticVerifier — sözdizimi doğrulama (Layer 5, Seviye 1).
##
## "En profesyonel olan" = taklit değil, GERÇEK derleyici. Bu sınıf
## Godot'un kendi GDScript derleyicisini çağırır:
##   1. Verilen kaynaktan bir GDScript nesnesi oluştur
##   2. set_source_code() + reload() ile motora derlet
##   3. reload() dönüş kodunu oku — OK ise syntax geçerli, değilse hata
##
## Godot neyi reddederse Verifier de reddeder. %100 motor-doğru.
##
## NOT: reload() motor API'sidir; editör/runtime ortamında çalışır.
## Container'da Godot yok — bu seviyenin gerçek testi Godot içinde olur.
## Container tarafında mantık + edge-case ön-kontrolleri stress edilir.

## Derleme öncesi yapılan ucuz ön-kontroller — derleyiciye gitmeden
## bariz sorunları yakalar (boş kaynak, dengesiz parantez).
## Bunlar derleyici hatasının daha okunur halini verir.


func _init() -> void:
	level = AIVerificationResult.VerifyLevel.SYNTACTIC
	level_name = "syntactic"


## Bir GDScript kaynağını sözdizimsel olarak doğrular.
## Dönen: AIVerificationResult — PASS (derlendi) / FAIL (syntax hatası).
func verify(source_code: String, context: Dictionary = {}) -> AIVerificationResult:
	var result: AIVerificationResult = _new_result(context)

	# --- Girdi geçerliliği ---
	var validity: Dictionary = _check_source_validity(source_code)
	if not validity["ok"]:
		result.mark_fail("Sözdizimi: %s" % validity["reason"])
		return result

	# --- Ön-kontrol: dengesiz parantez/köşeli/süslü ---
	# Derleyiciye gitmeden bariz yapısal hatayı yakala — daha okunur mesaj.
	var bracket: Dictionary = _check_bracket_balance(source_code)
	if not bracket["ok"]:
		result.mark_fail("Sözdizimi: %s" % bracket["reason"])
		return result

	# --- Gerçek derleme: Godot GDScript derleyicisi ---
	var compile: Dictionary = _compile_with_engine(source_code)
	if compile["ok"]:
		result.mark_pass(
			{
				"compiled": true,
				"method": "GDScript.reload()",
				"line_count": source_code.split("\n").size(),
			},
			"engine_compile"
		)
		result.message = "Sözdizimi geçerli — motor derlemesi başarılı"
	else:
		result.mark_fail(
			"Sözdizimi hatası — motor derlemesi başarısız: %s" % compile["reason"],
			PackedStringArray([compile["reason"]])
		)
	return result


# ============================================================
# GERÇEK DERLEME — Godot motoru
# ============================================================

## Kaynağı Godot'un GDScript derleyicisiyle derler.
## Dönen: {ok: bool, reason: String}
func _compile_with_engine(source_code: String) -> Dictionary:
	# Yeni bir GDScript nesnesi — bağımsız, projeyi etkilemez
	var script := GDScript.new()
	script.source_code = source_code

	# reload() motoru tetikler: lexer + parser + analyzer çalışır.
	# Dönen Error kodu OK ise derleme başarılı.
	var err: int = script.reload()

	if err == OK:
		return {"ok": true, "reason": ""}

	# Hata kodu insan-okunur mesaja çevrilir
	var reason: String = _error_code_to_text(err)
	return {"ok": false, "reason": reason}


## Godot Error enum kodunu okunur metne çevirir.
func _error_code_to_text(err: int) -> String:
	match err:
		ERR_PARSE_ERROR:
			return "Parse hatası (sözdizimi geçersiz)"
		ERR_COMPILATION_FAILED:
			return "Derleme başarısız"
		ERR_INVALID_DATA:
			return "Geçersiz veri"
		ERR_SCRIPT_FAILED:
			return "Script yükleme başarısız"
		_:
			return "Derleme hatası (Error kodu %d)" % err


# ============================================================
# ÖN-KONTROL — parantez dengesi
# ============================================================

## Parantez/köşeli/süslü ayraç dengesini kontrol eder.
## String literal ve yorum içindeki ayraçlar sayılmaz.
## Dönen: {ok: bool, reason: String}
func _check_bracket_balance(source_code: String) -> Dictionary:
	var pairs: Dictionary = {")": "(", "]": "[", "}": "{"}
	var openers: Dictionary = {"(": true, "[": true, "{": true}
	var stack: Array = []

	var lines: Array = _tokenize_lines(source_code)
	for line_info in lines:
		var code: String = line_info["code"]
		var in_string: bool = false
		var quote_char: String = ""
		var i: int = 0
		while i < code.length():
			var ch: String = code[i]
			if in_string:
				if ch == quote_char:
					in_string = false
			else:
				if ch == "\"" or ch == "'":
					in_string = true
					quote_char = ch
				elif openers.has(ch):
					stack.append({"ch": ch, "line": line_info["num"]})
				elif pairs.has(ch):
					if stack.is_empty():
						return {
							"ok": false,
							"reason": "Satır %d: fazladan '%s' kapama" % [
								line_info["num"], ch
							],
						}
					var top: Dictionary = stack.pop_back()
					if top["ch"] != pairs[ch]:
						return {
							"ok": false,
							"reason": "Satır %d: '%s' ile '%s' eşleşmiyor" % [
								line_info["num"], top["ch"], ch
							],
						}
			i += 1

	if not stack.is_empty():
		var unclosed: Dictionary = stack[0]
		return {
			"ok": false,
			"reason": "Satır %d: '%s' kapatılmamış" % [
				unclosed["line"], unclosed["ch"]
			],
		}
	return {"ok": true, "reason": ""}
