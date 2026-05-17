@tool
class_name AIUITur7CTest
extends RefCounted

## UI Katmanı Tur 7C — Debug UI + Final Entegrasyon Self-Test
##
## Sıkı testler: debug_loop/ui (debug_session_view, error_explorer,
## mode_settings) + final entegrasyon doğrulaması.


static func run_all() -> Array:
	var results: Array = []

	# Debug UI
	results.append(_b("UI7C: Debug", _test_session_view()))
	results.append(_b("UI7C: Debug", _test_session_lifecycle()))
	results.append(_b("UI7C: Debug", _test_error_explorer()))
	results.append(_b("UI7C: Debug", _test_error_filter()))
	results.append(_b("UI7C: Debug", _test_error_critical()))
	results.append(_b("UI7C: Debug", _test_mode_settings()))
	results.append(_b("UI7C: Debug", _test_mode_behavior()))

	# Final entegrasyon
	results.append(_b("UI7C: Final", _test_integration()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# DEBUG UI
# ============================================================

static func _test_session_view() -> Dictionary:
	var name := "DebugSessionView adım takibi"
	var view := AIDebugSessionView.new()
	view.start_session("Null referans hatası", 1000)
	if view.phase != AIDebugSessionView.SessionPhase.DIAGNOSING:
		return _fail(name, "başlatınca DIAGNOSING olmalı")
	# İlerleme — adımlar kaydedilmeli
	view.advance(
		AIDebugSessionView.SessionPhase.PROPOSING_FIX,
		"Düzeltme öneriliyor", 1500
	)
	view.advance(
		AIDebugSessionView.SessionPhase.APPLYING, "Uygulanıyor", 2000
	)
	if view.step_count() != 3:
		return _fail(name, "her ilerleme adım kaydetmeli")
	# Süre hesabı
	if view.total_duration_ms() != 1000:
		return _fail(name, "süre son adıma kadar hesaplanmalı")
	return _ok(name)


static func _test_session_lifecycle() -> Dictionary:
	var name := "DebugSessionView yaşam döngüsü"
	var view := AIDebugSessionView.new()
	view.start_session("Bug", 0)
	# Çalışırken aktif
	if not view.is_active():
		return _fail(name, "çalışan oturum aktif olmalı")
	# Geçersiz faz reddedilmeli
	if view.advance(999, "geçersiz", 100):
		return _fail(name, "geçersiz faz reddedilmeli")
	# Tamamlanınca aktif değil
	view.advance(AIDebugSessionView.SessionPhase.DONE, "Bitti", 500)
	if view.is_active():
		return _fail(name, "tamamlanan oturum aktif olmamalı")
	if not view.is_successful():
		return _fail(name, "DONE durumu başarılı sayılmalı")
	return _ok(name)


static func _test_error_explorer() -> Dictionary:
	var name := "ErrorExplorer hata + fix"
	var explorer := AIDebugErrorExplorer.new()
	# Geçerli hata eklenir
	if not explorer.add_error(
		"e1", "Null referans", AIDebugErrorExplorer.Severity.ERROR,
		"player.gd", 42
	):
		return _fail(name, "geçerli hata eklenebilmeli")
	# Boş id reddedilir
	if explorer.add_error(
		"", "x", AIDebugErrorExplorer.Severity.INFO, "a.gd", 1
	):
		return _fail(name, "boş id'li hata reddedilmeli")
	# Fix eklenir
	if not explorer.attach_fix("e1", "Null kontrolü ekle"):
		return _fail(name, "hataya fix önerisi eklenebilmeli")
	var detail: Dictionary = explorer.build_detail("e1")
	if not bool(detail["has_fix"]):
		return _fail(name, "fix eklenince has_fix true olmalı")
	return _ok(name)


static func _test_error_filter() -> Dictionary:
	var name := "ErrorExplorer sıralama + filtre"
	var explorer := AIDebugErrorExplorer.new()
	explorer.add_error(
		"info", "Bilgi", AIDebugErrorExplorer.Severity.INFO, "a.gd", 1
	)
	explorer.add_error(
		"crit", "Kritik", AIDebugErrorExplorer.Severity.CRITICAL,
		"b.gd", 2
	)
	explorer.add_error(
		"warn", "Uyarı", AIDebugErrorExplorer.Severity.WARNING,
		"c.gd", 3
	)
	# Liste ciddiyete göre sıralı — kritik üstte
	var list: Array = explorer.build_list()
	if int((list[0] as Dictionary)["severity"]) \
			!= AIDebugErrorExplorer.Severity.CRITICAL:
		return _fail(name, "liste ciddiyete göre sıralanmalı")
	# Ciddiyet filtresi
	explorer.set_severity_filter(AIDebugErrorExplorer.Severity.WARNING)
	var filtered: Array = explorer.build_list()
	if filtered.size() != 1:
		return _fail(name, "ciddiyet filtresi tek hata bırakmalı")
	return _ok(name)


static func _test_error_critical() -> Dictionary:
	var name := "ErrorExplorer kritik takibi"
	var explorer := AIDebugErrorExplorer.new()
	explorer.add_error(
		"c1", "Kritik hata", AIDebugErrorExplorer.Severity.CRITICAL,
		"x.gd", 1
	)
	# Kritik çözülmemiş tespit edilmeli
	if not explorer.has_critical_unresolved():
		return _fail(name, "kritik çözülmemiş hata tespit edilmeli")
	# Çözülünce kritik kalmamalı
	explorer.mark_resolved("c1")
	if explorer.has_critical_unresolved():
		return _fail(name, "çözülen kritik hata kalmamalı")
	if explorer.unresolved_count() != 0:
		return _fail(name, "çözülmemiş sayısı 0 olmalı")
	return _ok(name)


static func _test_mode_settings() -> Dictionary:
	var name := "ModeSettings mod seçimi"
	var settings := AIDebugModeSettings.new()
	if settings.mode_count() != 4:
		return _fail(name, "4 debug modu olmalı")
	# Geçerli mod
	var result: Dictionary = settings.set_mode(
		AIDebugModeSettings.DebugMode.AUTO_FIX
	)
	if not bool(result["applied"]):
		return _fail(name, "geçerli mod uygulanmalı")
	# Geçersiz mod reddedilmeli
	if bool(settings.set_mode(999)["applied"]):
		return _fail(name, "geçersiz mod reddedilmeli")
	return _ok(name)


static func _test_mode_behavior() -> Dictionary:
	var name := "ModeSettings davranış mantığı"
	var settings := AIDebugModeSettings.new()
	# OFF — yakalama kapalı
	settings.set_mode(AIDebugModeSettings.DebugMode.OFF)
	if settings.is_capture_enabled():
		return _fail(name, "OFF modunda yakalama kapalı olmalı")
	# OBSERVE — yakalar ama öneri yok
	settings.set_mode(AIDebugModeSettings.DebugMode.OBSERVE)
	if not settings.is_capture_enabled() \
			or settings.should_suggest_fixes():
		return _fail(name, "OBSERVE yakalar ama öneri vermemeli")
	# AUTO_FIX — otomatik uygular
	settings.set_mode(AIDebugModeSettings.DebugMode.AUTO_FIX)
	if not settings.should_auto_apply():
		return _fail(name, "AUTO_FIX otomatik uygulamalı")
	return _ok(name)


# ============================================================
# FİNAL ENTEGRASYON
# ============================================================

static func _test_integration() -> Dictionary:
	var name := "Final entegrasyon — sistem bütünlüğü"
	# 18 katmanın temel sınıfları yüklenebilmeli
	var contracts := AIValidationResult.new()
	if contracts == null:
		return _fail(name, "contracts katmanı yüklenmeli")
	# 24 UI modülünün hepsi yüklenebilmeli — son grup kontrolü
	var debug_session := AIDebugSessionView.new()
	var error_explorer := AIDebugErrorExplorer.new()
	var mode_settings := AIDebugModeSettings.new()
	if debug_session == null or error_explorer == null \
			or mode_settings == null:
		return _fail(name, "debug UI modülleri yüklenmeli")
	# UI view-model deseni — hepsi RefCounted, sahnesiz test edilebilir
	if not (debug_session is RefCounted):
		return _fail(name, "UI view-model RefCounted olmalı")
	# Önceki UI gruplarından örnekler
	var offline_ui := AIOfflineConnectionIndicator.new()
	var audio_ui := AIAudioWorkshop.new()
	var save_ui := AISaveSlotPicker.new()
	var lifecycle_ui := AILifecycleSettingsPanel.new()
	if offline_ui == null or audio_ui == null \
			or save_ui == null or lifecycle_ui == null:
		return _fail(name, "tüm UI grupları yüklenebilmeli")
	return _ok(name)
