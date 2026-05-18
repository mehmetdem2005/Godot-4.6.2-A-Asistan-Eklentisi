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
## Canlı görev listesi değiştiğinde — UI "Görevler" paneli buna bağlanır.
signal tasks_updated(registry: Array)

## Dinamik görev üretimi sınırları (kaçak/sonsuz döngü ve maliyet
## koruması — profesyonel disiplin).
const MAX_TOTAL_TASKS: int = 24
const MAX_REPAIRS_PER_FILE: int = 2
const MAX_ARCHITECT_SPAWN: int = 6

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
var _bp_paths: Array = []
var _bp_failed: Array = []
var _bp_project: String = ""
var _bp_classes: Array = []
# Dinamik görev grafiği: kuyruk (bekleyen) + registry (hepsi, canlı
# durum — panel kaynağı). _bp_current işlenen görev.
var _bp_queue: Array = []
var _bp_registry: Array = []
var _bp_current: Dictionary = {}
var _bp_seq: int = 0
var _bp_spawned: int = 0
var _bp_milestone_id: String = ""


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


## Sahne (.tscn) metnini hafif doğrular — saf, ağsız, test edilebilir.
## Godot .tscn metin formatı: `[gd_scene ...]` başlığı + en az bir
## `[node ...]`. Sahte PASS yok — işaret yoksa dürüst FAIL.
## Dönen: {ok: bool, reason: String}
func verify_scene_text(text: String) -> Dictionary:
	var t: String = text.strip_edges()
	if t.is_empty():
		return {"ok": false, "reason": "Sahne içeriği boş"}
	if not t.begins_with("[gd_scene"):
		return {
			"ok": false,
			"reason": "Geçerli .tscn değil ([gd_scene başlığı yok)",
		}
	if not t.contains("[node "):
		return {
			"ok": false,
			"reason": "Sahnede düğüm yok ([node bölümü bulunamadı)",
		}
	return {"ok": true, "reason": ""}


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
	# --- Kod çözümleme: CERRAHI (SEARCH/REPLACE) vs TAM dosya ---
	# LLM "<<<<<<< SEARCH" bloğu verdiyse tüm dosyayı YENİDEN YAZMA —
	# sadece eşleşen bölümü değiştir (kullanıcı isteği: "her seferinde
	# kodu baştan yazma, sadece ilgili kısmı değiştir"). Mock policy:
	# eşleşme yoksa/dosya yoksa sahte başarı yok — dürüst RET.
	var surgical: bool = false
	var blocks_applied: int = 0
	var code: String
	if raw_content.contains(AISearchReplaceHandler.SEARCH_MARKER):
		var rd: Dictionary = _executor.read_existing(target_path)
		if not bool(rd["ok"]):
			return _stage(
				"surgical", false,
				"Cerrahi düzenleme: hedef dosya okunamadı (%s) — var "
				% str(rd["error"])
				+ "olmayan dosya için SEARCH/REPLACE değil tam içerik üret"
			)
		var existing: String = str(rd["content"])
		var handler := AISearchReplaceHandler.new()
		var ar: AISearchReplaceHandler.ApplyResult = handler.process(
			existing, raw_content
		)
		if not ar.ok:
			var reason: String = ar.rejected_reason
			if reason.is_empty():
				reason = ar.error
			var dsr: Dictionary = _stage(
				"surgical", false, "Cerrahi düzenleme reddedildi: " + reason
			)
			dsr["verify_detail"] = reason
			dsr["failed_code"] = existing
			return dsr
		surgical = true
		blocks_applied = ar.blocks_applied
		code = ar.new_content
	else:
		code = extract_code(raw_content)
	if code.strip_edges().is_empty():
		return _stage("extract", false, "LLM çıktısından kod çıkarılamadı")

	# --- Üretilen-yazım kapısı (AAA: yalnız res://game/ altı; elle
	# yazılan kod / addons / project.godot ek olarak korunur) ---
	var pg: Dictionary = AIPathGuard.check_generated_write(target_path)
	if not bool(pg["allowed"]):
		return _stage("path_guard", false, str(pg["reason"]))

	# --- Verifier --- (.tscn = sahne metni; GDScript derleyicisinden
	# geçirmek ANLAMSIZ → sahneye özel hafif yapısal doğrulama)
	pipeline_progress.emit("Doğrulanıyor...")
	if target_path.ends_with(".tscn"):
		var sv: Dictionary = verify_scene_text(code)
		if not bool(sv["ok"]):
			var ds: Dictionary = _stage(
				"verify", false,
				"Sahne doğrulaması başarısız: " + str(sv["reason"])
			)
			ds["verify_level"] = "scene"
			ds["verify_detail"] = str(sv["reason"])
			ds["failed_code"] = code
			return ds
	else:
		var vr: Dictionary = _verifier.verify(code)
		if not bool(vr["passed"]):
			var detail: String = _verify_detail(vr)
			var d0: Dictionary = _stage(
				"verify", false,
				"Doğrulama başarısız (%s): %s" % [
					str(vr["failed_level"]), detail
				]
			)
			d0["verify_level"] = str(vr["failed_level"])
			d0["verify_detail"] = detail
			d0["failed_code"] = code
			return d0

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
	out["surgical"] = surgical
	out["blocks_applied"] = blocks_applied
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
	_bp_paths = []
	_bp_failed = []
	_bp_classes = []
	_bp_queue = []
	_bp_registry = []
	_bp_current = {}
	_bp_seq = 0
	_bp_spawned = 0
	_bp_milestone_id = ""

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
	_bp_milestone_id = milestone.id
	for t in tasks:
		var title: String = str(t.get("title", "")).strip_edges()
		var target: String = str(t.get("target_file", "")).strip_edges()
		if title.is_empty() or target.is_empty():
			continue
		_enqueue_task(title, target, "gen", 0, "", "")
	if _bp_registry.is_empty():
		_finalize_build_plan()
		return
	pipeline_progress.emit(
		"%d alt görev bulundu" % _bp_registry.size()
	)
	_emit_tasks()
	_run_next_task()


## Bir görevi planner ağacına + kuyruğa + registry'ye ekler.
## Dönen: eklendi mi (toplam üst sınır aşılırsa false — kaçak koruma).
func _enqueue_task(
	title: String, target: String, kind: String,
	attempt: int, error: String, failed_code: String
) -> bool:
	if _bp_seq >= MAX_TOTAL_TASKS:
		return false
	_bp_seq += 1
	var node: AIPlanNode = _planner.add_task(
		title, _bp_milestone_id, "CodeEngineer"
	)
	_planner.add_action("Yaz: " + target, node.id)
	var entry: Dictionary = {
		"id": _bp_seq,
		"title": title,
		"target_file": target,
		"kind": kind,
		"attempt": attempt,
		"status": "bekliyor",
		"error": error,
		"failed_code": failed_code,
		"node_id": node.id,
	}
	_bp_registry.append(entry)
	_bp_queue.append(entry)
	return true


func _run_next_task() -> void:
	if _bp_queue.is_empty():
		_finalize_build_plan()
		return
	_bp_current = _bp_queue.pop_front()
	_bp_current["status"] = "çalışıyor"
	var total: int = _bp_registry.size()
	var label: String = "Görev %d/%d: %s" % [
		int(_bp_current["id"]), total, str(_bp_current["title"])
	]
	if str(_bp_current["kind"]) == "repair":
		label = "Onarım %d/%d: %s" % [
			int(_bp_current["id"]), total, str(_bp_current["title"])
		]
	pipeline_progress.emit(label)
	_emit_tasks()
	var instruction: String = _build_task_instruction(_bp_current)
	var mode: String = (
		"repair" if str(_bp_current["kind"]) == "repair" else "full"
	)
	_chain.run(instruction, _bp_model, mode)


## Göreve göre LLM talimatı kurar (üretim vs onarım).
func _build_task_instruction(t: Dictionary) -> String:
	var instruction: String
	if str(t["kind"]) == "repair":
		var rtarget: String = str(t["target_file"])
		if rtarget.ends_with(".tscn"):
			instruction = (
				"ONARIM GÖREVİ. Aşağıdaki SAHNE (.tscn) doğrulamadan "
				+ "GEÇMEDİ.\nHEDEF DOSYA: " + rtarget + "\n"
				+ "DOĞRULAMA HATASI: " + str(t["error"]) + "\n"
				+ "HATALI SAHNE:\n```\n" + str(t["failed_code"]) + "\n```\n"
				+ "Hatayı gider; SADECE geçerli .tscn metni ver "
				+ "(markdown/açıklama YAZMA).\n\n"
				+ AIRolePrompts.TSCN_CONTRACT
			)
		else:
			instruction = (
				"ONARIM GÖREVİ. Aşağıdaki dosya Godot 4.6 derlemesinden "
				+ "GEÇMEDİ.\nHEDEF DOSYA: " + rtarget + "\n"
				+ "DOĞRULAMA HATASI: " + str(t["error"]) + "\n"
				+ "HATALI KOD:\n```\n" + str(t["failed_code"]) + "\n```\n"
				+ "Godot 4.6 API kurallarına UYARAK hatayı gider; TAM, "
				+ "derlenebilir düzeltilmiş dosyayı tek parça ver."
			)
	else:
		var target: String = str(t["target_file"])
		if target.ends_with(".tscn"):
			instruction = (
				"ALT GÖREV: " + str(t["title"]) + "\n"
				+ "GENEL HEDEF: " + _bp_goal + "\n"
				+ "HEDEF DOSYA: " + target + "\n\n"
				+ AIRolePrompts.TSCN_CONTRACT
			)
		else:
			instruction = (
				"ALT GÖREV: " + str(t["title"]) + "\n"
				+ "GENEL HEDEF: " + _bp_goal + "\n"
				+ "HEDEF DOSYA: " + target + "\n"
				+ "SADECE bu alt görev için tek dosyalık, tam ve geçerli "
				+ "GDScript üret; markdown kod bloğunda ver, açıklama "
				+ "yazma."
			)
	if not _bp_classes.is_empty():
		instruction += (
			"\n\nZATEN ÜRETİLEN SINIFLAR (atıf gerekiyorsa BU gerçek "
			+ "adları kullan, uydurma):\n" + "\n".join(_bp_classes)
		)
	if not _bp_project.strip_edges().is_empty():
		instruction += "\n\n" + _bp_project
	return instruction


## Canlı görev listesi anlık görüntüsü — UI paneli + test için.
func task_registry() -> Array:
	var out: Array = []
	for e in _bp_registry:
		out.append({
			"id": int(e["id"]),
			"title": str(e["title"]),
			"target_file": str(e["target_file"]),
			"kind": str(e["kind"]),
			"attempt": int(e["attempt"]),
			"status": str(e["status"]),
			"error": str(e["error"]),
		})
	return out


func _emit_tasks() -> void:
	tasks_updated.emit(task_registry())


## Verifier sonucundaki BAŞARISIZ seviyenin gerçek mesajını çıkarır
## (onarım turuna ve panele beslenen otoriter tanı).
func _verify_detail(vr: Dictionary) -> String:
	for r in vr.get("results", []):
		var vrr: AIVerificationResult = r
		if vrr.outcome == AIVerificationResult.Outcome.FAIL:
			if not vrr.message.strip_edges().is_empty():
				return vrr.message
	return "Godot 4.6 derlemesi geçmedi (ayrıntı motor Output'unda)"


## Üretilen koddan class_name'i çıkarır (varsa). Görevler arası
## tutarlılık için — sonraki görev gerçek sınıfa atıf yapabilsin.
func _scan_class_name(code: String) -> String:
	for raw_line in code.split("\n"):
		var line: String = str(raw_line).strip_edges()
		if line.begins_with("class_name "):
			var rest: String = line.substr(11).strip_edges()
			var stop: int = rest.find(" ")
			if stop != -1:
				rest = rest.substr(0, stop)
			return rest.strip_edges()
	return ""


func _on_chain_completed(res: Dictionary) -> void:
	if not _bp_active:
		return
	var t: Dictionary = _bp_current
	# Architect "EK DOSYA:" önerilerini dinamik göreve çevir (yalnız
	# tam zincirde — onarımda Architect yok).
	if str(t["kind"]) != "repair":
		_spawn_from_architect(res)
	if bool(res.get("ok", false)):
		var applied: Dictionary = apply_generated_code(
			str(t["target_file"]), str(res.get("content", "")),
			str(res.get("role_name", "CodeEngineer"))
		)
		if bool(applied.get("needs_approval", false)):
			t["status"] = "onay-bekliyor"
			t["error"] = str(applied.get("message", ""))
			var d: Dictionary = _stage(
				"hitl", false,
				"İnsan onayı bekleniyor: " + str(applied.get("message", ""))
			)
			d["needs_approval"] = true
			d["paths"] = _bp_paths.duplicate()
			d["failed_tasks"] = _bp_failed.duplicate()
			d["tasks"] = task_registry()
			_bp_active = false
			_emit_tasks()
			_emit_done(d)
			return
		if bool(applied.get("ok", false)):
			t["status"] = "tamam"
			_planner.mark_completed(str(t["node_id"]))
			_bp_paths.append(str(applied.get("path", t["target_file"])))
			var cls: String = _scan_class_name(
				extract_code(str(res.get("content", "")))
			)
			if not cls.is_empty():
				_bp_classes.append(
					"- %s (%s)" % [cls, str(t["target_file"])]
				)
		else:
			_handle_task_failure(
				t, str(applied.get("message", "")),
				str(applied.get("failed_code", ""))
			)
	else:
		_handle_task_failure(t, str(res.get("status_note", "")), "")
	_emit_tasks()
	_run_next_task()


## Başarısız görevi: sınır içinde dinamik ONARIM görevi doğur,
## sınır aşılırsa kalıcı başarısız işaretle (kaçak koruması).
func _handle_task_failure(
	t: Dictionary, reason: String, failed_code: String
) -> void:
	if (int(t["attempt"]) < MAX_REPAIRS_PER_FILE
			and _bp_seq < MAX_TOTAL_TASKS
			and not failed_code.strip_edges().is_empty()):
		t["status"] = "onarılıyor"
		t["error"] = reason
		_enqueue_task(
			"Onar: " + str(t["title"]), str(t["target_file"]),
			"repair", int(t["attempt"]) + 1, reason, failed_code
		)
		pipeline_progress.emit(
			"Onarım görevi eklendi: " + str(t["title"])
		)
	else:
		t["status"] = "başarısız"
		t["error"] = reason
		_bp_failed.append({
			"title": str(t["title"]),
			"reason": reason,
		})


## Architect çıktısındaki `EK DOSYA: ad.gd — amaç` satırlarını
## yeni dinamik görevlere çevirir (sınırlı, tekrarsız).
func _spawn_from_architect(res: Dictionary) -> void:
	var arch_name: String = AICellRoles.role_name(
		AICellRoles.Role.ARCHITECT
	)
	for entry in res.get("transcript", []):
		if str(entry.get("role", "")) != arch_name:
			continue
		for raw_line in str(entry.get("content", "")).split("\n"):
			var line: String = str(raw_line).strip_edges()
			if not line.begins_with("EK DOSYA:"):
				continue
			if (_bp_spawned >= MAX_ARCHITECT_SPAWN
					or _bp_seq >= MAX_TOTAL_TASKS):
				return
			var body: String = line.substr(9).strip_edges()
			var sep: int = body.find("—")
			if sep == -1:
				sep = body.find(" - ")
			var fname: String = body
			var purpose: String = body
			if sep != -1:
				fname = body.substr(0, sep).strip_edges()
				purpose = body.substr(sep + 1).strip_edges()
			var target: String = _decomposer.sanitize_target(
				fname, purpose
			)
			if _has_target(target):
				continue
			if _enqueue_task(
				(purpose if not purpose.is_empty() else fname),
				target, "gen", 0, "", ""
			):
				_bp_spawned += 1
				pipeline_progress.emit(
					"Architect ek görev önerdi: " + target
				)


func _has_target(target: String) -> bool:
	for e in _bp_registry:
		if str(e["target_file"]) == target:
			return true
	return false


func _finalize_build_plan() -> void:
	_bp_active = false
	var done: int = 0
	var fail: int = 0
	for e in _bp_registry:
		if str(e["status"]) == "tamam":
			done += 1
		elif str(e["status"]) == "başarısız":
			fail += 1
	var total: int = _bp_registry.size()
	var ok: bool = fail == 0 and done > 0
	var msg: String
	if done == 0:
		msg = "Hiçbir alt görev üretilemedi"
	elif fail == 0:
		msg = "%d/%d görev tamamlandı" % [done, total]
	else:
		msg = "%d/%d tamam, %d başarısız" % [done, total, fail]
	var d: Dictionary = _stage("build_plan", ok, msg)
	d["paths"] = _bp_paths.duplicate()
	d["failed_tasks"] = _bp_failed.duplicate()
	d["plan_progress"] = _planner.progress()
	d["tasks"] = task_registry()
	_emit_tasks()
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
