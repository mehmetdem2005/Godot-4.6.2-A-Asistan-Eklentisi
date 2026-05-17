@tool
class_name AIDeleteBlockHandler
extends RefCounted

## DeleteBlockHandler — blok silme protokolü (Surgical Edit).
##
## Bir kod bloğunu güvenli siler. LLM "şu fonksiyonu sil" dediğinde,
## tüm dosyayı yeniden yazmak yerine sadece o bloğu çıkarır.
##
## İki silme yöntemi:
##   - Metin bloğu: başlangıç-bitiş metni verilir, arası silinir
##   - Satır aralığı: satır numaraları verilir
##
## Güvenlik: silinecek blok benzersiz olmalı; silme sonrası dosya
## hâlâ tutarlı görünmeli (kaba kontrol — boş kalmamalı).
##
## Mock policy: blok bulunamazsa/belirsizse sahte başarı yok — ret.

## Bir silme uygulamasının sonucu.
class DeleteResult extends RefCounted:
	var ok: bool = false
	var new_content: String = ""
	var rejected_reason: String = ""
	var deleted_lines: int = 0

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"rejected_reason": rejected_reason,
			"deleted_lines": deleted_lines,
		}


# ============================================================
# SİLME — metin bloğu
# ============================================================

## Bir metin bloğunu siler — verilen metin birebir + benzersiz olmalı.
## source: dosya içeriği. block_text: silinecek tam metin.
## Dönen: DeleteResult.
func delete_text_block(source: String, block_text: String) -> DeleteResult:
	var result := DeleteResult.new()

	if block_text.strip_edges().is_empty():
		result.rejected_reason = "Silinecek blok boş"
		return result

	var occurrences: int = _count_occurrences(source, block_text)
	if occurrences == 0:
		result.rejected_reason = "Silinecek blok dosyada bulunamadı"
		return result
	if occurrences > 1:
		result.rejected_reason = (
			"Blok %d kez geçiyor — belirsiz, daha fazla bağlam gerekli"
			% occurrences
		)
		return result

	var new_content: String = source.replace(block_text, "")
	# Silme sonrası tamamen boş kalmamalı
	if new_content.strip_edges().is_empty() and not source.strip_edges().is_empty():
		result.rejected_reason = (
			"Silme dosyayı tamamen boşaltır — tehlikeli, reddedildi"
		)
		return result

	# Arta kalan çift boş satırları temizle (kozmetik)
	new_content = _collapse_blank_runs(new_content)
	result.new_content = new_content
	result.ok = true
	result.deleted_lines = block_text.split("\n").size()
	return result


# ============================================================
# SİLME — satır aralığı
# ============================================================

## Bir satır aralığını siler (her ikisi dahil).
## source: içerik. start_line / end_line: 1-tabanlı, dahil.
## Dönen: DeleteResult.
func delete_line_range(
	source: String, start_line: int, end_line: int
) -> DeleteResult:
	var result := DeleteResult.new()
	var lines: PackedStringArray = source.split("\n")

	if start_line < 1 or end_line > lines.size():
		result.rejected_reason = "Satır aralığı dosya dışında"
		return result
	if start_line > end_line:
		result.rejected_reason = "Geçersiz aralık: başlangıç > bitiş"
		return result

	var out: PackedStringArray = PackedStringArray()
	for i in range(lines.size()):
		var line_no: int = i + 1
		if line_no >= start_line and line_no <= end_line:
			continue  # bu satır silinir
		out.append(lines[i])

	var new_content: String = "\n".join(out)
	if new_content.strip_edges().is_empty() and not source.strip_edges().is_empty():
		result.rejected_reason = "Silme dosyayı tamamen boşaltır — reddedildi"
		return result

	result.new_content = new_content
	result.ok = true
	result.deleted_lines = end_line - start_line + 1
	return result


# ============================================================
# DAHİLİ
# ============================================================

## Bir metnin başka metinde kaç kez geçtiğini sayar.
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


## Üç veya daha fazla ardışık boş satırı tek boş satıra indirir.
func _collapse_blank_runs(content: String) -> String:
	var lines: PackedStringArray = content.split("\n")
	var out: PackedStringArray = PackedStringArray()
	var blank_run: int = 0
	for line in lines:
		if line.strip_edges().is_empty():
			blank_run += 1
			if blank_run <= 2:
				out.append(line)
		else:
			blank_run = 0
			out.append(line)
	return "\n".join(out)


## LLM'e verilecek protokol talimatı.
static func protocol_instructions() -> String:
	return (
		"Kod silmek için silinecek tam bloğu ver. Blok dosyada birebir "
		+ "ve benzersiz olmalı. Sadece silinecek kısmı belirt — "
		+ "dosyanın geri kalanına dokunma."
	)
