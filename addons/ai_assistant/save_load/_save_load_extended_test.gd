@tool
class_name AISaveLoadExtendedTest
extends RefCounted

## Madde 09 — Save/Load Mantık Tamamlama Self-Test
##
## Sıkı testler: backup (rotator, restorer, corruption_recovery),
## versioning (version_checker, migration_registry, migration_engine),
## autosave (scheduler, checkpoint_trigger, mobile_pause,
## battery_warning), persistence_helpers (serializer_registry,
## screenshot_capturer, load_state).


static func run_all() -> Array:
	var results: Array = []

	# Backup
	results.append(_b("SaveExt: Backup", _test_rotator_plan()))
	results.append(_b("SaveExt: Backup", _test_rotator_eviction()))
	results.append(_b("SaveExt: Backup", _test_restorer_select()))
	results.append(_b("SaveExt: Backup", _test_restorer_all_corrupt()))
	results.append(_b("SaveExt: Backup", _test_corruption_recovery()))

	# Versioning
	results.append(_b("SaveExt: Version", _test_version_compatible()))
	results.append(_b("SaveExt: Version", _test_version_too_new()))
	results.append(_b("SaveExt: Version", _test_migration_chain()))
	results.append(_b("SaveExt: Version", _test_migration_incomplete()))
	results.append(_b("SaveExt: Version", _test_migration_noop()))

	# Autosave
	results.append(_b("SaveExt: Autosave", _test_autosave_interval()))
	results.append(_b("SaveExt: Autosave", _test_autosave_unsafe()))
	results.append(_b("SaveExt: Autosave", _test_checkpoint_critical()))
	results.append(_b("SaveExt: Autosave", _test_checkpoint_debounce()))
	results.append(_b("SaveExt: Autosave", _test_mobile_pause()))
	results.append(_b("SaveExt: Autosave", _test_battery_warning()))

	# Persistence Helpers
	results.append(_b("SaveExt: Helpers", _test_serializer_roundtrip()))
	results.append(_b("SaveExt: Helpers", _test_serializer_unknown()))
	results.append(_b("SaveExt: Helpers", _test_screenshot_scale()))
	results.append(_b("SaveExt: Helpers", _test_loadstate_progress()))
	results.append(_b("SaveExt: Helpers", _test_loadstate_failure()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# BACKUP
# ============================================================

static func _test_rotator_plan() -> Dictionary:
	var name := "Rotator rotasyon planı"
	var r := AISaveBackupRotator.new(3)
	var steps: Array = r.plan_rotation("save.dat", [1, 2])
	# Ana dosya bak.1'e taşınmalı
	var found_main: bool = false
	for step in steps:
		if str(step["from"]) == "save.dat" \
				and str(step["to"]) == "save.dat.bak.1":
			found_main = true
	if not found_main:
		return _fail(name, "ana dosya bak.1'e taşınmalı")
	return _ok(name)


static func _test_rotator_eviction() -> Dictionary:
	var name := "Rotator sınır aşımı silme"
	var r := AISaveBackupRotator.new(3)
	# 3 yedek varken rotasyon — en eskisi silinir
	var steps: Array = r.plan_rotation("s", [1, 2, 3])
	var found_delete: bool = false
	for step in steps:
		if str(step["action"]) == "delete":
			found_delete = true
	if not found_delete:
		return _fail(name, "sınırı aşan yedek silinmeli")
	return _ok(name)


static func _test_restorer_select() -> Dictionary:
	var name := "Restorer sağlam yedek seçimi"
	var restorer := AISaveBackupRestorer.new()
	# Yedek 1 bozuk, yedek 2 sağlam — 2 seçilmeli
	var result: AISaveBackupRestorer.RestoreResult = \
		restorer.select_restore_source("save.dat", {1: false, 2: true})
	if not result.success:
		return _fail(name, "sağlam yedek bulunmalı")
	if result.chosen_index != 2:
		return _fail(name, "ilk sağlam yedek (2) seçilmeli")
	return _ok(name)


static func _test_restorer_all_corrupt() -> Dictionary:
	var name := "Restorer hepsi bozuk"
	var restorer := AISaveBackupRestorer.new()
	var result: AISaveBackupRestorer.RestoreResult = \
		restorer.select_restore_source(
			"save.dat", {1: false, 2: false, 3: false}
		)
	if result.success:
		return _fail(name, "hepsi bozukken başarısız olmalı")
	return _ok(name)


static func _test_corruption_recovery() -> Dictionary:
	var name := "CorruptionRecovery strateji seçimi"
	var rec := AISaveCorruptionRecovery.new()
	# Bozuk + yedek var -> geri yükle
	var with_backup: AISaveCorruptionRecovery.RecoveryPlan = \
		rec.plan_recovery(
			AISaveCorruptionRecovery.CorruptionType.UNPARSEABLE, true
		)
	if with_backup.strategy != AISaveCorruptionRecovery.RecoveryStrategy \
			.RESTORE_BACKUP:
		return _fail(name, "bozuk+yedek -> geri yükleme olmalı")
	# Bozuk + yedek yok -> kurtarılamaz
	var no_backup: AISaveCorruptionRecovery.RecoveryPlan = \
		rec.plan_recovery(
			AISaveCorruptionRecovery.CorruptionType.TAMPERED, false
		)
	if no_backup.strategy != AISaveCorruptionRecovery.RecoveryStrategy \
			.UNRECOVERABLE:
		return _fail(name, "bozuk+yedek yok -> kurtarılamaz olmalı")
	return _ok(name)


# ============================================================
# VERSIONING
# ============================================================

static func _test_version_compatible() -> Dictionary:
	var name := "Version uyumlu sürüm"
	var checker := AISaveVersionChecker.new(3)
	# Aynı sürüm — uyumlu
	if not checker.can_load(3):
		return _fail(name, "aynı sürüm yüklenebilmeli")
	# Eski sürüm — geçişle yüklenebilir
	if not checker.needs_migration(1):
		return _fail(name, "eski sürüm geçiş gerektirmeli")
	return _ok(name)


static func _test_version_too_new() -> Dictionary:
	var name := "Version çok yeni kayıt"
	var checker := AISaveVersionChecker.new(3)
	# Kayıt oyundan yeni — yüklenemez
	if checker.can_load(5):
		return _fail(name, "oyundan yeni kayıt yüklenememeli")
	if not checker.is_too_new(5):
		return _fail(name, "v5 > v3 too_new olmalı")
	return _ok(name)


static func _test_migration_chain() -> Dictionary:
	var name := "Migration tam zincir"
	var registry := AISaveMigrationRegistry.new()
	registry.register(1, func(d: Dictionary) -> Dictionary:
		var copy: Dictionary = d.duplicate()
		copy["version"] = 2
		return copy)
	registry.register(2, func(d: Dictionary) -> Dictionary:
		var copy: Dictionary = d.duplicate()
		copy["version"] = 3
		return copy)
	var engine := AISaveMigrationEngine.new(registry)
	var result: AISaveMigrationEngine.MigrationResult = engine.migrate(
		{"data": "x"}, 1, 3
	)
	if not result.success:
		return _fail(name, "tam zincir başarılı olmalı")
	if result.steps_applied != 2:
		return _fail(name, "2 geçiş adımı uygulanmalı")
	return _ok(name)


static func _test_migration_incomplete() -> Dictionary:
	var name := "Migration eksik zincir"
	var registry := AISaveMigrationRegistry.new()
	# Sadece v1->v2 kayıtlı; v2->v3 yok
	registry.register(1, func(d: Dictionary) -> Dictionary:
		return d.duplicate())
	var engine := AISaveMigrationEngine.new(registry)
	var result: AISaveMigrationEngine.MigrationResult = engine.migrate(
		{"data": "x"}, 1, 3
	)
	if result.success:
		return _fail(name, "eksik zincir başarısız olmalı")
	return _ok(name)


static func _test_migration_noop() -> Dictionary:
	var name := "Migration geçiş gerekmez"
	var engine := AISaveMigrationEngine.new()
	# Kaynak == hedef
	var result: AISaveMigrationEngine.MigrationResult = engine.migrate(
		{"data": "x"}, 3, 3
	)
	if not result.success:
		return _fail(name, "geçiş gerekmeyince başarılı olmalı")
	if result.steps_applied != 0:
		return _fail(name, "geçiş adımı olmamalı")
	return _ok(name)


# ============================================================
# AUTOSAVE
# ============================================================

static func _test_autosave_interval() -> Dictionary:
	var name := "Autosave aralık tetiği"
	var s := AISaveAutosaveScheduler.new()
	s.set_interval(300.0)
	# Aralık dolmadan kayıt yok
	if bool(s.tick(100.0)["should_save"]):
		return _fail(name, "aralık dolmadan kayıt olmamalı")
	# Aralık dolunca kayıt
	if not bool(s.tick(250.0)["should_save"]):
		return _fail(name, "aralık dolunca kayıt olmalı")
	return _ok(name)


static func _test_autosave_unsafe() -> Dictionary:
	var name := "Autosave güvensiz bölge"
	var s := AISaveAutosaveScheduler.new()
	s.set_interval(100.0)
	s.set_save_safe(false)
	# Aralık dolsa bile güvensizken kayıt yok
	if bool(s.tick(200.0)["should_save"]):
		return _fail(name, "güvensiz bölgede kayıt bekletilmeli")
	return _ok(name)


static func _test_checkpoint_critical() -> Dictionary:
	var name := "Checkpoint kritik olay"
	var t := AISaveCheckpointTrigger.new()
	var result: Dictionary = t.notify_event("level_complete")
	if not bool(result["should_save"]):
		return _fail(name, "kritik olay hemen kaydetmeli")
	# Bilinmeyen olay tetik yapmamalı
	if bool(t.notify_event("rastgele_olay")["should_save"]):
		return _fail(name, "bilinmeyen olay tetik yapmamalı")
	return _ok(name)


static func _test_checkpoint_debounce() -> Dictionary:
	var name := "Checkpoint düşük olay debounce"
	var t := AISaveCheckpointTrigger.new()
	# İlk düşük olay — kayıt yok
	if bool(t.notify_event("area_entered")["should_save"]):
		return _fail(name, "tek düşük olay kayıt yapmamalı")
	# Eşiğe kadar birikince kayıt
	t.notify_event("area_entered")
	if not bool(t.notify_event("area_entered")["should_save"]):
		return _fail(name, "3 düşük olay birikince kayıt olmalı")
	return _ok(name)


static func _test_mobile_pause() -> Dictionary:
	var name := "MobilePause acil kayıt"
	var h := AISaveMobilePauseHandler.new()
	# Temizken arka plan — kayıt yok
	if bool(h.on_app_background()["should_save"]):
		return _fail(name, "temiz durumda arka plan kayıt yapmamalı")
	# Kirliyken arka plan — acil kayıt
	h.mark_dirty()
	var result: Dictionary = h.on_app_background()
	if not bool(result["should_save"]):
		return _fail(name, "kirli durumda arka plan acil kayıt yapmalı")
	if str(result["scope"]) != "minimal":
		return _fail(name, "acil kayıt minimal kapsamlı olmalı")
	return _ok(name)


static func _test_battery_warning() -> Dictionary:
	var name := "BatteryWarning koruyucu kayıt"
	var h := AISaveBatteryWarningHandler.new()
	# Normal pil — kayıt yok
	if bool(h.report_battery(50.0, false)["should_save"]):
		return _fail(name, "normal pilde kayıt olmamalı")
	# Kritik pil — koruyucu kayıt
	if not bool(h.report_battery(10.0, false)["should_save"]):
		return _fail(name, "kritik pilde koruyucu kayıt olmalı")
	# Tekrar kritik — tek seferlik, kayıt yok
	if bool(h.report_battery(10.0, false)["should_save"]):
		return _fail(name, "kritik kayıt tek seferlik olmalı")
	return _ok(name)


# ============================================================
# PERSISTENCE HELPERS
# ============================================================

static func _test_serializer_roundtrip() -> Dictionary:
	var name := "Serializer encode/decode round-trip"
	var registry := AISaveSerializerRegistry.new()
	registry.register(
		"Point",
		func(v: Variant) -> Dictionary:
			var dict: Dictionary = v
			return {"x": dict["x"], "y": dict["y"]},
		func(d: Variant) -> Dictionary:
			var dict: Dictionary = d
			return {"x": dict["x"], "y": dict["y"]}
	)
	var encoded: Dictionary = registry.encode("Point", {"x": 3, "y": 7})
	if not bool(encoded["ok"]):
		return _fail(name, "encode başarılı olmalı")
	var decoded: Dictionary = registry.decode(encoded["encoded"])
	if not bool(decoded["ok"]):
		return _fail(name, "decode başarılı olmalı")
	var value: Dictionary = decoded["value"]
	if int(value["x"]) != 3:
		return _fail(name, "round-trip değeri korumalı")
	return _ok(name)


static func _test_serializer_unknown() -> Dictionary:
	var name := "Serializer bilinmeyen tip"
	var registry := AISaveSerializerRegistry.new()
	var encoded: Dictionary = registry.encode("KayitliDegil", 42)
	if bool(encoded["ok"]):
		return _fail(name, "kayıtlı olmayan tip reddedilmeli")
	return _ok(name)


static func _test_screenshot_scale() -> Dictionary:
	var name := "Screenshot ölçekleme"
	var cap := AISaveScreenshotCapturer.new()
	# Büyük kaynak küçültülmeli
	var big_scale: float = cap.compute_scale(1920, 1080)
	if big_scale >= 1.0:
		return _fail(name, "büyük kaynak küçültülmeli (<1.0)")
	# Küçük kaynak büyütülmemeli
	var small_scale: float = cap.compute_scale(100, 100)
	if small_scale != 1.0:
		return _fail(name, "küçük kaynak büyütülmemeli (=1.0)")
	return _ok(name)


static func _test_loadstate_progress() -> Dictionary:
	var name := "LoadState aşama ilerlemesi"
	var ls := AISaveLoadState.new()
	ls.begin()
	# Doğru sırada ilerleme
	var advance: Dictionary = ls.advance(AISaveLoadState.LoadPhase.READING)
	if not bool(advance["ok"]):
		return _fail(name, "doğru aşamada ilerleme başarılı olmalı")
	# Sıra dışı ilerleme reddedilmeli
	var wrong: Dictionary = ls.advance(AISaveLoadState.LoadPhase.APPLYING)
	if bool(wrong["ok"]):
		return _fail(name, "sıra dışı ilerleme reddedilmeli")
	return _ok(name)


static func _test_loadstate_failure() -> Dictionary:
	var name := "LoadState başarısızlık"
	var ls := AISaveLoadState.new()
	ls.begin()
	ls.fail("test hatası")
	if not ls.is_failed():
		return _fail(name, "fail çağrısı başarısız işaretlemeli")
	# Başarısız sonrası ilerleme olmamalı
	var advance: Dictionary = ls.advance(AISaveLoadState.LoadPhase.READING)
	if bool(advance["ok"]):
		return _fail(name, "başarısız durumda ilerleme olmamalı")
	if ls.failed_phase_name().is_empty():
		return _fail(name, "başarısızlık aşaması kaydedilmeli")
	return _ok(name)
