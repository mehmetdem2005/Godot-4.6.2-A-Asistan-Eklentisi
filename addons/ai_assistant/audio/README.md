# Madde 08 — Audio System (Çekirdek)

Ses, sahne mutasyonundan ayrı bir disiplin: bus mimarisi, mekânsal
ses, çalma yönetimi kendi uzmanlığı.

## Bu sürüm — Çekirdek (bus + playback + spatial, 6 modül)

### bus_architecture
- bus_architect.gd — Ses bus ağacı: Master + Music/SFX/UI/Ambient/
  Voice. Döngü tespiti, ağaç doğrulama.
- volume_manager.gd — Kullanıcı ses ayarları. Yüzde<->desibel
  logaritmik çevrim. Save/Load ile kalıcı.
- eq_preset.gd — 5 EQ profili (flat/underwater/cave/combat/radio),
  6 frekans bandı, profil geçişi (blend).

### playback
- audio_pool.gd — Ses çalar havuzu. Voice stealing: havuz dolunca
  düşük öncelikli ses kesilir (mobil kanal sınırı gerçek).
- playback_dispatcher.gd — Yüksek seviyeli play() API. 4 kategori
  (SFX/UI/Ambient/Voice) -> bus + öncelik eşlemesi.

### spatial
- spatial_audio.gd — Mekânsal ses: mesafe zayıflama (3 eğri),
  reverb bölgesi (AABB), occlusion (engel boğması).

## Mimari not

Bu modüller Godot AudioServer/AudioStreamPlayer kullanan sistemin
test edilebilir MANTIK katmanıdır. Gerçek ses çıkışı ince Node
sarmalayıcıların işi — sahnesiz test mümkün olsun diye ayrıldı.

## Kalan (sonraki turlar)

procedural_synth (9 — oscillator/envelope/filter/synth_engine...),
music_layering (4), templates (2), budget (2), lifecycle (2),
ai_generation_stubs (2), ui (6).

## Kalite

gdlint R01-R14 + stress test (çekirdek logic 38/38) + 22 GDScript test.


## Audio Sentez (Tur 3) — procedural_synth + music_layering

### procedural_synth (9) — saf DSP
- oscillator.gd — Dalga formu üreteci (sine/square/saw/triangle).
- envelope.gd — ADSR ses zarfı.
- filter.gd — Alçak/yüksek geçiren filtre.
- noise.gd — Deterministik gürültü üreteci (white/pink).
- lfo.gd — Düşük frekanslı modülasyon osilatörü.
- sample_buffer.gd — Tampon matematiği (mix, normalize, fade, RMS).
- sfxr_presets.gd — 10 retro ses efekti önayarı.
- synth_engine.gd — Sentez zinciri orkestratörü.
- vorbis_encoder.gd — Tampon -> PCM16 -> OGG kodlama hazırlığı.

### music_layering (4)
- intensity_manager.gd — Aksiyon yoğunluğu -> aktif katman sayısı.
- crossfade_engine.gd — Çapraz geçiş (eşit-güç eğrisi).
- stem_player_pool.gd — Senkron katman çalar havuzu.
- loop_point_handler.gd — İntro + döngü noktası yönetimi.


## Audio Tamamlama (Tur 4) — templates + budget + lifecycle + ai_stubs

### templates (2)
- genre_audio_registry.gd — 9 tür için ses kimliği şablonu.
- template_applier.gd — Şablonu somut kurulum planına çevirir.

### budget (2)
- memory_estimator.gd — Ses bellek kullanım tahmini.
- audio_budget_enforcer.gd — Mobil tier'lara göre ses bellek bütçesi.

### lifecycle (2)
- audio_focus_handler.gd — Odak kaybı/ducking ses yönetimi.
- scene_audio_cleanup.gd — Sahne geçişinde ses temizliği.

### ai_generation_stubs (3)
- ai_audio_gen_provider.gd — AI ses üretim arayüzü.
- elevenlabs_sfx_provider.gd / stable_audio_provider.gd
  — Phase 2+ stub'ları (Phase 1: NOT_AVAILABLE + procedural fallback).
