@tool
extends SceneTree

## ÇOK-ADIMLI PLAN koşturucu — Plan C canlı kanıtı.
##
## büyük istek → Decomposer (CANLI DeepSeek alt görevler) → her görev
## için çoklu rol hattı (Architect→CodeEngineer→Reviewer, CANLI) →
## Verifier → HITL → Executor (GERÇEK dosya yazımı). Sonunda yazılan
## tüm dosyalar diskten okunup gösterilir.
##
## DEEPSEEK_KEY=... godot --headless --path . \
##   --script res://tools/build_plan_runner.gd

const Bridge := preload(
	"res://addons/ai_assistant/pilot_cell/agent_live_bridge.gd"
)
const Orch := preload(
	"res://addons/ai_assistant/pilot_cell/pipeline_orchestrator.gd"
)

const GOAL: String = (
	"Basit bir oyun mantığı: bir skor sayacı ve bir can (health) "
	+ "sistemi. Skor artırma ve hasar alma fonksiyonları olsun."
)

var _orch: Node = null
var _done: bool = false
var _success: bool = false
var _started: bool = false
var _elapsed: float = 0.0


func _initialize() -> void:
	var key: String = OS.get_environment("DEEPSEEK_KEY")
	if key.is_empty():
		print("HATA: DEEPSEEK_KEY boş")
		quit(2)
		return

	var router := AIProviderRouter.new()
	router.set_api_key(AIProviderRequest.Provider.DEEPSEEK, key)

	var bridge := Bridge.new()
	get_root().add_child(bridge)
	bridge.attach_router(router)

	_orch = Orch.new()
	get_root().add_child(_orch)
	_orch.attach_bridge(bridge)
	_orch.pipeline_progress.connect(func(s: String) -> void:
		print("  [adım] " + s)
	)
	_orch.pipeline_completed.connect(_on_done)


func _begin() -> void:
	print("=== ÇOK-ADIMLI PLAN BAŞLIYOR ===")
	var proj: String = AIProjectScanner.new().project_summary()
	var ok: bool = _orch.run_build_plan(GOAL, GOAL, "", proj)
	if not ok:
		print("HATA: run_build_plan başlatılamadı")


func _on_done(result: Dictionary) -> void:
	print("=== PLAN SONUCU ===")
	print("  ok=" + str(result.get("ok", false)))
	print("  stage=" + str(result.get("stage", "")))
	print("  message=" + str(result.get("message", "")))
	var paths: Array = result.get("paths", [])
	var failed: Array = result.get("failed_tasks", [])
	for ft in failed:
		print("  BAŞARISIZ: %s — %s" % [
			str(ft.get("title", "")), str(ft.get("reason", "")),
		])
	var read_count: int = 0
	for p in paths:
		if FileAccess.file_exists(str(p)):
			var f := FileAccess.open(str(p), FileAccess.READ)
			if f != null:
				print("  --- DİSKTEN OKUNAN: " + str(p) + " ---")
				print(f.get_as_text())
				f.close()
				read_count += 1
	# Çok-adım kanıtı: ≥2 dosya gerçekten yazılmış olmalı.
	_success = (
		bool(result.get("ok", false))
		and read_count >= 2
		and failed.is_empty()
	)
	if _success:
		print("SONUC: PLAN_TAMAM (%d dosya)" % read_count)
	else:
		print("SONUC: PLAN_BASARISIZ (%d dosya)" % read_count)
	_done = true


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _started:
		_started = true
		_begin()
		return false
	if _done:
		# Başarısız → sıfır-olmayan kod (regresyon otomatik yakalansın).
		quit(0 if _success else 1)
		return true
	if _elapsed > 180.0:
		print("HATA: 180s zaman aşımı")
		print("SONUC: PLAN_ZAMAN_ASIMI")
		quit(4)
		return true
	return false
