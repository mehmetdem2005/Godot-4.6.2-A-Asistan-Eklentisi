@tool
class_name AICommentLossDetector
extends RefCounted

## CommentLossDetector — yorum kaybı dedektörü (Surgical Edit / doğrulama).
##
## LLM bir düzenleme yaparken yorumları sessizce silebilir. format_drift
## yorum SAYISINI kontrol eder; bu dedektör daha derin gider: HANGİ
## yorumlar kayboldu, kaybolan yorum kritik mi (docstring, TODO, lisans).
##
## Yorum tipleri ve önemi:
##   - Docstring (## ile başlayan): yüksek önem — API belgesi
##   - TODO/FIXME/HACK: orta önem — bilinçli işaret
##   - Normal yorum (#): düşük önem ama yine de kayıp
##
## Mock policy: kayıp gerçek metin karşılaştırmasından bulunur.

## Kaybolan yorumun önem derecesi.
enum LossSeverity { LOW, MEDIUM, HIGH }

const SEVERITY_NAMES: Dictionary = {
	LossSeverity.LOW: "low",
	LossSeverity.MEDIUM: "medium",
	LossSeverity.HIGH: "high",
}

## Yüksek önemli yorumları işaret eden örüntüler.
const IMPORTANT_MARKERS: Array = ["TODO", "FIXME", "HACK", "XXX", "NOTE", "WARNING"]


## Yorum kaybı analiz sonucu.
class CommentLossReport extends RefCounted:
	var has_loss: bool = false
	var lost_comments: Array = []      ## [{text, severity}]
	var before_count: int = 0
	var after_count: int = 0

	## En yüksek kayıp önem derecesi.
	func max_severity() -> String:
		var has_high: bool = false
		var has_medium: bool = false
		for c in lost_comments:
			if c["severity"] == "high":
				has_high = true
			elif c["severity"] == "medium":
				has_medium = true
		if has_high:
			return "high"
		if has_medium:
			return "medium"
		if not lost_comments.is_empty():
			return "low"
		return "none"

	func to_dict() -> Dictionary:
		return {
			"has_loss": has_loss,
			"lost_count": lost_comments.size(),
			"max_severity": max_severity(),
			"before_count": before_count,
			"after_count": after_count,
		}


# ============================================================
# TESPİT
# ============================================================

## Öncesi ve sonrası içeriği karşılaştırır, kaybolan yorumları bulur.
## before / after: düzenleme öncesi ve sonrası.
## Dönen: CommentLossReport.
func detect(before: String, after: String) -> CommentLossReport:
	var report := CommentLossReport.new()

	var before_comments: Array = _extract_comments(before)
	var after_comments: Array = _extract_comments(after)
	report.before_count = before_comments.size()
	report.after_count = after_comments.size()

	# Sonrası içerikteki yorumları küme olarak — hızlı arama
	var after_set: Dictionary = {}
	for c in after_comments:
		after_set[c] = true

	# Öncesinde olup sonrasında olmayan yorumlar = kayıp
	for comment in before_comments:
		if not after_set.has(comment):
			report.lost_comments.append({
				"text": comment,
				"severity": SEVERITY_NAMES[_comment_severity(comment)],
			})

	report.has_loss = not report.lost_comments.is_empty()
	return report


# ============================================================
# DAHİLİ
# ============================================================

## Bir içerikten tüm yorum satırlarını çıkarır.
## Sadece tam yorum satırları (# ile başlayan) — satır-sonu yorumlar
## bu sürümde kapsam dışı (kod-içi # ayrımı güvenilmez).
func _extract_comments(content: String) -> Array:
	var comments: Array = []
	for line in content.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			comments.append(stripped)
	return comments


## Bir yorumun önem derecesini belirler.
func _comment_severity(comment: String) -> int:
	# Docstring — ## ile başlar, API belgesi
	if comment.begins_with("##"):
		return LossSeverity.HIGH
	# TODO/FIXME gibi bilinçli işaretler
	var upper: String = comment.to_upper()
	for marker in IMPORTANT_MARKERS:
		if upper.contains(marker):
			return LossSeverity.MEDIUM
	# Normal yorum
	return LossSeverity.LOW


## Bir kaybın kabul edilebilir olup olmadığı.
## HIGH önemli kayıp (docstring) kabul edilemez.
func is_loss_acceptable(report: CommentLossReport) -> bool:
	return report.max_severity() != "high"
