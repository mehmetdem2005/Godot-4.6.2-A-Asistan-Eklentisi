# Faz 12 — Adaptif paralel derin düşünme

## Amaç

Seri `Architect → CodeEngineer → Reviewer` hattını kaldırıp yalnız gerçek dependency'lerde bekleyen, paralel uzman konseyleri kullanan ve belirsizlikte çalışma sırasında derinleşen bilişsel DAG kurmak.

## Temel değişiklik

Eski model:

```text
Architect
   ↓
CodeEngineer
   ↓
Reviewer
```

Yeni model:

```text
Niyet Kalibrasyonu
        ↓
Bağlam/Kanıt ajanları ×3 — paralel
        ↓
Stratejik Uzman Konseyi ×5 — paralel
        ↓
Çok Ölçekli Ayrıştırma
        ↓
Bağımsız Hipotezler ×3 — paralel
        ↓
Karşı-Olgusal Eleştiri ×3 — paralel
        ↓
Mimari Sentez
        ↓
Bağımsız Çözüm Adayları ×3 — paralel
        ↓
Red Team ×5 + Simülasyon ×4 — paralel dalgalar
        ↓
Kanıt Ağırlıklı Uzlaşma
        ↓
Nihai İnşa
        ↓
Bağımsız Doğrulama ×4 — paralel
        ↓
Belirsizlik yüksekse Meta Tur I ve II
```

## Derinlik

- temel bilişsel derinlik: 13 katman
- birinci meta derinleşme: 17 katman
- ikinci meta derinleşme: 21 katman
- temel grafik: 35 düşünme düğümü
- maksimum toplam: 64 düğüm
- maksimum eşzamanlı canlı ajan: 6
- maksimum meta-derinleşme: 2 tur

## Gerçek paralellik

`AIAdaptiveRoleGraphRunner`, tek meşgul bridge'i paylaşmaz. Altı ayrı `AIAgentLiveBridge` oluşturur; her bridge kendi `AIHTTPTransport` örneğine sahiptir ve ortak `AIProviderRouter` üzerinden aynı anda istek gönderebilir.

Global sıra yoktur. Bir düğüm yalnız kendi dependency'leri terminal olduğunda hazır olur. Aynı dalgadaki context, council, hypothesis, candidate, red-team, simulation ve verification ajanları paralel çalışır.

## Zekâ/karar modeli

- her düğüm confidence ve uncertainty taşır
- role-weighted evidence consensus
- kör çoğunluk yerine kanıt, test, güvenlik veto ve uzman ağırlığı
- Reviewer/QA güvenlik FAIL'i veto oluşturur
- uzman anlaşmazlığı ölçülür
- güven düşükse veya security veto varsa grafik otomatik derinleşir
- iki yeni paradigma-üstü turda skeptic, alternatif mimari, failure testleri, yeniden sentez ve yeniden inşa çalışır

## DeepSeek profili

Bütün canlı bilişsel düğümler:

```text
model=deepseek-v4-pro
thinking=enabled
reasoning_effort=max
max_tokens=384000
```

profiline zorlanır. Kullanıcının eski model seçimi maksimum profili düşüremez.

## Güvenlik sınırı

- Paralel olan kısım düşünme, eleştiri, hipotez ve doğrulamadır.
- Nihai dosya/editör mutasyonu hâlâ Verifier → HITL → Executor hattından geçer.
- Aynı dosyada kontrolsüz paralel yazma açılmaz.
- Max worker, node ve deepening sınırları sonsuz tartışma/maliyet patlamasını engeller.
- Final konsey kabul eşiğini geçmezse çıktı Executor'a gönderilmez.

## Testler

40 yeni contract testi:

- reasoning policy ve 21 katman: 8
- DAG yapı/paralel dalgalar: 10
- execution/meta-deepening: 10
- evidence consensus/security veto: 8
- runner contract: 4

Beklenen genel toplam: **1006 test**.
