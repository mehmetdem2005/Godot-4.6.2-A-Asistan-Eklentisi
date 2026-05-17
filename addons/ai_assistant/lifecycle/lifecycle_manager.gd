@tool
class_name AILifecycleManager
extends RefCounted

## LifecycleManager — yaşam döngüsü yöneticisi (Madde 10 ana API).
##
## App Lifecycle sisteminin tek giriş noktası. Alt parçaları birleştirir:
##   state_machine    — uygulama durumu (active/paused/background...)
##   event_dispatcher — sistem olaylarını handler'lara dağıtır
##   resume_chain     — arka plandan dönüş zinciri
##   memory/battery/network/orientation/inactivity — monitörler
##
## Oyun kodu sadece bu sınıfla konuşur. Android sistem olayı gelince
## (örn. notification_main_loop_request) manager uygun zinciri
## tetikler.
##
## Akış örneği — uygulama arka plana atılıyor:
##   1. on_pause() çağrılır
##   2. state_machine ACTIVE -> BACKGROUND
##   3. APP_PAUSE olayı dağıtılır (ses durur, kayıt yapılır...)
##
## Akış — uygulama geri geliyor:
##   1. on_resume() çağrılır
##   2. state_machine BACKGROUND -> RESUMING
##   3. resume_chain çalışır (bütünlük, ağ, ses, ui...)
##   4. state_machine RESUMING -> ACTIVE
##
## Mock policy: her durum gerçek olaydan; sahte geçiş yok.

## Alt bileşenler.
var state_machine: AILifecycleStateMachine
var dispatcher: AILifecycleEventDispatcher
var resume_chain: AILifecycleResumeChain
var memory_monitor: AILifecycleMemoryMonitor
var battery_monitor: AILifecycleBatteryMonitor
var network_monitor: AILifecycleNetworkMonitor


func _init() -> void:
	state_machine = AILifecycleStateMachine.new()
	dispatcher = AILifecycleEventDispatcher.new()
	resume_chain = AILifecycleResumeChain.new()
	memory_monitor = AILifecycleMemoryMonitor.new()
	battery_monitor = AILifecycleBatteryMonitor.new()
	network_monitor = AILifecycleNetworkMonitor.new()


# ============================================================
# YAŞAM DÖNGÜSÜ OLAYLARI
# ============================================================

## Uygulama başlatma tamamlandı — STARTING'den ACTIVE'e.
## Dönen: {ok: bool, reason: String}
func on_start_complete() -> Dictionary:
	var transition: Dictionary = state_machine.transition_to(
		AILifecycleStateMachine.AppState.ACTIVE
	)
	return {"ok": transition["ok"], "reason": transition["reason"]}


## Uygulama duraklatılıyor (kısa kesinti — bildirim gibi).
## ACTIVE -> PAUSED. APP_PAUSE olayı dağıtılır.
func on_pause() -> Dictionary:
	var transition: Dictionary = state_machine.transition_to(
		AILifecycleStateMachine.AppState.PAUSED
	)
	if transition["ok"]:
		dispatcher.dispatch(AILifecycleEventDispatcher.EVENT_APP_PAUSE)
	return {"ok": transition["ok"], "reason": transition["reason"]}


## Uygulama arka plana atılıyor (başka uygulamaya geçildi).
## APP_PAUSE olayı dağıtılır — kayıt yapılmalı.
func on_background() -> Dictionary:
	var transition: Dictionary = state_machine.transition_to(
		AILifecycleStateMachine.AppState.BACKGROUND
	)
	if transition["ok"]:
		dispatcher.dispatch(AILifecycleEventDispatcher.EVENT_APP_PAUSE)
	return {"ok": transition["ok"], "reason": transition["reason"]}


## Uygulama ön plana geri geliyor.
## BACKGROUND/PAUSED -> RESUMING -> resume zinciri -> ACTIVE.
## Dönen: {ok, chain_result, reason}
func on_resume() -> Dictionary:
	var state: int = state_machine.current_state

	# PAUSED'dan dönüş — basit, doğrudan ACTIVE
	if state == AILifecycleStateMachine.AppState.PAUSED:
		var direct: Dictionary = state_machine.transition_to(
			AILifecycleStateMachine.AppState.ACTIVE
		)
		if direct["ok"]:
			dispatcher.dispatch(
				AILifecycleEventDispatcher.EVENT_APP_RESUME
			)
		return {
			"ok": direct["ok"], "chain_result": {},
			"reason": "Duraklamadan döndü",
		}

	# BACKGROUND'dan dönüş — RESUMING + zincir
	var to_resuming: Dictionary = state_machine.transition_to(
		AILifecycleStateMachine.AppState.RESUMING
	)
	if not to_resuming["ok"]:
		return {
			"ok": false, "chain_result": {},
			"reason": "RESUMING'e geçilemedi: " + to_resuming["reason"],
		}

	# Resume zincirini çalıştır
	var chain_result: Dictionary = resume_chain.run()

	# Zincir başarılıysa ACTIVE'e, değilse BACKGROUND'a geri dön
	if chain_result["ok"]:
		state_machine.transition_to(
			AILifecycleStateMachine.AppState.ACTIVE
		)
		dispatcher.dispatch(AILifecycleEventDispatcher.EVENT_APP_RESUME)
		return {
			"ok": true, "chain_result": chain_result,
			"reason": "Geri dönüş tamamlandı",
		}
	else:
		# Kritik adım başarısız — arka plana geri dön
		state_machine.transition_to(
			AILifecycleStateMachine.AppState.BACKGROUND
		)
		return {
			"ok": false, "chain_result": chain_result,
			"reason": "Resume zinciri başarısız: " + str(
				chain_result["halted_at"]
			),
		}


# ============================================================
# MONİTÖR ENTEGRASYONU
# ============================================================

## Bellek durumu bildirir — kritikse LOW_MEMORY olayı dağıtılır.
## usage_ratio: bellek kullanım oranı (0-1).
func report_memory(usage_ratio: float) -> void:
	var level: int = memory_monitor.evaluate(usage_ratio)
	if level == AILifecycleMemoryMonitor.PressureLevel.CRITICAL:
		dispatcher.dispatch(AILifecycleEventDispatcher.EVENT_LOW_MEMORY)


## Pil durumu bildirir — kritikse BATTERY_LOW olayı dağıtılır.
func report_battery(percent: float, charging: bool) -> void:
	battery_monitor.evaluate(percent, charging)
	if battery_monitor.needs_warning():
		dispatcher.dispatch(AILifecycleEventDispatcher.EVENT_BATTERY_LOW)


## Ağ durumu bildirir — değişimde uygun olay dağıtılır.
func report_network(connection_type: int) -> void:
	var change: Dictionary = network_monitor.update(connection_type)
	if change["changed"]:
		var event: String = str(change["event"])
		if event == "network_lost":
			dispatcher.dispatch(
				AILifecycleEventDispatcher.EVENT_NETWORK_LOST
			)
		elif event == "network_gained":
			dispatcher.dispatch(
				AILifecycleEventDispatcher.EVENT_NETWORK_GAINED
			)


# ============================================================
# DURUM
# ============================================================

## Uygulama oynanabilir durumda mı?
func is_interactive() -> bool:
	return state_machine.is_interactive()


## Tam durum özeti.
func summary() -> Dictionary:
	return {
		"state": state_machine.state_name(),
		"memory": memory_monitor.level_name(),
		"battery": battery_monitor.level_name(),
		"network": network_monitor.type_name(),
		"resume_steps": resume_chain.step_count(),
	}
