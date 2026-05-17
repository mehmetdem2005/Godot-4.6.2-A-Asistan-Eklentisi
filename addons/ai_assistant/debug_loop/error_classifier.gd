@tool
class_name AIDebugErrorClassifier
extends RefCounted

## ErrorClassifier — hata sınıflandırıcı (Madde 02 / Debug Loop).
##
## Debug Loop'un ilk adımı: kod çalıştı, hata çıktı — bu NE TÜR bir
## hata? Sınıflandırma deterministiktir (LLM'siz): hata metnindeki
## örüntülere bakar, kategoriye atar.
##
## Kategori, sonraki adımı belirler:
##   PARSE_ERROR    — sözdizimi; satır numarası kesin, hızlı düzeltme
##   API_ERROR      — yanlış metod/sınıf; Godot 3->4 mapper'a gider
##   TYPE_ERROR     — tip uyuşmazlığı
##   NULL_ERROR     — null nesneye erişim
##   RUNTIME_ERROR  — genel çalışma hatası
##   UNKNOWN        — örüntü eşleşmedi; LLM analizi gerekir
##
## Mehmet'in "sürekli başka hatalar alıyorum" acısının kökü: hatayı
## doğru sınıflandırmamak. Yanlış kategori = yanlış düzeltme = yeni
## hata. Bu sınıf o döngüyü kırar.
##
## Mock policy: sınıflandırma gerçek hata metninden; tahmin yok,
## eşleşme yoksa açıkça UNKNOWN.

## Hata kategorileri.
enum ErrorCategory { PARSE_ERROR, API_ERROR, TYPE_ERROR, NULL_ERROR, RUNTIME_ERROR, UNKNOWN }

const CATEGORY_NAMES: Dictionary = {
	ErrorCategory.PARSE_ERROR: "parse_error",
	ErrorCategory.API_ERROR: "api_error",
	ErrorCategory.TYPE_ERROR: "type_error",
	ErrorCategory.NULL_ERROR: "null_error",
	ErrorCategory.RUNTIME_ERROR: "runtime_error",
	ErrorCategory.UNKNOWN: "unknown",
}


## Bir hata sınıflandırma sonucu.
class ErrorClass extends RefCounted:
	var category: int = AIDebugErrorClassifier.ErrorCategory.UNKNOWN
	var line: int = -1                 ## Hata satırı (-1 = bilinmiyor)
	var symbol: String = ""            ## İlgili sembol/metod adı
	var raw_message: String = ""
	var needs_llm: bool = false        ## LLM analizi gerekli mi

	func category_name() -> String:
		return AIDebugErrorClassifier.CATEGORY_NAMES.get(category, "?")

	func to_dict() -> Dictionary:
		return {
			"category": category_name(),
			"line": line,
			"symbol": symbol,
			"needs_llm": needs_llm,
		}


# ============================================================
# SINIFLANDIRMA
# ============================================================

## Bir hata metnini sınıflandırır.
## error_text: Godot'un ürettiği ham hata satırı.
## Dönen: ErrorClass.
func classify(error_text: String) -> ErrorClass:
	var result := ErrorClass.new()
	result.raw_message = error_text
	var lower: String = error_text.to_lower()

	# --- Satır numarası çıkar (varsa) ---
	result.line = _extract_line(error_text)

	# --- Parse hatası — sözdizimi ---
	if lower.contains("parse error") or lower.contains("parse hata"):
		result.category = ErrorCategory.PARSE_ERROR
		result.symbol = _extract_quoted(error_text)
		return result

	# --- API hatası — yanlış metod/sınıf ---
	if lower.contains("invalid call") \
			or lower.contains("nonexistent function") \
			or lower.contains("function not found") \
			or lower.contains("cannot find") \
			or lower.contains("invalid get index"):
		result.category = ErrorCategory.API_ERROR
		result.symbol = _extract_quoted(error_text)
		return result

	# --- Null hatası ---
	if lower.contains("null instance") \
			or lower.contains("null nesneye") \
			or lower.contains("on a null") \
			or lower.contains("nil value"):
		result.category = ErrorCategory.NULL_ERROR
		return result

	# --- Tip hatası ---
	if lower.contains("type mismatch") \
			or lower.contains("cannot convert") \
			or lower.contains("expected argument") \
			or lower.contains("invalid type"):
		result.category = ErrorCategory.TYPE_ERROR
		result.symbol = _extract_quoted(error_text)
		return result

	# --- Genel çalışma hatası ---
	if lower.contains("error") or lower.contains("hata"):
		result.category = ErrorCategory.RUNTIME_ERROR
		# Genel runtime — LLM analizi faydalı
		result.needs_llm = true
		return result

	# --- Eşleşme yok — LLM gerekli ---
	result.category = ErrorCategory.UNKNOWN
	result.needs_llm = true
	return result


# ============================================================
# DAHİLİ — ayrıştırma
# ============================================================

## Hata metninden satır numarasını çıkarır. Bulunamazsa -1.
## Godot biçimi: "dosya.gd:42 - ..." veya "satır 42".
func _extract_line(text: String) -> int:
	# ":SAYI" örüntüsü ara
	var colon_idx: int = text.find(":")
	while colon_idx != -1 and colon_idx < text.length() - 1:
		var rest: String = text.substr(colon_idx + 1)
		var num: String = ""
		for ch in rest:
			if ch >= "0" and ch <= "9":
				num += ch
			else:
				break
		if not num.is_empty():
			return int(num)
		colon_idx = text.find(":", colon_idx + 1)
	return -1


## Hata metnindeki tırnak içi sembolü çıkarır.
## Godot iki tür tırnak kullanır: "dup" (çift) ve 'instance' (tek).
## İkisini de tanır — hangisi önce gelirse onu kullanır.
func _extract_quoted(text: String) -> String:
	var double_q: String = _extract_between(text, "\"")
	var single_q: String = _extract_between(text, "'")
	# Hangi tırnak metinde daha önce geçiyorsa onu tercih et
	var double_pos: int = text.find("\"")
	var single_pos: int = text.find("'")
	if double_pos == -1:
		return single_q
	if single_pos == -1:
		return double_q
	return double_q if double_pos < single_pos else single_q


## Belirli bir tırnak karakteri arasındaki metni çıkarır.
func _extract_between(text: String, quote: String) -> String:
	var first: int = text.find(quote)
	if first == -1:
		return ""
	var second: int = text.find(quote, first + 1)
	if second == -1:
		return ""
	return text.substr(first + 1, second - first - 1)
