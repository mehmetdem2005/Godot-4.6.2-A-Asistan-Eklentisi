@tool
class_name AIOutputParser
extends RefCounted

## OutputParser — rol çıktısı ayrıştırıcı (Layer 9 / Pilot Cell zekâsı).
##
## Ajan beyni LLM'den ham metin döndürür. Ama pipeline'ın akması için
## o metin YAPILANDIRILMIŞ veri olmalı: DeliveryManager'ın çıktısı bir
## task listesi, CodeEngineer'ınki bir kod bloğu olmalı ki bir sonraki
## ajan onu kullanabilsin.
##
## Bu sınıf her rol grubunun ham çıktısını ayrıştırır:
##   - Plan rolleri (PM, Architect): madde listesi
##   - DeliveryManager: numaralı task listesi
##   - Kod rolleri: SEARCH/REPLACE bloğu veya kod
##   - Denetim rolleri (QA, Reviewer): PASS/FAIL + bulgular
##
## ÖNEMLİ — savunmacı ayrıştırma:
##   LLM her zaman temiz format döndürmez. Parser çıkarabildiğini
##   çıkarır; çıkaramazsa ham metni korur ve "yapılandırılamadı"
##   işaretler. ASLA veri uydurmaz — boş/belirsiz çıktıyı dürüstçe
##   raporlar.
##
## Mock policy: ayrıştırma gerçek metinden yapılır; eksik bilgi
## uydurulmaz.

## Ayrıştırma sonucu tipi.
enum ParsedKind { PLAN_ITEMS, TASK_LIST, CODE_EDIT, REVIEW, RAW_TEXT }

const PARSED_KIND_NAMES: Dictionary = {
	ParsedKind.PLAN_ITEMS: "plan_items",
	ParsedKind.TASK_LIST: "task_list",
	ParsedKind.CODE_EDIT: "code_edit",
	ParsedKind.REVIEW: "review",
	ParsedKind.RAW_TEXT: "raw_text",
}


## Ayrıştırılmış bir rol çıktısı.
class ParsedOutput extends RefCounted:
	var kind: int = AIOutputParser.ParsedKind.RAW_TEXT
	var structured: bool = false       ## Yapılandırma başarılı mı
	var items: Array = []              ## Çıkarılan maddeler/tasklar
	var raw_text: String = ""          ## Her zaman korunur — ham metin
	var verdict: String = ""           ## REVIEW için: "pass" | "fail" | ""
	var note: String = ""              ## Ayrıştırma durumu

	func to_dict() -> Dictionary:
		return {
			"kind": AIOutputParser.PARSED_KIND_NAMES.get(kind, "?"),
			"structured": structured,
			"item_count": items.size(),
			"verdict": verdict,
			"note": note,
		}


# ============================================================
# ANA AYRIŞTIRMA — role göre yönlendirir
# ============================================================

## Bir rolün ham LLM çıktısını ayrıştırır.
## role: AICellRoles.Role. content: ham LLM metni.
## Dönen: ParsedOutput.
func parse(role: int, content: String) -> ParsedOutput:
	var result := ParsedOutput.new()
	result.raw_text = content

	if content.strip_edges().is_empty():
		result.kind = ParsedKind.RAW_TEXT
		result.structured = false
		result.note = "Boş çıktı — ayrıştırılacak içerik yok"
		return result

	# Role göre uygun ayrıştırıcıya yönlendir
	if AICellRoles.is_code_generating(role):
		return _parse_code_edit(content)
	match role:
		AICellRoles.Role.DELIVERY_MANAGER:
			return _parse_task_list(content)
		AICellRoles.Role.PRODUCT_MANAGER, AICellRoles.Role.ARCHITECT:
			return _parse_plan_items(content)
		AICellRoles.Role.QA_ENGINEER, AICellRoles.Role.REVIEWER:
			return _parse_review(content)
		_:
			# Diğer roller — ham metin korunur
			result.kind = ParsedKind.RAW_TEXT
			result.structured = true
			result.note = "Serbest metin çıktısı"
			return result


# ============================================================
# PLAN MADDELERİ — PM, Architect
# ============================================================

## Madde listesi ayrıştırır. "- ", "* ", "• " veya "1. " başlangıçlı
## satırları madde olarak alır.
func _parse_plan_items(content: String) -> ParsedOutput:
	var result := ParsedOutput.new()
	result.kind = ParsedKind.PLAN_ITEMS
	result.raw_text = content

	var items: Array = _extract_list_items(content)
	result.items = items
	result.structured = items.size() > 0
	if result.structured:
		result.note = "%d plan maddesi çıkarıldı" % items.size()
	else:
		result.note = "Madde listesi bulunamadı — ham metin korundu"
	return result


# ============================================================
# TASK LİSTESİ — DeliveryManager
# ============================================================

## Numaralı task listesi ayrıştırır. Her task bir sözlük:
## {index, text}.
func _parse_task_list(content: String) -> ParsedOutput:
	var result := ParsedOutput.new()
	result.kind = ParsedKind.TASK_LIST
	result.raw_text = content

	var raw_items: Array = _extract_list_items(content)
	var tasks: Array = []
	for i in range(raw_items.size()):
		tasks.append({
			"index": i + 1,
			"text": raw_items[i],
		})
	result.items = tasks
	result.structured = tasks.size() > 0
	if result.structured:
		result.note = "%d task çıkarıldı" % tasks.size()
	else:
		result.note = "Task listesi bulunamadı — ham metin korundu"
	return result


# ============================================================
# KOD DÜZENLEME — Code/Scene/Shader/Asset Engineer
# ============================================================

## Kod çıktısı ayrıştırır. SEARCH/REPLACE bloğu varsa onu işaretler;
## yoksa kod bloğu (``` çitleri) arar; o da yoksa ham metin.
func _parse_code_edit(content: String) -> ParsedOutput:
	var result := ParsedOutput.new()
	result.kind = ParsedKind.CODE_EDIT
	result.raw_text = content

	# SEARCH/REPLACE protokolü var mı (Surgical Edit formatı)
	if content.contains("<<<<<<< SEARCH") and content.contains(">>>>>>> REPLACE"):
		result.structured = true
		result.items = [{"type": "search_replace", "content": content}]
		result.note = "SEARCH/REPLACE bloğu tespit edildi"
		return result

	# Markdown kod bloğu var mı
	var code: String = _extract_code_fence(content)
	if not code.is_empty():
		result.structured = true
		result.items = [{"type": "code_block", "content": code}]
		result.note = "Kod bloğu çıkarıldı"
		return result

	# Yapılandırılmış format yok — ham metin korunur, uydurma yok
	result.structured = false
	result.note = "Yapılandırılmış kod formatı yok — ham metin korundu"
	return result


# ============================================================
# İNCELEME — QA, Reviewer
# ============================================================

## İnceleme çıktısı ayrıştırır. PASS/FAIL kararı + bulgu maddeleri.
func _parse_review(content: String) -> ParsedOutput:
	var result := ParsedOutput.new()
	result.kind = ParsedKind.REVIEW
	result.raw_text = content

	# Karar — PASS / FAIL ara (büyük/küçük harf duyarsız)
	var lowered: String = content.to_lower()
	# "fail" önce kontrol — "pass" içeren metinde fail varsa fail kazanır
	if lowered.contains("fail") or lowered.contains("başarısız") \
			or lowered.contains("reddedil"):
		result.verdict = "fail"
	elif lowered.contains("pass") or lowered.contains("başarılı") \
			or lowered.contains("onaylan") or lowered.contains("geçti"):
		result.verdict = "pass"
	else:
		result.verdict = ""

	# Bulgular — madde listesi
	result.items = _extract_list_items(content)
	result.structured = not result.verdict.is_empty()
	if result.structured:
		result.note = "İnceleme kararı: %s, %d bulgu" % [
			result.verdict, result.items.size()
		]
	else:
		result.note = "Net PASS/FAIL kararı bulunamadı"
	return result


# ============================================================
# DAHİLİ — metin ayrıştırma yardımcıları
# ============================================================

## Bir metinden liste maddelerini çıkarır.
## "- ", "* ", "• " ile başlayan veya "1. " / "2) " numaralı satırlar.
func _extract_list_items(content: String) -> Array:
	var items: Array = []
	for line in content.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.is_empty():
			continue
		var item_text: String = _strip_list_marker(stripped)
		if not item_text.is_empty() and item_text != stripped:
			# İşaretçi bulundu ve kaldırıldı — geçerli madde
			items.append(item_text)
	return items


## Bir satırın başındaki liste işaretçisini kaldırır.
## İşaretçi yoksa satırı değiştirmeden döndürür.
func _strip_list_marker(line: String) -> String:
	# Madde işaretleri: - * •
	for marker in ["- ", "* ", "• "]:
		if line.begins_with(marker):
			return line.substr(marker.length()).strip_edges()
	# Numaralı: "1. ", "2) ", "10. " vb.
	var dot: int = line.find(". ")
	var paren: int = line.find(") ")
	var sep: int = -1
	if dot >= 0 and (paren < 0 or dot < paren):
		sep = dot
	elif paren >= 0:
		sep = paren
	if sep > 0 and sep <= 3:
		# Başında sayı mı
		var prefix: String = line.substr(0, sep)
		if prefix.is_valid_int():
			return line.substr(sep + 2).strip_edges()
	return line


## Markdown kod çitleri (```) arasındaki içeriği çıkarır.
## Çit yoksa boş string.
func _extract_code_fence(content: String) -> String:
	var fence: String = "```"
	var first: int = content.find(fence)
	if first < 0:
		return ""
	# İlk çitten sonraki satır sonuna kadar (dil etiketi) atla
	var content_start: int = content.find("\n", first)
	if content_start < 0:
		return ""
	content_start += 1
	var second: int = content.find(fence, content_start)
	if second < 0:
		return ""
	return content.substr(content_start, second - content_start).strip_edges()
