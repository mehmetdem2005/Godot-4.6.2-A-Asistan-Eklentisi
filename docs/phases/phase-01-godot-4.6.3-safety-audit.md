# Faz 1 — Godot 4.6.3 Güvenlik ve Uyumluluk Denetimi

> Faz 8 konsolidasyon notu: Bu belge Faz 1 sırasında kaydedilmiş tarihsel güvenlik tabanıdır. Sonraki fazların gerçek test sonuçları ve güncel açık kapılar `docs/RELEASE_READINESS.md` ile `release/readiness_manifest.json` içinde tutulur.

Durum: Otomatik kapsam tamamlandı  
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
- Faz 1 sırasında son kayıtlı tabanda 857 self-test ve 313 GDScript dosyası için lint başarısı raporlanmıştı.

## 3. İlk risk bulguları

### R-001 — Godot 4.6.3 doğrulaması yoktu

Faz 1 sırasında `plugin.cfg` Godot 4.6.2 hedefini bildiriyordu ve gerçek 4.6.3 parse/editor kanıtı henüz yoktu.

Karar: Sürüm metni test kanıtı alınmadan değiştirilmedi. Faz 3 ve sonraki kalite kapılarında resmî Godot 4.6.3 binary'si doğrulanarak parse, contract ve runtime hygiene testleri çalıştırıldı.

### R-002 — Varsayılan dal yönetişimi

Deponun varsayılan dalı `claude/godot-ai-game-builder-FRhQk` olarak kaldı. Fazlar kısa ömürlü, birbirine bağlı taslak PR dalları olarak yürütüldü.

Karar: Varsayılan dal otomatik değiştirilmez. Faz 8 konsolidasyon PR'ı, manuel kapılar tamamlandıktan sonra kullanıcı kararıyla varsayılan dala retarget edilmelidir.

### R-003 — Genel erişimli depo

Depo public görünürlükte. Kaynak kodu, fixture, doküman ve CI logları secret taramasından geçmelidir.

Karar: Faz 3'te secret leakage gate, Faz 6'da Authorization/API anahtarı redaksiyon sözleşmeleri, Faz 7'de proje/export secret audit'i eklendi.

### R-004 — Otomatik onarım yetki sınırı

Otomatik yazma ve onarım `res://game/` sandbox'ı ile sınırlandırılmıştır.

Karar: Release candidate bu sınırı genişletmez. Proje bazlı daha geniş capability tasarımı yeni ve ayrı bir gelecek sürüm konusu olmalıdır.

### R-005 — Editör public API sınırları

`EditorInterface` ve canlı scene mutasyonları motor sürümleri arasında davranış farkı gösterebilir. Private editör node'larına bağımlılık kabul edilmez.

Karar: Faz 2 editör mutasyon hattını Godot 4.6 public API'si ve `EditorUndoRedoManager` üzerine taşıdı; canlı editör 3/3 smoke kanıtı release öncesi manuel kapı olarak açık tutuldu.

## 4. Faz 1 güvenlik kuralları

1. Ana dala doğrudan yazılmaz.
2. Kod davranışı kontrolsüz biçimde genişletilmez.
3. Yeni yazma, silme, indirme veya internet yetkisi açık kabul kriteri olmadan açılmaz.
4. API anahtarı ve Authorization header hiçbir loga girmez.
5. Her faz ayrı dal ve taslak PR ile ilerler.
6. Godot 4.6.3 test kanıtı olmadan uyumluluk iddiası yapılmaz.

## 5. Faz 1 kabul kriterleri

- [x] Ayrı güvenli faz dalı oluşturuldu.
- [x] Faz kapsamı issue olarak kaydedildi.
- [x] Mevcut mimari sıfırdan yazılmadan envanterlendi.
- [x] İlk güvenlik ve yönetişim riskleri kaydedildi.
- [x] Sonraki fazlar uygulanabilir işlere ayrıldı.
- [x] Godot 4.6.3 otomatik parse/contract/runtime kanıtı sonraki fazlarda alındı.
- [ ] Canlı editör Undo/Redo smoke kanıtı release manifestinde hâlâ `pending`.

## 6. Konsolidasyon durumu

Bu tarihsel belge Faz 8 dalına taşınmıştır. Güncel birleşme kararı yalnız `AIReleaseReadinessAudit` sonucu, final CI ve üç manuel kapı birlikte değerlendirildikten sonra verilmelidir.
