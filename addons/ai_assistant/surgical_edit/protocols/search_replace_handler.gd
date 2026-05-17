@tool
class_name AISearchReplaceHandler
extends RefCounted

## SearchReplaceHandler — SEARCH/REPLACE protokol işleyicisi (Surgical Edit).
##
## Full-rewrite yerine LLM'in CERRAHI düzenleme yapması için protokol.
## Aider'ın savaş-test edilmiş formatı:
##
##   <<<<<<< SEARCH
##   (değiştirilecek tam metin — dosyada birebir var olmalı)
##   =======
##   (yeni metin)
##   >>>>>>> REPLACE
##
## LLM bu blokları üretir. Bu sınıf:
##   1. Blokları metinden ayrıştırır
##   2. SEARCH metninin dosyada BENZERSIZ olduğunu doğrular
##      (birden çok eşleşme = belirsiz = ret)
##   3. SEARCH'ü REPLACE ile değiştirir
##   4. Sonucu döndürür — başarı/ret + sebep
##
## Master plan: "Aider-style protocol + uniqueness check + AST validation".
##
## Mock policy: eşleşme bulunmazsa/belirsizse SAHTE başarı yok — ret.

## Protokol işaretçileri.
const SEARCH_MARKER: String = "<<<<<<< SEARCH"
const SEPARATOR: String = "======="
const REPLACE_MARKER: String = ">>>>>>> REPLACE"


## Tek bir SEARCH/REPLACE bloğu.
class EditBlock extends RefCounted:
	var search_text: String = ""
	var replace_text: String = ""

	## Bu blok bir silme mi (replace boş).
	func is_deletion() -> bool:
		return replace_text.is_empty()

	## Bu blok bir ekleme mi (search boş).
	func is_pure_insertion() -> bool:
		return search_text.is_empty()


## Bir düzenleme uygulamasının sonucu.
class ApplyResult extends RefCounted:
	var ok: bool = false
	var new_content: String = ""      ## Düzenlenmiş tam içerik
	var blocks_applied: int = 0
	var error: String = ""
	var rejected_reason: String = ""  ## Ret nedeni (varsa)

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"blocks_applied": blocks_applied,
			"error": error,
			"rejected_reason": rejected_reason,
		}


# ============================================================
# AYRIŞTIRMA — LLM çıktısından blok çıkar
# ============================================================

## LLM çıktısından SEARCH/REPLACE bloklarını ayrıştırır.
## Dönen: {ok: bool, blocks: Array[EditBlock], error: String}
func parse_blocks(llm_output: String) -> Dictionary:
	var blocks: Array = []
	var lines: PackedStringArray = llm_output.split("\n")

	var i: int = 0
	while i < lines.size():
		var line: String = lines[i].strip_edges()
		if line == SEARCH_MARKER:
			# Bir blok başladı — SEARCH metnini topla
			var block := EditBlock.new()
			var search_lines: PackedStringArray = PackedStringArray()
			var replace_lines: PackedStringArray = PackedStringArray()
			i += 1
			# SEPARATOR'a kadar SEARCH
			var found_sep: bool = false
			while i < lines.size():
				if lines[i].strip_edges() == SEPARATOR:
					found_sep = true
					i += 1
					break
				search_lines.append(lines[i])
				i += 1
			if not found_sep:
				return {
					"ok": false,
					"blocks": [],
					"error": "SEARCH bloğu kapatılmadı (======= eksik)",
				}
			# REPLACE_MARKER'a kadar REPLACE
			var found_end: bool = false
			while i < lines.size():
				if lines[i].strip_edges() == REPLACE_MARKER:
					found_end = true
					i += 1
					break
				replace_lines.append(lines[i])
				i += 1
			if not found_end:
				return {
					"ok": false,
					"blocks": [],
					"error": "REPLACE bloğu kapatılmadı (>>>>>>> REPLACE eksik)",
				}
			block.search_text = "\n".join(search_lines)
			block.replace_text = "\n".join(replace_lines)
			blocks.append(block)
		else:
			i += 1

	if blocks.is_empty():
		return {
			"ok": false,
			"blocks": [],
			"error": "Hiç SEARCH/REPLACE bloğu bulunamadı",
		}
	return {"ok": true, "blocks": blocks, "error": ""}


# ============================================================
# UYGULAMA — blokları kaynağa uygula
# ============================================================

## SEARCH/REPLACE bloklarını bir kaynağa uygular.
## source: orijinal dosya içeriği. blocks: EditBlock listesi.
## Dönen: ApplyResult.
##
## Her blok için: SEARCH metni dosyada TAM ve BENZERSIZ olmalı.
## Birden çok eşleşme -> belirsiz -> RET. Eşleşme yok -> RET.
func apply_blocks(source: String, blocks: Array) -> ApplyResult:
	var result := ApplyResult.new()
	var content: String = source

	for block in blocks:
		var edit: EditBlock = block

		# Saf ekleme (SEARCH boş) — bu protokolde desteklenmez
		# (INSERT_AT_ANCHOR protokolünün işi)
		if edit.is_pure_insertion():
			result.ok = false
			result.rejected_reason = (
				"Boş SEARCH — saf ekleme bu protokolde değil "
				+ "(INSERT_AT_ANCHOR kullanılmalı)"
			)
			return result

		# SEARCH metni dosyada kaç kez geçiyor
		var occurrences: int = _count_occurrences(content, edit.search_text)

		if occurrences == 0:
			result.ok = false
			result.rejected_reason = (
				"SEARCH metni dosyada bulunamadı — birebir eşleşmeli"
			)
			return result
		if occurrences > 1:
			result.ok = false
			result.rejected_reason = (
				"SEARCH metni %d kez geçiyor — belirsiz, daha fazla bağlam gerekli"
				% occurrences
			)
			return result

		# Tam bir eşleşme — değiştir
		content = content.replace(edit.search_text, edit.replace_text)
		result.blocks_applied += 1

	result.ok = true
	result.new_content = content
	return result


## LLM çıktısını tek adımda ayrıştırıp uygular.
## Dönen: ApplyResult.
func process(source: String, llm_output: String) -> ApplyResult:
	var parsed: Dictionary = parse_blocks(llm_output)
	if not parsed["ok"]:
		var result := ApplyResult.new()
		result.ok = false
		result.error = parsed["error"]
		result.rejected_reason = "Protokol ayrıştırma hatası"
		return result
	return apply_blocks(source, parsed["blocks"])


# ============================================================
# DAHİLİ
# ============================================================

## Bir metnin başka bir metinde kaç kez (örtüşmesiz) geçtiğini sayar.
func _count_occurrences(haystack: String, needle: String) -> int:
	if needle.is_empty():
		return 0
	var count: int = 0
	var from_idx: int = 0
	while true:
		var idx: int = haystack.find(needle, from_idx)
		if idx < 0:
			break
		count += 1
		from_idx = idx + needle.length()
	return count


# ============================================================
# FORMAT — LLM'e verilecek protokol talimatı
# ============================================================

## LLM'e verilecek protokol açıklaması — prompt'a eklenir.
## LLM bu formatta çıktı üretmeli.
static func protocol_instructions() -> String:
	return (
		"Düzenlemeyi SEARCH/REPLACE bloğu olarak ver. ASLA tüm dosyayı "
		+ "yeniden yazma. Format:\n"
		+ SEARCH_MARKER + "\n"
		+ "(değiştirilecek mevcut kod — dosyada BİREBİR var olmalı)\n"
		+ SEPARATOR + "\n"
		+ "(yeni kod)\n"
		+ REPLACE_MARKER + "\n"
		+ "SEARCH metni dosyada tam ve benzersiz olmalı. Birden çok "
		+ "değişiklik için birden çok blok kullan."
	)
