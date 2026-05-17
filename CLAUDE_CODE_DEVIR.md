# DEVİR BELGESİ — ai-asistann (Godot 4.6.2 Otonom AI Oyun-Geliştirme Eklentisi)

> **Bu belge bir DEVİR PROTOKOLÜDÜR.** Projeyi devralan Claude Code
> oturumu, kod yazmaya başlamadan ÖNCE bu belgenin tamamını okumalıdır.
> Belge; projenin ne olduğunu, neyin bittiğini, neyin kaldığını, hangi
> sırayla ve hangi kalite disipliniyle ilerleneceğini tanımlar.

---

## 0. DEVİR PROTOKOLÜ — ÖNCE BUNU OKU

### 0.1. Sen kimsin, görevin ne
Bu projeyi önceki bir Claude oturumu kullanıcı (Mehmet) ile birlikte
geliştirdi. O oturumun container'ında **ağ kapalıydı ve Godot yoktu** —
bu yüzden gerçek çalıştırma/ağ testleri yapılamadı. Sen bir sandbox
ortamındasın: **Godot çalıştırabilir, gerçek ağ çağrısı yapabilirsin.**
Görevin, projeyi kullanıcının "bitti" tanımına ulaştırmaktır (bkz. §3).

### 0.2. Devir protokolünün kuralları
1. **Önce oku, sonra yaz.** Bu belgeyi ve §5'teki kalite disiplinini
   tam okumadan tek satır kod yazma.
2. **Mevcut durumu diskten teyit et.** Bu belge bir tarihte yazıldı;
   sen başlamadan `find addons/ai_assistant -name "*.gd" | wc -l`
   çalıştır, §2'deki sayılarla karşılaştır. Sapma varsa kullanıcıya
   bildir.
3. **Mevcut kodu okumadan üstüne yazma.** Bu projenin en sık hatası
   "zaten var olan bir modülü yeniden yazmak"tı. Bir dosya yazmadan
   önce o işi yapan bir modül var mı diye ara.
4. **Kalite kapısından geçmeden teslim etme.** Her değişiklik sonrası
   §5'teki 6-adımlı disiplin uygulanır. Atlanmaz.
5. **"Mock yasak".** Sahte başarı üretme. Desteklenmeyen/yapılamayan
   iş için SKIP / NEEDS_LLM / REJECT / NOT_AVAILABLE / structured=false
   döndürülür — sessizce "başarılı" denmez.
6. **Test sayısı asla düşmez.** Her teslimde toplam test sayısı korunur
   veya artar. Düşerse bir şey kırılmıştır.
7. **Kullanıcı Türkçe konuşur.** Tüm kod yorumları, README, kullanıcıya
   mesajlar Türkçe. Kullanıcı genelde "devam" / "geçti" der — bu
   "sıradaki planlı işe geç" demektir.
8. **Her aşama sonunda kullanıcıya net durum raporu ver:** ne yapıldı,
   kaç test, ne kaldı. "Bitti" kelimesini yalnızca §3'teki tüm maddeler
   karşılandığında kullan.

### 0.3. Bilinen geçmiş hatalar — tekrarlama
- Önceki oturum birkaç kez "proje bitti" dedi, oysa bitmemişti.
  "Bitti" = §3'teki 8 maddenin TAMAMI. Kod yazılması ≠ ürün bitmesi.
- Önceki oturum bir kez "yeni HTTP modülü yazacağız" dedi — modül
  zaten vardı. Daima önce ara.
- `agents/` adında bir klasör ESKİ eklentiden kalmadır; bu projede
  yoktur, ajanlar `pilot_cell/` altındadır. Kullanıcının projesinde
  görürsen silinmesi gerektiğini söyle.

---

## 1. PROJE NEDİR

**ai-asistann** — Godot 4.6.2 (Forward Mobile renderer, Android hedef)
için bir editör eklentisi. Amaç: Devin/Cursor seviyesinde **otonom AI
oyun-geliştirme sistemi.** Kullanıcı bir görev verir ("bana bir
platformcu yap"); 14 rollü bir AI ajan hücresi görevi planlar, kod
üretir (LLM ile), doğrular, insan onayından geçirir ve uygular.

### 1.1. Kesin kısıtlar (kullanıcı şartları — değiştirilemez)
- **Sadece Android telefon.** Kullanıcının PC'si yok. Tüm geliştirme
  telefonda Godot ile yapılır.
- **Bütçe sınırlı.** Pahalı çözümlerden kaçın.
- **GDScript-only.** C# yok.
- **Godot 4.6.2+**, Forward Mobile renderer, AA-indie kalite hedefi.
- **Dil: Türkçe** (kod yorumları, UI, kullanıcı iletişimi).

### 1.2. Teknik ortam notları
- Eklenti yolu: `addons/ai_assistant/`
- Test eklentisi: `addons/ai_contract_tests/` (plugin.cfg + plugin.gd)
- GDScript kuralları kritik (bkz. §5.2 — gdlint 14 kuralı).

---

## 2. ŞU ANA KADAR YAPILANLAR (devralınan durum)

### 2.1. Sayısal özet (devir anında)
- **288 `.gd` dosyası** (`addons/ai_assistant/` altında)
- **717 otomatik test** — hepsi geçiyor (kullanıcı Godot'ta doğruladı)
- **gdlint** ile 289 dosya taranıyor, 14 kural, 0 hata
- **gdlint öz-testi** 18/18 geçiyor

### 2.2. 18 katmanlı mimari (HEPSİ YAZILDI, TEST EDİLDİ)
Katman → dosya sayısı:
```
contracts: 26    memory: 7      knowledge: 5     planner: 4
executor: 10     verifier: 5    observability: 7 router: 16
hitl: 6          surgical_edit: 17  workspace: 13  pilot_cell: 13
quality_gates: 6 save_load: 47  audio: 37        lifecycle: 29
offline: 26      debug_loop: 14
```
Roller: Contracts (veri sözleşmeleri), Memory (4 katmanlı bellek:
Working/Episodic/Semantic/Procedural), Knowledge (TF-IDF RAG),
Planner (DAG + plan ağacı), Executor (sandbox dosya işlemleri),
Verifier (kod doğrulama), Observability (iz/metrik/maliyet), Router
(çok-sağlayıcı LLM yönlendirme), HITL (insan onayı), Surgical Edit
(cerrahi kod düzenleme), Workspace (9 sekmeli UI durumu), Pilot Cell
(14 AI ajan rolü + reflection), Quality Gates (sahne bütçe kontrolü),
Save/Load, Audio, Lifecycle, Offline, Debug Loop.

### 2.3. UI view-model katmanı (YAZILDI, TEST EDİLDİ — ama görsel YOK)
24 UI modülü `<katman>/ui/` altında. Her biri test edilebilir bir
`*ViewModel` / view sınıfıdır (RefCounted, saf sunum mantığı).
```
offline/ui: 6    audio/ui: 6    save_load/ui: 6
lifecycle/ui: 3  debug_loop/ui: 3
```
**KRİTİK:** Bunlar arayüzün BEYNİDİR — "hangi renk, hangi metin"
mantığı. Gerçek görünen Godot `Control` düğümleri / sahneleri **HİÇ
YAZILMADI.** Yani şu an eklenti açıldığında tıklanabilir bir pencere
YOKTUR. (Bkz. §4 — Adım 3.)

### 2.4. Canlı API altyapısı (YAZILDI — ama gerçek çağrı DOĞRULANMADI)
- `router/http_transport.gd` — gerçek HTTP (Godot `HTTPRequest`),
  `live_mode` anahtarı, asenkron `request_completed`. (Önceki turlarda
  yazılmıştı.)
- `router/api_key_store.gd` — API anahtarını AES-256-CBC ile şifreleyip
  `user://ai_assistant_keys.dat`'a saklar. Cihaza özel anahtar türetme
  (`OS.get_unique_id()`), HMAC-SHA256 bütünlük, PKCS7 dolgu.
- `router/live_connection_test.gd` — uçtan uca ilk gerçek DeepSeek
  çağrısı. **Node** tabanlı, **asenkron** (`test_finished` sinyali).
  712'lik senkron panele GİRMEZ — ayrı, elle tetiklenen araç.
- 4 sağlayıcı adapteri (DeepSeek/OpenAI/Anthropic/Gemini) hazır.

**DİKKAT:** Bu altyapının kodu var ve birim testleri geçiyor. AMA
**hiç gerçek ağ çağrısı yapılmadı** — önceki oturumun ortamı izin
vermiyordu. İlk işin bunu doğrulamak (bkz. §4 — Adım 1).

### 2.5. Kalite araçları
- `gdlint.py` — projeye özel yazılmış GDScript statik analiz aracı,
  14 kural (bkz. §5.2). Proje kökünde.
- `gdlint_selftest.py` — gdlint'in kendi öz-testi, 18 senaryo.
- `KURULUM_TEST.md` — kurulum + beklenen test çıktısı.

---

## 3. "BİTTİ" TANIMI (kullanıcının kabul kriteri)

Kullanıcı şunu söyledi — proje ANCAK bunların TAMAMI sağlanınca biter:

```
[ ] 1. Eklenti açılır (görünür bir panel çıkar)
[ ] 2. İzlenebilir (sistemin ne yaptığı panelde görülür)
[ ] 3. Yönetilebilir (panelden komut verilebilir, kontrol edilir)
[ ] 4. Erişilebilirlik tam (tüm sekmeler/özellikler panelden erişilir)
[ ] 5. Ayarlar sekmesi çalışır (gerçekten ayar değiştirir)
[ ] 6. Bellek tam (gerçek kullanımda bellek dolar/çalışır)
[ ] 7. Tüm API'ler bağlı (gerçek LLM çağrısı yapılır)
[ ] 8. Komutlar gerçekten uygulanır (AI üretir, sistem uygular)
```

Bu 8 madde karşılanmadan "bitti" denmez. Her aşama sonunda bu listeyi
güncelle, kullanıcıya hangi maddelerin işaretlendiğini göster.

---

## 4. KALAN İŞ — YOL HARİTASI (sıralı, gerekçeli)

> Sıra önemlidir. Her adım bir öncekine dayanır. Atlama.

### ADIM 1 — Canlı API doğrulaması  [bitti tanımı: #7]
**Neden ilk:** Adım 2 ve 3'ün anlamlı olması için sistemin gerçekten
"düşünebildiği" kanıtlanmalı. API çalışmıyorsa üstüne kurulan her şey
boşluğa inşa edilir.

**Yapılacaklar:**
1. Kullanıcıdan DeepSeek API anahtarını al.
2. Sandbox'ta Godot'u çalıştır. `live_connection_test.gd`'yi bir Node
   olarak kur:
   - `save_api_key("<deepseek-anahtarı>")` çağır → anahtar şifreli
     `user://`'a yazılır.
   - `run_test()` çağır → DeepSeek'e gerçek POST gider.
   - `test_finished` sinyalini dinle.
3. Sonuç `{ok: true, reply: "...BAGLANTI_TAMAM..."}` ise API çalışıyor.
4. `{ok: false}` ise hata mesajını oku, teşhis et:
   - 401 → anahtar geçersiz/formatı yanlış.
   - DNS/bağlantı hatası → ağ sorunu.
   - JSON ayrıştırma hatası → adapter / endpoint sorunu.
5. Çalışana kadar düzelt. **Bu adım bitmeden Adım 2'ye geçme.**

**Doğrulama:** Gerçek DeepSeek yanıtı alınmış olmalı. Kanıtı
kullanıcıya göster.

---

### ADIM 2 — Modüller arası köprüler  [bitti tanımı: #6, #8]
**Neden ikinci:** Modüller (memory, debug_loop, pilot_cell, router)
tek tek var ve test edildi, AMA birbirine bağlı DEĞİL. Sistem ancak
köprüler kurulunca "canlı" olur.

**Yapılacaklar (sıra önemli):**

**2a. Pilot Cell ↔ Router köprüsü** — 14 ajanın `Brain`'i gerçek
`AIProviderRouter` + canlı `http_transport` ile çağrı yapsın.
`live_mode=true`. Şu an ajanlar `live_mode=false`'da "NEEDS_LLM"
döndürüyor — bu köprüyle gerçek cevap üretmeli.

**2b. Hata ↔ Bellek köprüsü** (kullanıcının özel isteği) —
`debug_loop` bir hata çözünce, çözümü `memory`'nin Episodic +
Procedural katmanına yazsın. Yeni hata gelince ÖNCE bellekte "bu hata
daha önce görüldü mü, çözümü ne" diye aransın. Görülmüşse eski çözüm
önerilsin, baştan uğraşılmasın. Bu YENİ MODÜL değil — var olan iki
katmanı bağlayan ince bir köprü sınıfı.

**2c. Uçtan uca komut akışı** — kullanıcı görevi → Planner → Pilot
Cell → Router (gerçek LLM) → Verifier → HITL → Executor (gerçek dosya
yazma). Bu zincirin gerçekten çalıştığını bir entegrasyon testiyle
kanıtla (basit bir görevle, örn. "bir merhaba scripti üret").

**Doğrulama:** Her köprü için stress test + GDScript test + panel
zincirleme. 2c için gerçek bir uçtan uca çalıştırma kanıtı.

---

### ADIM 3 — Görünür panel (kod-tabanlı UI)  [bitti tanımı: #1-5]
**Neden son:** Artık sistem gerçekten çalışıyor (Adım 1-2). Panel
çalışan sistemin üstüne oturur, onu gösterir/yönetir.

**KULLANICI KARARI (kesin):** Sahneler `.tscn` dosyası OLARAK
KURULMAYACAK. Her şey **scriptle** yapılacak — `Control` düğümleri kod
içinde `.new()` ile yaratılacak, özellikleri kodda atanacak,
`add_child()` ile bağlanacak. Gerekçe: `.tscn` gdlint ile taranamaz,
testle doğrulanamaz; kod taranabilir/test edilebilir. Bu karar projenin
"her şey taranır/test edilir" disiplininin UI'a taşınmasıdır.

**Yapılacaklar:**
1. `EditorPlugin`'e takılan bir ana dock paneli (kodla kurulan).
   Açıldığında görünür.
2. `workspace` katmanının 9 sekmesi (Overview, Kanban, Live Feed,
   Plan Tree, Cost, Verifier, Checkpoints, Settings + 1). View-model'leri
   `workspace/` ve `*/ui/` altında HAZIR — panel onları okuyup çizecek.
3. Her sekme: ilgili view-model'i okur, `Control` düğümlerini kodla
   kurar, kullanıcı etkileşimini view-model'e geri bağlar.
4. Ayarlar sekmesi gerçek ayar değiştirmeli (API anahtarı girişi de
   buraya — `api_key_store`'a yazar; §2.4'teki dosya tabanlı altyapının
   görsel ön yüzü).
5. `frontend-design` skill'ini oku (`/mnt/skills/public/frontend-design`)
   — UI kalite standartları için.

**Doğrulama:** Panel mantığı (hangi sekme aktif, hangi veri gösterilir)
view-model olarak test edilir. Görsel kısım Godot'ta kullanıcı tarafından
göz ile doğrulanır.

---

### ADIM 4 — Final entegrasyon  [bitti tanımı: hepsi]
- §3'teki 8 maddenin tamamı işaretli mi kontrol et.
- Tam sistem testi: eklenti aç → panel çık → görev ver → AI üretsin
  → onayla → uygulansın → sonucu panelde gör.
- Kullanıcıya son durum raporu. ANCAK bu noktada "bitti" denir.

---

## 5. KALİTE DİSİPLİNİ — HER DEĞİŞİKLİKTE UYGULA

### 5.1. 6-adımlı disiplin (her tur)
1. **Kod yaz** → ara `gdlint` kontrolü.
2. **Python stress testi** ile mantığı doğrula (idealize değil, gerçek
   kodun aynı mekanizmasıyla).
3. **GDScript test dosyası** yaz (`_*_test.gd`), ana panele zincirle
   (`contracts/_self_test.gd` içinde yeni PHASE olarak ekle).
4. **Tam pre-flight:** çok-satırlı enum taraması + tüm dizinlerde
   gdlint + öz-test 18/18 + test tutarlılık (defs==calls) + toplam
   test sayımı.
5. **README + KURULUM_TEST.md** güncelle.
6. **Paketle**, kullanıcıya sun.

### 5.2. gdlint 14 kuralı (R01-R14)
R01 `@tool` ilk satır · R02 `extends` · R03 `class_name` pozisyon ·
R04 `const` ile PackedXArray YASAK · R05 `const` içinde fonksiyon
YASAK · R06 tab-indent · R07 inner class `extends` inline · R08
kolon-boşluk · R09 func-kolon · R10 parantez dengesi · R11 tab+space
karışık YASAK · R12 cross-file enum referansı (enum TEK SATIRDA) ·
R13 çift fonksiyon YASAK · R14 ad çakışması (GDScript yerleşikleri +
Object/Node miras metodları).

### 5.3. Test dosyası deseni
- `static func run_all() -> Array`
- `_b(batch, result)` ile batch etiketi, `_ok()/_fail()` yardımcıları
- Her test `{ok, name, reason}` Dict döndürür
- Ana panele zincirleme: `_self_test.gd` içinde
  `for X in AIYeniTest.run_all(): results.append(X)`

### 5.4. GDScript teknik notları
- `@tool` ilk satır, `class_name` `extends`'ten sonra, tab-indent.
- Inner class: `class X extends Y:` inline.
- `const` ile PackedXArray YASAK, `const` içinde fonksiyon YASAK.
- Enum TEK SATIRDA olmalı (R12).
- Metod adı GDScript yerleşikleri / Object / Node miras metodlarıyla
  çakışmamalı (R14).
- Node-tabanlı sınıflar sahnesiz test edilemez → mantık RefCounted
  view-model'lere ayrılır, Node ince sarmalayıcı kalır.
- Asenkron iş (ağ) senkron test panistine girmez — ayrı tutulur.

### 5.5. Mimari desenler
- "Mock yasak" — sahte başarı yok.
- Her bug bir gdlint kuralına dönüşür.
- Büyük modül çekirdek + kalan diye bölünür.
- Ortak desen sınıfları tekrarı önler (`cache_base`, `genre_schema_base`
  vb.).
- UI: her modül test edilebilir `*ViewModel` (RefCounted) + ince
  görsel `Control`.

---

## 6. DOSYA HARİTASI

```
addons/ai_assistant/
  <18 katman>/              — mantık modülleri (§2.2)
  <katman>/ui/              — 24 UI view-model (§2.3)
  contracts/_self_test.gd   — ANA TEST PANELİ (yeni testler buraya zincirlenir)
  router/http_transport.gd        — gerçek HTTP
  router/api_key_store.gd         — şifreli anahtar deposu
  router/live_connection_test.gd  — ilk gerçek API çağrısı (asenkron)
addons/ai_contract_tests/   — test eklentisi (plugin.cfg + plugin.gd)
gdlint.py                   — statik analiz aracı (14 kural)
gdlint_selftest.py          — gdlint öz-testi (18 senaryo)
KURULUM_TEST.md             — kurulum + beklenen çıktı
```

---

## 7. İLK OTURUM — NE YAPACAKSIN

1. Bu belgeyi tam okudun. Şimdi projeyi diskten teyit et (§0.2 madde 2).
2. `gdlint.py`'yi tüm `addons/ai_assistant` üzerinde çalıştır → 0 hata
   beklenir. `gdlint_selftest.py` → 18/18 beklenir.
3. Godot'ta `ai_contract_tests` eklentisini etkinleştir, `_self_test.gd`
   panelini çalıştır → **717/717** beklenir.
4. Bu üçü doğrulanınca: kullanıcıdan DeepSeek anahtarını iste, **ADIM
   1**'e başla.
5. Her adım sonunda §3 listesini güncelle, kullanıcıya raporla.

**"Bitti" yalnızca §3'teki 8 madde işaretlenince söylenir. O ana
kadar dürüst ol: ne yapıldı, ne kaldı, net söyle.**
