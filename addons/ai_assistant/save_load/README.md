# Madde 09 — Save/Load (Çekirdek)

Oyunların olmazsa olmazı: ilerlemeyi güvenle kaydet/yükle.

## Bu sürüm — Çekirdek (core + integrity, 8 modül)

### core
- serializer.gd — Oyun durumu -> kendini-tanımlayan JSON zarfı
  (_meta + data). Şema sürümü her kayda gömülür.
- deserializer.gd — JSON -> oyun durumu. SAVUNMACI: bozuk dosyada
  çökmez, açık hata döner.
- atomic_writer.gd — Atomik yazma: tmp'ye yaz -> doğrula -> rename.
  "Yarım save imkansız" — çökme asıl kaydı bozmaz.
- slot_manager.gd — Slot kataloğu: 3 manuel + autosave + quicksave.
- save_manager.gd — Ana API. save() / load_slot() / delete_slot().

### integrity
- hmac_signer.gd — HMAC-SHA256 imza. Kurcalama tek baytta yakalanır.
- integrity_verifier.gd — Üst-seviye bütünlük kararı.
- anomaly_detector.gd — Anti-cheat: değer anomalisi (opsiyonel).

## Save/Load 5 invariant'ı

1. Atomik yazma — yarım kayıt imkansız
2. Şema versiyonu — her kayıt sürümünü taşır
3. Bütünlük imzası — kurcalama yakalanır
4. Savunmacı okuma — bozuk dosya çökmez
5. Slot izolasyonu — slotlar birbirini etkilemez

## Kalan (sonraki turlar)

backup (3), versioning (3), autosave (4), genre_schemas (10),
persistence_helpers (3), cloud_stubs (5), ui (6).

## Kalite

gdlint R01-R13 + stress test (çekirdek logic 41/41) + 24 GDScript test.


## Mantık Tamamlama (Tur 1) — backup + versioning + autosave + helpers

### backup
- backup_rotator.gd — Yedek dosya rotasyonu (save.bak.1..N).
- backup_restorer.gd — En yeni sağlam yedeği seçer.
- corruption_recovery.gd — Bozulma türü -> kurtarma stratejisi.

### versioning
- version_compatibility_checker.gd — Kayıt sürümü uyumluluğu.
- migration_registry.gd — Sürüm geçiş dönüştürücüleri kaydı.
- migration_engine.gd — Adımlı şema geçişi (atomik).

### autosave
- autosave_scheduler.gd — Zaman tabanlı otomatik kayıt.
- checkpoint_trigger.gd — Olay tabanlı kayıt (öncelikli + debounce).
- mobile_pause_handler.gd — Android arka plan acil kaydı.
- battery_warning_handler.gd — Düşük pil koruyucu kaydı.

### persistence_helpers
- serializer_registry.gd — Özel tip (Vector2, Color...) dönüştürücüleri.
- screenshot_capturer.gd — Kayıt thumbnail metadata + ölçekleme.
- load_state.gd — Yükleme süreci aşama yöneticisi.


## Mantık Tamamlama (Tur 2) — genre_schemas + cloud_stubs

### genre_schemas (10)
- genre_schema_base.gd — Tür şeması temeli: alan tanımı, doğrulama,
  varsayılan tamamlama, iskelet üretimi.
- 9 tür şeması — fps_3d, platformer_2d, rpg_topdown, puzzle,
  racing_3d, survival_3d, visual_novel, strategy_isometric, horror_3d.
- schema_registry.gd — Tüm şemaların kaydı, tür tespiti, doğrulama.

### cloud_stubs (5)
- cloud_sync_iface.gd — Bulut senkronizasyon ortak arayüzü.
- google_play_cloud_stub.gd / steam_cloud_stub.gd / icloud_stub.gd
  — Platform stub'ları (Phase 1: dürüstçe NOT_AVAILABLE).
- conflict_resolver.gd — Yerel/bulut çakışma çözümü; belirsizse
  kullanıcıya sorar.
