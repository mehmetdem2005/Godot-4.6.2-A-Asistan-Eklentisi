@tool
class_name AIUITur7BTest
extends RefCounted

## UI Katmanı Tur 7B — Save/Load UI + Lifecycle UI Self-Test
##
## Sıkı testler: save_load/ui (slot_card, slot_picker, save_menu,
## save_progress_indicator, corruption_recovery_dialog,
## migration_notice_dialog), lifecycle/ui (lifecycle_settings_panel,
## permission_status_view, notification_settings).


static func run_all() -> Array:
	var results: Array = []

	# Save/Load UI
	results.append(_b("UI7B: Save", _test_slot_card()))
	results.append(_b("UI7B: Save", _test_slot_picker()))
	results.append(_b("UI7B: Save", _test_save_menu()))
	results.append(_b("UI7B: Save", _test_progress_indicator()))
	results.append(_b("UI7B: Save", _test_corruption_dialog()))
	results.append(_b("UI7B: Save", _test_migration_dialog()))

	# Lifecycle UI
	results.append(_b("UI7B: Lifecycle", _test_settings_panel()))
	results.append(_b("UI7B: Lifecycle", _test_permission_view()))
	results.append(_b("UI7B: Lifecycle", _test_notification_settings()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# SAVE/LOAD UI
# ============================================================

static func _test_slot_card() -> Dictionary:
	var name := "SlotCard durum kartları"
	var card := AISaveSlotCard.new("slot_1")
	# Boş slot — yüklenemez
	card.set_empty()
	if card.is_loadable():
		return _fail(name, "boş slot yüklenememeli")
	# Dolu slot — yüklenebilir
	card.set_filled({"character_name": "Kahraman", "playtime": 3900.0})
	if not card.is_loadable():
		return _fail(name, "dolu slot yüklenebilmeli")
	var card_data: Dictionary = card.build_card()
	if str(card_data["title"]) != "Kahraman":
		return _fail(name, "dolu slot başlığı metadata'dan gelmeli")
	# Bozuk slot — silinebilir ama yüklenemez
	card.set_corrupted()
	if card.is_loadable() or not card.is_deletable():
		return _fail(name, "bozuk slot silinebilir ama yüklenemez olmalı")
	return _ok(name)


static func _test_slot_picker() -> Dictionary:
	var name := "SlotPicker mod + seçim"
	var picker := AISaveSlotPicker.new()
	if picker.slot_count() != 5:
		return _fail(name, "5 slot olmalı (3 manuel + auto + quick)")
	# Yükleme modu — dolu slot seçilebilir
	picker.set_mode(AISaveSlotPicker.PickerMode.LOAD)
	picker.set_slot_filled("slot_1", {"genre": "rpg_topdown"})
	var load_result: Dictionary = picker.select_slot("slot_1")
	if not bool(load_result["selected"]):
		return _fail(name, "yükleme modunda dolu slot seçilebilmeli")
	# Yükleme modunda boş slot reddedilmeli
	picker.set_slot_empty("slot_2")
	var empty_result: Dictionary = picker.select_slot("slot_2")
	if bool(empty_result["selected"]):
		return _fail(name, "yükleme modunda boş slot reddedilmeli")
	return _ok(name)


static func _test_save_menu() -> Dictionary:
	var name := "SaveMenu onay akışı"
	var menu := AISaveMenu.new()
	menu.open(true)  # kaydetme modu
	menu.picker().set_slot_filled("slot_1", {"genre": "fps_3d"})
	# Dolu slota kayıt — üzerine yazma onayı istemeli
	var save_req: Dictionary = menu.request_save("slot_1")
	if str(save_req["action"]) != "need_confirm":
		return _fail(name, "dolu slota kayıt onay istemeli")
	if not menu.awaiting_confirmation():
		return _fail(name, "menü onay bekler durumda olmalı")
	# Onay — kaydetme eylemi
	var confirmed: Dictionary = menu.confirm()
	if str(confirmed["confirmed_action"]) != "save":
		return _fail(name, "onay kaydetme eylemini döndürmeli")
	return _ok(name)


static func _test_progress_indicator() -> Dictionary:
	var name := "SaveProgressIndicator yaşam döngüsü"
	var indicator := AISaveProgressIndicator.new()
	# Kayıt başladı — görünür
	indicator.on_save_started()
	if not indicator.is_visible():
		return _fail(name, "kayıt başlayınca gösterge görünmeli")
	if not indicator.is_saving():
		return _fail(name, "kayıt sırasında saving durumunda olmalı")
	# Başarı — sonra otomatik gizlenmeli
	indicator.on_save_succeeded()
	indicator.tick(1.0)
	if not indicator.is_visible():
		return _fail(name, "başarı göstergesi süre dolmadan görünmeli")
	indicator.tick(2.0)
	if indicator.is_visible():
		return _fail(name, "süre dolunca gösterge gizlenmeli")
	return _ok(name)


static func _test_corruption_dialog() -> Dictionary:
	var name := "CorruptionRecoveryDialog seçenekler"
	# Yedek var — restore seçeneği olmalı
	var dialog := AISaveCorruptionDialog.new()
	dialog.prepare("slot_1", true)
	var options: Array = dialog.button_options()
	var has_restore: bool = false
	for opt in options:
		if str((opt as Dictionary)["choice"]) == "restore_backup":
			has_restore = true
	if not has_restore:
		return _fail(name, "yedek varsa restore seçeneği olmalı")
	# Yedek yok — restore seçeneği olmamalı
	var no_backup := AISaveCorruptionDialog.new()
	no_backup.prepare("slot_2", false)
	var restore_result: Dictionary = no_backup.record_decision(
		AISaveCorruptionDialog.RecoveryChoice.RESTORE_BACKUP
	)
	if bool(restore_result["recorded"]):
		return _fail(name, "yedek yokken restore seçilememeli")
	return _ok(name)


static func _test_migration_dialog() -> Dictionary:
	var name := "MigrationNoticeDialog türler"
	var dialog := AISaveMigrationDialog.new()
	# Başarılı geçiş — bilgilendirme
	dialog.prepare_success(1, 3)
	if not dialog.is_informational():
		return _fail(name, "başarılı geçiş bilgilendirme olmalı")
	# Başarısız geçiş — sorun, yedek seçeneği
	dialog.prepare_failure(1, 3)
	if not dialog.is_problem():
		return _fail(name, "başarısız geçiş sorun olmalı")
	if (dialog.button_options() as Array).size() != 2:
		return _fail(name, "başarısız geçiş 2 buton (yedek) içermeli")
	return _ok(name)


# ============================================================
# LIFECYCLE UI
# ============================================================

static func _test_settings_panel() -> Dictionary:
	var name := "LifecycleSettingsPanel ayar"
	var panel := AILifecycleSettingsPanel.new()
	# Geçerli bool değişiklik
	var result: Dictionary = panel.set_value("vibration_enabled", false)
	if not bool(result["applied"]):
		return _fail(name, "geçerli bool ayar uygulanmalı")
	if not panel.has_changes():
		return _fail(name, "varsayılandan sapma değişiklik sayılmalı")
	# Yanlış tip reddedilmeli
	var bad: Dictionary = panel.set_value("vibration_enabled", "metin")
	if bool(bad["applied"]):
		return _fail(name, "yanlış tip değer reddedilmeli")
	# Bilinmeyen ayar reddedilmeli
	if bool(panel.set_value("olmayan_ayar", true)["applied"]):
		return _fail(name, "bilinmeyen ayar reddedilmeli")
	return _ok(name)


static func _test_permission_view() -> Dictionary:
	var name := "PermissionStatusView akış"
	var view := AILifecyclePermissionView.new()
	# Sorulmamış izin — doğrudan istenmeli
	var not_req: Dictionary = view.resolve_request_flow("notifications")
	if str(not_req["action"]) != "request":
		return _fail(name, "sorulmamış izin doğrudan istenmeli")
	# Verilmiş izin — istek gerekmemeli
	view.update_status(
		"notifications", AILifecyclePermissionView.PermStatus.GRANTED
	)
	var granted: Dictionary = view.resolve_request_flow("notifications")
	if str(granted["action"]) != "none":
		return _fail(name, "verilmiş izin için istek gerekmemeli")
	# Reddedilmiş izin — önce gerekçe gösterilmeli
	view.update_status(
		"storage", AILifecyclePermissionView.PermStatus.DENIED
	)
	var denied: Dictionary = view.resolve_request_flow("storage")
	if str(denied["action"]) != "show_rationale_first":
		return _fail(name, "reddedilmiş izin önce gerekçe göstermeli")
	return _ok(name)


static func _test_notification_settings() -> Dictionary:
	var name := "NotificationSettings ana + kanal"
	var settings := AILifecycleNotificationSettings.new()
	# Ana açık + kanal açık — effective
	if not settings.is_channel_effective("events"):
		return _fail(name, "ana+kanal açıkken effective olmalı")
	# Kanal kapatılınca — effective değil
	settings.set_channel("events", false)
	if settings.is_channel_effective("events"):
		return _fail(name, "kanal kapalıyken effective olmamalı")
	# Ana anahtar kapalı — hiçbir kanal effective değil
	settings.set_master(false)
	if settings.active_channel_count() != 0:
		return _fail(name, "ana kapalıyken hiçbir kanal aktif olmamalı")
	if not settings.all_silent():
		return _fail(name, "ana kapalıyken tüm bildirimler sessiz olmalı")
	return _ok(name)
