# Layer 10 — Quality Gates (Mobil Performans Bütçesi)

Bu eklenti Android telefon için oyun üretiyor. Üretilen sahne
telefonu kasmamalı. Layer 10 bunu garanti eder: bir sahne mobilde
çalışır mı, çalışmazsa ne yapmalı.

## Dosyalar

- mobile_budget.gd — Telefon donanım sınırları. 3 profil
  (LOW_END / MID_RANGE / HIGH_END), her biri için kare-başına
  vertex/draw call/ışık/texture/kemik/materyal limitleri.
- budget_checker.gd — Bir sahnenin metriklerini bütçeye karşı
  denetler. Sonuç PASS / WARN / FAIL.
- lod_policy.gd — Detay seviyesi (LOD) kuralları. Uzak nesneler
  düşük detayda çizilir — mobil performansın anahtarı.
- optimization_advisor.gd — Bütçe aşımında somut öneri üretir
  (MultiMesh, lightmap bake, texture atlas, occlusion culling...).
- quality_gate.gd — Layer 10 ana motoru. "Bu sahne mobilde
  çalışır mı" kapısı.
- _quality_gates_test.gd — 20 sıkı test.

## Bütçe profilleri (kare başına, 60 FPS hedefi)

         LOW_END   MID_RANGE   HIGH_END
vertices  80.000    200.000     500.000
drawcall      80        150         300
lights         4          8          16
texture     128MB      256MB       512MB

## Pilot Cell entegrasyonu

PerformanceEngineer rolü (Layer 9) bu kapıyı kullanır:
  1. Ürettiği sahnenin metriklerini QualityGate'e verir
  2. Kapı PASS/WARN/FAIL der
  3. FAIL ise advisor önerilerini alır
  4. Surgical Edit ile sahneyi düzeltir, tekrar dener

## Önemli — sahte PASS yok

Kapı gerçek metriklerden karar verir. Bütçeyi aşan sahne asla
PASS almaz; düzeltilmesi gerekir.

## Kalite

gdlint.py R01-R13 + stress test (quality gates logic 31/31).
