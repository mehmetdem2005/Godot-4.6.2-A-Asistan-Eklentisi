@tool
class_name AIDebugSessionView
extends RefCounted

## DebugSessionView — debug oturumu görünümü (Madde 02 / debug_loop / ui).
##
## Live Feed'e bağlı debug oturumu detay paneli. Bir debug oturumu
## çalışırken (AI bir bug'ı teşhis edip düzeltirken) bu panel
## adımları canlı gösterir: hangi aşamada, ne yapılıyor, ne kadar
## sürdü.
##
## Bu view-model oturum durumunu tutar: adım listesi, mevcut aşama,
## geçen süre. Görsel panel bunu okur ve canlı akış olarak çizer.
##
## debug_loop çekirdeği (mantık katmanı) ile beslenir.
##
## Mock policy: görünüm gerçek debug oturumu olaylarından.

## Debug oturumu aşamaları.
enum SessionPhase { IDLE, DIAGNOSING, PROPOSING_FIX, APPLYING, VERIFYING, DONE, FAILED }

const PHASE_NAMES: Dictionary = {
	SessionPhase.IDLE: "idle",
	SessionPhase.DIAGNOSING: "diagnosing",
	SessionPhase.PROPOSING_FIX: "proposing_fix",
	SessionPhase.APPLYING: "applying",
	SessionPhase.VERIFYING: "verifying",
	SessionPhase.DONE: "done",
	SessionPhase.FAILED: "failed",
}

const PHASE_LABELS: Dictionary = {
	SessionPhase.IDLE: "Beklemede",
	SessionPhase.DIAGNOSING: "Teşhis ediliyor",
	SessionPhase.PROPOSING_FIX: "Düzeltme öneriliyor",
	SessionPhase.APPLYING: "Uygulanıyor",
	SessionPhase.VERIFYING: "Doğrulanıyor",
	SessionPhase.DONE: "Tamamlandı",
	SessionPhase.FAILED: "Başarısız",
}


## Bir oturum adımının kaydı.
class SessionStep extends RefCounted:
	var phase: int = AIDebugSessionView.SessionPhase.IDLE
	var detail: String = ""
	var timestamp_ms: int = 0

	func to_dict() -> Dictionary:
		return {
			"phase": phase, "detail": detail,
			"timestamp_ms": timestamp_ms,
		}


## Mevcut oturum aşaması.
var phase: int = SessionPhase.IDLE

## Oturum adımları — kronolojik.
var _steps: Array = []

## Oturumun başladığı zaman (ms).
var session_start_ms: int = 0

## İncelenen bug'ın kısa açıklaması.
var bug_summary: String = ""


# ============================================================
# OTURUM YAŞAM DÖNGÜSÜ
# ============================================================

## Yeni bir debug oturumu başlatır.
## summary: bug'ın kısa açıklaması. start_ms: başlangıç zamanı.
func start_session(summary: String, start_ms: int) -> void:
	bug_summary = summary
	session_start_ms = start_ms
	phase = SessionPhase.DIAGNOSING
	_steps.clear()
	_record_step(SessionPhase.DIAGNOSING, "Oturum başladı", start_ms)


## Oturumu yeni bir aşamaya ilerletir.
## new_phase: yeni aşama. detail: aşama detayı. now_ms: şu anki zaman.
## Dönen: true = geçerli ilerleme.
func advance(new_phase: int, detail: String, now_ms: int) -> bool:
	if not PHASE_NAMES.has(new_phase):
		return false
	phase = new_phase
	_record_step(new_phase, detail, now_ms)
	return true


## Bir adım kaydeder.
func _record_step(step_phase: int, detail: String, now_ms: int) -> void:
	var step := SessionStep.new()
	step.phase = step_phase
	step.detail = detail
	step.timestamp_ms = now_ms
	_steps.append(step)


# ============================================================
# SUNUM
# ============================================================

## Oturum adımlarının görsel listesini üretir.
## Dönen: her biri {phase, phase_label, detail, elapsed_ms} dizi.
func build_step_list() -> Array:
	var list: Array = []
	for step_obj in _steps:
		var step: SessionStep = step_obj
		list.append({
			"phase": step.phase,
			"phase_label": PHASE_LABELS.get(step.phase, "?"),
			"detail": step.detail,
			"elapsed_ms": step.timestamp_ms - session_start_ms,
		})
	return list


## Mevcut aşamanın görsel etiketi.
func phase_label() -> String:
	return PHASE_LABELS.get(phase, "?")


## Mevcut aşamanın adı.
func phase_name() -> String:
	return PHASE_NAMES.get(phase, "?")


## Oturumun toplam süresi (ms) — son adıma kadar.
func total_duration_ms() -> int:
	if _steps.is_empty():
		return 0
	var last: SessionStep = _steps[_steps.size() - 1]
	return last.timestamp_ms - session_start_ms


# ============================================================
# SORGULAMA
# ============================================================

## Oturum şu an aktif mi (çalışıyor)?
func is_active() -> bool:
	return phase != SessionPhase.IDLE \
		and phase != SessionPhase.DONE \
		and phase != SessionPhase.FAILED


## Oturum başarıyla bitti mi?
func is_successful() -> bool:
	return phase == SessionPhase.DONE


## Oturum başarısız mı bitti?
func is_failed() -> bool:
	return phase == SessionPhase.FAILED


## Kaydedilen adım sayısı.
func step_count() -> int:
	return _steps.size()
