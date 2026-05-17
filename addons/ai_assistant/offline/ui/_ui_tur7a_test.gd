@tool
class_name AIUITur7ATest
extends RefCounted

## UI Katmanı Tur 7A — Offline UI + Audio UI Self-Test
##
## Sıkı testler: offline/ui (connection_indicator, capability_view,
## sync_queue_view, bandwidth_dashboard, cache_management,
## wifi_only_dialog), audio/ui (audio_workshop, bus_mixer_panel,
## procedural_sfx_designer, music_layering_view, audio_budget_gauge,
## genre_template_picker).


static func run_all() -> Array:
	var results: Array = []

	# Offline UI
	results.append(_b("UI7A: Offline", _test_connection_indicator()))
	results.append(_b("UI7A: Offline", _test_capability_view()))
	results.append(_b("UI7A: Offline", _test_sync_queue_view()))
	results.append(_b("UI7A: Offline", _test_bandwidth_dashboard()))
	results.append(_b("UI7A: Offline", _test_cache_management()))
	results.append(_b("UI7A: Offline", _test_wifi_dialog()))

	# Audio UI
	results.append(_b("UI7A: Audio", _test_audio_workshop()))
	results.append(_b("UI7A: Audio", _test_bus_mixer()))
	results.append(_b("UI7A: Audio", _test_bus_mixer_solo()))
	results.append(_b("UI7A: Audio", _test_sfx_designer()))
	results.append(_b("UI7A: Audio", _test_music_layering()))
	results.append(_b("UI7A: Audio", _test_budget_gauge()))
	results.append(_b("UI7A: Audio", _test_genre_picker()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# OFFLINE UI
# ============================================================

static func _test_connection_indicator() -> Dictionary:
	var name := "ConnectionIndicator durum eşlemesi"
	var indicator := AIOfflineConnectionIndicator.new()
	# Çevrimiçi
	indicator.update_from_connection(true, false, false)
	if indicator.state != AIOfflineConnectionIndicator.IndicatorState \
			.ONLINE:
		return _fail(name, "çevrimiçi durum ONLINE olmalı")
	# Çevrimdışı — sorun göstermeli
	indicator.update_from_connection(false, false, false)
	if not indicator.shows_problem():
		return _fail(name, "çevrimdışı sorun göstermeli")
	# Yavaş bağlantı
	indicator.update_from_connection(true, true, false)
	if indicator.state != AIOfflineConnectionIndicator.IndicatorState \
			.SLOW:
		return _fail(name, "yavaş bağlantı SLOW olmalı")
	return _ok(name)


static func _test_capability_view() -> Dictionary:
	var name := "CapabilityView yetenek durumu"
	var view := AIOfflineCapabilityView.new()
	# Çevrimiçi — LLM kullanılabilir
	view.set_online(true)
	if not view.is_available("llm_generation"):
		return _fail(name, "çevrimiçi LLM kullanılabilir olmalı")
	# Çevrimdışı — LLM kullanılamaz, cache kullanılabilir
	view.set_online(false)
	if view.is_available("llm_generation"):
		return _fail(name, "çevrimdışı LLM kullanılamaz olmalı")
	if not view.is_available("cached_results"):
		return _fail(name, "çevrimdışı önbellek kullanılabilir olmalı")
	return _ok(name)


static func _test_sync_queue_view() -> Dictionary:
	var name := "SyncQueueView satır durumu"
	var view := AIOfflineSyncQueueView.new()
	var ops: Array = [
		{"id": "a", "type": "save_sync", "retry_count": 0},
		{"id": "b", "type": "analytics", "retry_count": 2},
	]
	var rows: Array = view.build_rows(ops)
	if rows.size() != 2:
		return _fail(name, "her işlem için bir satır olmalı")
	# b satırı retry'lı — RETRYING durumu
	var b_row: Dictionary = rows[1]
	if int(b_row["status"]) != AIOfflineSyncQueueView.RowStatus.RETRYING:
		return _fail(name, "retry'lı işlem RETRYING olmalı")
	# Özet
	var summary: Dictionary = view.build_summary(ops)
	if int(summary["total"]) != 2 or int(summary["retrying"]) != 1:
		return _fail(name, "özet sayıları doğru olmalı")
	return _ok(name)


static func _test_bandwidth_dashboard() -> Dictionary:
	var name := "BandwidthDashboard sınır göstergesi"
	var dashboard := AIOfflineBandwidthDashboard.new()
	# Sınırsız
	var unlimited: Dictionary = dashboard.build_cap_gauge(1000, 0)
	if int(unlimited["status"]) != AIOfflineBandwidthDashboard.CapStatus \
			.UNLIMITED:
		return _fail(name, "sınırsız UNLIMITED olmalı")
	# Aşım
	var exceeded: Dictionary = dashboard.build_cap_gauge(100, 100)
	if int(exceeded["status"]) != AIOfflineBandwidthDashboard.CapStatus \
			.EXCEEDED:
		return _fail(name, "sınır aşımı EXCEEDED olmalı")
	# Kullanım grafiği — büyükten küçüğe
	var chart: Array = dashboard.build_usage_chart({
		"llm": 5000, "asset": 10000,
	})
	if int((chart[0] as Dictionary)["bytes"]) != 10000:
		return _fail(name, "grafik büyükten küçüğe sıralanmalı")
	return _ok(name)


static func _test_cache_management() -> Dictionary:
	var name := "CacheManagement temizleme eylemi"
	var mgmt := AIOfflineCacheManagement.new()
	mgmt.update_stats("embedding", 50, 0.8, 1024 * 100)
	# Dolu önbellek temizlenebilir
	var action: Dictionary = mgmt.clear_action("embedding")
	if not bool(action["can_clear"]):
		return _fail(name, "dolu önbellek temizlenebilmeli")
	# Temizlendikten sonra
	mgmt.mark_cleared("embedding")
	var after: Dictionary = mgmt.clear_action("embedding")
	if bool(after["can_clear"]):
		return _fail(name, "boş önbellek temizlenememeli")
	return _ok(name)


static func _test_wifi_dialog() -> Dictionary:
	var name := "WifiOnlyDialog karar"
	var dialog := AIOfflineWifiOnlyDialog.new()
	dialog.prepare("Varlık paketi", 10 * 1024 * 1024)
	# Mobil veri kararı
	dialog.record_decision(AIOfflineWifiOnlyDialog.DialogChoice.USE_MOBILE)
	if not dialog.proceeds_now():
		return _fail(name, "mobil veri kararı proceeds_now olmalı")
	# Wi-Fi bekleme kararı
	var dialog2 := AIOfflineWifiOnlyDialog.new()
	dialog2.prepare("Model", 50 * 1024 * 1024)
	dialog2.record_decision(
		AIOfflineWifiOnlyDialog.DialogChoice.WAIT_WIFI
	)
	if not dialog2.waits_for_wifi():
		return _fail(name, "Wi-Fi kararı waits_for_wifi olmalı")
	return _ok(name)


# ============================================================
# AUDIO UI
# ============================================================

static func _test_audio_workshop() -> Dictionary:
	var name := "AudioWorkshop panel geçişi"
	var workshop := AIAudioWorkshop.new()
	# Panel geçişi
	workshop.switch_panel(AIAudioWorkshop.AudioPanel.SFX_DESIGNER)
	if workshop.active_panel != AIAudioWorkshop.AudioPanel.SFX_DESIGNER:
		return _fail(name, "panel geçişi çalışmalı")
	# Geri navigasyon
	if not workshop.go_back():
		return _fail(name, "geri navigasyon çalışmalı")
	if workshop.active_panel != AIAudioWorkshop.AudioPanel.BUS_MIXER:
		return _fail(name, "geri navigasyon önceki panele dönmeli")
	return _ok(name)


static func _test_bus_mixer() -> Dictionary:
	var name := "BusMixer ses + mute"
	var mixer := AIAudioBusMixerPanel.new()
	mixer.add_standard_channels()
	# Ses ayarı — sınıra çekilmeli
	mixer.set_volume("Music", 100.0)
	var music: AIAudioBusMixerPanel.ChannelStrip = mixer.get_channel(
		"Music"
	)
	if music.volume_db > AIAudioBusMixerPanel.MAX_DB:
		return _fail(name, "ses üst sınıra çekilmeli")
	# Mute — duyulmaz
	mixer.set_muted("SFX", true)
	if mixer.is_audible("SFX"):
		return _fail(name, "susturulan kanal duyulmamalı")
	return _ok(name)


static func _test_bus_mixer_solo() -> Dictionary:
	var name := "BusMixer solo mantığı"
	var mixer := AIAudioBusMixerPanel.new()
	mixer.add_channel("Music")
	mixer.add_channel("SFX")
	# Music solo — sadece Music duyulur
	mixer.set_soloed("Music", true)
	if not mixer.is_audible("Music"):
		return _fail(name, "solo kanal duyulmalı")
	if mixer.is_audible("SFX"):
		return _fail(name, "solo varken solo olmayan kanal duyulmamalı")
	return _ok(name)


static func _test_sfx_designer() -> Dictionary:
	var name := "SfxDesigner parametre düzenleme"
	var designer := AIAudioSfxDesigner.new()
	designer.load_preset("jump", {"frequency": 300.0})
	# Parametre ayarı
	designer.set_param("frequency", 500.0)
	if not is_equal_approx(designer.get_param("frequency"), 500.0):
		return _fail(name, "parametre ayarlanmalı")
	if not designer.is_modified("frequency"):
		return _fail(name, "değiştirilen parametre işaretlenmeli")
	# Sınır dışı — kliplenmeli
	var result: Dictionary = designer.set_param("frequency", 99999.0)
	if not bool(result["clamped"]):
		return _fail(name, "sınır dışı değer kliplenmeli")
	return _ok(name)


static func _test_music_layering() -> Dictionary:
	var name := "MusicLayeringView eşik mantığı"
	var view := AIAudioMusicLayeringView.new()
	view.add_stem("base", 0, "Temel", 0.0)
	view.add_stem("melody", 1, "Melodi", 0.3)
	view.add_stem("drums", 2, "Davul", 0.6)
	# Önizleme yoğunluğu 0.5
	view.set_preview_intensity(0.5)
	# base (0.0) ve melody (0.3) aktif, drums (0.6) değil
	if not view.is_active_at_preview(0):
		return _fail(name, "düşük eşikli katman aktif olmalı")
	if view.is_active_at_preview(2):
		return _fail(name, "yüksek eşikli katman pasif olmalı")
	# Eşikler artan — tutarlı
	if not view.thresholds_consistent():
		return _fail(name, "artan eşikler tutarlı olmalı")
	return _ok(name)


static func _test_budget_gauge() -> Dictionary:
	var name := "AudioBudgetGauge durum"
	var gauge := AIAudioBudgetGauge.new()
	# Sağlıklı
	var healthy: Dictionary = gauge.build_gauge(
		10 * 1024 * 1024, 100 * 1024 * 1024
	)
	if int(healthy["state"]) != AIAudioBudgetGauge.GaugeState.HEALTHY:
		return _fail(name, "düşük kullanım HEALTHY olmalı")
	# Kritik
	var critical: Dictionary = gauge.build_gauge(
		100 * 1024 * 1024, 100 * 1024 * 1024
	)
	if int(critical["state"]) != AIAudioBudgetGauge.GaugeState.CRITICAL:
		return _fail(name, "bütçe dolunca CRITICAL olmalı")
	# En büyük ses
	var largest: String = gauge.largest_sound({
		"a": 100, "b": 500, "c": 50,
	})
	if largest != "b":
		return _fail(name, "en büyük ses doğru bulunmalı")
	return _ok(name)


static func _test_genre_picker() -> Dictionary:
	var name := "GenreTemplatePicker seçim"
	var picker := AIAudioGenreTemplatePicker.new()
	if picker.card_count() != 9:
		return _fail(name, "9 tür kartı olmalı")
	# Geçerli tür seç
	if not picker.select_genre("horror_3d"):
		return _fail(name, "geçerli tür seçilebilmeli")
	if not picker.can_apply():
		return _fail(name, "seçim sonrası uygulanabilir olmalı")
	# Uygula
	picker.mark_applied()
	if picker.can_apply():
		return _fail(name, "uygulandıktan sonra tekrar uygulanamamalı")
	# Bilinmeyen tür reddi
	if picker.select_genre("olmayan_tur"):
		return _fail(name, "bilinmeyen tür reddedilmeli")
	return _ok(name)
