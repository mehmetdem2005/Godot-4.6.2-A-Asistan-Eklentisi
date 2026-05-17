@tool
class_name AIIterationModel
extends RefCounted

## IterationModel — iteration sekmesi modeli (Layer 11).
##
## Iteration sekmesinin altındaki mantık. Bir iteration'ın faz akışını
## (PLANNING -> ACTIVE -> REVIEW -> RETRO -> CLOSED), task ilerlemesini
## ve geçiş kurallarını yönetir. Görsel Control bu modeli okur.
##
## AIIteration contract'ı (Layer 0) ile uyumlu — Phase enum aynı.
##
## Mock policy: ilerleme gerçek task durumundan hesaplanır.

## Iteration faz akışı (AIIteration.Phase ile birebir).
const PHASE_FLOW: Array = [
	AIIteration.Phase.PLANNING,
	AIIteration.Phase.ACTIVE,
	AIIteration.Phase.REVIEW,
	AIIteration.Phase.RETRO,
	AIIteration.Phase.CLOSED,
]

const PHASE_NAMES: Dictionary = {
	AIIteration.Phase.PLANNING: "Planlama",
	AIIteration.Phase.ACTIVE: "Aktif",
	AIIteration.Phase.REVIEW: "İnceleme",
	AIIteration.Phase.RETRO: "Retrospektif",
	AIIteration.Phase.CLOSED: "Kapalı",
}

## Aktif iteration bilgileri.
var iteration_number: int = 1
var goal: String = ""
var current_phase: int = AIIteration.Phase.PLANNING

## Task ilerleme — task_id -> tamamlandı mı (bool).
var _task_completion: Dictionary = {}


# ============================================================
# FAZ AKIŞI
# ============================================================

## Mevcut fazın adı.
func phase_name() -> String:
	return PHASE_NAMES.get(current_phase, "?")


## Bir sonraki faza geçer. Akış sıralı — atlama yok.
## Dönen: {ok: bool, new_phase: int, reason: String}
func advance_phase() -> Dictionary:
	var idx: int = PHASE_FLOW.find(current_phase)
	if idx < 0:
		return {"ok": false, "new_phase": current_phase, "reason": "Bilinmeyen faz"}
	if idx + 1 >= PHASE_FLOW.size():
		return {
			"ok": false,
			"new_phase": current_phase,
			"reason": "Iteration zaten kapalı (son faz)",
		}
	# ACTIVE -> REVIEW geçişi: tüm task'lar bitmiş olmalı
	if current_phase == AIIteration.Phase.ACTIVE and not all_tasks_complete():
		return {
			"ok": false,
			"new_phase": current_phase,
			"reason": "Aktif fazda tamamlanmamış task var — REVIEW'e geçilemez",
		}
	current_phase = PHASE_FLOW[idx + 1]
	return {"ok": true, "new_phase": current_phase, "reason": ""}


## Iteration kapandı mı?
func is_closed() -> bool:
	return current_phase == AIIteration.Phase.CLOSED


## Bir sonraki faza geçilebilir mi (kuralları kontrol eder)?
func can_advance() -> bool:
	var idx: int = PHASE_FLOW.find(current_phase)
	if idx < 0 or idx + 1 >= PHASE_FLOW.size():
		return false
	if current_phase == AIIteration.Phase.ACTIVE and not all_tasks_complete():
		return false
	return true


# ============================================================
# TASK İLERLEMESİ
# ============================================================

## Iteration'a bir task ekler — başlangıçta tamamlanmamış.
func add_task(task_id: String) -> void:
	if task_id.is_empty():
		push_warning("IterationModel.add_task: boş task_id")
		return
	if not _task_completion.has(task_id):
		_task_completion[task_id] = false


## Bir task'ı tamamlandı/tamamlanmadı olarak işaretler.
func set_task_complete(task_id: String, complete: bool) -> bool:
	if not _task_completion.has(task_id):
		return false
	_task_completion[task_id] = complete
	return true


## Toplam task sayısı.
func task_count() -> int:
	return _task_completion.size()


## Tamamlanan task sayısı.
func completed_count() -> int:
	var n: int = 0
	for task_id in _task_completion:
		if _task_completion[task_id]:
			n += 1
	return n


## Tüm task'lar tamamlandı mı? (Boş iteration = tamamlanmış sayılır.)
func all_tasks_complete() -> bool:
	if _task_completion.is_empty():
		return true
	return completed_count() == _task_completion.size()


## Iteration ilerleme oranı (0.0 - 1.0).
func progress() -> float:
	if _task_completion.is_empty():
		return 0.0
	return float(completed_count()) / float(_task_completion.size())


# ============================================================
# DURUM
# ============================================================

## Iteration durum özeti — UI başlığı için.
func summary() -> Dictionary:
	return {
		"number": iteration_number,
		"goal": goal,
		"phase": phase_name(),
		"phase_id": current_phase,
		"task_count": task_count(),
		"completed": completed_count(),
		"progress": progress(),
		"can_advance": can_advance(),
		"is_closed": is_closed(),
	}


## Faz ilerleme yüzdesi — kaçıncı fazda (0.0 - 1.0).
func phase_progress() -> float:
	var idx: int = PHASE_FLOW.find(current_phase)
	if idx < 0:
		return 0.0
	return float(idx) / float(PHASE_FLOW.size() - 1)
