@tool
class_name AILifecycleStateMachine
extends RefCounted

## AppStateMachine — uygulama durum makinesi (Madde 10 / App Lifecycle).
##
## Android oyun = sürekli kesintide yaşayan oyun. Telefon araması,
## bildirim, ekran kilidi — uygulama durmadan arka plan/ön plan
## arasında gidip gelir. Bu sınıf uygulamanın HANGİ DURUMDA
## olduğunu izler ve geçişlerin GEÇERLİ olduğunu garanti eder.
##
## Durumlar:
##   STARTING   — açılış (henüz hazır değil)
##   ACTIVE     — ön planda, kullanıcı oynuyor
##   PAUSED     — odak kaybı (bildirim, kısa kesinti) — hâlâ görünür
##   BACKGROUND — arka planda (başka uygulamaya geçildi)
##   RESUMING   — arka plandan geri dönüş (resume zinciri çalışıyor)
##   TERMINATING — kapanış
##
## Geçersiz geçiş (örn. BACKGROUND'dan doğrudan ACTIVE'e) reddedilir
## — RESUMING'den geçilmeli, çünkü resume zinciri çalışmalı.
##
## Mock policy: durum gerçek olaylardan değişir; sahte geçiş yok.

## Uygulama yaşam döngüsü durumları.
enum AppState { STARTING, ACTIVE, PAUSED, BACKGROUND, RESUMING, TERMINATING }

const STATE_NAMES: Dictionary = {
	AppState.STARTING: "starting",
	AppState.ACTIVE: "active",
	AppState.PAUSED: "paused",
	AppState.BACKGROUND: "background",
	AppState.RESUMING: "resuming",
	AppState.TERMINATING: "terminating",
}

## Geçerli durum geçişleri — kaynak -> [izin verilen hedefler].
const VALID_TRANSITIONS: Dictionary = {
	AppState.STARTING: [AppState.ACTIVE, AppState.TERMINATING],
	AppState.ACTIVE: [AppState.PAUSED, AppState.BACKGROUND,
		AppState.TERMINATING],
	AppState.PAUSED: [AppState.ACTIVE, AppState.BACKGROUND,
		AppState.TERMINATING],
	AppState.BACKGROUND: [AppState.RESUMING, AppState.TERMINATING],
	AppState.RESUMING: [AppState.ACTIVE, AppState.BACKGROUND,
		AppState.TERMINATING],
	AppState.TERMINATING: [],
}


## Şu anki durum.
var current_state: int = AppState.STARTING

## Durum geçmişi — son geçişler.
var _history: Array = []

## Geçmişte tutulacak maksimum kayıt.
const MAX_HISTORY: int = 32


# ============================================================
# GEÇİŞ
# ============================================================

## Bir duruma geçmeye çalışır.
## target: hedef durum.
## Dönen: {ok: bool, from: String, to: String, reason: String}
func transition_to(target: int) -> Dictionary:
	if not STATE_NAMES.has(target):
		return {
			"ok": false, "from": state_name(),
			"to": "?", "reason": "Geçersiz hedef durum",
		}

	# Aynı duruma geçiş — no-op, hata değil
	if target == current_state:
		return {
			"ok": true, "from": state_name(),
			"to": state_name(), "reason": "Zaten bu durumda",
		}

	# Geçiş geçerli mi
	var allowed: Array = VALID_TRANSITIONS.get(current_state, [])
	if not allowed.has(target):
		return {
			"ok": false, "from": state_name(),
			"to": STATE_NAMES[target],
			"reason": "Geçersiz geçiş: %s -> %s" % [
				state_name(), STATE_NAMES[target]
			],
		}

	# Geçişi uygula
	var from_state: int = current_state
	current_state = target
	_record(from_state, target)
	return {
		"ok": true, "from": STATE_NAMES[from_state],
		"to": STATE_NAMES[target], "reason": "Geçiş tamam",
	}


## Bir geçişi geçmişe kaydeder.
func _record(from_state: int, to_state: int) -> void:
	_history.append({
		"from": from_state,
		"to": to_state,
		"tick": Time.get_ticks_msec(),
	})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()


# ============================================================
# SORGULAMA
# ============================================================

## Şu anki durumun adı.
func state_name() -> String:
	return STATE_NAMES.get(current_state, "?")


## Bir geçiş geçerli mi (uygulamadan).
func can_transition_to(target: int) -> bool:
	if target == current_state:
		return true
	var allowed: Array = VALID_TRANSITIONS.get(current_state, [])
	return allowed.has(target)


## Uygulama kullanıcıya görünür mü? (ACTIVE veya PAUSED)
func is_visible() -> bool:
	return current_state == AppState.ACTIVE \
		or current_state == AppState.PAUSED


## Uygulama arka planda mı?
func is_backgrounded() -> bool:
	return current_state == AppState.BACKGROUND


## Uygulama oynanabilir durumda mı? (sadece ACTIVE)
func is_interactive() -> bool:
	return current_state == AppState.ACTIVE


## Geçiş geçmişi sayısı.
func history_count() -> int:
	return _history.size()


## Durum özeti.
func summary() -> Dictionary:
	return {
		"current_state": state_name(),
		"is_visible": is_visible(),
		"is_interactive": is_interactive(),
		"history_count": _history.size(),
	}
