@tool
class_name AIPipelineOrchestratorTest
extends RefCounted

## Uçtan Uca Orkestratör Self-Test (Aşama 4c).
##
## Doğrular: kod çıkarma, Planner entegrasyonu, SENKRON çekirdek
## (verify → HITL kapısı → Executor gerçek yazım), HITL kapısının
## ARTIK gerçekten çağrıldığı ve engelleyebildiği (Executor↔HITL
## bağı), geçersiz kodun yazılmadığı (mock policy).
##
## Gerçek LLM ağ adımı ASENKRON — burada değil; tools/e2e_runner.gd'de
## gerçek anahtarla kanıtlanır (devir §5.4).

const VALID_CODE: String = (
	"extends Node\n\n\nfunc _ready() -> void:\n\tprint(\"merhaba\")\n"
)


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("E2E: Kod", _test_extract_fenced()))
	results.append(_b("E2E: Kod", _test_extract_plain()))
	results.append(_b("E2E: Plan", _test_build_plan()))
	results.append(_b("E2E: Çekirdek", _test_apply_valid_executes()))
	results.append(_b("E2E: Çekirdek", _test_apply_invalid_blocked()))
	results.append(_b("E2E: Çekirdek", _test_apply_empty()))
	results.append(_b("E2E: HITL", _test_hitl_gate_blocks()))
	results.append(_b("E2E: Durum", _test_no_bridge()))
	results.append(_b("E2E: Sohbet", _test_chat_no_bridge()))
	results.append(_b("E2E: Plan", _test_build_plan_no_bridge()))
	results.append(_b("E2E: Plan", _test_build_plan_no_router()))
	results.append(_b("E2E: Plan", _test_scan_class_name()))
	results.append(_b("E2E: Dinamik", _test_enqueue_registry_cap()))
	results.append(_b("E2E: Dinamik", _test_repair_spawn_and_bound()))
	results.append(_b("E2E: Dinamik", _test_spawn_from_architect()))
	results.append(_b("E2E: Dinamik", _test_status_color_consistency()))
	results.append(_b("E2E: Sahne", _test_verify_scene_text()))
	results.append(_b("E2E: Sahne", _test_scene_target_skips_gd_verify()))
	results.append(_b("E2E: Sahne", _test_scene_repair_instruction()))
	return results


static func _test_scene_repair_instruction() -> Dictionary:
	var name := ".tscn onarım talimatı sahne-bilinçli (GDScript değil)"
	var o := _new()
	var scene_rep: String = o._build_task_instruction({
		"kind": "repair", "title": "Ana Sahne",
		"target_file": "res://game/scenes/main.tscn",
		"error": "[gd_scene başlığı yok", "failed_code": "[node x]",
	})
	var gd_rep: String = o._build_task_instruction({
		"kind": "repair", "title": "Oyuncu",
		"target_file": "res://game/scripts/player.gd",
		"error": "parse error", "failed_code": "func (",
	})
	o.free()
	if not scene_rep.contains("SAHNE") or not scene_rep.contains("[gd_scene"):
		return _fail(name, "sahne onarımı sahne dilini kullanmalı")
	if scene_rep.contains("GDScript derlemesi"):
		return _fail(name, "sahne onarımı GDScript çerçevesi kullanmamalı")
	if not gd_rep.contains("derlenebilir"):
		return _fail(name, ".gd onarımı GDScript çerçevesini korumalı")
	return _ok(name)


static func _test_verify_scene_text() -> Dictionary:
	var name := "verify_scene_text geçerli .tscn'i kabul, bozuğu reddeder"
	var o := _new()
	var good := (
		"[gd_scene load_steps=2 format=3]\n\n"
		+ "[ext_resource type=\"Script\" "
		+ "path=\"res://game/scripts/player.gd\" id=\"1\"]\n\n"
		+ "[node name=\"Root\" type=\"Node2D\"]\n"
		+ "script = ExtResource(\"1\")\n"
	)
	var ok_res: Dictionary = o.verify_scene_text(good)
	var empty_res: Dictionary = o.verify_scene_text("   ")
	var no_hdr: Dictionary = o.verify_scene_text("[node name=\"X\"]")
	var no_node: Dictionary = o.verify_scene_text(
		"[gd_scene format=3]\n"
	)
	o.free()
	if not bool(ok_res["ok"]):
		return _fail(name, "geçerli sahne reddedildi: "
			+ str(ok_res["reason"]))
	if bool(empty_res["ok"]):
		return _fail(name, "boş sahne kabul edildi")
	if bool(no_hdr["ok"]):
		return _fail(name, "[gd_scene başlığı yokken kabul edildi")
	if bool(no_node["ok"]):
		return _fail(name, "düğümsüz sahne kabul edildi")
	return _ok(name)


static func _test_scene_target_skips_gd_verify() -> Dictionary:
	var name := ".tscn hedefi GDScript derleyicisine takılmaz, yazılır"
	var o := _new()
	var tpath := "res://game/scenes/__e2e_scene__.tscn"
	var scene := (
		"[gd_scene format=3]\n\n[node name=\"Root\" type=\"Node2D\"]\n"
	)
	var r: Dictionary = o.apply_generated_code(tpath, scene, "CodeEngineer")
	o.free()
	var wrote: bool = FileAccess.file_exists(tpath)
	if wrote:
		DirAccess.remove_absolute(tpath)
	if str(r["stage"]) != "executed" or not bool(r["ok"]):
		return _fail(name, "sahne yazılmalıydı: %s / %s" % [
			str(r["stage"]), str(r["message"])])
	if not wrote:
		return _fail(name, ".tscn res://game/scenes/ altına yazılmalıydı")
	return _ok(name)


## Planner milestone'u hazır, dinamik kuyruğu test edilebilir orkestratör.
static func _planned() -> AIPipelineOrchestrator:
	var o := AIPipelineOrchestrator.new()
	var g: AIPlanNode = o._planner.start_plan("hedef")
	var m: AIPlanNode = o._planner.add_milestone("Üretim", g.id)
	o._bp_milestone_id = m.id
	o._bp_active = true
	return o


static func _test_enqueue_registry_cap() -> Dictionary:
	var name := "Görev kuyruğu MAX_TOTAL_TASKS ile sınırlı (kaçak yok)"
	var o := _planned()
	var added := 0
	for i in AIPipelineOrchestrator.MAX_TOTAL_TASKS + 8:
		if o._enqueue_task("G%d" % i, "user://u/g%d.gd" % i,
				"gen", 0, "", ""):
			added += 1
	var reg: Array = o.task_registry()
	o.free()
	if added != AIPipelineOrchestrator.MAX_TOTAL_TASKS:
		return _fail(name, "sınır uygulanmadı: %d" % added)
	if reg.size() != AIPipelineOrchestrator.MAX_TOTAL_TASKS:
		return _fail(name, "registry sınırı yanlış: %d" % reg.size())
	if str(reg[0]["status"]) != "bekliyor":
		return _fail(name, "yeni görev 'bekliyor' olmalı")
	return _ok(name)


static func _test_repair_spawn_and_bound() -> Dictionary:
	var name := "Hata → sınırlı onarım görevi, sınırda kalıcı başarısız"
	var o := _planned()
	o._enqueue_task("Oyuncu", "user://u/p.gd", "gen", 0, "", "")
	var cur: Dictionary = o._bp_queue.pop_front()
	# 1. hata: onarım görevi doğmalı
	o._handle_task_failure(cur, "syntactic: xx", "extends Node")
	if o._bp_queue.size() != 1:
		o.free()
		return _fail(name, "onarım görevi kuyruğa eklenmedi")
	if str(cur["status"]) != "onarılıyor":
		o.free()
		return _fail(name, "kaynak görev 'onarılıyor' olmalı")
	var rep: Dictionary = o._bp_queue[0]
	if str(rep["kind"]) != "repair" or int(rep["attempt"]) != 1:
		o.free()
		return _fail(name, "onarım görevi kind/attempt yanlış")
	# Sınırda (attempt=MAX): artık başarısız, _bp_failed dolar
	var maxed: Dictionary = {
		"title": "Oyuncu", "target_file": "user://u/p.gd",
		"kind": "repair",
		"attempt": AIPipelineOrchestrator.MAX_REPAIRS_PER_FILE,
		"status": "çalışıyor", "error": "", "node_id": "x",
	}
	o._handle_task_failure(maxed, "yine hata", "extends Node")
	o.free()
	if str(maxed["status"]) != "başarısız":
		return _fail(name, "sınırda 'başarısız' olmalı")
	return _ok(name)


static func _test_spawn_from_architect() -> Dictionary:
	var name := "Architect 'EK DOSYA' satırı dinamik görev doğurur (tekrarsız)"
	var o := _planned()
	o._decomposer = AIPlanDecomposer.new()
	var res := {
		"transcript": [
			{"role": "Architect", "content":
				"Yapı:\nEK DOSYA: enemy.gd — Düşman AI\n"
				+ "EK DOSYA: enemy.gd — kopya (aynı hedef, atlanmalı)"},
		],
	}
	o._spawn_from_architect(res)
	var reg: Array = o.task_registry()
	o.free()
	if reg.size() != 1:
		return _fail(name, "tek görev (dedup) beklendi: %d" % reg.size())
	if not str(reg[0]["target_file"]).begins_with("res://game/"):
		return _fail(name, "güvenli AAA hedef yolu üretilmeli")
	return _ok(name)


static func _test_status_color_consistency() -> Dictionary:
	var name := "Tüm görev durumları UI renk haritasında tanımlı"
	for st in ["bekliyor", "çalışıyor", "onarılıyor", "onay-bekliyor",
			"tamam", "başarısız"]:
		if not AIStudioScreen.STATUS_COLORS.has(st):
			return _fail(name, "UI renk eksik: " + st)
	return _ok(name)


static func _test_scan_class_name() -> Dictionary:
	var name := "class_name çıkarılır (görevler arası tutarlılık)"
	var o := _new()
	var code := "@tool\nclass_name SceneData\nextends Resource\n"
	var got: String = o._scan_class_name(code)
	if got != "SceneData":
		o.free()
		return _fail(name, "class_name yanlış: '%s'" % got)
	# class_name yoksa boş (uydurma yok).
	if o._scan_class_name("extends Node\nfunc _ready():\n\tpass") != "":
		o.free()
		return _fail(name, "class_name yokken boş dönmeli")
	o.free()
	return _ok(name)


static func _test_build_plan_no_bridge() -> Dictionary:
	var name := "Köprüsüz run_build_plan dürüst başarısızlık"
	var o := _new()
	var captured: Array = []
	o.pipeline_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	var started: bool = o.run_build_plan("hedef", "envanter oyunu yap")
	o.free()
	if started:
		return _fail(name, "köprü yokken başlamamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "bridge aşamasında dürüst hata dönmeli")
	return _ok(name)


static func _test_build_plan_no_router() -> Dictionary:
	var name := "Router'sız köprüde run_build_plan dürüst durur"
	var o := _new()
	var bridge := AIAgentLiveBridge.new()
	o.attach_bridge(bridge)
	var captured: Array = []
	o.pipeline_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	var started: bool = o.run_build_plan("hedef", "oyun yap")
	bridge.free()
	o.free()
	if started:
		return _fail(name, "router yokken başlamamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "router yok → dürüst hata")
	if str(captured[0]["stage"]) != "bridge":
		return _fail(name, "bridge aşamasında durmalı: "
			+ str(captured[0]["stage"]))
	return _ok(name)


static func _test_chat_no_bridge() -> Dictionary:
	var name := "Köprüsüz run_chat dürüst başarısızlık"
	var o := _new()
	var captured: Array = []
	o.pipeline_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	var started: bool = o.run_chat("merhaba")
	o.free()
	if started:
		return _fail(name, "köprü yokken başlamamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "bridge aşamasında dürüst hata dönmeli")
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _new() -> AIPipelineOrchestrator:
	return AIPipelineOrchestrator.new()


# ============================================================
# KOD ÇIKARMA
# ============================================================

static func _test_extract_fenced() -> Dictionary:
	var name := "Markdown çitli koddan kod çıkarılır"
	var o := _new()
	var raw := "İşte kod:\n```gdscript\nextends Node\n```\nbitti"
	var code: String = o.extract_code(raw)
	o.free()
	if code != "extends Node":
		return _fail(name, "çit soyulmadı: '%s'" % code)
	return _ok(name)


static func _test_extract_plain() -> Dictionary:
	var name := "Çitsiz içerik aynen döner"
	var o := _new()
	var code: String = o.extract_code("extends Node")
	o.free()
	if code != "extends Node":
		return _fail(name, "düz metin korunmalı")
	return _ok(name)


# ============================================================
# PLANNER ENTEGRASYONU
# ============================================================

static func _test_build_plan() -> Dictionary:
	var name := "Planner zinciri ACTION düğümü üretir"
	var o := _new()
	var node: AIPlanNode = o.build_plan("Merhaba oyunu", "hello.gd yaz")
	var ok: bool = node != null and node.level == AIPlanNode.Level.ACTION
	o.free()
	if not ok:
		return _fail(name, "ACTION seviyeli düğüm dönmeli")
	return _ok(name)


# ============================================================
# SENKRON ÇEKİRDEK
# ============================================================

static func _test_apply_valid_executes() -> Dictionary:
	var name := "Geçerli kod: verify→gate→GERÇEK yazım"
	var o := _new()
	# AAA: üretilen yazım yalnız res://game/ altına; testten sonra
	# repoyu kirletmemek için yazılan dosya temizlenir.
	var tpath := "res://game/scripts/__e2e_hello_ok__.gd"
	var r: Dictionary = o.apply_generated_code(
		tpath,
		"```gdscript\n" + VALID_CODE + "```",
		"CodeEngineer"
	)
	o.free()
	var wrote: bool = FileAccess.file_exists(tpath)
	if wrote:
		DirAccess.remove_absolute(tpath)
	if str(r["stage"]) != "executed":
		return _fail(name, "executed aşamasına ulaşmalı: " +
			str(r["stage"]) + " / " + str(r["message"]))
	if not bool(r["ok"]):
		return _fail(name, "gerçek yazım başarılı olmalı: " +
			str(r["message"]))
	if not wrote:
		return _fail(name, "dosya res://game/ altına yazılmalıydı")
	return _ok(name)


static func _test_apply_invalid_blocked() -> Dictionary:
	var name := "Geçersiz kod: verify'da durur, YAZILMAZ (mock)"
	var o := _new()
	var r: Dictionary = o.apply_generated_code(
		"res://game/scripts/__e2e_bad__.gd",
		"func ( bu gecersiz gdscript !!!",
		"CodeEngineer"
	)
	o.free()
	if bool(r["ok"]):
		return _fail(name, "geçersiz kod ok olmamalı")
	if str(r["stage"]) != "verify":
		return _fail(name, "verify aşamasında durmalı: " + str(r["stage"]))
	return _ok(name)


static func _test_apply_empty() -> Dictionary:
	var name := "Boş içerik: extract aşamasında durur"
	var o := _new()
	var r: Dictionary = o.apply_generated_code(
		"res://game/scripts/__e2e_empty__.gd", "   ```\n```  ",
		"CodeEngineer"
	)
	o.free()
	if bool(r["ok"]) or str(r["stage"]) != "extract":
		return _fail(name, "boş kod extract'ta durmalı: " + str(r["stage"]))
	return _ok(name)


# ============================================================
# HITL KAPISI — Executor↔HITL bağı kanıtı
# ============================================================

static func _test_hitl_gate_blocks() -> Dictionary:
	var name := "HITL kapısı gerçekten çağrılır ve engeller"
	var o := _new()
	# Eşiği LOW yap — normal yazma bile insan onayı istesin
	o.hitl_coordinator().set_approval_threshold(
		AIRiskAssessor.RiskLevel.LOW
	)
	var r: Dictionary = o.apply_generated_code(
		"res://game/scripts/__e2e_gated__.gd",
		"```gdscript\n" + VALID_CODE + "```",
		"CodeEngineer"
	)
	o.free()
	if str(r["stage"]) != "hitl":
		return _fail(name, "HITL aşamasında durmalı: " + str(r["stage"]))
	if bool(r["ok"]):
		return _fail(name, "onay beklerken yazılmamalı")
	if not bool(r["needs_approval"]):
		return _fail(name, "needs_approval true olmalı")
	return _ok(name)


# ============================================================
# DURUM
# ============================================================

static func _test_no_bridge() -> Dictionary:
	var name := "Köprüsüz run_task dürüst başarısızlık"
	var o := _new()
	var captured: Array = []
	o.pipeline_completed.connect(func(res: Dictionary) -> void:
		captured.append(res)
	)
	var started: bool = o.run_task(
		"hedef", "user://x.gd", "yap", AICellRoles.Role.CODE_ENGINEER
	)
	o.free()
	if started:
		return _fail(name, "köprü yokken başlamamalı")
	if captured.is_empty() or bool(captured[0]["ok"]):
		return _fail(name, "bridge aşamasında dürüst hata dönmeli")
	return _ok(name)
