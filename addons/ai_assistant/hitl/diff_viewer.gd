@tool
class_name AIDiffViewer
extends RefCounted

## DiffViewer — değişiklik görüntüleyici (Layer 8 / HITL).
##
## İnsan bir işlemi onaylayacaksa, NE değişeceğini görmeli. Bu sınıf
## "öncesi" ve "sonrası" içeriği alır, satır satır farkı çıkarır:
##   - eklenen satırlar (+)
##   - silinen satırlar (-)
##   - değişmeyen satırlar (bağlam)
##
## LCS (en uzun ortak alt dizi) tabanlı diff — gerçek bir fark
## algoritması, sadece "hepsi değişti" demez.
##
## Mock policy: diff gerçek içerik karşılaştırmasından üretilir.

## Satır değişiklik tipi.
enum LineKind { CONTEXT, ADDED, REMOVED }


## Diff'teki tek bir satır.
class DiffLine extends RefCounted:
	var kind: int = AIDiffViewer.LineKind.CONTEXT
	var text: String = ""
	var old_line_no: int = -1   ## Eski dosyadaki satır no (-1 = yok)
	var new_line_no: int = -1   ## Yeni dosyadaki satır no (-1 = yok)

	func prefix() -> String:
		match kind:
			AIDiffViewer.LineKind.ADDED:
				return "+"
			AIDiffViewer.LineKind.REMOVED:
				return "-"
			_:
				return " "

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"text": text,
			"old_line_no": old_line_no,
			"new_line_no": new_line_no,
		}


## Bir diff'in tam sonucu.
class DiffResult extends RefCounted:
	var lines: Array = []          ## DiffLine listesi
	var added_count: int = 0
	var removed_count: int = 0
	var is_new_file: bool = false  ## Öncesi boştu — tamamen yeni
	var is_deletion: bool = false  ## Sonrası boş — dosya siliniyor

	## Değişiklik var mı?
	func has_changes() -> bool:
		return added_count > 0 or removed_count > 0

	## İnsan-okunur özet.
	func summary() -> String:
		if is_new_file:
			return "Yeni dosya — %d satır" % added_count
		if is_deletion:
			return "Dosya siliniyor — %d satır" % removed_count
		if not has_changes():
			return "Değişiklik yok"
		return "+%d satır, -%d satır" % [added_count, removed_count]

	## Diff'i metin olarak biçimler — UI'da gösterilmeye hazır.
	func to_text() -> String:
		var out: PackedStringArray = PackedStringArray()
		for line in lines:
			out.append((line as DiffLine).prefix() + " " + (line as DiffLine).text)
		return "\n".join(out)


# ============================================================
# DIFF ÜRETİMİ
# ============================================================

## İki içerik arasındaki farkı hesaplar.
## old_content: değişiklik öncesi. new_content: sonrası.
## Dönen: DiffResult.
func compute_diff(old_content: String, new_content: String) -> DiffResult:
	var result := DiffResult.new()

	var old_empty: bool = old_content.strip_edges().is_empty()
	var new_empty: bool = new_content.strip_edges().is_empty()
	result.is_new_file = old_empty and not new_empty
	result.is_deletion = not old_empty and new_empty

	var old_lines: PackedStringArray = old_content.split("\n")
	var new_lines: PackedStringArray = new_content.split("\n")

	# LCS tablosu ile ortak alt dizi
	var lcs: Array = _lcs(old_lines, new_lines)
	result.lines = _build_diff_lines(old_lines, new_lines, lcs)

	for line in result.lines:
		match (line as DiffLine).kind:
			LineKind.ADDED:
				result.added_count += 1
			LineKind.REMOVED:
				result.removed_count += 1
	return result


## Bir AIActionSpec'in ne yapacağını diff olarak sunar.
## file_op: mevcut içeriği okumak için (varsa).
## new_content: işlemin yazacağı içerik.
## Dönen: DiffResult.
func preview_action(
	action: AIActionSpec, file_op: AISandboxedFileOp, new_content: String
) -> DiffResult:
	if action == null:
		return compute_diff("", "")
	# Hedef dosya varsa mevcut içeriği oku
	var old_content: String = ""
	if file_op != null and not action.target_path.is_empty():
		var read: Dictionary = file_op.read_file(action.target_path)
		if read.get("ok", false):
			old_content = read.get("content", "")
	return compute_diff(old_content, new_content)


# ============================================================
# LCS — en uzun ortak alt dizi
# ============================================================

## İki satır dizisinin LCS uzunluk tablosunu kurar, sonra ortak
## satırların indeks çiftlerini döndürür: [[old_idx, new_idx], ...].
func _lcs(old_lines: PackedStringArray, new_lines: PackedStringArray) -> Array:
	var m: int = old_lines.size()
	var n: int = new_lines.size()

	# DP tablosu (m+1) x (n+1)
	var dp: Array = []
	for i in range(m + 1):
		var row: Array = []
		row.resize(n + 1)
		row.fill(0)
		dp.append(row)

	for i in range(m - 1, -1, -1):
		for j in range(n - 1, -1, -1):
			if old_lines[i] == new_lines[j]:
				dp[i][j] = dp[i + 1][j + 1] + 1
			else:
				dp[i][j] = maxi(dp[i + 1][j], dp[i][j + 1])

	# Geri izleme — ortak satır çiftleri
	var pairs: Array = []
	var i: int = 0
	var j: int = 0
	while i < m and j < n:
		if old_lines[i] == new_lines[j]:
			pairs.append([i, j])
			i += 1
			j += 1
		elif dp[i + 1][j] >= dp[i][j + 1]:
			i += 1
		else:
			j += 1
	return pairs


## LCS çiftlerinden tam diff satır listesi kurar.
func _build_diff_lines(
	old_lines: PackedStringArray, new_lines: PackedStringArray, lcs: Array
) -> Array:
	var lines: Array = []
	var oi: int = 0
	var ni: int = 0

	for pair in lcs:
		var common_old: int = pair[0]
		var common_new: int = pair[1]
		# Ortak satırdan önceki silinenler (eski tarafta fazlalık)
		while oi < common_old:
			lines.append(_make_line(LineKind.REMOVED, old_lines[oi], oi + 1, -1))
			oi += 1
		# Ortak satırdan önceki eklenenler (yeni tarafta fazlalık)
		while ni < common_new:
			lines.append(_make_line(LineKind.ADDED, new_lines[ni], -1, ni + 1))
			ni += 1
		# Ortak (değişmeyen) satır
		lines.append(_make_line(
			LineKind.CONTEXT, old_lines[oi], oi + 1, ni + 1
		))
		oi += 1
		ni += 1

	# Kalan silinenler
	while oi < old_lines.size():
		lines.append(_make_line(LineKind.REMOVED, old_lines[oi], oi + 1, -1))
		oi += 1
	# Kalan eklenenler
	while ni < new_lines.size():
		lines.append(_make_line(LineKind.ADDED, new_lines[ni], -1, ni + 1))
		ni += 1
	return lines


## Tek bir DiffLine üretir.
func _make_line(kind: int, text: String, old_no: int, new_no: int) -> DiffLine:
	var line := DiffLine.new()
	line.kind = kind
	line.text = text
	line.old_line_no = old_no
	line.new_line_no = new_no
	return line
