# Layer 5 — Verifier (Doğrulama)

Executor (Layer 4) bir GDScript dosyası yazdı. Bu katman o kodun
DOĞRU olduğunu kanıtlar — yazılan şey gerçekten çalışıyor mu?

## Dosyalar

- verify_level_base.gd — Tüm doğrulama seviyelerinin ortak temeli.
  Kaynak tokenize, yorum ayıklama, girinti hesabı.
- syntactic_verifier.gd — Seviye 1: kod derleniyor mu?
  Godot'un GERÇEK GDScript derleyicisini çağırır (GDScript.reload()).
  Taklit değil — motor neyi reddederse Verifier de reddeder.
- semantic_verifier.gd — Seviye 2: kod anlamlı mı?
  Çift fonksiyon, çift üye, tanımsız enum değeri, ulaşılamaz kod,
  class_name/extends tutarlılığı, boş fonksiyon gövdesi.
- verifier_engine.gd — Layer 5 ana motoru. Seviyeleri sırayla
  koşturur (kademeli — bir seviye düşerse sonrakiler atlanır).
- _verifier_test.gd — 20 sıkı test.

## 5 seviye (şu an 2'si gerçek)

- SYNTACTIC   ✓ uygulandı — derleniyor mu
- SEMANTIC    ✓ uygulandı — anlamlı mı
- RUNTIME     ⬜ sonraki phase — çalışınca çöküyor mu
- BEHAVIORAL  ⬜ sonraki phase — beklendiği gibi mi
- PERFORMANCE ⬜ sonraki phase — yeterince hızlı mı

Uygulanmamış seviyeler SKIP/NOT_IMPLEMENTED raporlar (sahte PASS yok).

## Neden önemli

Bu oturumda iki gerçek bug çıktı: çift 'persist' fonksiyonu ve
olmayan 'FUNCTIONAL' enum değeri. İkisi de SEMANTIC seviye hatası.
Verifier artık sistemin KENDİ yaptığı bu hata türünü yakalayabiliyor.

## Kademeli doğrulama

Bir seviye FAIL verirse sonrakiler çalışmaz — syntax hatası varsa
semantic analiz anlamsız, bozuk kodu çalıştırmak tehlikeli.

## Kalite

gdlint.py R01-R13 + stress test (semantic logic 8/8).
SYNTACTIC seviye Godot'un gerçek derleyicisini kullandığı için
asıl testi Godot içinde anlamlıdır.
