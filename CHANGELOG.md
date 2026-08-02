# Changelog

## 1.1.0-rc.1 — 2026-08-02

Godot 4.6.3, DeepSeek V4, güvenli editör mutasyonu ve Android/dar ekran üretim sertleştirmesi için release candidate.

### Faz 1 — Güvenlik ve uyumluluk tabanı

- Mevcut mimari, yetkiler ve ilk 4.6.3 geçiş riskleri envanterlendi.
- Ana dala doğrudan yazmama, secret loglamama ve test kanıtı olmadan uyumluluk iddia etmeme kuralları sabitlendi.

### Faz 2 — Editör mutasyon çekirdeği

- `EditorInterface` erişimi Godot 4.6 public API sözleşmesine taşındı.
- Node, property ve script işlemleri `EditorUndoRedoManager` geçmişine alındı.
- Hedef sahne doğrulaması ve action kimliğine bağlı tek-kullanımlık yetki eklendi.
- Bütünlük hatasında rollback ve güvenlik-kritik ProjectSettings engeli eklendi.

### Faz 3 — Godot 4.6.3 kalite kapısı

- Resmî Godot 4.6.3 binary'si release SHA-256 digest'iyle doğrulanıyor.
- Plugin import/parse/compile ve tam contract paketi GitHub Actions'a bağlandı.
- Secret leakage ve mimari invariant taramaları eklendi.

### Faz 4 — Runtime hygiene ve editör smoke harness

- SceneTree dışında Timer başlatma uyarısı giderildi.
- ObjectDB/Resource kapanış sızıntıları temizlendi.
- Ayrı editör fixture'ı üzerinde node/property/script Undo/Redo smoke harness eklendi.
- Runtime hygiene regresyonları CI hard gate'i oldu.

### Faz 5 — DeepSeek V4 backend geçişi

- Canlı router `AIDeepSeekV4Adapter` kullanıyor.
- V4 Pro/Flash, düşünme modu, reasoning effort ve 384K çıktı politikası merkezileştirildi.
- Legacy model değerleri ağ gövdesine çıkmadan V4 kimliğine normalize ediliyor.
- Purpose/thinking cache ayrımı ve gerçek response model kimliği eklendi.

### Faz 6 — Canlı sağlayıcı gözlemlenebilirliği

- Provider, model, token kullanımı, finish reason, HTTP, latency, cache ve request metadata'sı sonuç sözleşmesine eklendi.
- 401/429 ve ağ hatalarında Authorization/API anahtarı redaksiyonu eklendi.
- Katı gerçek V4 Pro headless runner eklendi.

### Faz 7 — Android ve dar ekran sertleştirmesi

- 360/480/720/1080 responsive profilleri eklendi.
- Ana dokunmatik hedefler en az 48 mantıksal piksele sabitlendi.
- AI Studio ve Workspace canlı yön/boyut değişimine bağlandı.
- Mobile renderer, HTTPS endpoint, embedded secret ve INTERNET izni readiness audit'i eklendi.

### Faz 8 — Sürüm konsolidasyonu

- Makine-okunur release readiness manifesti ve doğrulayıcısı eklendi.
- Plugin metadata `1.1.0-rc.1` ve Godot 4.6.3 olarak güncellendi.
- Faz 1–8 dokümantasyonu, V4 migration, rollback ve tek konsolidasyon PR stratejisi kaydedildi.
- Açık manuel kapılar varken `merge_ready=true` beyanı CI tarafından reddediliyor.

### Değişen davranışlar

- `deepseek-chat` artık sağlayıcıya eski model adı olarak gönderilmez; V4 Pro + düşünme kapalı davranışına eşlenir.
- `deepseek-reasoner` artık sağlayıcıya eski model adı olarak gönderilmez; V4 Pro + düşünme açık davranışına eşlenir.
- DeepSeek cache anahtarları purpose ve düşünme moduna duyarlıdır; eski cache sonuçları yeniden kullanılmayabilir.
- Canlı köprü sonuç sözlüğü yeni gözlemlenebilirlik alanları taşır; mevcut alanlar korunmuştur.
- Eklenti sol dock yerine üst editör ana ekranında tam ekran çalışır.

### Otomatik doğrulama geçmişi

- Faz 4: 862 test
- Faz 5: 869 test
- Faz 6: 872 test
- Faz 7: 886 test
- Faz 8: **896 test** — 10 release-readiness sözleşmesi ve manifest sayı kapısı; Actions run `30745482272`

### Release öncesi açık kapılar

- Masaüstü canlı editör Undo/Redo smoke
- Gerçek anahtarlı DeepSeek V4 Pro canlı E2E
- Android Godot 4.6.3 editör smoke
- Kullanıcı onaylı tek konsolidasyon PR birleşmesi

Bu sürüm, bu kapılar tamamlanana kadar release candidate olarak kalır.
