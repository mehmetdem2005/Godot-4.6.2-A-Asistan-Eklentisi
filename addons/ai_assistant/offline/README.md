# Madde 07 — Offline / Graceful Degradation (Çekirdek)

İnternet bir zorunluluk değil, bir araç. Sistem internet yokken
çökmez; daraltılmış ama anlamlı bir kapasitede çalışmaya devam eder.

## Bu sürüm — Çekirdek (connection + cache + fallback, 8 modül)

### connection
- connection_monitor.gd — Bağlantı kalite durum makinesi: online/
  degraded/offline. Gecikme + ardışık hata sayısına bakar.
- latency_tracker.gd — Gecikme hareketli ortalaması, yavaşlama
  ve kötüleşme tespiti.

### cache
- cache_base.gd — Ortak önbellek temeli: LRU eviction + TTL +
  boyut sınırı. İsabet/ıska istatistiği.
- llm_response_cache.gd — LLM cevap önbelleği. Deterministik
  anahtar (prompt+model+sıcaklık).
- embedding_cache.gd — Embedding vektör önbelleği. Embedding'ler
  değişmez — TTL yok, sadece LRU.

### fallback
- capability_mapper.gd — Hangi yetenek online/offline kullanılabilir.
  3 sınıf: online_only / cache_backed / always.
- template_library.gd — LLM yokken hazır kod şablonları
  (boilerplate GDScript iskeletleri).
- procedural_fallback_router.gd — Offline beyni: bir iş ağ mı,
  önbellek mi, şablon mı, kuyruk mu, yoksa REJECT mi.

## "Mock yasak" ilkesi

Yapılamayan iş için sahte başarı yok — router açıkça QUEUE veya
REJECT der. Sistem daralarak ama dürüstçe çalışır.

## Kalan (sonraki turlar)

cache (asset_metadata, validation, rag_result), bandwidth (3),
queue (3), ui (6).

## Kalite

gdlint R01-R14 + stress test (çekirdek logic 39/39) + 24 GDScript test.


## Offline Tamamlama (Tur 6) — cache kalan + bandwidth + queue

### cache (kalan 3)
- rag_result_cache.gd — RAG arama sonucu önbelleği (koleksiyon invalidate).
- asset_metadata_cache.gd — Varlık metadata önbelleği (klasör invalidate).
- validation_cache.gd — Kod doğrulama önbelleği (içerik-hash anahtarı).

### bandwidth (3)
- data_meter.gd — Kategori bazlı veri kullanım kaydı.
- bandwidth_tracker.gd — Anlık hız izleme (kayan pencere, yavaş tespit).
- bandwidth_governor.gd — Mobil veri üst sınırı denetimi.

### queue (3)
- priority_resolver.gd — Çok faktörlü öncelik hesabı (tür+bekleme+retry).
- sync_queue.gd — Kalıcı senkronizasyon kuyruğu (serileştirilebilir).
- queue_processor.gd — Bağlantı gelince batch işleme + retry/abandon.
