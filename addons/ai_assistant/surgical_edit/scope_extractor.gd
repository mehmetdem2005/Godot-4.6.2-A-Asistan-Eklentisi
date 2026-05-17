@tool
class_name AIScopeExtractor
extends RefCounted

## ScopeExtractor — kapsam penceresi çıkarıcı (Surgical Edit).
##
## Full-rewrite'ı önlemenin KALBİ burası. LLM'e tüm dosyayı verirsen,
## doğal olarak tüm dosyayı yeniden yazar. Çözüm: LLM'e SADECE düzenlenecek
## kısmı + biraz bağlam ver. LLM gördüğü kadarını değiştirir.
##
## Bu sınıf bir GDScript dosyasından "kapsam penceresi" çıkarır:
##   - Hedef fonksiyon/sınıf nerede başlıyor-bitiyor (girinti analizi)
##   - Onun etrafına N satır bağlam ekle
##   - Sadece bu pencereyi döndür — asla tüm dosyayı
##
## Master plan: "Function-scope: hedef fonksiyon + 20 satır context;
## full file dönmez".
##
## Mock policy: kapsam gerçek kaynak analizinden çıkar.

## Çıkarılmış bir kapsam penceresi.
class ScopeWindow extends RefCounted:
	var found: bool = false           ## Hedef bulundu mu
	var content: String = ""          ## Pencere içeriği (LLM'e verilecek)
	var start_line: int = -1          ## Dosyadaki başlangıç satırı (1-tabanlı)
	var end_line: int = -1            ## Dosyadaki bitiş satırı
	var target_start_line: int = -1   ## Asıl hedefin başı (bağlam hariç)
	var target_end_line: int = -1     ## Asıl hedefin sonu
	var is_full_file: bool = false    ## UYARI: tüm dosya döndü mü
	var reason: String = ""

	## Pencere kaç satır.
	func line_count() -> int:
		if start_line < 0 or end_line < 0:
			return 0
		return end_line - start_line + 1

	func to_dict() -> Dictionary:
		return {
			"found": found,
			"start_line": start_line,
			"end_line": end_line,
			"target_start_line": target_start_line,
			"target_end_line": target_end_line,
			"line_count": line_count(),
			"is_full_file": is_full_file,
			"reason": reason,
		}


## Hedef etrafında verilecek varsayılan bağlam satırı sayısı.
const DEFAULT_CONTEXT_LINES: int = 20

## Bir pencere bu satır sayısını aşarsa uyarı — fazla geniş.
const MAX_REASONABLE_WINDOW: int = 120


# ============================================================
# FONKSİYON KAPSAMI ÇIKARMA
# ============================================================

## Belirli bir fonksiyonun kapsam penceresini çıkarır.
## source: tüm dosya içeriği. function_name: hedef fonksiyon.
## context_lines: hedef etrafına eklenecek bağlam.
## Dönen: ScopeWindow.
func extract_function_scope(
	source: String, function_name: String,
	context_lines: int = DEFAULT_CONTEXT_LINES
) -> ScopeWindow:
	var window := ScopeWindow.new()
	var lines: PackedStringArray = source.split("\n")

	# Fonksiyon tanımının satırını bul
	var func_line: int = _find_function_line(lines, function_name)
	if func_line < 0:
		window.found = false
		window.reason = "Fonksiyon bulunamadı: %s" % function_name
		return window

	# Fonksiyonun bittiği satırı bul (girinti analizi)
	var func_end: int = _find_block_end(lines, func_line)

	window.found = true
	window.target_start_line = func_line + 1   # 1-tabanlı
	window.target_end_line = func_end + 1

	# Bağlam ekle — sınırları taşırma
	var win_start: int = maxi(0, func_line - context_lines)
	var win_end: int = mini(lines.size() - 1, func_end + context_lines)
	window.start_line = win_start + 1
	window.end_line = win_end + 1

	# Pencere içeriğini topla
	var window_lines: PackedStringArray = PackedStringArray()
	for i in range(win_start, win_end + 1):
		window_lines.append(lines[i])
	window.content = "\n".join(window_lines)

	# Tüm dosya mı döndü — bu istenmeyen durum
	window.is_full_file = (win_start == 0 and win_end == lines.size() - 1)
	if window.is_full_file:
		window.reason = "UYARI: pencere tüm dosyayı kapsıyor (dosya küçük)"
	elif window.line_count() > MAX_REASONABLE_WINDOW:
		window.reason = "UYARI: pencere geniş (%d satır)" % window.line_count()
	else:
		window.reason = "Fonksiyon kapsamı çıkarıldı (%d satır)" % window.line_count()
	return window


## Belirli bir satır aralığının kapsam penceresini çıkarır.
## Bug-at-line tipi düzenlemeler için — satır numarası verilmiş.
func extract_line_scope(
	source: String, target_line: int,
	context_lines: int = DEFAULT_CONTEXT_LINES
) -> ScopeWindow:
	var window := ScopeWindow.new()
	var lines: PackedStringArray = source.split("\n")

	if target_line < 1 or target_line > lines.size():
		window.found = false
		window.reason = "Satır numarası dosya dışında: %d" % target_line
		return window

	var idx: int = target_line - 1
	window.found = true
	window.target_start_line = target_line
	window.target_end_line = target_line

	var win_start: int = maxi(0, idx - context_lines)
	var win_end: int = mini(lines.size() - 1, idx + context_lines)
	window.start_line = win_start + 1
	window.end_line = win_end + 1

	var window_lines: PackedStringArray = PackedStringArray()
	for i in range(win_start, win_end + 1):
		window_lines.append(lines[i])
	window.content = "\n".join(window_lines)

	window.is_full_file = (win_start == 0 and win_end == lines.size() - 1)
	window.reason = "Satır kapsamı çıkarıldı (%d satır)" % window.line_count()
	return window


# ============================================================
# DAHİLİ — yapısal analiz
# ============================================================

## Bir fonksiyon tanımının satır indeksini bulur. Bulunamazsa -1.
func _find_function_line(lines: PackedStringArray, function_name: String) -> int:
	for i in range(lines.size()):
		var stripped: String = lines[i].strip_edges()
		# "func ad(" veya "static func ad("
		var without_static: String = stripped
		if without_static.begins_with("static "):
			without_static = without_static.substr(7).strip_edges()
		if without_static.begins_with("func "):
			var after: String = without_static.substr(5).strip_edges()
			var paren: int = after.find("(")
			if paren > 0:
				var name: String = after.substr(0, paren).strip_edges()
				if name == function_name:
					return i
	return -1


## Bir bloğun (fonksiyon vb.) bittiği satır indeksini bulur.
## Girinti analizi: blok başlangıcının girintisinden daha derin
## satırlar bloğa aittir; girinti geri düşünce blok biter.
func _find_block_end(lines: PackedStringArray, block_start: int) -> int:
	if block_start >= lines.size():
		return block_start
	var base_indent: int = _indent_depth(lines[block_start])

	var last_content_line: int = block_start
	for i in range(block_start + 1, lines.size()):
		var line: String = lines[i]
		var stripped: String = line.strip_edges()
		# Boş satır / yorum — blok sınırı belirlemez, atla
		if stripped.is_empty():
			continue
		var indent: int = _indent_depth(line)
		# Girinti base'e eşit veya daha az — blok bitti
		if indent <= base_indent:
			return last_content_line
		last_content_line = i
	# Dosya sonuna kadar blok devam etti
	return last_content_line


## Bir satırın girinti derinliği (tab sayısı).
func _indent_depth(line: String) -> int:
	var depth: int = 0
	for ch in line:
		if ch == "\t":
			depth += 1
		else:
			break
	return depth


## Bir kaynağın tek bir fonksiyondan mı ibaret olduğunu kontrol eder.
## Çok kısa dosyalarda kapsam = tüm dosya olabilir; bu bilgilendirme için.
func is_source_small(source: String, threshold: int = 40) -> bool:
	return source.split("\n").size() <= threshold
