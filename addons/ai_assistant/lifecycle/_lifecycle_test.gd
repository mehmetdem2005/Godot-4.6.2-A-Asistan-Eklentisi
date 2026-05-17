@tool
class_name AILifecycleTest
extends RefCounted

## Madde 10 — App Lifecycle Çekirdek Self-Test
##
## Sıkı testler: core (state machine, event dispatcher, resume chain,
## lifecycle manager), monitors (memory, battery, network, orientation,
## inactivity), permissions (manager, flow).


static func run_all() -> Array:
	var results: Array = []

	# AppStateMachine
	results.append(_b("Lifecycle: State", _test_state_valid_transitions()))
	results.append(_b("Lifecycle: State", _test_state_invalid_blocked()))
	results.append(_b("Lifecycle: State", _test_state_terminal()))

	# EventDispatcher
	results.append(_b("Lifecycle: Event", _test_event_register_dispatch()))
	results.append(_b("Lifecycle: Event", _test_event_unknown_rejected()))

	# ResumeChain
	results.append(_b("Lifecycle: Resume", _test_resume_all_ok()))
	results.append(_b("Lifecycle: Resume", _test_resume_critical_halt()))
	results.append(_b("Lifecycle: Resume", _test_resume_optional_continue()))

	# MemoryMonitor
	results.append(_b("Lifecycle: Memory", _test_memory_levels()))
	results.append(_b("Lifecycle: Memory", _test_memory_emergency()))

	# BatteryMonitor
	results.append(_b("Lifecycle: Battery", _test_battery_levels()))
	results.append(_b("Lifecycle: Battery", _test_battery_charging()))
	results.append(_b("Lifecycle: Battery", _test_battery_fps()))

	# NetworkMonitor
	results.append(_b("Lifecycle: Network", _test_network_events()))
	results.append(_b("Lifecycle: Network", _test_network_metered()))

	# OrientationHandler
	results.append(_b("Lifecycle: Orient", _test_orientation_lock()))

	# InactivityMonitor
	results.append(_b("Lifecycle: Inactivity", _test_inactivity_thresholds()))
	results.append(_b("Lifecycle: Inactivity", _test_inactivity_reset()))

	# PermissionManager
	results.append(_b("Lifecycle: Perm", _test_perm_status()))
	results.append(_b("Lifecycle: Perm", _test_perm_can_request()))

	# PermissionFlow
	results.append(_b("Lifecycle: PermFlow", _test_flow_steps()))
	results.append(_b("Lifecycle: PermFlow", _test_flow_result()))

	# LifecycleManager — entegrasyon
	results.append(_b("Lifecycle: Manager", _test_manager_pause_resume()))
	results.append(_b("Lifecycle: Manager", _test_manager_background()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# STATE MACHINE
# ============================================================

static func _test_state_valid_transitions() -> Dictionary:
	var name := "State geçerli geçişler"
	var sm := AILifecycleStateMachine.new()
	# STARTING -> ACTIVE
	if not sm.transition_to(AILifecycleStateMachine.AppState.ACTIVE)["ok"]:
		return _fail(name, "STARTING -> ACTIVE geçerli olmalı")
	# ACTIVE -> BACKGROUND
	if not sm.transition_to(
		AILifecycleStateMachine.AppState.BACKGROUND
	)["ok"]:
		return _fail(name, "ACTIVE -> BACKGROUND geçerli olmalı")
	return _ok(name)


static func _test_state_invalid_blocked() -> Dictionary:
	var name := "State geçersiz geçiş engeli"
	var sm := AILifecycleStateMachine.new()
	sm.transition_to(AILifecycleStateMachine.AppState.ACTIVE)
	sm.transition_to(AILifecycleStateMachine.AppState.BACKGROUND)
	# BACKGROUND -> ACTIVE doğrudan GEÇERSİZ (RESUMING gerekli)
	var direct: Dictionary = sm.transition_to(
		AILifecycleStateMachine.AppState.ACTIVE
	)
	if direct["ok"]:
		return _fail(name, "BACKGROUND -> ACTIVE doğrudan engellenmeli")
	return _ok(name)


static func _test_state_terminal() -> Dictionary:
	var name := "State sonlanma durumu"
	var sm := AILifecycleStateMachine.new()
	sm.transition_to(AILifecycleStateMachine.AppState.TERMINATING)
	# TERMINATING'den çıkış yok
	if sm.transition_to(AILifecycleStateMachine.AppState.ACTIVE)["ok"]:
		return _fail(name, "TERMINATING'den çıkış olmamalı")
	return _ok(name)


# ============================================================
# EVENT DISPATCHER
# ============================================================

static func _test_event_register_dispatch() -> Dictionary:
	var name := "Event kayıt ve dağıtım"
	var dispatcher := AILifecycleEventDispatcher.new()
	var hits: Array = [0]
	var handler := func(_payload: Dictionary) -> void:
		hits[0] += 1
	if not dispatcher.register(
		AILifecycleEventDispatcher.EVENT_LOW_MEMORY, handler
	):
		return _fail(name, "bilinen olaya kayıt başarılı olmalı")
	var result: Dictionary = dispatcher.dispatch(
		AILifecycleEventDispatcher.EVENT_LOW_MEMORY
	)
	if not result["ok"]:
		return _fail(name, "dağıtım başarılı olmalı")
	if hits[0] != 1:
		return _fail(name, "handler çağrılmalı")
	return _ok(name)


static func _test_event_unknown_rejected() -> Dictionary:
	var name := "Event bilinmeyen reddi"
	var dispatcher := AILifecycleEventDispatcher.new()
	var handler := func(_payload: Dictionary) -> void:
		pass
	# Bilinmeyen olay — kayıt reddedilmeli
	if dispatcher.register("olmayan_olay_xyz", handler):
		return _fail(name, "bilinmeyen olaya kayıt reddedilmeli")
	# Bilinmeyen olay — dağıtım reddedilmeli
	if dispatcher.dispatch("olmayan_olay_xyz")["ok"]:
		return _fail(name, "bilinmeyen olay dağıtılamamalı")
	return _ok(name)


# ============================================================
# RESUME CHAIN
# ============================================================

static func _test_resume_all_ok() -> Dictionary:
	var name := "Resume tüm adımlar başarılı"
	var chain := AILifecycleResumeChain.new()
	chain.add_step("bütünlük", func() -> bool: return true, true)
	chain.add_step("ağ", func() -> bool: return true, false)
	chain.add_step("ses", func() -> bool: return true, false)
	var result: Dictionary = chain.run()
	if not result["ok"]:
		return _fail(name, "tüm adımlar geçince zincir başarılı olmalı")
	if int(result["completed"]) != 3:
		return _fail(name, "3 adım tamamlanmalı")
	return _ok(name)


static func _test_resume_critical_halt() -> Dictionary:
	var name := "Resume kritik adım zinciri durdurur"
	var chain := AILifecycleResumeChain.new()
	# İlk adım kritik ve başarısız
	chain.add_step("bütünlük", func() -> bool: return false, true)
	chain.add_step("ağ", func() -> bool: return true, false)
	var result: Dictionary = chain.run()
	if result["ok"]:
		return _fail(name, "kritik başarısızlık zinciri durdurmalı")
	if str(result["halted_at"]) != "bütünlük":
		return _fail(name, "durma noktası kritik adım olmalı")
	return _ok(name)


static func _test_resume_optional_continue() -> Dictionary:
	var name := "Resume opsiyonel adım devam eder"
	var chain := AILifecycleResumeChain.new()
	# Opsiyonel adım başarısız — zincir devam etmeli
	chain.add_step("ağ", func() -> bool: return false, false)
	chain.add_step("ses", func() -> bool: return true, false)
	var result: Dictionary = chain.run()
	if not result["ok"]:
		return _fail(name, "opsiyonel başarısızlık zinciri durdurmamalı")
	if int(result["completed"]) != 1:
		return _fail(name, "1 adım tamamlanmalı (ses)")
	return _ok(name)


# ============================================================
# MEMORY MONITOR
# ============================================================

static func _test_memory_levels() -> Dictionary:
	var name := "Memory baskı seviyeleri"
	var m := AILifecycleMemoryMonitor.new()
	if m.evaluate(0.5) != AILifecycleMemoryMonitor.PressureLevel.NORMAL:
		return _fail(name, "%50 kullanım NORMAL olmalı")
	if m.evaluate(0.80) != AILifecycleMemoryMonitor.PressureLevel.MODERATE:
		return _fail(name, "%80 kullanım MODERATE olmalı")
	if m.evaluate(0.95) != AILifecycleMemoryMonitor.PressureLevel.CRITICAL:
		return _fail(name, "%95 kullanım CRITICAL olmalı")
	return _ok(name)


static func _test_memory_emergency() -> Dictionary:
	var name := "Memory acil kayıt"
	var m := AILifecycleMemoryMonitor.new()
	m.evaluate(0.95)
	if not m.needs_emergency_save():
		return _fail(name, "CRITICAL'de acil kayıt gerekli olmalı")
	m.evaluate(0.5)
	if m.needs_emergency_save():
		return _fail(name, "NORMAL'de acil kayıt gereksiz")
	return _ok(name)


# ============================================================
# BATTERY MONITOR
# ============================================================

static func _test_battery_levels() -> Dictionary:
	var name := "Battery seviyeler"
	var m := AILifecycleBatteryMonitor.new()
	if m.evaluate(50.0, false) != AILifecycleBatteryMonitor \
			.BatteryLevel.NORMAL:
		return _fail(name, "%50 NORMAL olmalı")
	if m.evaluate(15.0, false) != AILifecycleBatteryMonitor \
			.BatteryLevel.LOW:
		return _fail(name, "%15 LOW olmalı")
	if m.evaluate(5.0, false) != AILifecycleBatteryMonitor \
			.BatteryLevel.CRITICAL:
		return _fail(name, "%5 CRITICAL olmalı")
	return _ok(name)


static func _test_battery_charging() -> Dictionary:
	var name := "Battery şarj durumu"
	var m := AILifecycleBatteryMonitor.new()
	# Şarjda — düşük pilde bile güç tasarrufu yok
	m.evaluate(5.0, true)
	if m.should_save_power():
		return _fail(name, "şarjdayken güç tasarrufu olmamalı")
	# Şarjda değil — düşük pilde tasarruf
	m.evaluate(15.0, false)
	if not m.should_save_power():
		return _fail(name, "düşük pil + şarjsız tasarruf olmalı")
	return _ok(name)


static func _test_battery_fps() -> Dictionary:
	var name := "Battery FPS önerisi"
	var m := AILifecycleBatteryMonitor.new()
	# Kritik + şarjsız — düşük FPS
	m.evaluate(5.0, false)
	if m.recommended_fps() >= 60:
		return _fail(name, "kritik pilde FPS düşürülmeli")
	# Şarjda — tam FPS
	m.evaluate(5.0, true)
	if m.recommended_fps() != 60:
		return _fail(name, "şarjda tam FPS olmalı")
	return _ok(name)


# ============================================================
# NETWORK MONITOR
# ============================================================

static func _test_network_events() -> Dictionary:
	var name := "Network olay tespiti"
	var m := AILifecycleNetworkMonitor.new()
	# NONE -> WIFI: bağlantı geldi
	var gained: Dictionary = m.update(
		AILifecycleNetworkMonitor.ConnectionType.WIFI
	)
	if str(gained["event"]) != "network_gained":
		return _fail(name, "bağlantı gelince network_gained olmalı")
	# WIFI -> NONE: bağlantı kayboldu
	var lost: Dictionary = m.update(
		AILifecycleNetworkMonitor.ConnectionType.NONE
	)
	if str(lost["event"]) != "network_lost":
		return _fail(name, "bağlantı kesilince network_lost olmalı")
	return _ok(name)


static func _test_network_metered() -> Dictionary:
	var name := "Network ölçülü bağlantı"
	var m := AILifecycleNetworkMonitor.new()
	# WiFi — ölçülü değil, büyük indirme güvenli
	m.update(AILifecycleNetworkMonitor.ConnectionType.WIFI)
	if not m.is_safe_for_large_download():
		return _fail(name, "WiFi'da büyük indirme güvenli olmalı")
	# Mobil — ölçülü, büyük indirme güvensiz
	m.update(AILifecycleNetworkMonitor.ConnectionType.MOBILE)
	if m.is_safe_for_large_download():
		return _fail(name, "mobil veride büyük indirme güvensiz olmalı")
	return _ok(name)


# ============================================================
# ORIENTATION
# ============================================================

static func _test_orientation_lock() -> Dictionary:
	var name := "Orientation kilit politikası"
	var h := AILifecycleOrientationHandler.new()
	# PORTRAIT_ONLY — yatay reddedilmeli
	h.set_lock_policy(AILifecycleOrientationHandler.LockPolicy.PORTRAIT_ONLY)
	var landscape: Dictionary = h.handle_change(
		AILifecycleOrientationHandler.Orientation.LANDSCAPE
	)
	if landscape["applied"]:
		return _fail(name, "PORTRAIT_ONLY yatayı reddetmeli")
	# Dikey kabul edilmeli
	var portrait: Dictionary = h.handle_change(
		AILifecycleOrientationHandler.Orientation.PORTRAIT
	)
	if not portrait["applied"]:
		return _fail(name, "PORTRAIT_ONLY dikeyi kabul etmeli")
	return _ok(name)


# ============================================================
# INACTIVITY
# ============================================================

static func _test_inactivity_thresholds() -> Dictionary:
	var name := "Inactivity eşikler"
	var m := AILifecycleInactivityMonitor.new()
	m.set_thresholds(60.0, 120.0)
	# 30sn — hâlâ aktif
	m.tick(30.0)
	if m.current_state != AILifecycleInactivityMonitor \
			.InactivityState.ACTIVE:
		return _fail(name, "30sn'de aktif olmalı")
	# 70sn toplam — uyarı
	m.tick(40.0)
	if not m.should_show_warning():
		return _fail(name, "70sn'de uyarı gösterilmeli")
	# 130sn toplam — oto-duraklat
	m.tick(60.0)
	if not m.is_auto_paused():
		return _fail(name, "130sn'de oto-duraklatma olmalı")
	return _ok(name)


static func _test_inactivity_reset() -> Dictionary:
	var name := "Inactivity etkileşim sıfırlama"
	var m := AILifecycleInactivityMonitor.new()
	m.tick(100.0)
	m.register_activity()
	if m.idle_seconds != 0.0:
		return _fail(name, "etkileşim idle sayacını sıfırlamalı")
	if m.current_state != AILifecycleInactivityMonitor \
			.InactivityState.ACTIVE:
		return _fail(name, "etkileşim sonrası aktif olmalı")
	return _ok(name)


# ============================================================
# PERMISSION MANAGER
# ============================================================

static func _test_perm_status() -> Dictionary:
	var name := "Permission durum takibi"
	var m := AILifecyclePermissionManager.new()
	# Bilinmeyen izin — UNKNOWN
	if m.get_status("microphone") != AILifecyclePermissionManager \
			.PermStatus.UNKNOWN:
		return _fail(name, "sorulmamış izin UNKNOWN olmalı")
	# Verildi olarak işaretle
	m.set_status("microphone", AILifecyclePermissionManager \
		.PermStatus.GRANTED)
	if not m.is_granted("microphone"):
		return _fail(name, "GRANTED izin verilmiş sayılmalı")
	return _ok(name)


static func _test_perm_can_request() -> Dictionary:
	var name := "Permission isteme uygunluğu"
	var m := AILifecyclePermissionManager.new()
	# UNKNOWN — istenebilir
	if not m.can_request("camera"):
		return _fail(name, "UNKNOWN izin istenebilir olmalı")
	# GRANTED — istenmez
	m.set_status("camera", AILifecyclePermissionManager \
		.PermStatus.GRANTED)
	if m.can_request("camera"):
		return _fail(name, "GRANTED izin tekrar istenmemeli")
	# DENIED_PERMANENTLY — istenemez, ayar gerekir
	m.set_status("storage", AILifecyclePermissionManager \
		.PermStatus.DENIED_PERMANENTLY)
	if m.can_request("storage"):
		return _fail(name, "kalıcı reddedilen istenemez")
	if not m.needs_settings_redirect("storage"):
		return _fail(name, "kalıcı red ayar yönlendirmesi gerektirir")
	return _ok(name)


# ============================================================
# PERMISSION FLOW
# ============================================================

static func _test_flow_steps() -> Dictionary:
	var name := "PermFlow akış adımları"
	var flow := AILifecyclePermissionFlow.new()
	var mgr: AILifecyclePermissionManager = flow.manager()
	# UNKNOWN — doğrudan iste
	var unknown: Dictionary = flow.next_step("microphone")
	if str(unknown["step"]) != "request_directly":
		return _fail(name, "UNKNOWN doğrudan istenmeli")
	# DENIED — gerekçe göster
	mgr.set_status("camera", AILifecyclePermissionManager \
		.PermStatus.DENIED)
	if not flow.needs_rationale("camera"):
		return _fail(name, "DENIED için gerekçe gösterilmeli")
	# GRANTED — istek gerekmez
	mgr.set_status("storage", AILifecyclePermissionManager \
		.PermStatus.GRANTED)
	if flow.request_needed("storage"):
		return _fail(name, "GRANTED için istek gerekmemeli")
	return _ok(name)


static func _test_flow_result() -> Dictionary:
	var name := "PermFlow sonuç işleme"
	var flow := AILifecyclePermissionFlow.new()
	# İzin verildi
	if flow.handle_result("microphone", true) != "granted":
		return _fail(name, "verilen izin granted olmalı")
	# Red + bir daha sorma — kalıcı red
	if flow.handle_result("camera", false, true) != "denied_permanently":
		return _fail(name, "red+bir daha sorma kalıcı red olmalı")
	# Sadece red
	if flow.handle_result("storage", false, false) != "denied":
		return _fail(name, "sadece red denied olmalı")
	return _ok(name)


# ============================================================
# LIFECYCLE MANAGER — entegrasyon
# ============================================================

static func _test_manager_pause_resume() -> Dictionary:
	var name := "Manager duraklat-devam akışı"
	var manager := AILifecycleManager.new()
	manager.on_start_complete()
	# Duraklat
	if not manager.on_pause()["ok"]:
		return _fail(name, "duraklatma başarılı olmalı")
	if manager.is_interactive():
		return _fail(name, "duraklamada etkileşimsiz olmalı")
	# Devam et — PAUSED'dan basit dönüş
	if not manager.on_resume()["ok"]:
		return _fail(name, "duraklamadan dönüş başarılı olmalı")
	if not manager.is_interactive():
		return _fail(name, "dönüş sonrası etkileşimli olmalı")
	return _ok(name)


static func _test_manager_background() -> Dictionary:
	var name := "Manager arka plan-dönüş zinciri"
	var manager := AILifecycleManager.new()
	manager.on_start_complete()
	# Resume zincirine bir adım ekle
	manager.resume_chain.add_step(
		"bütünlük", func() -> bool: return true, true
	)
	# Arka plana at
	if not manager.on_background()["ok"]:
		return _fail(name, "arka plana atma başarılı olmalı")
	# Geri dön — RESUMING + zincir + ACTIVE
	var resume: Dictionary = manager.on_resume()
	if not resume["ok"]:
		return _fail(name, "arka plandan dönüş başarılı olmalı")
	if not manager.is_interactive():
		return _fail(name, "zincir sonrası ACTIVE olmalı")
	return _ok(name)
