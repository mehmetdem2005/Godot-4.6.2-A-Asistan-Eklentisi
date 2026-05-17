@tool
class_name AIProjectWideRenameHandler
extends RefCounted

## ProjectWideRenameHandler — sembol yeniden adlandırma (Surgical Edit).
##
## Bir sembolü (değişken, fonksiyon, sınıf adı) yeniden adlandırmak
## tehlikelidir: aynı isim başka yerlerde de geçebilir, yanlış
## eşleşme kod kırar. Bu protokol KELİME-SINIRI duyarlı yeniden
## adlandırma yapar — "health" ararken "healthbar"ı eşleştirmez.
##
## Tek dosyada veya birden çok dosyada çalışır. Her dosyada kaç
## değişiklik yapıldığını raporlar.
##
## Mock policy: eşleşme yoksa açıkça raporlanır; kısmi/belirsiz
## eşleşme uydurulmaz.

## Bir yeniden adlandırma sonucu (tek dosya).
class RenameResult extends RefCounted:
	var ok: bool = false
	var new_content: String = ""
	var replacements: int = 0          ## Kaç eşleşme değiştirildi
	var rejected_reason: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"replacements": replacements,
			"rejected_reason": rejected_reason,
		}


## Kimlik (identifier) karakteri sayılan karakterler.
## Bunlardan biri sembolün yanındaysa, kelime sınırı DEĞİLDİR.
const IDENT_CHARS: String = (
	"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
)


# ============================================================
# YENİDEN ADLANDIRMA — tek dosya
# ============================================================

## Bir dosyada bir sembolü yeniden adlandırır.
## source: dosya içeriği. old_name: eski sembol. new_name: yeni.
## Dönen: RenameResult.
##
## Kelime-sınırı duyarlı: "health" -> "hp" yaparken "healthbar"
## değişmez ("health" + "bar" bitişik, kelime değil).
func rename_in_source(
	source: String, old_name: String, new_name: String
) -> RenameResult:
	var result := RenameResult.new()

	if old_name.is_empty():
		result.rejected_reason = "Eski sembol adı boş"
		return result
	if new_name.is_empty():
		result.rejected_reason = "Yeni sembol adı boş"
		return result
	if old_name == new_name:
		result.rejected_reason = "Eski ve yeni ad aynı — değişiklik yok"
		return result
	if not _is_valid_identifier(new_name):
		result.rejected_reason = "Yeni ad geçerli bir kimlik değil: " + new_name
		return result

	# Kelime-sınırı duyarlı değiştir
	var output: String = ""
	var i: int = 0
	var count: int = 0
	while i < source.length():
		var match_idx: int = source.find(old_name, i)
		if match_idx < 0:
			output += source.substr(i)
			break
		# Eşleşmeden önceki kısmı ekle
		output += source.substr(i, match_idx - i)
		# Kelime sınırı kontrolü — eşleşmenin iki yanı
		var before_ok: bool = match_idx == 0 or not _is_ident_char(
			source[match_idx - 1]
		)
		var after_pos: int = match_idx + old_name.length()
		var after_ok: bool = after_pos >= source.length() or not _is_ident_char(
			source[after_pos]
		)
		if before_ok and after_ok:
			# Gerçek bir sembol eşleşmesi — değiştir
			output += new_name
			count += 1
		else:
			# Bitişik kimlik parçası — değiştirme
			output += old_name
		i = after_pos

	if count == 0:
		result.rejected_reason = (
			"Sembol bulunamadı (kelime olarak): " + old_name
		)
		return result

	result.new_content = output
	result.replacements = count
	result.ok = true
	return result


# ============================================================
# YENİDEN ADLANDIRMA — çok dosya
# ============================================================

## Birden çok dosyada bir sembolü yeniden adlandırır.
## files: {dosya_yolu: içerik}. old_name / new_name: sembol.
## Dönen: {
##   ok: bool,
##   total_replacements: int,
##   per_file: {yol: replacement_sayısı},
##   updated: {yol: yeni_içerik}
## }
func rename_across_files(
	files: Dictionary, old_name: String, new_name: String
) -> Dictionary:
	var per_file: Dictionary = {}
	var updated: Dictionary = {}
	var total: int = 0

	for path in files:
		var content: String = files[path]
		var single: RenameResult = rename_in_source(
			content, old_name, new_name
		)
		if single.ok:
			per_file[path] = single.replacements
			updated[path] = single.new_content
			total += single.replacements

	return {
		"ok": total > 0,
		"total_replacements": total,
		"per_file": per_file,
		"updated": updated,
	}


# ============================================================
# DAHİLİ
# ============================================================

## Bir karakter kimlik karakteri mi (harf, rakam, _)?
func _is_ident_char(ch: String) -> bool:
	return IDENT_CHARS.contains(ch)


## Bir metin geçerli bir kimlik mi (harf/_ ile başlar)?
func _is_valid_identifier(name: String) -> bool:
	if name.is_empty():
		return false
	var first: String = name[0]
	if not (first == "_" or first.to_lower() != first.to_upper()):
		return false
	for ch in name:
		if not _is_ident_char(ch):
			return false
	return true


## LLM'e verilecek protokol talimatı.
static func protocol_instructions() -> String:
	return (
		"Sembol yeniden adlandırmak için eski ve yeni adı ver. "
		+ "Yeniden adlandırma kelime-sınırı duyarlıdır — sadece tam "
		+ "sembol eşleşmeleri değişir, bitişik kelimeler korunur."
	)
