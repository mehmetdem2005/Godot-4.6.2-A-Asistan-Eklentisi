@tool
class_name AIFormatDriftDetector
extends RefCounted

## FormatDriftDetector — format kayması dedektörü (Surgical Edit).
##
## LLM bir düzenleme yaptığında, istenmeyen yan etkiler olabilir:
##   - Girinti tab'dan boşluğa kayar (veya tersi)
##   - Yorumlar sessizce silinir
##   - Boş satırlar yok olur / eklenir
##   - Dosya sonu newline değişir
##
## Bu sınıf "öncesi" ve "sonrası" içeriği karşılaştırır, bu kaymaları
## tespit eder. Master plan'ın 6 post-edit validation check'inden biri.
##
## Önemli: bu dedektör DEĞİŞİKLİK BEKLENEN bölgeyle DEĞİŞMEMESİ GEREKEN
## bölgeyi ayırt edemez tek başına — ama genel "kötüye gidiş" sinyalleri
## verir. scope_creep_detector ile birlikte tam tablo oluşur.
##
## Mock policy: kayma gerçek metin karşılaştırmasından gelir.

## Tespit edilen kayma tipi.
enum DriftKind { INDENT_STYLE, COMMENT_LOSS, BLANK_LINE_CHANGE, EOF_NEWLINE }

const DRIFT_KIND_NAMES: Dictionary = {
	DriftKind.INDENT_STYLE: "indent_style",
	DriftKind.COMMENT_LOSS: "comment_loss",
	DriftKind.BLANK_LINE_CHANGE: "blank_line_change",
	DriftKind.EOF_NEWLINE: "eof_newline",
}


## Format kayması analiz sonucu.
class DriftReport extends RefCounted:
	var has_drift: bool = false
	var findings: Array = []           ## [{kind, severity, detail}]
	var comment_count_before: int = 0
	var comment_count_after: int = 0

	## En yüksek önem derecesi ("none"/"warning"/"error").
	func max_severity() -> String:
		var has_error: bool = false
		var has_warning: bool = false
		for f in findings:
			if f["severity"] == "error":
				has_error = true
			elif f["severity"] == "warning":
				has_warning = true
		if has_error:
			return "error"
		if has_warning:
			return "warning"
		return "none"

	func to_dict() -> Dictionary:
		return {
			"has_drift": has_drift,
			"findings": findings,
			"max_severity": max_severity(),
			"comment_before": comment_count_before,
			"comment_after": comment_count_after,
		}


# ============================================================
# TESPİT
# ============================================================

## Öncesi ve sonrası içeriği karşılaştırır, format kaymalarını bulur.
## before: düzenleme öncesi. after: düzenleme sonrası.
## Dönen: DriftReport.
func detect(before: String, after: String) -> DriftReport:
	var report := DriftReport.new()

	# --- 1. Girinti stili kayması ---
	_check_indent_style(before, after, report)

	# --- 2. Yorum kaybı ---
	_check_comment_loss(before, after, report)

	# --- 3. Boş satır değişimi ---
	_check_blank_lines(before, after, report)

	# --- 4. Dosya sonu newline ---
	_check_eof_newline(before, after, report)

	report.has_drift = not report.findings.is_empty()
	return report


## Girinti stili kaymasını kontrol eder — tab'dan boşluğa geçiş vb.
func _check_indent_style(before: String, after: String, report: DriftReport) -> void:
	var before_uses_tab: bool = _uses_tab_indent(before)
	var after_uses_tab: bool = _uses_tab_indent(after)
	var before_uses_space: bool = _uses_space_indent(before)
	var after_uses_space: bool = _uses_space_indent(after)

	# Öncesi tab idi, sonrası boşluk getirdi — kayma
	if before_uses_tab and after_uses_space and not before_uses_space:
		report.findings.append({
			"kind": DRIFT_KIND_NAMES[DriftKind.INDENT_STYLE],
			"severity": "error",
			"detail": "Girinti tab'dan boşluğa kaydı (GDScript tab kullanır)",
		})
	# Sonrası hiç tab kullanmıyor ama öncesi kullanıyordu
	elif before_uses_tab and not after_uses_tab and not after.strip_edges().is_empty():
		report.findings.append({
			"kind": DRIFT_KIND_NAMES[DriftKind.INDENT_STYLE],
			"severity": "warning",
			"detail": "Sonuçta tab girinti kalmadı — kayma olabilir",
		})


## Yorum kaybını kontrol eder.
func _check_comment_loss(before: String, after: String, report: DriftReport) -> void:
	var before_comments: int = _count_comment_lines(before)
	var after_comments: int = _count_comment_lines(after)
	report.comment_count_before = before_comments
	report.comment_count_after = after_comments

	if after_comments < before_comments:
		var lost: int = before_comments - after_comments
		report.findings.append({
			"kind": DRIFT_KIND_NAMES[DriftKind.COMMENT_LOSS],
			"severity": "warning",
			"detail": "%d yorum satırı kayboldu" % lost,
		})


## Boş satır sayısı değişimini kontrol eder.
func _check_blank_lines(before: String, after: String, report: DriftReport) -> void:
	var before_blanks: int = _count_blank_lines(before)
	var after_blanks: int = _count_blank_lines(after)
	var diff: int = absi(after_blanks - before_blanks)
	# Küçük fark normal — büyük fark dikkat çeker
	if diff >= 5:
		report.findings.append({
			"kind": DRIFT_KIND_NAMES[DriftKind.BLANK_LINE_CHANGE],
			"severity": "warning",
			"detail": "Boş satır sayısı %d değişti" % diff,
		})


## Dosya sonu newline değişimini kontrol eder.
func _check_eof_newline(before: String, after: String, report: DriftReport) -> void:
	var before_eof: bool = before.ends_with("\n")
	var after_eof: bool = after.ends_with("\n")
	if before_eof and not after_eof:
		report.findings.append({
			"kind": DRIFT_KIND_NAMES[DriftKind.EOF_NEWLINE],
			"severity": "warning",
			"detail": "Dosya sonu newline kayboldu",
		})


# ============================================================
# DAHİLİ — sayım yardımcıları
# ============================================================

## İçerikte tab-girintili satır var mı?
func _uses_tab_indent(content: String) -> bool:
	for line in content.split("\n"):
		if line.begins_with("\t"):
			return true
	return false


## İçerikte boşluk-girintili satır var mı? (kod satırı — boş değil)
func _uses_space_indent(content: String) -> bool:
	for line in content.split("\n"):
		if line.begins_with(" ") and not line.strip_edges().is_empty():
			return true
	return false


## Yorum satırı sayısı (sadece # ile başlayanlar).
func _count_comment_lines(content: String) -> int:
	var count: int = 0
	for line in content.split("\n"):
		if line.strip_edges().begins_with("#"):
			count += 1
	return count


## Boş satır sayısı.
func _count_blank_lines(content: String) -> int:
	var count: int = 0
	for line in content.split("\n"):
		if line.strip_edges().is_empty():
			count += 1
	return count
