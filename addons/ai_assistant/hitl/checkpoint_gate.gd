@tool
class_name AICheckpointGate
extends RefCounted

## CheckpointGate — kontrol noktası kapısı (Layer 8 / HITL).
##
## Phase 4'te Executor'da bir kapı bırakmıştık: yıkıcı işlemler
## "HITL bekliyor" diye SKIP ediliyordu. Bu sınıf O KAPININ gerçek
## mekanizması.
##
## Akış:
##   1. Bir işlem gelir -> RiskAssessor risk biçer
##   2. Risk eşiğin altındaysa -> kapı AÇIK, otomatik geç
##   3. Risk eşiği geçerse -> kapı KAPALI, checkpoint oluştur, BEKLE
##   4. İnsan karar verir: APPROVE / REJECT / MODIFY
##   5. Karara göre işlem devam eder / iptal olur / değiştirilir
##
## Checkpoint'ler asenkron — bir kuyrukta birikir (InterventionConsole
## onları insana sunar). Bu sınıf tek checkpoint'in yaşam döngüsünü
## ve kapı kararını yönetir.
##
## Mock policy: kapı gerçek risk değerlendirmesine göre karar verir;
## insan kararı verilmeden riskli işlem GEÇMEZ.

## Bir checkpoint'in durumu.
enum CheckpointStatus { PENDING, APPROVED, REJECTED, MODIFIED }

const STATUS_NAMES: Dictionary = {
	CheckpointStatus.PENDING: "pending",
	CheckpointStatus.APPROVED: "approved",
	CheckpointStatus.REJECTED: "rejected",
	CheckpointStatus.MODIFIED: "modified",
}

## İnsan kararı tipi.
enum Decision { APPROVE, REJECT, MODIFY }


## Tek bir kontrol noktası.
class Checkpoint extends RefCounted:
	var id: String = ""
	var status: int = AICheckpointGate.CheckpointStatus.PENDING
	var created_at: String = ""
	var resolved_at: String = ""
	var description: String = ""        ## İşlem ne yapacak
	var risk_level: int = 0             ## AIRiskAssessor.RiskLevel
	var risk_reasons: PackedStringArray = PackedStringArray()
	var diff_text: String = ""          ## Değişikliğin diff'i (varsa)
	var decision_note: String = ""      ## İnsanın karar notu
	var modified_content: String = ""   ## MODIFY ise yeni içerik
	var task_ref: String = ""

	func is_pending() -> bool:
		return status == AICheckpointGate.CheckpointStatus.PENDING

	func is_resolved() -> bool:
		return not is_pending()

	## İşlem devam edebilir mi (onaylandı veya değiştirildi)?
	func is_cleared() -> bool:
		return (
			status == AICheckpointGate.CheckpointStatus.APPROVED
			or status == AICheckpointGate.CheckpointStatus.MODIFIED
		)

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"status": AICheckpointGate.STATUS_NAMES.get(status, "pending"),
			"created_at": created_at,
			"resolved_at": resolved_at,
			"description": description,
			"risk_level": risk_level,
			"risk_reasons": risk_reasons,
			"diff_text": diff_text,
			"decision_note": decision_note,
			"task_ref": task_ref,
		}


## Risk değerlendirici — kapı kararı için.
var _risk_assessor: AIRiskAssessor

## Bekleyen + çözülmüş tüm checkpoint'ler.
var _checkpoints: Array = []


func _init() -> void:
	_risk_assessor = AIRiskAssessor.new()


## Risk eşiğini ayarlar — bu seviye ve üstü insan onayı ister.
func set_approval_threshold(level: int) -> void:
	_risk_assessor.approval_threshold = level


# ============================================================
# KAPI KARARI
# ============================================================

## Bir işlemin kapıdan geçip geçemeyeceğine karar verir.
## action: AIActionSpec. description: insan-okunur açıklama.
## diff_text: değişikliğin diff'i (opsiyonel).
##
## Dönen: {
##   passed: bool,            kapı açık mı (otomatik geçti mi)
##   needs_checkpoint: bool,  insan onayı gerekiyor mu
##   checkpoint: Checkpoint veya null,
##   risk: AIRiskAssessor.RiskAssessment
## }
func evaluate(
	action: AIActionSpec, description: String, diff_text: String = ""
) -> Dictionary:
	var risk: AIRiskAssessor.RiskAssessment = _risk_assessor.assess_action(action)

	if not risk.needs_approval:
		# Kapı AÇIK — risk düşük, otomatik geç
		return {
			"passed": true,
			"needs_checkpoint": false,
			"checkpoint": null,
			"risk": risk,
		}

	# Kapı KAPALI — checkpoint oluştur, insan kararı beklensin
	var checkpoint := Checkpoint.new()
	checkpoint.id = AIContractBase.generate_id("ckpt")
	checkpoint.created_at = AIContractBase.now_iso()
	checkpoint.description = description
	checkpoint.risk_level = risk.level
	checkpoint.risk_reasons = risk.reasons
	checkpoint.diff_text = diff_text
	if action != null:
		checkpoint.task_ref = action.id
	_checkpoints.append(checkpoint)

	return {
		"passed": false,
		"needs_checkpoint": true,
		"checkpoint": checkpoint,
		"risk": risk,
	}


# ============================================================
# İNSAN KARARI
# ============================================================

## Bir checkpoint'e insan kararı uygular.
## checkpoint_id: hangi checkpoint. decision: APPROVE/REJECT/MODIFY.
## note: karar notu. modified_content: MODIFY ise yeni içerik.
## Dönen: {ok: bool, checkpoint: Checkpoint veya null, error: String}
func resolve(
	checkpoint_id: String, decision: int, note: String = "",
	modified_content: String = ""
) -> Dictionary:
	var checkpoint: Checkpoint = _find_checkpoint(checkpoint_id)
	if checkpoint == null:
		return {"ok": false, "checkpoint": null, "error": "Checkpoint bulunamadı"}
	if not checkpoint.is_pending():
		return {
			"ok": false,
			"checkpoint": checkpoint,
			"error": "Checkpoint zaten çözülmüş",
		}

	checkpoint.resolved_at = AIContractBase.now_iso()
	checkpoint.decision_note = note

	match decision:
		Decision.APPROVE:
			checkpoint.status = CheckpointStatus.APPROVED
		Decision.REJECT:
			checkpoint.status = CheckpointStatus.REJECTED
		Decision.MODIFY:
			checkpoint.status = CheckpointStatus.MODIFIED
			checkpoint.modified_content = modified_content
		_:
			return {
				"ok": false,
				"checkpoint": checkpoint,
				"error": "Geçersiz karar tipi",
			}
	return {"ok": true, "checkpoint": checkpoint, "error": ""}


# ============================================================
# SORGULAMA
# ============================================================

## Bekleyen (henüz karar verilmemiş) checkpoint'ler.
func pending_checkpoints() -> Array:
	var result: Array = []
	for c in _checkpoints:
		if (c as Checkpoint).is_pending():
			result.append(c)
	return result


## Bekleyen checkpoint sayısı.
func pending_count() -> int:
	return pending_checkpoints().size()


## Tüm checkpoint'ler.
func all_checkpoints() -> Array:
	return _checkpoints


## Belirli bir checkpoint'i id ile bulur. Yoksa null.
func _find_checkpoint(checkpoint_id: String) -> Checkpoint:
	for c in _checkpoints:
		if (c as Checkpoint).id == checkpoint_id:
			return c
	return null


## Bir checkpoint'i id ile döndürür (dışarıya açık).
func get_checkpoint(checkpoint_id: String) -> Checkpoint:
	return _find_checkpoint(checkpoint_id)


## Çözülmüş checkpoint'leri temizler — bekleyenler korunur.
func clear_resolved() -> void:
	var kept: Array = []
	for c in _checkpoints:
		if (c as Checkpoint).is_pending():
			kept.append(c)
	_checkpoints = kept
