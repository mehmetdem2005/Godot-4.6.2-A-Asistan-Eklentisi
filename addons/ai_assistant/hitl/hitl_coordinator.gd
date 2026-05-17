@tool
class_name AIHITLCoordinator
extends RefCounted

## HITLCoordinator — insan-döngü-içinde koordinatörü (Layer 8).
##
## Layer 8'in tek giriş noktası. Beş bileşeni birleştirir:
##   risk     — AIRiskAssessor       (işlem ne kadar riskli)
##   gate     — AICheckpointGate     (kapı: geç / dur-bekle)
##   diff     — AIDiffViewer         (ne değişecek, insana göster)
##   console  — AIInterventionConsole (bekleyen kararlar kuyruğu)
##
## Phase 4'te Executor'da bıraktığımız kapı: "yıkıcı işlem HITL bekliyor".
## Bu sınıf O ENTEGRASYON NOKTASI. Executor bir işlem yapmadan önce
## HITLCoordinator.gate_action() çağırır:
##   - Risk düşük  -> {cleared: true}  -> Executor devam eder
##   - Risk yüksek -> {cleared: false, checkpoint} -> Executor BEKLER,
##     insan karar verene kadar işlem yapılmaz
##
## Mock policy: koordinatör sahte onay üretmez — riskli işlem ancak
## gerçek insan kararıyla geçer.

var risk: AIRiskAssessor
var gate: AICheckpointGate
var diff: AIDiffViewer
var console: AIInterventionConsole

## HITL açık mı? false ise tüm işlemler otomatik geçer (riskli mod —
## sadece tam-otomatik test senaryoları için; varsayılan AÇIK).
var enabled: bool = true


func _init() -> void:
	risk = AIRiskAssessor.new()
	gate = AICheckpointGate.new()
	diff = AIDiffViewer.new()
	console = AIInterventionConsole.new(gate)


# ============================================================
# EXECUTOR ENTEGRASYONU — ana kapı
# ============================================================

## Bir işlemi HITL kapısından geçirir. Executor bunu işlem ÖNCESİ çağırır.
##
## action: AIActionSpec. description: insan-okunur açıklama.
## new_content: işlemin yazacağı içerik (diff için, opsiyonel).
## file_op: mevcut içeriği okumak için (diff için, opsiyonel).
##
## Dönen: {
##   cleared: bool,           işlem devam edebilir mi (true = yap)
##   needs_approval: bool,    insan onayı bekleniyor mu
##   checkpoint: Checkpoint veya null,
##   risk_level: int,
##   reason: String
## }
func gate_action(
	action: AIActionSpec, description: String,
	new_content: String = "", file_op: AISandboxedFileOp = null
) -> Dictionary:
	# HITL kapalıysa her şey geçer (riskli mod)
	if not enabled:
		return {
			"cleared": true,
			"needs_approval": false,
			"checkpoint": null,
			"risk_level": AIRiskAssessor.RiskLevel.LOW,
			"reason": "HITL devre dışı — otomatik geçiş",
		}

	# Diff hazırla (içerik verildiyse)
	var diff_text: String = ""
	if not new_content.is_empty() and action != null:
		var diff_result: AIDiffViewer.DiffResult = diff.preview_action(
			action, file_op, new_content
		)
		diff_text = diff_result.summary() + "\n" + diff_result.to_text()

	# Kapıdan geçir
	var eval: Dictionary = gate.evaluate(action, description, diff_text)

	if eval["passed"]:
		# Kapı açık — risk düşük
		return {
			"cleared": true,
			"needs_approval": false,
			"checkpoint": null,
			"risk_level": (eval["risk"] as AIRiskAssessor.RiskAssessment).level,
			"reason": "Risk düşük — otomatik onay",
		}

	# Kapı kapalı — checkpoint oluştu, insan beklenecek
	var checkpoint: AICheckpointGate.Checkpoint = eval["checkpoint"]
	# Konsol abonelerine haber ver (UI)
	console.notify_new_checkpoint(checkpoint)

	return {
		"cleared": false,
		"needs_approval": true,
		"checkpoint": checkpoint,
		"risk_level": (eval["risk"] as AIRiskAssessor.RiskAssessment).level,
		"reason": "Yüksek risk — insan onayı gerekli",
	}


## Bir checkpoint çözüldükten SONRA, işlemin devam edip edemeyeceğini
## kontrol eder. Executor, insan kararından sonra bunu çağırır.
##
## Dönen: {
##   cleared: bool,            işlem yapılabilir mi
##   was_modified: bool,       insan içeriği değiştirdi mi
##   modified_content: String, MODIFY ise yeni içerik
##   status: String
## }
func check_resolution(checkpoint_id: String) -> Dictionary:
	var checkpoint: AICheckpointGate.Checkpoint = gate.get_checkpoint(
		checkpoint_id
	)
	if checkpoint == null:
		return {
			"cleared": false,
			"was_modified": false,
			"modified_content": "",
			"status": "checkpoint_bulunamadi",
		}
	if checkpoint.is_pending():
		return {
			"cleared": false,
			"was_modified": false,
			"modified_content": "",
			"status": "hala_bekliyor",
		}

	var was_modified: bool = (
		checkpoint.status == AICheckpointGate.CheckpointStatus.MODIFIED
	)
	return {
		"cleared": checkpoint.is_cleared(),
		"was_modified": was_modified,
		"modified_content": checkpoint.modified_content,
		"status": AICheckpointGate.STATUS_NAMES.get(checkpoint.status, "?"),
	}


# ============================================================
# YAPILANDIRMA
# ============================================================

## Risk onay eşiğini ayarlar — bu seviye ve üstü insana sorulur.
func set_approval_threshold(level: int) -> void:
	risk.approval_threshold = level
	gate.set_approval_threshold(level)


## HITL'i açar/kapatır.
func set_enabled(value: bool) -> void:
	enabled = value


# ============================================================
# DURUM
# ============================================================

## Layer 8 durum özeti — UI dashboard için.
func status() -> Dictionary:
	return {
		"enabled": enabled,
		"approval_threshold": AIRiskAssessor.level_name(risk.approval_threshold),
		"pending_checkpoints": console.pending_count(),
		"console": console.status(),
	}
