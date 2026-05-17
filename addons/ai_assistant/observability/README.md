# Layer 6 — Observability (Gözlemlenebilirlik)

Sistem 6 katmanlı ama "kör" çalışıyordu — bir plan yürütülürken ne
olduğu dışarıdan görünmüyordu. Bu katman o gözü açar.

## Dosyalar

- trace_collector.gd — Yapılandırılmış iz kaydı. Her olay zaman
  damgalı, span-hiyerarşili bir iz. Ring buffer (son 5000).
- metrics_collector.gd — Sayısal ölçüm: counter (artan sayaç),
  gauge (anlık değer), histogram (dağılım — min/max/ortalama).
- cost_tracker.gd — Maliyet takibi. AICostRecord biriktirir,
  bütçe sınırı izler, sağlayıcı/rol dağılımı, cache hit oranı.
- feed_emitter.gd — Canlı olay akışı. Kullanıcı-dönük AIFeedEvent
  yayını, abone (UI) bildirimi, geçmiş tampon.
- replay_engine.gd — İz geri sarma. Adım adım ileri/geri, hataya
  atlama, hata bağlamı çıkarma — tanı için.
- observability_hub.gd — Layer 6 ana koordinatörü. 5 bileşeni
  tek çatıda birleştirir, diğer katmanlar buraya tek referansla bağlanır.
- _observability_test.gd — 26 sıkı test.

## İki ayrı göz

- trace + replay -> GELİŞTİRİCİ gözü (iç tanı, "neden başarısız oldu")
- feed -> KULLANICI gözü (canlı akış, "şu an ne oluyor")
- metrics + cost -> ÖZET göz (sayısal durum, bütçe)

## Bütçe koruması

CostTracker bütçe sınırı tanımlanabilir. Eşiğin %80'inde UYARI,
aşımda BLOK. Bütçe-sınırlı bir proje için kritik.

## Kullanım (diğer katmanlar için)

ObservabilityHub.report_event(...) tek çağrı — trace + feed +
metrics aynı anda güncellenir. begin_task/end_task task yaşam
döngüsünü otomatik izler.

## Kalite

gdlint.py R01-R13 + stress test (observability logic 27/27).
