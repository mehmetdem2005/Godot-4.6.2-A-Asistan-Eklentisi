# Faz 1 — Godot 4.6.3 Güvenlik ve Uyumluluk Denetimi

Durum: Başlatıldı  
Hedef motor: Godot 4.6.3  
Dal: `agent/godot-4-6-3-phase-1-safety-audit`  
İlgili iş: #13

## 1. Fazın amacı

Bu faz davranış veya yetki genişletmez. Mevcut AI Asistan kod tabanını koruyarak Godot 4.6.3 geçişi için doğrulanabilir bir güvenlik ve uyumluluk tabanı oluşturur.

## 2. Doğrulanan mevcut yetenekler

- Eklenti gerçek bir `EditorPlugin` giriş noktasına ve tam ekran editör paneline sahip.
- Scene/node/property/script/project-setting işlemleri için yapılandırılmış editör action hattı mevcut.
- Script düzenlemelerinde tam dosya ezmek yerine SEARCH/REPLACE tabanlı cerrahi düzenleme hattı mevcut.
- Otonom hata döngüsünde bounded retry ve circuit breaker mevcut.
- Otonom onarım `res://game/` sandbox'ı ile sınırlandırılmış.
- API anahtarı kaynak koda yazılmadan yerel şifreli depoya kaydediliyor.
- Son kayıtlı tabanda 857 self-test ve 313 GDScript dosyası için lint başarısı raporlanmış.

## 3. İlk risk bulguları

### R-001 — Godot 4.6.3 doğrulaması yok

`plugin.cfg` hâlâ Godot 4.6.2 hedefini bildiriyor. Kod tabanının 4.6.3 üzerinde parse, editor-load, headless self-test ve canlı editör smoke test sonuçları henüz bu fazda kanıtlanmış değil.

Karar: Sürüm metni, test kanıtı alınmadan 4.6.3 olarak değiştirilmez.

### R-002 — Varsayılan dal yönetişimi

Deponun varsayılan dalı `claude/godot-ai-game-builder-FRhQk`. Üretim için kalıcı `main` ve kısa ömürlü faz dalları kullanılmalı.

Karar: Bu faz mevcut varsayılan dalı değiştirmez. Sonraki yönetişim fazında korumalı `main`, branch protection ve PR zorunluluğu ele alınır.

### R-003 — Genel erişimli depo

Depo public görünürlükte. Kaynak kodunda API anahtarı bulunmaması olumlu olsa da test fixture'ları, log örnekleri, hata raporları ve gelecekteki indirme kayıtları secret taramasından geçmelidir.

Karar: Faz 2'de secret redaction ve repository secret scan sözleşmesi eklenir.

### R-004 — Otomatik onarım yetki sınırı

Mevcut onarımın `res://game/` ile sınırlandırılması güvenlidir; ancak hedef eklenti farklı projelerde çalışacağı için sabit sandbox yolu ölçeklenebilir değildir.

Karar: Sandbox genişletilmez. Faz 3'te proje bazlı allowlist ve capability token tasarlanır.

### R-005 — Editör public API sınırları

`EditorInterface` ve canlı scene mutasyonları motor sürümleri arasında davranış farkı gösterebilir. Private editör node'larına bağımlılık kabul edilmez.

Karar: 4.6.3 uyumluluk matrisi public API bazında çıkarılır; private-tree erişimi tespit edilirse engellenir.

## 4. Faz 1 güvenlik kuralları

1. Ana dala doğrudan yazılmaz.
2. Kod davranışı değiştirilmez.
3. Yeni yazma, silme, indirme veya internet yetkisi açılmaz.
4. API anahtarı ve Authorization header hiçbir loga girmez.
5. Her sonraki faz ayrı dal ve taslak PR ile ilerler.
6. Godot 4.6.3 test kanıtı olmadan uyumluluk iddiası yapılmaz.

## 5. Faz 2 için hazırlanmış iş listesi

Faz 2 adı: **Godot 4.6.3 Compatibility Gate**

- Engine sürüm doğrulayıcısı
- Godot 4.6.3 parse ve plugin-load test koşucusu
- `EditorPlugin`, `EditorInterface`, `EditorUndoRedoManager` ve debugger köprülerinin sözleşme testleri
- Plugin metadata sürüm güncellemesi yalnız testler geçerse
- Secret/log redaction regresyon testleri
- Android editor için temel smoke-test kontrol listesi

## 6. Faz 1 kabul kriterleri

- [x] Ayrı güvenli faz dalı oluşturuldu.
- [x] Faz kapsamı issue olarak kaydedildi.
- [x] Mevcut mimari sıfırdan yazılmadan envanterlendi.
- [x] İlk güvenlik ve yönetişim riskleri kaydedildi.
- [x] Faz 2 uygulanabilir işlere ayrıldı.
- [ ] Godot 4.6.3 üzerinde gerçek test — Faz 2 kapsamı.

## 7. Bilinen doğrulama sınırı

Bu çalışma ortamında Godot 4.6.3 çalıştırılabilir dosyası bulunmadığından gerçek parse/editor smoke testi bu fazda yürütülmedi. Bu eksik, uyumluluk iddiası ile kapatılmadı; Faz 2'nin birincil kabul kriteri olarak bırakıldı.
