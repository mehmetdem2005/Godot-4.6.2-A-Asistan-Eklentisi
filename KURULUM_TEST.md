# Kurulum ve Test — Phase 0-4

Bu paket, otonom AI geliştirme sisteminin dokuz katman + Surgical Edit ve **tek tıkla çalışan test panelini** içerir.
Kod yazmana gerek yok — sadece düğmeye basacaksın.

## İçindekiler

```
addons/
├── ai_assistant/
│   ├── contracts/    ← Layer 0: 22 contract + veri tipleri
│   ├── memory/       ← Layer 1: 4 katmanlı hafıza sistemi
│   ├── knowledge/    ← Layer 2: bilgi tabanı + RAG
│   ├── planner/      ← Layer 3: hiyerarşik planlama
│   ├── executor/     ← Layer 4: çalıştırma + korumalı sandbox
│   ├── verifier/     ← Layer 5: üretilen kodu doğrulama
│   ├── observability/ ← Layer 6: iz, metrik, maliyet, feed
│   ├── router/      ← Layer 7: çoklu LLM sağlayıcı
│   ├── hitl/        ← Layer 8: insan onay/müdahale
│   ├── surgical_edit/ ← Cerrahi kod düzenleme
│   ├── workspace/   ← Layer 11: Task Workspace UI
│   ├── pilot_cell/  ← Layer 9: 14-rollü çok-ajanlı sistem
│   └── quality_gates/ ← Layer 10: mobil performans bütçesi
└── ai_contract_tests/  ← test paneli plugin'i
gdlint.py             ← GDScript statik analiz aracı (13 kural)
gdlint_selftest.py    ← linter'ın kendi öz-testi
```

Toplam **299 GDScript dosyası**, **749 otomatik test** (gerçek
Godot 4.6.2 headless'ta doğrulandı).

## AŞAMA DURUMU (Claude Code sandbox doğrulaması)

Devir belgesinin yol haritası tamamlandı ve GERÇEK ortamda kanıtlandı:

```
[✓] Aşama 0-1  Godot 4.6.2 kuruldu; gdlint 0 hata; 749/749 test geçti
[✓] Aşama 3    ADIM 1: GERÇEK DeepSeek çağrısı (ok=true, ~1.1s)
[✓] Aşama 4a   Pilot Cell ↔ Router canlı köprüsü (ajan gerçek üretti)
[✓] Aşama 4b   Hata ↔ Bellek köprüsü
[✓] Aşama 4c   Uçtan uca: görev→LLM→verify→HITL→Executor diske YAZDI
[✓] Aşama 5    Ana eklenti + görünür panel (plugin.cfg/plugin.gd)
```

"Bitti" tablosu: #6 #7 #8 kanıtlandı; #1-5 panel kuruldu, görsel
doğrulama kullanıcıya (telefonda Godot) bırakıldı.

### Ana "AI Asistan" panelini açma

1. **Project > Project Settings > Plugins**
2. **"AI Asistan"** satırında **Enable**
3. Sol dock'ta (üst-sağ yuva) **"AI Asistan"** paneli belirir
4. Panelde: DeepSeek anahtarını gir + Kaydet → "Canlı mod"u işaretle
   → Görev yaz (örn. "ekrana merhaba yazan script üret") → **▶ Üret
   ve Uygula**. Sistem üretir, doğrular, HITL'den geçirir, uygular.

Headless test koşumu (geliştirici): `godot --headless --path .
--script res://tools/headless_test_runner.gd` → 749/749 beklenir.

## Kurulum (Android Godot 4.6)

### Adım 1 — Dosyaları kopyala
Zip'i aç. İçindeki `addons/` klasörünü, projenin `addons/`
klasörüyle birleştir. Üzerine yazma değil, ekleme — her yeni
phase önceki klasörlerin yanına eklenir.

Sonuç şöyle olmalı:
```
projen/
└── addons/
    ├── ai_assistant/
    │   ├── contracts/   ← Layer 0
    │   ├── memory/      ← Layer 1
    │   ├── knowledge/   ← Layer 2
    │   ├── planner/     ← Layer 3
    │   ├── executor/    ← Layer 4
    │   ├── verifier/    ← Layer 5
    │   ├── observability/ ← Layer 6
    │   ├── router/      ← Layer 7
    │   ├── hitl/        ← Layer 8
    │   ├── surgical_edit/ ← Surgical Edit
    │   ├── workspace/   ← Layer 11
    │   ├── pilot_cell/  ← Layer 9
    │   └── quality_gates/ ← Layer 10
    └── ai_contract_tests/
```

### Adım 2 — Editörü yenile
Godot'ta: **Project menüsü > Reload Current Project**

### Adım 3 — Test plugin'ini aktive et
1. **Project > Project Settings** aç
2. **Plugins** sekmesine geç
3. Listede **"AI Contract Tests"** göreceksin
4. Yanındaki **Enable** kutusunu işaretle

### Adım 4 — Test panelini aç
1. Üst menü: **Project > Tools**
2. **"AI Contract Testleri"** girdisine tıkla

### Adım 5 — Testleri çalıştır
Pencerede **"▶ Testleri Çalıştır"** düğmesine bas.
Üstte özet: **"✓ 717/717 test geçti"**

## Beklenen sonuç

Testler beş gruba (phase) ayrılır:

```
=== Self-Test Sonuçları ===

--- PHASE 0: Contracts (Layer 0) ---
  ✓ 47 test — 22 contract, serialize round-trip,
    doğrulama kuralları, durum geçişleri

--- PHASE 1: Memory (Layer 1) ---
  ✓ 22 test — working/episodic/semantic/procedural
    hafıza, salience decay, atomik disk kalıcılığı

--- PHASE 2: Knowledge & RAG (Layer 2) ---
  ✓ 25 test — tokenizer, idempotent normalize,
    TF-IDF retriever, bilgi tabanı

--- PHASE 3: Planner (Layer 3) ---
  ✓ 24 test — DAG döngü tespiti, topolojik sıralama,
    hiyerarşik ağaç, bağımlılık döngü reddi

--- PHASE 4: Executor & Sandbox (Layer 4) ---
  ✓ 38 test — PathGuard güvenlik, write-ahead journal,
    undo stack, gerçek dosya I/O, kota, hız limiti,
    bütünlük doğrulama, atomik transaction batch

--- PHASE 5: Verifier (Layer 5) ---
  ✓ 20 test — syntactic (gerçek motor derlemesi),
    semantic (çift tanım, tanımsız enum, ulaşılamaz kod)

--- PHASE 6: Observability (Layer 6) ---
  ✓ 26 test — trace + span, metrics (counter/gauge/
    histogram), cost tracker + bütçe, feed emitter, replay

--- PHASE 7: Multi-Provider Router (Layer 7) ---
  ✓ 23 test — 4 sağlayıcı adapter (DeepSeek/OpenAI/
    Anthropic/Gemini), prompt cache, mod sistemi, fallback

--- PHASE 8: HITL (Layer 8) ---
  ✓ 26 test — risk değerlendirme, LCS diff viewer,
    checkpoint kapısı, müdahale konsolu, koordinatör

--- PHASE 10: Surgical Edit ---
  ✓ 25 test — intent sınıflandırma, kapsam çıkarma,
    SEARCH/REPLACE protokolü, format drift, orchestrator

--- PHASE 11: Workspace UI (Layer 11) ---
  ✓ 20 test — sekme yönetimi + DPI, Kanban kolon akışı,
    canlı akış filtreleme, iteration faz akışı

--- PHASE 12: Pilot Cell (Layer 9) ---
  ✓ 20 test — 14 rol + pipeline, ajan mesajlaşma,
    mesaj veri yolu, reflection turları, orkestratör

--- PHASE 13: Quality Gates (Layer 10) ---
  ✓ 20 test — mobil bütçe profilleri, sahne denetimi,
    LOD politikası, optimizasyon önerileri, kalite kapısı

--- PHASE 12b: Pilot Cell Ajan Zekâsı ---
  ✓ 16 test — 14 rol promptu, ajan beyni (düşünme),
    canlı mod, Router yayılımı

--- PHASE 12c: Pilot Cell Çıktı Ayrıştırma ---
  ✓ 16 test — plan/task/kod/inceleme ayrıştırma,
    role yönlendirme, savunmacı davranış (uydurma yok)

--- PHASE 12d: Pilot Cell Bağlam Aktarımı ---
  ✓ 12 test — yapılandırılmış bağlam aktarımı, key
    predecessor eşleme, pipeline entegrasyonu

--- PHASE 10b: Surgical Edit Protokolleri ---
  ✓ 21 test — insert/delete/rename/multistep/explicit
    protokolleri, atomik geri alma, kelime-sınırı duyarlı

--- PHASE 10c: Surgical Edit Doğrulamaları ---
  ✓ 18 test — yorum kaybı, isim kayması, kapsam taşması,
    niyet uyumu denetimi

--- PHASE 7b: HTTP Transport ---
  ✓ 7 test — dry-run davranışı, boş URL reddi, istek
    kaydı, hata kodu eşlemesi

--- PHASE 11b: Workspace Kalan 6 Sekme ---
  ✓ 25 test — Overview, Plan Tree, Cost, Verifier,
    Checkpoints, Settings sekme modelleri

--- PHASE 14: Save/Load (Madde 09 çekirdek) ---
  ✓ 24 test — serileştirme, atomik yazma, slot yönetimi,
    HMAC bütünlük, anomali tespiti, uçtan uca round-trip

--- PHASE 15: Audio System (Madde 08 çekirdek) ---
  ✓ 22 test — bus mimarisi, ses çevrimi, EQ profilleri,
    havuz voice stealing, mekânsal ses (mesafe/reverb/occlusion)

--- PHASE 16: App Lifecycle (Madde 10 çekirdek) ---
  ✓ 24 test — durum makinesi, olay dağıtımı, resume zinciri,
    bellek/pil/ağ/yön/hareketsizlik monitörleri, izin akışı

--- PHASE 17: Offline / Graceful Degradation (Madde 07 çekirdek) ---
  ✓ 24 test — bağlantı durum makinesi, gecikme takibi,
    LRU+TTL önbellek, yetenek haritası, şablon fallback, yönlendirme

--- PHASE 18: Debug Loop (Madde 02 çekirdek) ---
  ✓ 23 test — hata sınıflandırma, Godot 3→4 API haritası,
    kök neden analizi, düzeltme planı, retry + circuit breaker

--- PHASE 19: Save/Load Mantık Tamamlama (Madde 09) ---
  ✓ 21 test — yedek rotasyonu/geri yükleme, bozulma kurtarma,
    sürüm uyumluluğu, şema geçişi, otomatik kayıt, pil/duraklatma

--- PHASE 20: Genre Schemas + Cloud Stubs (Madde 09) ---
  ✓ 18 test — 9 tür şeması, şema doğrulama/registry,
    bulut stub'ları, çakışma çözümü

--- PHASE 21: Audio Sentez (Madde 08) ---
  ✓ 27 test — osilatör/zarf/filtre/gürültü/LFO, örnek tamponu,
    sfxr önayarları, sentez motoru, müzik katmanlama

--- PHASE 22: Audio Tamamlama (Madde 08) ---
  ✓ 15 test — tür ses şablonları, bellek tahmini/bütçesi,
    ses odak yönetimi, sahne temizliği, AI üretim stub'ları

--- PHASE 23: Lifecycle Tamamlama (Madde 10) ---
  ✓ 15 test — wake lock/geri tuşu/parlaklık/titreşim, bildirim
    kanalları/zamanlayıcı/overlay, deep link ayrıştırma/yönlendirme

--- PHASE 24: Offline Tamamlama (Madde 07) ---
  ✓ 18 test — RAG/varlık/doğrulama önbellekleri, veri sayacı,
    bant genişliği izleme/denetimi, senkronizasyon kuyruğu

--- PHASE 25: UI Katmanı 7A — Offline+Audio UI ---
  ✓ 13 test — bağlantı göstergesi/yetenek paneli/kuyruk görünümü/
    veri panosu/önbellek yönetimi, ses sekmesi/bus mikseri/sfx
    tasarımcısı/müzik katmanlama/bütçe göstergesi/tür seçici

--- PHASE 26: UI Katmanı 7B — Save/Load+Lifecycle UI ---
  ✓ 9 test — slot kartı/seçici/menü, kayıt göstergesi, bozulma
    ve geçiş diyalogları, yaşam döngüsü ayarları, izin durumu,
    bildirim ayarları

--- PHASE 27: UI Katmanı 7C — Debug UI + Final Entegrasyon ---
  ✓ 8 test — debug oturum görünümü, hata gezgini (sıralama/filtre/
    kritik takibi), debug mod ayarları, final sistem bütünlüğü

--- PHASE 28: Canlı API — Anahtar Deposu (Layer 7) ---
  ✓ 5 test — AES-256 şifrele/çöz round-trip, kayıtsız sağlayıcı
    boş döner, boş anahtar reddi, çoklu sağlayıcı bağımsızlığı

--- TOPLAM: 717 geçti, 0 başarısız ---
--- AŞAMA: ADIM 1 (Canlı API altyapısı) tamamlandı ---
```

## Phase 4 hakkında not — gerçek dosya işlemleri

Layer 4 testleri **gerçekten dosya oluşturur, yazar, siler** —
`user://ai_assistant/executor/test/` klasörü altında. Test
bitince bu dosyalar otomatik temizlenir. Panik yok, normal.

Executor'ın yazma işlemleri beş katmanlı güvenlik zincirinden
geçer: yol kontrolü, geri-alma snapshot'ı, işlem günlüğü,
atomik yazım, yazım sonrası bütünlük doğrulama.

## Sorun çıkarsa

**"AI Contract Tests" Plugins listesinde yok:**
→ `addons/ai_contract_tests/plugin.cfg` doğru yerde mi kontrol et.
→ Editörü yeniden başlat.

**Tools menüsünde "AI Contract Testleri" yok:**
→ Plugin enable edilmemiş. Adım 3'ü tekrarla.

**Test başarısız (kırmızı) çıkarsa:**
→ Kırmızı satırdaki sebep mesajını bana ilet. Düzeltiriz.
→ Bu, mock policy'nin çalıştığı anlamına gelir — sahte
  "passed" yok, gerçek sorun varsa gösterir.

**Derleme hatası (panel hiç açılmıyor):**
→ Godot'ta alt taraftaki **Output** panelindeki kırmızı
  satırları bana ilet. Parse/Compile Error mesajları kritik.

**"Surface is not supported by device" hatası:**
→ Bu bizim kodumuzla ilgili DEĞİL — Godot'un mobil pencere/
  renderer uyarısı. Test panelini etkilemez, görmezden gel.

## Geliştirici aracı — gdlint.py

Pakete dahil `gdlint.py`, GDScript statik analiz aracıdır.
13 kural uygular (R01-R13): @tool konumu, const kuralları,
girinti, parantez dengesi, cross-file enum referans
doğrulama, çift fonksiyon tespiti.

Kullanım: `python3 gdlint.py <klasörler>` — Godot gerektirmez.
R14 (yerleşik + miras-metod ad çakışması), R12 (enum referans) için tüm klasörler TEK komutta birlikte
verilmelidir. `gdlint_selftest.py` linter'ın kendini doğrular.
