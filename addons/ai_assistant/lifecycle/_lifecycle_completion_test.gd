@tool
class_name AILifecycleCompletionTest
extends RefCounted

## Madde 10 — Lifecycle Tamamlama Self-Test
##
## Sıkı testler: device_control (wake_lock, back_button,
## screen_brightness, vibration), notifications (channels, scheduler,
## foreground_overlay, stub), deep_links (intent_handler, url_router,
## deferred_link), templates (lifecycle_templates).


static func run_all() -> Array:
	var results: Array = []

	# device_control
	results.append(_b("LifeExt: Device", _test_wake_lock()))
	results.append(_b("LifeExt: Device", _test_back_button()))
	results.append(_b("LifeExt: Device", _test_brightness()))
	results.append(_b("LifeExt: Device", _test_vibration()))

	# notifications
	results.append(_b("LifeExt: Notif", _test_channels()))
	results.append(_b("LifeExt: Notif", _test_scheduler()))
	results.append(_b("LifeExt: Notif", _test_scheduler_past()))
	results.append(_b("LifeExt: Notif", _test_overlay()))
	results.append(_b("LifeExt: Notif", _test_notification_stub()))

	# deep_links
	results.append(_b("LifeExt: DeepLink", _test_intent_parse()))
	results.append(_b("LifeExt: DeepLink", _test_intent_reject()))
	results.append(_b("LifeExt: DeepLink", _test_url_router()))
	results.append(_b("LifeExt: DeepLink", _test_deferred_resolve()))
	results.append(_b("LifeExt: DeepLink", _test_deferred_expiry()))

	# templates
	results.append(_b("LifeExt: Template", _test_templates()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# DEVICE CONTROL
# ============================================================

static func _test_wake_lock() -> Dictionary:
	var name := "WakeLock çoklu sahip"
	var wake := AILifecycleWakeLock.new()
	# İki sistem wake lock alır
	wake.acquire("cutscene")
	wake.acquire("video")
	if not wake.is_screen_kept_awake():
		return _fail(name, "wake lock varken ekran açık olmalı")
	# Biri bırakır — diğeri tutar
	wake.release("cutscene")
	if not wake.is_screen_kept_awake():
		return _fail(name, "biri bırakınca diğeri ekranı tutmalı")
	# Hepsi bırakır
	wake.release("video")
	if not wake.can_screen_sleep():
		return _fail(name, "hepsi bırakınca ekran sönebilmeli")
	return _ok(name)


static func _test_back_button() -> Dictionary:
	var name := "BackButton bağlam tabanlı"
	var back := AILifecycleBackButton.new()
	# Oyun ekranında geri — duraklat menüsü açılmalı
	back.push_screen(AILifecycleBackButton.SCREEN_GAMEPLAY)
	var in_game: Dictionary = back.handle_back()
	if str(in_game["action"]) != "open_pause":
		return _fail(name, "oyunda geri tuşu duraklat açmalı")
	# Duraklat menüsünde geri — oyuna dön
	var in_pause: Dictionary = back.handle_back()
	if str(in_pause["action"]) != "resume_game":
		return _fail(name, "duraklatta geri tuşu oyuna dönmeli")
	return _ok(name)


static func _test_brightness() -> Dictionary:
	var name := "ScreenBrightness pil tasarrufu"
	var brightness := AILifecycleScreenBrightness.new()
	brightness.capture_original(0.8)
	# Pil tasarrufu açık — yüksek parlaklık tavana çekilir
	brightness.set_power_save(true)
	var result: Dictionary = brightness.request_brightness(0.95)
	if not bool(result["clamped"]):
		return _fail(name, "tasarrufta yüksek parlaklık kısılmalı")
	if float(result["applied"]) > 0.65:
		return _fail(name, "tasarruf tavanı uygulanmalı")
	return _ok(name)


static func _test_vibration() -> Dictionary:
	var name := "Vibration debounce + ayar"
	var vibration := AILifecycleVibration.new()
	# İlk titreşim — çalışmalı
	var first: Dictionary = vibration.request("medium", 1000)
	if not bool(first["vibrate"]):
		return _fail(name, "ilk titreşim çalışmalı")
	# Hemen ardından — debounce engellemeli
	var second: Dictionary = vibration.request("light", 1010)
	if bool(second["vibrate"]):
		return _fail(name, "debounce yakın titreşimi engellemeli")
	# Kapalıyken — hiç titremez
	vibration.set_enabled(false)
	var disabled: Dictionary = vibration.request("heavy", 5000)
	if bool(disabled["vibrate"]):
		return _fail(name, "kapalıyken titreşim olmamalı")
	return _ok(name)


# ============================================================
# NOTIFICATIONS
# ============================================================

static func _test_channels() -> Dictionary:
	var name := "NotificationChannels tanım"
	var channels := AILifecycleNotificationChannels.new()
	channels.define_default_channels()
	if channels.channel_count() < 4:
		return _fail(name, "varsayılan kanallar tanımlanmalı")
	# Geçersiz kanal reddedilmeli
	if channels.define_channel("", "Boş", 1):
		return _fail(name, "boş id'li kanal reddedilmeli")
	return _ok(name)


static func _test_scheduler() -> Dictionary:
	var name := "NotificationScheduler planlama"
	var scheduler := AILifecycleNotificationScheduler.new()
	# Gelecek zamana planla
	var result: Dictionary = scheduler.schedule(
		"daily_1", "daily_reward", "Ödül", "Hazır!", 5000, 1000
	)
	if not bool(result["scheduled"]):
		return _fail(name, "geçerli bildirim planlanmalı")
	# Aynı id ile tekrar — çift bildirim olmamalı
	scheduler.schedule(
		"daily_1", "daily_reward", "Ödül", "Yeni", 6000, 1000
	)
	if scheduler.scheduled_count() != 1:
		return _fail(name, "aynı id çift bildirim yapmamalı")
	return _ok(name)


static func _test_scheduler_past() -> Dictionary:
	var name := "NotificationScheduler geçmiş zaman"
	var scheduler := AILifecycleNotificationScheduler.new()
	# Geçmiş zamana planlanamaz
	var result: Dictionary = scheduler.schedule(
		"old", "general", "Eski", "...", 500, 1000
	)
	if bool(result["scheduled"]):
		return _fail(name, "geçmiş zamana bildirim planlanmamalı")
	return _ok(name)


static func _test_overlay() -> Dictionary:
	var name := "ForegroundOverlay öncelik sırası"
	var overlay := AILifecycleForegroundOverlay.new()
	# Düşük ve yüksek öncelikli ekle
	overlay.enqueue("low", "Normal mesaj", 1, 3.0)
	overlay.enqueue("high", "Acil mesaj", 5, 3.0)
	# Tick — yüksek öncelik önce gösterilmeli
	overlay.tick(0.1)
	if overlay.current_message() != "Acil mesaj":
		return _fail(name, "yüksek öncelik önce gösterilmeli")
	return _ok(name)


static func _test_notification_stub() -> Dictionary:
	var name := "NotificationStub Phase 1"
	var stub := AILifecycleNotificationStub.new()
	# Phase 1 — native kullanılamaz
	if stub.is_available():
		return _fail(name, "Phase 1 native bildirim kullanılamaz")
	# Gönderim fallback'e yönlendirmeli
	var result: Dictionary = stub.send_native("Başlık", "Gövde", "general")
	if not bool(result["used_fallback"]):
		return _fail(name, "Phase 1 fallback kullanmalı")
	return _ok(name)


# ============================================================
# DEEP LINKS
# ============================================================

static func _test_intent_parse() -> Dictionary:
	var name := "IntentHandler link ayrıştırma"
	var handler := AILifecycleIntentHandler.new()
	var parsed: AILifecycleIntentHandler.ParsedLink = handler.parse(
		"mygame://event/halloween"
	)
	if not parsed.valid:
		return _fail(name, "geçerli link ayrıştırılmalı")
	if parsed.host != "event":
		return _fail(name, "host doğru ayrıştırılmalı")
	return _ok(name)


static func _test_intent_reject() -> Dictionary:
	var name := "IntentHandler geçersiz link reddi"
	var handler := AILifecycleIntentHandler.new()
	# Yanlış şema
	if handler.parse("other://event").valid:
		return _fail(name, "yanlış şema reddedilmeli")
	# Şemasız
	if handler.parse("event/halloween").valid:
		return _fail(name, "şemasız link reddedilmeli")
	return _ok(name)


static func _test_url_router() -> Dictionary:
	var name := "URLRouter yönlendirme"
	var handler := AILifecycleIntentHandler.new()
	var router := AILifecycleURLRouter.new()
	# Bilinen host yönlendirilmeli
	var parsed: AILifecycleIntentHandler.ParsedLink = handler.parse(
		"mygame://event/halloween"
	)
	var result: AILifecycleURLRouter.RouteResult = router.route(parsed)
	if not result.matched:
		return _fail(name, "bilinen host yönlendirilmeli")
	if result.action != "open_event":
		return _fail(name, "doğru eyleme yönlendirilmeli")
	# Bilinmeyen host
	var unknown: AILifecycleIntentHandler.ParsedLink = handler.parse(
		"mygame://bilinmeyen/x"
	)
	if router.route(unknown).matched:
		return _fail(name, "bilinmeyen host reddedilmeli")
	return _ok(name)


static func _test_deferred_resolve() -> Dictionary:
	var name := "DeferredLink çözümleme"
	var resolver := AILifecycleDeferredLink.new()
	resolver.defer_link("mygame://reward/daily", 1000)
	# Oyun hazır olunca çözülmeli
	var result: Dictionary = resolver.resolve(2000)
	if not bool(result["resolved"]):
		return _fail(name, "bekleyen link çözülmeli")
	if str(result["link"]) != "mygame://reward/daily":
		return _fail(name, "çözülen link doğru olmalı")
	return _ok(name)


static func _test_deferred_expiry() -> Dictionary:
	var name := "DeferredLink eskime"
	var resolver := AILifecycleDeferredLink.new()
	resolver.defer_link("mygame://event/old", 1000)
	# Çok geç çözüm — link eskimiş olmalı
	var late_time: int = 1000 + AILifecycleDeferredLink \
		.LINK_EXPIRY_SECONDS + 100
	var result: Dictionary = resolver.resolve(late_time)
	if bool(result["resolved"]):
		return _fail(name, "eskimiş link çözülmemeli")
	return _ok(name)


# ============================================================
# TEMPLATES
# ============================================================

static func _test_templates() -> Dictionary:
	var name := "LifecycleTemplates 5 şablon"
	var templates := AILifecycleTemplates.new()
	if templates.template_count() != 5:
		return _fail(name, "5 şablon tipi olmalı")
	# Duraklat menüsü — butonları olmalı
	var pause: Dictionary = templates.pause_menu()
	var buttons: Array = pause["buttons"]
	if buttons.size() < 2:
		return _fail(name, "duraklat menüsü butonlar içermeli")
	# Çıkış onayı — iki seçenek
	var exit_dialog: Dictionary = templates.exit_confirmation()
	if (exit_dialog["buttons"] as Array).size() != 2:
		return _fail(name, "çıkış onayı 2 buton içermeli")
	return _ok(name)
