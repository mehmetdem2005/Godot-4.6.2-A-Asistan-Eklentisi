# Surgical Edit — Cerrahi Kod Düzenleme (Full-Rewrite Önleme)

LLM'in doğal davranışı: "şu dosyayı düzelt" -> tüm dosyayı yeniden
yaz. Bu yıkıcı: değişken adları değişir, yorumlar kaybolur, format
bozulur, başka fonksiyonlar yanlışlıkla "iyileştirilir".

Bu modül her kod-üreten LLM çağrısının üstüne middleware olarak
girer ve cerrahi düzenleme zorlar.

## Dosyalar

- intent_classifier.gd — Görevi 9 niyet kategorisine sınıflandırır
  (yeni dosya / fonksiyon değişimi / silme / yeniden adlandırma...).
  Uzunluk-ağırlıklı puanlama: spesifik kelime genel kelimeyi bastırır.
- scope_extractor.gd — Full-rewrite önlemenin KALBİ. LLM'e tüm dosya
  yerine sadece hedef fonksiyon + 20 satır context verir.
- protocols/search_replace_handler.gd — Aider-tarzı SEARCH/REPLACE
  protokolü. Benzersizlik kontrolü: belirsiz eşleşme reddedilir.
- validation/format_drift_detector.gd — Düzenleme sonrası format
  kayması (girinti, yorum kaybı) tespiti.
- edit_orchestrator.gd — Middleware ana motoru, hepsini birleştirir.
- _surgical_edit_test.gd — 25 sıkı test.

## Akış

1. IntentClassifier — bu ne tür düzenleme?
2. ScopeExtractor — LLM'e minimal context (tüm dosya DEĞİL)
3. (LLM çağrısı — Pilot Cell yapar, SEARCH/REPLACE formatı zorlanır)
4. SearchReplaceHandler — çıktıyı ayrıştır + uygula
5. FormatDriftDetector — format bozulmuş mu?
6. Kabul / ret + retry (max 3)

## Temel garantiler

- LLM'e asla tüm dosya verilmez (büyük dosyada) — sadece kapsam
- SEARCH metni dosyada birebir + benzersiz olmalı; belirsizse RET
- Format kayması (tab->boşluk) error -> RET
- Tehlikeli intent (REPLACE_FILE) -> HITL onayı şart
- Sahte başarı yok: protokol/doğrulama ihlali ret olur

## Bu sürümün kapsamı

Çekirdek 5 modül (intent, scope, SEARCH/REPLACE, drift, orchestrator).
Master plan'daki diğer 5 protokol (INSERT_AT_ANCHOR, DELETE_BLOCK,
RENAME, MULTI_STEP, EXPLICIT_REPLACE) ve 5 ek doğrulama sonraki
Surgical Edit oturumuna bırakıldı.

## Kalite

gdlint.py R01-R13 + stress test (surgical logic 23/23 + düzeltme 10/10).


## GÜNCELLEME — 5 Ek Protokol (bu sürüm)

protocols/ altına 5 yeni düzenleme protokolü eklendi:

- insert_at_anchor_handler.gd — Çapaya saf ekleme (SEARCH/REPLACE'in
  yapamadığı). Çapa benzersiz olmalı.
- delete_block_handler.gd — Blok/satır aralığı silme. Dosyayı
  boşaltan silme reddedilir.
- project_wide_rename_handler.gd — Sembol yeniden adlandırma,
  kelime-sınırı duyarlı (health != healthbar). Çok dosya destekli.
- multi_step_edit_handler.gd — Sıralı çok adımlı düzenleme.
  ATOMİK: bir adım başarısızsa tüm dizi geri alınır.
- explicit_replace_handler.gd — Kontrollü tam dosya değişimi.
  Onay zorunlu; küçük değişimde surgical edit önerilir.

Artık 6 protokol var (search_replace + bu 5). Her biri belirsiz/
bulunamayan hedefte reddeder — sahte başarı yok.

Kalan: 4 ek doğrulama (comment_loss, naming_drift, scope_creep,
intent_alignment) sonraki Surgical Edit oturumuna.

## GÜNCELLEME — 4 Ek Doğrulama (bu sürüm)

validation/ altına 4 yeni düzenleme-sonrası doğrulama eklendi:

- comment_loss_detector.gd — Kaybolan yorumları tespit eder.
  Docstring kaybı HIGH, TODO/FIXME MEDIUM, normal LOW önemde.
- naming_drift_detector.gd — İzinsiz sembol adı değişimini yakalar.
  Sembol KAYBI tehlikeli (dış referans kırılır), ekleme normal.
- scope_creep_detector.gd — Düzenlemenin istenenden fazla yere
  taşıp taşmadığını ölçer. NONE/MINOR/MAJOR.
- intent_alignment_checker.gd — Yapılan düzenlemenin niyetle
  uyuşup uyuşmadığını denetler (DELETE küçülmeli, ADD büyümeli...).

Artık 5 doğrulama var (format_drift + bu 4). Surgical Edit
TAMAMLANDI: 6 protokol + 5 doğrulama + intent/scope/orchestrator.

NOT scope_creep: bir satırı DEĞİŞTİRMEK satır-diff'te 2 işlemdir
(1 silme + 1 ekleme) — expected_change_lines buna göre verilir.