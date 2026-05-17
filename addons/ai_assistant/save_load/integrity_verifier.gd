@tool
class_name AISaveIntegrityVerifier
extends RefCounted

## IntegrityVerifier — bütünlük doğrulayıcı (Madde 09 / Save-Load).
##
## HMACSigner imza üretir/doğrular; bu sınıf bütünlük denetimini
## ÜST SEVİYEDE yönetir. Bir kayıt dosyası alır, tüm bütünlük
## kontrollerinden geçirir, tek bir net karar döndürür:
## "bu kayıt güvenilir mi".
##
## Kontroller:
##   - İmza var mı, tutuyor mu (HMAC)
##   - Zarf yapısı bütün mü (_meta + data + _integrity)
##   - Boyut makul mu (boş/devasa değil)
##
## Save/Load invariant'ı: bozuk/kurcalanmış kayıt YÜKLENMEZ —
## kullanıcıya temiz hata gösterilir, oyun çökmez.
##
## Mock policy: doğrulama gerçek imza kontrolünden geçer.

## Bütünlük sorununun türü.
enum IntegrityIssue { NONE, MISSING_SIGNATURE, SIGNATURE_MISMATCH, MALFORMED_ENVELOPE, EMPTY_CONTENT, SIZE_ANOMALY }

const ISSUE_NAMES: Dictionary = {
	IntegrityIssue.NONE: "sağlam",
	IntegrityIssue.MISSING_SIGNATURE: "imza eksik",
	IntegrityIssue.SIGNATURE_MISMATCH: "imza tutmuyor",
	IntegrityIssue.MALFORMED_ENVELOPE: "bozuk zarf",
	IntegrityIssue.EMPTY_CONTENT: "boş içerik",
	IntegrityIssue.SIZE_ANOMALY: "boyut anomalisi",
}

## Makul kayıt boyutu üst sınırı (bayt) — bunun üstü şüpheli.
const MAX_REASONABLE_SIZE: int = 16 * 1024 * 1024  # 16 MB


## Bir bütünlük denetiminin sonucu.
class IntegrityReport extends RefCounted:
	var trusted: bool = false          ## Kayıt güvenilir mi
	var issue: int = AISaveIntegrityVerifier.IntegrityIssue.NONE
	var detail: String = ""

	func issue_name() -> String:
		return AISaveIntegrityVerifier.ISSUE_NAMES.get(issue, "?")

	func to_dict() -> Dictionary:
		return {
			"trusted": trusted,
			"issue": issue_name(),
			"detail": detail,
		}


## Bütünlük imzalayıcı.
var _signer: AISaveHMACSigner


func _init(signer: AISaveHMACSigner = null) -> void:
	if signer != null:
		_signer = signer
	else:
		_signer = AISaveHMACSigner.new()


# ============================================================
# BÜTÜNLÜK DENETİMİ
# ============================================================

## İmzalı bir kayıt zarfını tam bütünlük denetiminden geçirir.
## envelope: {content: String, signature: String}.
## Dönen: IntegrityReport.
func verify(envelope: Dictionary) -> IntegrityReport:
	var report := IntegrityReport.new()

	# --- Zarf yapısı ---
	if not envelope.has("content"):
		report.issue = IntegrityIssue.MALFORMED_ENVELOPE
		report.detail = "Zarf 'content' alanı taşımıyor"
		return report
	var content: String = str(envelope["content"])

	# --- Boş içerik ---
	if content.strip_edges().is_empty():
		report.issue = IntegrityIssue.EMPTY_CONTENT
		report.detail = "Kayıt içeriği boş"
		return report

	# --- Boyut anomalisi ---
	var size: int = content.to_utf8_buffer().size()
	if size > MAX_REASONABLE_SIZE:
		report.issue = IntegrityIssue.SIZE_ANOMALY
		report.detail = "Kayıt anormal büyük: %d bayt" % size
		return report

	# --- İmza varlığı ---
	if not envelope.has("signature"):
		report.issue = IntegrityIssue.MISSING_SIGNATURE
		report.detail = "Kayıt imzasız — bütünlük doğrulanamaz"
		return report
	var signature: String = str(envelope["signature"])
	if signature.is_empty():
		report.issue = IntegrityIssue.MISSING_SIGNATURE
		report.detail = "İmza alanı boş"
		return report

	# --- İmza doğrulama (HMAC) ---
	if not _signer.verify(content, signature):
		report.issue = IntegrityIssue.SIGNATURE_MISMATCH
		report.detail = "İmza tutmuyor — kayıt kurcalanmış veya bozuk"
		return report

	# Tüm kontroller geçti
	report.trusted = true
	report.issue = IntegrityIssue.NONE
	report.detail = "Tüm bütünlük kontrolleri geçti"
	return report


## İmzalı bir zarf oluşturur — kaydetmeden önce.
## content: imzalanacak kayıt metni.
## Dönen: {content: String, signature: String}.
func create_signed_envelope(content: String) -> Dictionary:
	return {
		"content": content,
		"signature": _signer.sign_content(content),
	}


## Bir kaydın güvenilir olup olmadığını döndürür — hızlı kontrol.
func is_trusted(envelope: Dictionary) -> bool:
	return verify(envelope).trusted
