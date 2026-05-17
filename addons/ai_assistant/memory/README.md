# Layer 1 — Memory System (Bellek Sistemi)

Sistemin 4 katmanlı belleği. AIMemoryRecord contract'ını (Layer 0) kullanır.

## 4 Bellek Deposu

| Depo | Kalıcı | Decay | Karakter |
|------|--------|-------|----------|
| Working    | Hayır | Hızlı (0.1)   | Anlık çalışma belleği, 20 kayıt kapasiteli |
| Episodic   | Evet  | Yavaş (0.005) | Olay/deneyim belleği — ne yaptık ne oldu |
| Semantic   | Evet  | Çok yavaş (0.001) | Kavram/bilgi — Godot API, pattern'ler |
| Procedural | Evet  | Yok (0.0)     | Nasıl-yapılır — öğrenilmiş prosedürler |

## Dosyalar

- `memory_store_base.gd` — Ortak temel: ekleme, sorgulama, decay, ATOMİK disk yazımı
- `working_memory.gd` — Anlık bellek (diske yazılmaz, görev sınırında temizlenir)
- `episodic_memory.gd` — Olay belleği (iteration/debug sonuçları)
- `semantic_memory.gd` — Bilgi belleği (API gerçekleri, pattern'ler, verified boost)
- `procedural_memory.gd` — Prosedür belleği (başarı oranı takibi)
- `memory_manager.gd` — 4 depoyu yöneten ana sınıf
- `_memory_test.gd` — 22 sıkı test

## Tasarım kararları

- **Atomik disk yazımı**: önce `.tmp` dosyaya yaz, sonra rename — yarım dosya riski yok
- **Decay**: zaman geçtikçe önemsiz bellek silinir; erişim sayısı decay'i yavaşlatır
- **Kapasite eviction**: working memory dolunca en düşük önemli kayıt çıkar
- **Katman koruması**: bir kayıt yanlış depoya eklenemez
- **Bozuk kayıt koruması**: diskten yüklenen geçersiz kayıt atlanır (mock policy)

## Test

22 memory testi ana panele zincirlendi. Toplam panel testi:
47 (contract) + 22 (memory) = 69 test.

Project > Tools > "AI Contract Testleri" > Testleri Çalıştır
Beklenen: 69/69 geçer.
