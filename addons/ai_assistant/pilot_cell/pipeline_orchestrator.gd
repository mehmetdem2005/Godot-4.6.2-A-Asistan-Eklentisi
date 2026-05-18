@tool
class_name AIPipelineOrchestrator
extends Node

## PipelineOrchestrator — uçtan uca komut akışı (Aşama 4c / devir ADIM 2c).
##
## SORUN (denetim bulgusu): Planner / Pilot Cell / Verifier / HITL /
## Executor tek tek çalışıyor ama BİRBİRİNİ ÇAĞIRMIYORDU. Ayrıca
## Executor, HITL kapısını (gate_action) HİÇ çağırmıyordu — yıkıcı
## işlem koruması sadece bir bayrak kontrolüydü.
##
## ÇÖZÜM: Mevcut katmanları DEĞİŞTİRMEDEN birbirine bağlayan üst
## orkestratör. Zincir:
##   görev → Planner (plan ağacı) → Pilot Cell (CANLI LLM, 4a köprüsü)
##   → kod çıkar → Verifier (doğrula) → HITL (gate_action — artık
##   gerçekten çağrılıyor) → Executor (gerçek dosya yazımı).
##
## İki yüz:
##   - run_task(): ASENKRON tam zincir (LLM ağ çağrısı içerir).
##   - apply_generated_code(): SENKRON çekirdek (verify→gate→execute) —
##     gerçek ağ olmadan test edilebilir.
##
## Mock policy: Verifier geçmezse YAZILMAZ; HITL onay isterse
## YAZILMAZ. Sahte "uygulandı" yok — her aşama dürüstçe raporlanır.

signal pipeline_completed(result: Dictionary)
signal pipeline_progress(step: String)

var _bridge: AIAgentLiveBridge = null
var _verifier: AIVerifierEngine = null
var _hitl: AIHITLCoordinator = null
var _executor: AIExecutorEngine = null
var _planner: AIHierarchicalPlanner = null

var _active_path: String = ""
var _active_role_name: String = ""


func _init() -> void:
	_verifier = AIVerifierEngine.new()
	_hitl = AIHITLCoordinator.new()
	_executor = AIExecutorEngine.new()
	_planner = AIHierarchicalPlanner.new()


## Canlı köprüyü bağlar (router'ı ayarlı bir AIAgentLiveBridge).
func attach_bridge(bridge: AIAgentLiveBridge) -> void:
	_bridge = bridge


## LLM cevabından GDScript kodunu çıkarır (```...``` çitlerini soyar).
func extract_code(content: String) -> String:
	var text: String = content.strip_edges()
	var fence: int = text.find("```")
	if fence == -1:
		return text
	var after: int = text.find("\n", fence)
	if after == -1:
		return text
	var rest: String = text.substr(after + 1)
	var close: int = rest.find("```")
	if close == -1:
		return rest.strip_edges()
	return rest.substr(0, close).strip_edges()


## Bir görev için plan ağacı kurar (Planner entegrasyonu).
## Dönen: çalıştırılacak ACTION düğümü (planner.tree içinde).
func build_plan(goal_title: String, action_title: String) -> AIPlanNode:
	var goal: AIPlanNode = _planner.start_plan(goal_title)
	var milestone: AIPlanNode = _planner.add_milestone(
		"Üretim", goal.id
	)
	var task: AIPlanNode = _planner.add_task(
		"Kod üret ve uygula", milestone.id, "CodeEngineer"
	)
	return _planner.add_action(action_title, task.id)


## SENKRON çekirdek: üretilmiş kodu doğrula → HITL kapısı → uygula.
## Gerçek ağ olmadan test edilebilir. Dönen aşama-bazlı sonuç.
func apply_generated_code(
	target_path: String, raw_content: String, role_name: String
) -> Dictionary:
	var code: String = extract_code(raw_content)
	if code.strip_edges().is_empty():
		return _stage("extract", false, "LLM çıktısından kod çıkarılamadı")

	# --- Verifier ---
	pipeline_progress.emit("Doğrulanıyor...")
	var vr: Dictionary = _verifier.verify(code)
	if not bool(vr["passed"]):
		return _stage(
			"verify", false,
			"Doğrulama başarısız: " + str(vr["failed_level"])
		)

	# --- ActionSpec ---
	var spec := AIActionSpec.create(
		AIActionSpec.ActionType.FILE_WRITE, target_path, role_name
	)
	spec.params = {"path": target_path, "content": code}

	# --- HITL kapısı (ARTIK gerçekten çağrılıyor) ---
	pipeline_progress.emit("HITL kapısı...")
	var gate: Dictionary = _hitl.gate_action(
		spec, "FILE_WRITE: " + target_path, code
	)
	if not bool(gate["cleared"]):
		var d: Dictionary = _stage(
			"hitl", false,
			"İnsan onayı bekleniyor: " + str(gate["reason"])
		)
		d["needs_approval"] = true
		d["risk_level"] = int(gate["risk_level"])
		return d

	# --- Executor (gerçek dosya yazımı) ---
	pipeline_progress.emit("Yazılıyor...")
	_executor.initialize()
	var node := AIPlanNode.create(
		AIPlanNode.Level.ACTION, "write " + target_path
	)
	var res: AIVerificationResult = _executor.execute_action(node, spec)
	var ok: bool = res.outcome == AIVerificationResult.Outcome.PASS
	var out: Dictionary = _stage(
		"executed", ok, res.message
	)
	out["path"] = target_path
	out["code_length"] = code.length()
	return out


## ASENKRON tam zincir: görev → plan → CANLI LLM → çekirdek.
## Sonuç 'pipeline_completed' sinyali ile gelir.
## model: boş değilse LLM isteği o modele sabitlenir (UI model seçimi);
## boş = adapter varsayılanı (geriye uyumlu).
func run_task(
	goal_title: String, target_path: String,
	instruction: String, role: int, model: String = ""
) -> bool:
	if _bridge == null:
		_emit_done(_stage(
			"bridge", false, "Canlı köprü bağlı değil"
		))
		return false

	build_plan(goal_title, "Yaz: " + target_path)
	_active_path = target_path
	_active_role_name = AICellRoles.role_name(role)

	if not _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.connect(_on_thought)

	pipeline_progress.emit("Ajan düşünüyor (canlı)...")
	return _bridge.think_live(role, instruction, {}, model)


func _on_thought(thought: Dictionary) -> void:
	if not bool(thought.get("ok", false)):
		_emit_done(_stage(
			"llm", false,
			"LLM cevabı alınamadı: " + str(thought.get("status_note", ""))
		))
		return
	var result: Dictionary = apply_generated_code(
		_active_path, str(thought.get("content", "")),
		_active_role_name
	)
	_emit_done(result)


## HITL koordinatörüne erişim — ayar paneli + test için.
func hitl_coordinator() -> AIHITLCoordinator:
	return _hitl


## Orkestratör durumu — UI / test için.
func pipeline_status() -> Dictionary:
	return {
		"bridge_attached": _bridge != null,
		"plan_progress": _planner.progress(),
	}


# ============================================================
# İÇ YARDIMCILAR
# ============================================================

func _stage(stage: String, ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"stage": stage,
		"message": message,
		"needs_approval": false,
	}


func _emit_done(result: Dictionary) -> void:
	pipeline_completed.emit(result)
