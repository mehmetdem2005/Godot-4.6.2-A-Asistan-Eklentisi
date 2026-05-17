# Madde 10 — App Lifecycle (Çekirdek)

Android oyun = sürekli kesintide yaşayan oyun. Telefon araması,
bildirim, düşük bellek, pil, ekran dönüşü — bunlar normal kesintiler,
oyun hepsine zarif tepki vermeli.

## Bu sürüm — Çekirdek (core + monitors + permissions, 12 modül)

### core
- app_state_machine.gd — Uygulama durum makinesi: starting/active/
  paused/background/resuming/terminating. Geçersiz geçiş engellenir.
- event_dispatcher.gd — Sistem olaylarını handler'lara dağıtır.
  Bilinmeyen olay reddedilir (yazım hatası yakalanır).
- resume_action_chain.gd — Arka plandan dönüş zinciri. Kritik adım
  başarısızsa durur, opsiyonel başarısızsa devam eder.
- lifecycle_manager.gd — Ana API. on_pause/on_resume/on_background.

### monitors
- memory_pressure_handler.gd — Bellek baskısı (normal/moderate/
  critical), acil kayıt önerisi.
- battery_monitor.gd — Pil seviyesi, güç tasarrufu, FPS önerisi.
- network_state_monitor.gd — Ağ durumu, ölçülü bağlantı tespiti.
- orientation_handler.gd — Ekran yönü, kilit politikası.
- inactivity_monitor.gd — Hareketsizlik -> uyarı -> oto-duraklat.

### permissions
- permission_manager.gd — İzin durumu takibi (unknown/granted/
  denied/denied_permanently).
- permission_request_flow.gd — İzin isteme akışı (gerekçe dahil).
- rationale_dialog_helper.gd — İzin gerekçe metinleri.

## Mimari not

Bu modüller Android sistem olaylarına tepki veren sistemin test
edilebilir MANTIK katmanıdır. Gerçek OS/DisplayServer çağrıları
ince Node sarmalayıcıların işi.

## Kalan (sonraki turlar)

device_control (4), notifications (4), deep_links (3),
templates (5), ui (3).

## Kalite

gdlint R01-R14 + stress test (çekirdek logic 55/55) + 24 GDScript test.


## Lifecycle Tamamlama (Tur 5) — device_control + notifications + deep_links + templates

### device_control (4)
- wake_lock_manager.gd — Ekran uyanık tutma (cutscene/video).
- back_button_handler.gd — Android geri tuşu bağlam tabanlı yönetim.
- screen_brightness.gd — Ekran parlaklığı + pil tasarrufu tavanı.
- vibration_helper.gd — Titreşim desenleri + debounce.

### notifications (4)
- notification_channel_setup.gd — Android bildirim kanalları.
- local_notification_scheduler.gd — Yerel bildirim zamanlama.
- foreground_overlay_notification.gd — Phase 1 oyun içi banner.
- notification_stub.gd — Phase 2+ native bildirim stub.

### deep_links (3)
- intent_handler.gd — Deep link ayrıştırma (şema/host/yol/param).
- url_router.gd — Link -> oyun eylemi yönlendirme tablosu.
- deferred_link_resolver.gd — Ertelenmiş link saklama/çözme.

### templates (1 birleşik dosya, 5 şablon)
- lifecycle_templates.gd — Duraklat menüsü, çıkış onayı, izin
  gerekçesi, pil uyarısı, düşük bellek uyarısı veri modelleri.
