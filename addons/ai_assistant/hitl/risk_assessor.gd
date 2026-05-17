@tool
class_name AIRiskAssessor
extends RefCounted

## RiskAssessor — risk değerlendirici (Layer 8 / HITL).
##
## Sistem otonom çalışırken HER işlemi insana sormak işe yaramaz —
## kullanıcı boğulur. AMA hiçbir şey sormamak tehlikeli. Çözüm: işlemin
## RİSKİNİ ölç, eşiği geçeni insana sor.
##
## Dört risk seviyesi:
##   LOW       — güvenli, otomatik geç (yeni dosya oluştur)
##   MEDIUM    — dikkat, ama otomatik (mevcut dosyayı değiştir)
##   HIGH      — insana sor (dosya sil, taşı)
##   CRITICAL  — insana sor + ekstra uyarı (proje ayarı, geri-alınamaz)
##
## Risk, işlemin doğasından hesaplanır: yıkıcı mı, geri-alınabilir mi,
## kaç dosya etkiliyor, sistem-kritik yola mı dokunuyor.
##
## Mock policy: risk gerçek işlem özelliklerinden hesaplanır.

## Risk seviyeleri — artan tehlike.
enum RiskLevel { LOW, MEDIUM, HIGH, CRITICAL }

const RISK_LEVEL_NAMES: Dictionary = {
	RiskLevel.LOW: "low",
	RiskLevel.MEDIUM: "medium",
	RiskLevel.HIGH: "high",
	RiskLevel.CRITICAL: "critical",
}

## Bu seviye ve üstü insan onayı gerektirir.
## Varsayılan: HIGH — yıkıcı işlemler sorulur, normal yazma geçer.
var approval_threshold: int = RiskLevel.HIGH

## Sistem-kritik yol parçaları — bunlara dokunan işlem riski yükseltir.
const CRITICAL_PATH_FRAGMENTS: Array = [
	"project.godot",
	"export_presets.cfg",
	".godot/",
	"addons/ai_assistant/",
]


## Bir risk değerlendirme sonucu.
class RiskAssessment extends RefCounted:
	var level: int = AIRiskAssessor.RiskLevel.LOW
	var score: int = 0                 ## Sayısal risk puanı
	var reasons: PackedStringArray = PackedStringArray()  ## Neden bu seviye
	var needs_approval: bool = false   ## İnsan onayı gerekli mi

	func to_dict() -> Dictionary:
		return {
			"level": AIRiskAssessor.RISK_LEVEL_NAMES.get(level, "low"),
			"score": score,
			"reasons": reasons,
			"needs_approval": needs_approval,
		}


# ============================================================
# DEĞERLENDİRME — ActionSpec
# ============================================================

## Bir AIActionSpec'in riskini değerlendirir.
## Dönen: RiskAssessment.
func assess_action(action: AIActionSpec) -> RiskAssessment:
	var assessment := RiskAssessment.new()
	if action == null:
		# Bilinmeyen işlem — güvenli tarafta, yüksek risk say
		assessment.level = RiskLevel.HIGH
		assessment.score = 100
		assessment.reasons.append("İşlem tanımı yok — güvenlik için yüksek risk")
		assessment.needs_approval = true
		return assessment

	var score: int = 0

	# --- Yıkıcı işlem mi ---
	if action.is_destructive():
		score += 50
		assessment.reasons.append(
			"Yıkıcı işlem tipi: %s" % action.action_type_name()
		)

	# --- Geri-alınabilir mi ---
	if not action.is_reversible:
		score += 40
		assessment.reasons.append("İşlem geri alınamaz")

	# --- Sistem-kritik yola mı dokunuyor ---
	var target: String = action.target_path
	for fragment in CRITICAL_PATH_FRAGMENTS:
		if target.contains(fragment):
			score += 60
			assessment.reasons.append(
				"Sistem-kritik konuma dokunuyor: %s" % fragment
			)
			break

	# --- Skoru seviyeye çevir ---
	assessment.score = score
	assessment.level = _score_to_level(score)
	if assessment.reasons.is_empty():
		assessment.reasons.append("Standart güvenli işlem")
	assessment.needs_approval = assessment.level >= approval_threshold
	return assessment


# ============================================================
# DEĞERLENDİRME — toplu / genel
# ============================================================

## Birden çok işlemin BİRLEŞİK riskini değerlendirir.
## Bir batch'te tek tek düşük ama toplamda yüksek risk olabilir.
## actions: AIActionSpec listesi.
func assess_batch(actions: Array) -> RiskAssessment:
	var assessment := RiskAssessment.new()
	if actions.is_empty():
		assessment.reasons.append("Boş işlem grubu")
		return assessment

	var max_score: int = 0
	var destructive_count: int = 0
	for action in actions:
		var single: RiskAssessment = assess_action(action)
		max_score = maxi(max_score, single.score)
		if action != null and (action as AIActionSpec).is_destructive():
			destructive_count += 1

	# Çok sayıda yıkıcı işlem — toplu risk yükselir
	var batch_score: int = max_score
	if destructive_count >= 3:
		batch_score += 30
		assessment.reasons.append(
			"%d yıkıcı işlem tek grupta" % destructive_count
		)

	# Büyük batch — etki alanı geniş
	if actions.size() >= 10:
		batch_score += 20
		assessment.reasons.append(
			"Büyük işlem grubu (%d işlem)" % actions.size()
		)

	assessment.score = batch_score
	assessment.level = _score_to_level(batch_score)
	if assessment.reasons.is_empty():
		assessment.reasons.append("Standart işlem grubu")
	assessment.needs_approval = assessment.level >= approval_threshold
	return assessment


## Genel bir risk değerlendirmesi — serbest parametrelerle.
## is_destructive, is_reversible, touches_critical: işlemin özellikleri.
## Doğrudan ActionSpec olmayan durumlar için.
func assess_raw(
	is_destructive: bool, is_reversible: bool, touches_critical: bool
) -> RiskAssessment:
	var assessment := RiskAssessment.new()
	var score: int = 0
	if is_destructive:
		score += 50
		assessment.reasons.append("Yıkıcı işlem")
	if not is_reversible:
		score += 40
		assessment.reasons.append("Geri alınamaz")
	if touches_critical:
		score += 60
		assessment.reasons.append("Sistem-kritik konum")
	assessment.score = score
	assessment.level = _score_to_level(score)
	if assessment.reasons.is_empty():
		assessment.reasons.append("Güvenli işlem")
	assessment.needs_approval = assessment.level >= approval_threshold
	return assessment


# ============================================================
# DAHİLİ
# ============================================================

## Sayısal risk puanını seviyeye çevirir.
func _score_to_level(score: int) -> int:
	if score >= 90:
		return RiskLevel.CRITICAL
	elif score >= 50:
		return RiskLevel.HIGH
	elif score >= 20:
		return RiskLevel.MEDIUM
	else:
		return RiskLevel.LOW


## Bir risk seviyesinin adı.
static func level_name(level: int) -> String:
	return RISK_LEVEL_NAMES.get(level, "low")
