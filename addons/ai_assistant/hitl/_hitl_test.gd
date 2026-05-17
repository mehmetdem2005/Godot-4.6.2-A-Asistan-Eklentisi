@tool
class_name AIHITLTest
extends RefCounted

## Phase 8 / Layer 8 — HITL (Human-in-the-Loop) Self-Test
##
## Sıkı testler: RiskAssessor (risk hesabı), DiffViewer (LCS diff),
## CheckpointGate (kapı + karar), InterventionConsole (kuyruk),
## HITLCoordinator (Executor entegrasyonu).


static func run_all() -> Array:
	var results: Array = []

	# RiskAssessor
	results.append(_b("HITL: Risk", _test_risk_safe_action()))
	results.append(_b("HITL: Risk", _test_risk_destructive()))
	results.append(_b("HITL: Risk", _test_risk_irreversible()))
	results.append(_b("HITL: Risk", _test_risk_critical_path()))
	results.append(_b("HITL: Risk", _test_risk_null_action()))
	results.append(_b("HITL: Risk", _test_risk_threshold()))
	results.append(_b("HITL: Risk", _test_risk_batch()))

	# DiffViewer
	results.append(_b("HITL: Diff", _test_diff_addition()))
	results.append(_b("HITL: Diff", _test_diff_deletion()))
	results.append(_b("HITL: Diff", _test_diff_no_change()))
	results.append(_b("HITL: Diff", _test_diff_new_file()))
	results.append(_b("HITL: Diff", _test_diff_middle_change()))

	# CheckpointGate
	results.append(_b("HITL: Gate", _test_gate_low_risk_passes()))
	results.append(_b("HITL: Gate", _test_gate_high_risk_stops()))
	results.append(_b("HITL: Gate", _test_gate_approve()))
	results.append(_b("HITL: Gate", _test_gate_reject()))
	results.append(_b("HITL: Gate", _test_gate_modify()))
	results.append(_b("HITL: Gate", _test_gate_double_resolve()))

	# InterventionConsole
	results.append(_b("HITL: Console", _test_console_queue_priority()))
	results.append(_b("HITL: Console", _test_console_approve()))
	results.append(_b("HITL: Console", _test_console_resolve_all()))
	results.append(_b("HITL: Console", _test_console_subscribe()))

	# HITLCoordinator
	results.append(_b("HITL: Coord", _test_coord_safe_cleared()))
	results.append(_b("HITL: Coord", _test_coord_risky_blocked()))
	results.append(_b("HITL: Coord", _test_coord_resolution_flow()))
	results.append(_b("HITL: Coord", _test_coord_disabled()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


## Test için bir ActionSpec üretir.
## destructive_type: yıkıcı bir tip kullan (FILE_DELETE).
static func _make_action(
	destructive: bool, reversible: bool, target: String
) -> AIActionSpec:
	var atype: int = (
		AIActionSpec.ActionType.FILE_DELETE if destructive
		else AIActionSpec.ActionType.FILE_WRITE
	)
	var action := AIActionSpec.create(atype, target, "Test işlemi")
	action.is_reversible = reversible
	return action


# ============================================================
# RISK ASSESSOR
# ============================================================

static func _test_risk_safe_action() -> Dictionary:
	var name := "Risk güvenli işlem LOW"
	var assessor := AIRiskAssessor.new()
	var action := _make_action(false, true, "res://game/player.gd")
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_action(action)
	if r.level != AIRiskAssessor.RiskLevel.LOW:
		return _fail(name, "normal yazma LOW olmalı")
	if r.needs_approval:
		return _fail(name, "düşük risk onay gerektirmemeli")
	return _ok(name)


static func _test_risk_destructive() -> Dictionary:
	var name := "Risk yıkıcı işlem yüksek"
	var assessor := AIRiskAssessor.new()
	var action := _make_action(true, true, "res://game/old.gd")
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_action(action)
	# Yıkıcı (+50) -> HIGH
	if r.level < AIRiskAssessor.RiskLevel.HIGH:
		return _fail(name, "yıkıcı işlem en az HIGH olmalı")
	if not r.needs_approval:
		return _fail(name, "yıkıcı işlem onay gerektirmeli")
	return _ok(name)


static func _test_risk_irreversible() -> Dictionary:
	var name := "Risk geri-alınamaz işlem CRITICAL"
	var assessor := AIRiskAssessor.new()
	# Yıkıcı (+50) + geri-alınamaz (+40) = 90 -> CRITICAL
	var action := _make_action(true, false, "res://x.gd")
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_action(action)
	if r.level != AIRiskAssessor.RiskLevel.CRITICAL:
		return _fail(name, "yıkıcı+geri-alınamaz CRITICAL olmalı")
	return _ok(name)


static func _test_risk_critical_path() -> Dictionary:
	var name := "Risk sistem-kritik yol"
	var assessor := AIRiskAssessor.new()
	var action := _make_action(false, true, "res://project.godot")
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_action(action)
	# project.godot'a dokunma +60 -> en az HIGH
	if r.level < AIRiskAssessor.RiskLevel.HIGH:
		return _fail(name, "kritik yola dokunma yüksek risk olmalı")
	return _ok(name)


static func _test_risk_null_action() -> Dictionary:
	var name := "Risk null işlem güvenli tarafta"
	var assessor := AIRiskAssessor.new()
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_action(null)
	# Bilinmeyen işlem — yüksek risk sayılmalı
	if r.level < AIRiskAssessor.RiskLevel.HIGH:
		return _fail(name, "null işlem yüksek risk sayılmalı")
	if not r.needs_approval:
		return _fail(name, "null işlem onay gerektirmeli")
	return _ok(name)


static func _test_risk_threshold() -> Dictionary:
	var name := "Risk eşik ayarı"
	var assessor := AIRiskAssessor.new()
	# Eşiği CRITICAL yap — sadece kritik işlemler sorulsun
	assessor.approval_threshold = AIRiskAssessor.RiskLevel.CRITICAL
	# HIGH seviyeli yıkıcı işlem — artık eşiğin altında
	var action := _make_action(true, true, "res://old.gd")
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_action(action)
	# HIGH < CRITICAL eşik -> onay gerekmez
	if r.needs_approval:
		return _fail(name, "eşik CRITICAL iken HIGH onay gerektirmemeli")
	return _ok(name)


static func _test_risk_batch() -> Dictionary:
	var name := "Risk toplu değerlendirme"
	var assessor := AIRiskAssessor.new()
	var actions: Array = [
		_make_action(true, true, "a.gd"),
		_make_action(true, true, "b.gd"),
		_make_action(true, true, "c.gd"),
	]
	var r: AIRiskAssessor.RiskAssessment = assessor.assess_batch(actions)
	# 3 yıkıcı işlem — batch skoru tek işlemden yüksek
	if r.level < AIRiskAssessor.RiskLevel.HIGH:
		return _fail(name, "3 yıkıcı işlemli batch yüksek risk olmalı")
	return _ok(name)


# ============================================================
# DIFF VIEWER
# ============================================================

static func _test_diff_addition() -> Dictionary:
	var name := "Diff satır ekleme"
	var viewer := AIDiffViewer.new()
	var result: AIDiffViewer.DiffResult = viewer.compute_diff(
		"satir1\nsatir2", "satir1\nsatir2\nsatir3"
	)
	if result.added_count != 1:
		return _fail(name, "1 eklenen satır beklenir")
	if result.removed_count != 0:
		return _fail(name, "silinen olmamalı")
	return _ok(name)


static func _test_diff_deletion() -> Dictionary:
	var name := "Diff satır silme"
	var viewer := AIDiffViewer.new()
	var result: AIDiffViewer.DiffResult = viewer.compute_diff(
		"satir1\nsatir2\nsatir3", "satir1\nsatir3"
	)
	if result.removed_count != 1:
		return _fail(name, "1 silinen satır beklenir")
	return _ok(name)


static func _test_diff_no_change() -> Dictionary:
	var name := "Diff değişiklik yok"
	var viewer := AIDiffViewer.new()
	var result: AIDiffViewer.DiffResult = viewer.compute_diff(
		"ayni\nicerik", "ayni\nicerik"
	)
	if result.has_changes():
		return _fail(name, "aynı içerik değişiklik içermemeli")
	return _ok(name)


static func _test_diff_new_file() -> Dictionary:
	var name := "Diff yeni dosya"
	var viewer := AIDiffViewer.new()
	var result: AIDiffViewer.DiffResult = viewer.compute_diff(
		"", "yeni\nicerik"
	)
	if not result.is_new_file:
		return _fail(name, "boş öncesi yeni dosya olmalı")
	return _ok(name)


static func _test_diff_middle_change() -> Dictionary:
	var name := "Diff orta satır değişimi"
	var viewer := AIDiffViewer.new()
	var result: AIDiffViewer.DiffResult = viewer.compute_diff(
		"a\nb\nc\nd", "a\nX\nc\nd"
	)
	# b -> X: 1 eklenen, 1 silinen, a/c/d korunur
	if result.added_count != 1 or result.removed_count != 1:
		return _fail(name, "orta değişim +1 -1 olmalı")
	return _ok(name)


# ============================================================
# CHECKPOINT GATE
# ============================================================

static func _test_gate_low_risk_passes() -> Dictionary:
	var name := "Gate düşük risk kapı açık"
	var gate := AICheckpointGate.new()
	var action := _make_action(false, true, "res://game/safe.gd")
	var result: Dictionary = gate.evaluate(action, "Güvenli yazma")
	if not result["passed"]:
		return _fail(name, "düşük risk kapıdan geçmeli")
	if result["needs_checkpoint"]:
		return _fail(name, "düşük risk checkpoint gerektirmemeli")
	return _ok(name)


static func _test_gate_high_risk_stops() -> Dictionary:
	var name := "Gate yüksek risk kapı kapalı"
	var gate := AICheckpointGate.new()
	var action := _make_action(true, false, "res://critical.gd")
	var result: Dictionary = gate.evaluate(action, "Tehlikeli silme")
	if result["passed"]:
		return _fail(name, "yüksek risk kapıdan geçmemeli")
	if not result["needs_checkpoint"]:
		return _fail(name, "yüksek risk checkpoint oluşturmalı")
	if result["checkpoint"] == null:
		return _fail(name, "checkpoint nesnesi null")
	return _ok(name)


static func _test_gate_approve() -> Dictionary:
	var name := "Gate onaylama"
	var gate := AICheckpointGate.new()
	var action := _make_action(true, false, "res://x.gd")
	var ev: Dictionary = gate.evaluate(action, "Test")
	var checkpoint: AICheckpointGate.Checkpoint = ev["checkpoint"]
	var result: Dictionary = gate.resolve(
		checkpoint.id, AICheckpointGate.Decision.APPROVE, "Onaylandı"
	)
	if not result["ok"]:
		return _fail(name, "onaylama başarısız")
	if not checkpoint.is_cleared():
		return _fail(name, "onaylanan checkpoint cleared olmalı")
	return _ok(name)


static func _test_gate_reject() -> Dictionary:
	var name := "Gate reddetme"
	var gate := AICheckpointGate.new()
	var action := _make_action(true, false, "res://x.gd")
	var ev: Dictionary = gate.evaluate(action, "Test")
	var checkpoint: AICheckpointGate.Checkpoint = ev["checkpoint"]
	gate.resolve(checkpoint.id, AICheckpointGate.Decision.REJECT, "Reddedildi")
	if checkpoint.is_cleared():
		return _fail(name, "reddedilen checkpoint cleared olmamalı")
	return _ok(name)


static func _test_gate_modify() -> Dictionary:
	var name := "Gate değiştirerek onay"
	var gate := AICheckpointGate.new()
	var action := _make_action(true, false, "res://x.gd")
	var ev: Dictionary = gate.evaluate(action, "Test")
	var checkpoint: AICheckpointGate.Checkpoint = ev["checkpoint"]
	gate.resolve(
		checkpoint.id, AICheckpointGate.Decision.MODIFY, "Düzeltildi",
		"yeni içerik"
	)
	if not checkpoint.is_cleared():
		return _fail(name, "değiştirilmiş checkpoint cleared olmalı")
	if checkpoint.modified_content != "yeni içerik":
		return _fail(name, "değiştirilmiş içerik kaydedilmedi")
	return _ok(name)


static func _test_gate_double_resolve() -> Dictionary:
	var name := "Gate çift karar reddi"
	var gate := AICheckpointGate.new()
	var action := _make_action(true, false, "res://x.gd")
	var ev: Dictionary = gate.evaluate(action, "Test")
	var checkpoint: AICheckpointGate.Checkpoint = ev["checkpoint"]
	gate.resolve(checkpoint.id, AICheckpointGate.Decision.APPROVE)
	# İkinci kez çözmeye çalış — reddedilmeli
	var second: Dictionary = gate.resolve(
		checkpoint.id, AICheckpointGate.Decision.REJECT
	)
	if second["ok"]:
		return _fail(name, "zaten çözülmüş checkpoint tekrar çözülmemeli")
	return _ok(name)


# ============================================================
# INTERVENTION CONSOLE
# ============================================================

static func _test_console_queue_priority() -> Dictionary:
	var name := "Console kuyruk risk önceliği"
	var gate := AICheckpointGate.new()
	var console := AIInterventionConsole.new(gate)
	# Düşük sonra yüksek riskli işlem ekle
	gate.evaluate(_make_action(true, true, "low.gd"), "orta")
	gate.evaluate(_make_action(true, false, "crit.gd"), "kritik")
	var q: Array = console.queue()
	if q.size() < 2:
		return _fail(name, "kuyrukta 2 checkpoint olmalı")
	# En riskli (CRITICAL) başta olmalı
	if q[0].risk_level < q[1].risk_level:
		return _fail(name, "yüksek risk kuyruğun başında olmalı")
	return _ok(name)


static func _test_console_approve() -> Dictionary:
	var name := "Console onaylama + geçmiş"
	var gate := AICheckpointGate.new()
	var console := AIInterventionConsole.new(gate)
	var ev: Dictionary = gate.evaluate(
		_make_action(true, false, "x.gd"), "test"
	)
	var checkpoint: AICheckpointGate.Checkpoint = ev["checkpoint"]
	console.approve(checkpoint.id, "tamam")
	if console.history().size() != 1:
		return _fail(name, "karar geçmişe eklenmedi")
	if console.pending_count() != 0:
		return _fail(name, "onaylanan checkpoint hâlâ bekliyor")
	return _ok(name)


static func _test_console_resolve_all() -> Dictionary:
	var name := "Console toplu çözüm"
	var gate := AICheckpointGate.new()
	var console := AIInterventionConsole.new(gate)
	gate.evaluate(_make_action(true, false, "a.gd"), "a")
	gate.evaluate(_make_action(true, false, "b.gd"), "b")
	var result: Dictionary = console.resolve_all(
		AICheckpointGate.Decision.REJECT, "toplu ret"
	)
	if result["resolved_count"] != 2:
		return _fail(name, "2 checkpoint toplu çözülmeliydi")
	if console.pending_count() != 0:
		return _fail(name, "toplu çözüm sonrası bekleyen kalmamalı")
	return _ok(name)


static func _test_console_subscribe() -> Dictionary:
	var name := "Console abone bildirimi"
	var gate := AICheckpointGate.new()
	var console := AIInterventionConsole.new(gate)
	var received: Array = []
	console.subscribe(func(c): received.append(c))
	var ev: Dictionary = gate.evaluate(
		_make_action(true, false, "x.gd"), "test"
	)
	console.notify_new_checkpoint(ev["checkpoint"])
	if received.size() != 1:
		return _fail(name, "abone checkpoint bildirimini almadı")
	return _ok(name)


# ============================================================
# HITL COORDINATOR
# ============================================================

static func _test_coord_safe_cleared() -> Dictionary:
	var name := "Coordinator güvenli işlem geçer"
	var coord := AIHITLCoordinator.new()
	var action := _make_action(false, true, "res://game/safe.gd")
	var result: Dictionary = coord.gate_action(action, "Güvenli yazma")
	if not result["cleared"]:
		return _fail(name, "güvenli işlem cleared olmalı")
	if result["needs_approval"]:
		return _fail(name, "güvenli işlem onay gerektirmemeli")
	return _ok(name)


static func _test_coord_risky_blocked() -> Dictionary:
	var name := "Coordinator riskli işlem bloklanır"
	var coord := AIHITLCoordinator.new()
	var action := _make_action(true, false, "res://critical.gd")
	var result: Dictionary = coord.gate_action(action, "Tehlikeli silme")
	if result["cleared"]:
		return _fail(name, "riskli işlem cleared OLMAMALI (sahte onay)")
	if not result["needs_approval"]:
		return _fail(name, "riskli işlem onay beklemelidir")
	if result["checkpoint"] == null:
		return _fail(name, "checkpoint oluşmadı")
	return _ok(name)


static func _test_coord_resolution_flow() -> Dictionary:
	var name := "Coordinator karar sonrası akış"
	var coord := AIHITLCoordinator.new()
	var action := _make_action(true, false, "res://x.gd")
	var gated: Dictionary = coord.gate_action(action, "Test")
	var checkpoint: AICheckpointGate.Checkpoint = gated["checkpoint"]
	# İnsan onaylar
	coord.console.approve(checkpoint.id, "onay")
	# Karar sonrası kontrol — işlem artık devam edebilmeli
	var resolution: Dictionary = coord.check_resolution(checkpoint.id)
	if not resolution["cleared"]:
		return _fail(name, "onaylanan checkpoint cleared olmalı")
	return _ok(name)


static func _test_coord_disabled() -> Dictionary:
	var name := "Coordinator devre dışı modda geçer"
	var coord := AIHITLCoordinator.new()
	coord.set_enabled(false)
	# HITL kapalı — riskli işlem bile geçmeli
	var action := _make_action(true, false, "res://critical.gd")
	var result: Dictionary = coord.gate_action(action, "Tehlikeli")
	if not result["cleared"]:
		return _fail(name, "HITL kapalıyken işlem geçmeli")
	return _ok(name)
