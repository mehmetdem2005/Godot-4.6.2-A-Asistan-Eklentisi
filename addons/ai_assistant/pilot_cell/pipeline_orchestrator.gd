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
var _chat_mode: bool = false

# --- Çok-adımlı plan (Plan C) ---
var _decomposer: AIPlanDecomposer = null
var _chain: AIRoleChainRunner = null
var _aux_bridge: AIAgentLiveBridge = null
var _bp_active: bool = false
var _bp_goal: String = ""
var _bp_model: String = ""
var _bp_tasks: Array = []
var _bp_idx: int = 0
var _bp_paths: Array = []
var _bp_failed: Array = []
var _bp_project: String = ""


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

	_chat_mode = false
	build_plan(goal_title, "Yaz: " + target_path)
	_active_path = target_path
	_active_role_name = AICellRoles.role_name(role)

	if not _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.connect(_on_thought)

	pipeline_progress.emit("Ajan düşünüyor (canlı)...")
	return _bridge.think_live(role, instruction, {}, model)


## Doğal SOHBET — kod hattı YOK (Verifier/HITL/Executor atlanır).
## Sıradan mesaj/soru için: LLM yanıtı doğrudan döner, dosya yazılmaz.
## Sonuç 'pipeline_completed' ile gelir (stage="chat").
## history: çok-turlu hafıza [{role, content}] (eski→yeni). Boş =
## eski stateless davranış (geriye uyumlu).
func run_chat(
	message: String, model: String = "", history: Array = [],
	project_context: String = ""
) -> bool:
	if _bridge == null:
		_emit_done(_stage("bridge", false, "Canlı köprü bağlı değil"))
		return false

	_chat_mode = true
	if not _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.connect(_on_thought)

	pipeline_progress.emit("Asistan yanıtlıyor (canlı)...")
	return _bridge.think_chat(message, model, history, project_context)


## ASENKRON ÇOK-ADIMLI ZİNCİR (Plan C): büyük BUILD isteği →
## Decomposer (alt görevler) → her görev için çoklu rol hattı
## (Architect→CodeEngineer→Reviewer) → kod çıkar → SENKRON çekirdek
## (verify→HITL→Executor) → sıradaki görev. Sonuç 'pipeline_completed'
## ile gelir (stage="build_plan"; paths[] + failed_tasks[]).
## Kısmi başarısızlık: o görev failed_tasks'e girer, döngü sürer.
## HITL onay isterse döngü DURUR (kısmi sonuç + needs_approval).
func run_build_plan(
	goal_title: String, instruction: String, model: String = "",
	project_context: String = ""
) -> bool:
	if _bridge == null:
		_emit_done(_stage("bridge", false, "Canlı köprü bağlı değil"))
		return false
	var router: AIProviderRouter = _bridge.router()
	if router == null:
		_emit_done(_stage(
			"bridge", false, "Router yok — çok-adımlı plan çalışamaz"
		))
		return false

	_chat_mode = false
	_bp_active = true
	_bp_goal = instruction
	_bp_model = model
	_bp_project = project_context
	_bp_tasks = []
	_bp_idx = 0
	_bp_paths = []
	_bp_failed = []

	# Yardımcı köprü: decomposer + zincir SIRAYLA kullanır (tek köprü,
	# çakışmasız — decomposer biter, sonra zincir başlar).
	_aux_bridge = AIAgentLiveBridge.new()
	add_child(_aux_bridge)
	_aux_bridge.attach_router(router)

	_decomposer = AIPlanDecomposer.new()
	add_child(_decomposer)
	_decomposer.attach_bridge(_aux_bridge)
	_decomposer.decomposed.connect(_on_decomposed)

	_chain = AIRoleChainRunner.new()
	add_child(_chain)
	_chain.attach_bridge(_aux_bridge)
	_chain.chain_progress.connect(_on_chain_progress)
	_chain.chain_completed.connect(_on_chain_completed)

	pipeline_progress.emit("İstek alt görevlere bölünüyor...")
	return _decomposer.decompose(instruction, model, _bp_project)


func _on_chain_progress(step: String) -> void:
	pipeline_progress.emit(step)


func _on_decomposed(tasks: Array) -> void:
	var goal: AIPlanNode = _planner.start_plan(_bp_goal)
	var milestone: AIPlanNode = _planner.add_milestone("Üretim", goal.id)
	for t in tasks:
		var title: String = str(t.get("title", "")).strip_edges()
		var target: String = str(t.get("target_file", "")).strip_edges()
		if title.is_empty() or target.is_empty():
			continue
		var node: AIPlanNode = _planner.add_task(
			title, milestone.id, "CodeEngineer"
		)
		_planner.add_action("Yaz: " + target, node.id)
		_bp_tasks.append({
			"title": title,
			"target_file": target,
			"node_id": node.id,
		})
	if _bp_tasks.is_empty():
		_finalize_build_plan()
		return
	pipeline_progress.emit(
		"%d alt görev bulundu" % _bp_tasks.size()
	)
	_run_next_task()


func _run_next_task() -> void:
	if _bp_idx >= _bp_tasks.size():
		_finalize_build_plan()
		return
	var t: Dictionary = _bp_tasks[_bp_idx]
	pipeline_progress.emit("Görev %d/%d: %s" % [
		_bp_idx + 1, _bp_tasks.size(), str(t["title"])
	])
	var instruction: String = (
		"ALT GÖREV: " + str(t["title"]) + "\n"
		+ "GENEL HEDEF: " + _bp_goal + "\n"
		+ "SADECE bu alt görev için tek dosyalık, tam ve geçerli "
		+ "GDScript üret; markdown kod bloğunda ver, açıklama yazma."
	)
	if not _bp_project.strip_edges().is_empty():
		instruction += "\n\n" + _bp_project
	_chain.run(instruction, _bp_model)


func _on_chain_completed(res: Dictionary) -> void:
	if not _bp_active:
		return
	var t: Dictionary = _bp_tasks[_bp_idx]
	if bool(res.get("ok", false)):
		var applied: Dictionary = apply_generated_code(
			str(t["target_file"]), str(res.get("content", "")),
			str(res.get("role_name", "CodeEngineer"))
		)
		if bool(applied.get("needs_approval", false)):
			# HITL kapısı — döngü durur, şu ana kadarki kısmi sonuç.
			var d: Dictionary = _stage(
				"hitl", false,
				"İnsan onayı bekleniyor: " + str(applied.get("message", ""))
			)
			d["needs_approval"] = true
			d["paths"] = _bp_paths.duplicate()
			d["failed_tasks"] = _bp_failed.duplicate()
			_bp_active = false
			_emit_done(d)
			return
		if bool(applied.get("ok", false)):
			_planner.mark_completed(str(t["node_id"]))
			_bp_paths.append(str(applied.get("path", t["target_file"])))
		else:
			_bp_failed.append({
				"title": str(t["title"]),
				"reason": str(applied.get("message", "")),
			})
	else:
		_bp_failed.append({
			"title": str(t["title"]),
			"reason": str(res.get("status_note", "")),
		})
	_bp_idx += 1
	_run_next_task()


func _finalize_build_plan() -> void:
	_bp_active = false
	var done: int = _bp_paths.size()
	var fail: int = _bp_failed.size()
	var total: int = _bp_tasks.size()
	var ok: bool = fail == 0 and done > 0
	var msg: String
	if done == 0:
		msg = "Hiçbir alt görev üretilemedi"
	elif fail == 0:
		msg = "%d/%d alt görev tamamlandı" % [done, total]
	else:
		msg = "%d/%d tamam, %d başarısız" % [done, total, fail]
	var d: Dictionary = _stage("build_plan", ok, msg)
	d["paths"] = _bp_paths.duplicate()
	d["failed_tasks"] = _bp_failed.duplicate()
	d["plan_progress"] = _planner.progress()
	_emit_done(d)


func _on_thought(thought: Dictionary) -> void:
	if not bool(thought.get("ok", false)):
		_emit_done(_stage(
			"llm", false,
			"LLM cevabı alınamadı: " + str(thought.get("status_note", ""))
		))
		return
	if _chat_mode:
		var chat: Dictionary = _stage(
			"chat", true, str(thought.get("content", ""))
		)
		_emit_done(chat)
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
