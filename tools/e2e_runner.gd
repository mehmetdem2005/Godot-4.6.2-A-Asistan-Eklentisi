@tool
extends SceneTree

## UÇTAN UCA koşturucu — Aşama 4c kanıtı (devir ADIM 2c).
##
## görev → Planner → Pilot Cell (CANLI DeepSeek) → kod çıkar →
## Verifier → HITL → Executor (GERÇEK dosya yazımı). Sonunda
## yazılan dosya diskten okunup gösterilir.
##
## DEEPSEEK_KEY=... godot --headless --path . \
##   --script res://tools/e2e_runner.gd

const Bridge := preload(
	"res://addons/ai_assistant/pilot_cell/agent_live_bridge.gd"
)
const Orch := preload(
	"res://addons/ai_assistant/pilot_cell/pipeline_orchestrator.gd"
)

const OUT_PATH: String = "user://ai_assistant/e2e/merhaba.gd"

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
	print("=== UÇTAN UCA ZİNCİR BAŞLIYOR ===")
	# Dosya varsa sil — temiz kanıt
	if FileAccess.file_exists(OUT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT_PATH))
	var ok: bool = _orch.run_task(
		"Merhaba betiği üret",
		OUT_PATH,
		"SADECE şu GDScript'i markdown kod bloğunda ver, açıklama "
		+ "yapma: extends Node, sonra bir _ready fonksiyonu, içinde "
		+ "print(\"merhaba dunya\").",
		AICellRoles.Role.CODE_ENGINEER
	)
	if not ok:
		print("HATA: run_task başlatılamadı")


func _on_done(result: Dictionary) -> void:
	print("=== PIPELINE SONUCU ===")
	print("  ok=" + str(result.get("ok", false)))
	print("  stage=" + str(result.get("stage", "")))
	print("  message=" + str(result.get("message", "")))
	print("  path=" + str(result.get("path", "")))
	var wrote: bool = false
	if FileAccess.file_exists(OUT_PATH):
		var f := FileAccess.open(OUT_PATH, FileAccess.READ)
		if f != null:
			print("  --- DİSKTEN OKUNAN DOSYA ---")
			print(f.get_as_text())
			f.close()
			wrote = true
	_success = bool(result.get("ok", false)) and wrote
	if _success:
		print("SONUC: E2E_TAMAM")
	else:
		print("SONUC: E2E_BASARISIZ")
	_done = true


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _started:
		_started = true
		_begin()
		return false
	if _done:
		# Başarısız E2E sıfır-olmayan kod döndürmeli — yoksa otomatik
		# ön-kontroller regresyonu fark etmez (PR #1 inceleme notu).
		quit(0 if _success else 1)
		return true
	if _elapsed > 70.0:
		print("HATA: 70s zaman aşımı")
		print("SONUC: E2E_ZAMAN_ASIMI")
		quit(4)
		return true
	return false
