@tool
class_name AIInsertAtAnchorHandler
extends RefCounted

## InsertAtAnchorHandler — çapaya ekleme protokolü (Surgical Edit).
##
## SEARCH/REPLACE protokolü değiştirme yapar — saf EKLEME yapamaz
## (boş SEARCH belirsizdir). Bu protokol o boşluğu doldurur: bir
## "çapa" metni bulur, ekleme yapılacak kodu o çapanın ÖNCESİNE veya
## SONRASINA yerleştirir.
##
## Kullanım: "şu fonksiyondan sonra yeni bir fonksiyon ekle",
## "şu satırın üstüne bir kontrol ekle".
##
## Çapa benzersiz olmalı — birden çok eşleşme = belirsiz = ret.
## Mevcut kod değişmez, sadece yeni içerik araya girer.
##
## Mock policy: çapa bulunamazsa/belirsizse sahte başarı yok — ret.

## Ekleme konumu.
enum InsertPosition { BEFORE_ANCHOR, AFTER_ANCHOR }

const POSITION_NAMES: Dictionary = {
	InsertPosition.BEFORE_ANCHOR: "before",
	InsertPosition.AFTER_ANCHOR: "after",
}


## Bir ekleme uygulamasının sonucu.
class InsertResult extends RefCounted:
	var ok: bool = false
	var new_content: String = ""
	var rejected_reason: String = ""
	var inserted_lines: int = 0

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"rejected_reason": rejected_reason,
			"inserted_lines": inserted_lines,
		}


# ============================================================
# EKLEME UYGULAMA
# ============================================================

## Bir çapanın önüne/arkasına içerik ekler.
## source: dosya içeriği. anchor: çapa metni (birebir + benzersiz).
## new_code: eklenecek kod. position: BEFORE/AFTER.
## Dönen: InsertResult.
func apply(
	source: String, anchor: String, new_code: String, position: int
) -> InsertResult:
	var result := InsertResult.new()

	if anchor.strip_edges().is_empty():
		result.rejected_reason = "Çapa metni boş — ekleme konumu belirsiz"
		return result
	if new_code.is_empty():
		result.rejected_reason = "Eklenecek içerik boş"
		return result

	# Çapa kaç kez geçiyor — benzersiz olmalı
	var occurrences: int = _count_occurrences(source, anchor)
	if occurrences == 0:
		result.rejected_reason = "Çapa metni dosyada bulunamadı"
		return result
	if occurrences > 1:
		result.rejected_reason = (
			"Çapa metni %d kez geçiyor — belirsiz, daha fazla bağlam gerekli"
			% occurrences
		)
		return result

	# Çapanın konumunu bul
	var anchor_index: int = source.find(anchor)
	var insert_at: int = anchor_index
	if position == InsertPosition.AFTER_ANCHOR:
		insert_at = anchor_index + anchor.length()

	# İçeriği araya yerleştir — uygun newline ile
	var before: String = source.substr(0, insert_at)
	var after: String = source.substr(insert_at)
	var glue_before: String = ""
	var glue_after: String = ""
	if position == InsertPosition.AFTER_ANCHOR:
		if not before.ends_with("\n"):
			glue_before = "\n"
		if not after.begins_with("\n"):
			glue_after = "\n"
	else:
		if not before.ends_with("\n") and not before.is_empty():
			glue_before = "\n"
		if not new_code.ends_with("\n"):
			glue_after = "\n"

	result.new_content = before + glue_before + new_code + glue_after + after
	result.ok = true
	result.inserted_lines = new_code.split("\n").size()
	return result


## Çapa yerine bir satır numarasına ekler.
## source: içerik. line_number: kaçıncı satır (1-tabanlı).
## new_code: eklenecek. position: o satırın önü/arkası.
func apply_at_line(
	source: String, line_number: int, new_code: String, position: int
) -> InsertResult:
	var result := InsertResult.new()
	var lines: PackedStringArray = source.split("\n")

	if line_number < 1 or line_number > lines.size():
		result.rejected_reason = "Satır numarası dosya dışında: %d" % line_number
		return result
	if new_code.is_empty():
		result.rejected_reason = "Eklenecek içerik boş"
		return result

	var idx: int = line_number - 1
	var out: PackedStringArray = PackedStringArray()
	for i in range(lines.size()):
		if i == idx and position == InsertPosition.BEFORE_ANCHOR:
			out.append(new_code)
		out.append(lines[i])
		if i == idx and position == InsertPosition.AFTER_ANCHOR:
			out.append(new_code)

	result.new_content = "\n".join(out)
	result.ok = true
	result.inserted_lines = new_code.split("\n").size()
	return result


# ============================================================
# DAHİLİ
# ============================================================

## Bir metnin başka bir metinde kaç kez geçtiğini sayar.
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


## LLM'e verilecek protokol talimatı.
static func protocol_instructions() -> String:
	return (
		"Saf ekleme için çapa belirt. Format:\n"
		+ "ANCHOR: (dosyada birebir ve benzersiz bir metin)\n"
		+ "POSITION: before | after\n"
		+ "CONTENT: (eklenecek kod)\n"
		+ "Mevcut kod değişmez, yeni içerik çapanın yanına eklenir."
	)
