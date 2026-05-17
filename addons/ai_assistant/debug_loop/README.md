# Madde 02 — Debug Loop (Çekirdek)

Devin'in karakteristik özelliği: AI kod yazıp bırakmıyor —
çalıştırıyor, hatayı yakalıyor, düzeltiyor, tekrar deniyor.
Mehmet'in "sürekli başka hata alıyorum" acısının çözümü.

## Bu sürüm — Çekirdek (core + intelligence + orchestration, 9 modül)

### core
- error_classifier.gd — Hatayı deterministik kategorize eder:
  parse/api/type/null/runtime. İki tırnak stilini tanır ("..." ve '...').
- godot4_api_mapper.gd — Godot 3→4 API hata haritası. LLM'siz,
  Mehmet'in en sık derdi olan eski-API hatalarını yakalar.
- autoload_guard.gd — Sandbox kodunun korumalı singleton'ları
  bozmasını engeller.
- sandbox_result.gd — Sandbox çalıştırma sonucu modeli.

### intelligence
- root_cause_analyzer.gd — Belirti değil kök neden. API hatası
  deterministik, ötekiler için LLM.
- fix_planner.gd — Kök nedeni somut düzeltme planına çevirir
  (surgical replace / surgical edit / needs_llm).

### orchestration
- retry_orchestrator.gd — Max 3 deneme + circuit breaker. Aynı
  hata tekrarlanırsa döngüyü kırar.
- escalation_manager.gd — Pes etme noktasında dürüstçe insana
  devreder, trace dışa aktarır.
- debug_loop_session.gd — Ana API: çalıştır → yakala → sınıflandır
  → kök neden → planla → tekrar dene.

## "Mock yasak" ilkesi

Çözülemeyen hata "çözüldü" denmez — needs_llm veya escalate.
Circuit breaker: aynı hata iki kez = döngü ilerlemiyor, dur.

## Kalan (sonraki tur)

ui (3): debug_session_view, error_explorer, mode_settings.

## Kalite

gdlint R01-R14 + stress test (çekirdek logic 45/45) + 23 GDScript test.
