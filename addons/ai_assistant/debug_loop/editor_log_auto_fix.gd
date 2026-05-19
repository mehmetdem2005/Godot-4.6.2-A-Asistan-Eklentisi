@tool
class_name AIEditorLogAutoFix
extends Node

## EditorLogAutoFix — log izleyici + onarım yönlendiriciyi pipeline'a
## bağlayan İNCE Node köprüsü (Parça 4 canlı integration).
##
## Akış: Timer her N saniyede watcher.poll() → her hata olayı için
## router.should_repair → yola karşı dosya oku → onarım talimatı kur →
## pipeline.run_task() (mevcut LLM hattı). Mevcut HITL/Executor/repair
## sayaçları zaten devrede; circuit breaker aynı hatada döngüyü kırar.
##
## DİSİPLİN: bu sınıf İNCE — gerçek hata yakalama (watcher) ve karar
## (router) saf+test edilmiş. Burası onları zamanlama ile birleştirir;
## live editor'da kullanıcı göz ile doğrular (devir §5.4).
##
## Mock policy: pipeline yoksa sessizce uyur; çalışmıyor demez ki
## kullanıcı şaşırsın — is_active() dürüstçe false döner.

const DEFAULT_LOG_PATH: String = "user://logs/godot.log"
const TICK_SECONDS: float = 5.0

signal repair_triggered(file_path: String, attempt: int, reason: String)
signal repair_skipped(file_path: String, reason: String)

var _watcher: AIErrorLogWatcher = null
var _router: AIAutonomousRepairRouter = null
var _pipeline: AIPipelineOrchestrator = null
var _timer: Timer = null
var _active: bool = false
var _busy: bool = false


## Otonom döngüyü başlatır. p_pipeline gereklidir; yoksa false.
func start(
	p_pipeline: AIPipelineOrchestrator,
	p_log_path: String = DEFAULT_LOG_PATH
) -> bool:
	if p_pipeline == null:
		return false
	_pipeline = p_pipeline
	_watcher = AIErrorLogWatcher.new(p_log_path)
	_router = AIAutonomousRepairRouter.new()
	if _timer == null:
		_timer = Timer.new()
		_timer.wait_time = TICK_SECONDS
		_timer.one_shot = false
		_timer.autostart = false
		add_child(_timer)
		_timer.timeout.connect(_tick)
	_timer.start()
	_active = true
	return true


## Döngüyü durdurur ve kaynakları serbest bırakır.
func stop() -> void:
	_active = false
	if _timer != null and _timer.is_inside_tree():
		_timer.stop()


func is_active() -> bool:
	return _active


## Tek bir polling adımı (testler ve manuel tetikleme için public).
func tick() -> Array:
	return _tick()


# ============================================================
# DAHİLİ
# ============================================================

func _tick() -> Array:
	var triggered: Array = []
	if not _active or _watcher == null or _router == null or _pipeline == null:
		return triggered
	if _busy:
		# Bir önceki onarım sürüyor — üst üste binme.
		return triggered
	var events: Array = _watcher.poll()
	for ev in events:
		var path: String = str(ev.get("file_path", ""))
		var sig: String = str(ev.get("signature", ""))
		var raw: String = str(ev.get("raw", ""))
		if path.is_empty():
			continue
		var decision: Dictionary = _router.should_repair(path, sig)
		if not bool(decision["ok"]):
			repair_skipped.emit(path, str(decision["reason"]))
			continue
		var code: String = _read_text(path)
		if code.is_empty():
			repair_skipped.emit(path, "Dosya okunamadı (boş/yok)")
			continue
		var instruction: String = _router.build_instruction(
			path, code, raw
		)
		_busy = true
		var ok: bool = _pipeline.run_task(
			"Otonom onarım", path, instruction,
			AICellRoles.Role.CODE_ENGINEER
		)
		_busy = false
		if ok:
			triggered.append({
				"path": path, "attempt": int(decision["attempt"]),
			})
			repair_triggered.emit(
				path, int(decision["attempt"]), raw
			)
		else:
			repair_skipped.emit(path, "Pipeline başlatılamadı (köprü?)")
	return triggered


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t
