# Changelog

## 1.1.0-rc.1 — 2026-08-02

Godot 4.6.3, DeepSeek V4 Pro Max, güvenli editör mutasyonu ve Android/dar ekran üretim sertleştirmesi için release candidate.

### Güvenlik ve editör mutasyonu

- `EditorInterface` erişimi Godot 4.6 public API sözleşmesine taşındı.
- Node, property ve script işlemleri `EditorUndoRedoManager` geçmişine alındı.
- Hedef sahne doğrulaması ve action kimliğine bağlı tek-kullanımlık yetki eklendi.
- Bütünlük hatasında rollback ve güvenlik-kritik ProjectSettings engeli eklendi.
- Secret leakage ve mimari invariant taramaları CI hard gate'i oldu.

### Godot 4.6.3 kalite kapısı

- Resmî Godot 4.6.3 binary'si release SHA-256 digest'iyle doğrulanıyor.
- Plugin import/parse/compile ve tam contract paketi GitHub Actions'a bağlandı.
- Runtime hygiene; Timer, ObjectDB ve Resource leak regresyonlarını reddediyor.
- İzole gerçek masaüstü editöründe node/property/script do → undo → redo → cleanup smoke doğrulandı.
- Smoke sırasında production proje dosyalarının değişmezliği zorunlu hale getirildi.

### DeepSeek V4 Pro Max

- Canlı DeepSeek router tek üretim modeline sabitlendi: `deepseek-v4-pro`.
- Bağlam penceresi `1.000.000`, maksimum çıktı `384.000` token olarak tanımlandı.
- Bütün canlı üretim amaçlarında `thinking.type=enabled` ve `reasoning_effort=max` zorlanıyor.
- Eski `deepseek-chat`, `deepseek-reasoner` ve Flash değerleri canlı ağ isteğinden önce V4 Pro Max'e yükseltiliyor.
- 1M toplam bağlama yaklaşan girdilerde çıktı bütçesi güvenli kalan alana indiriliyor; tükenmiş bağlam ağdan önce reddediliyor.
- Thinking isteklerinde etkisiz `temperature` alanı gönderilmiyor.
- Cache kimliği purpose, thinking ve reasoning effort ayrımını taşıyor.

### Uzun yanıt taşıması ve gözlemlenebilirlik

- HTTP timeout 1.800 saniyeye çıkarıldı.
- Yanıt gövdesi güvenlik limiti 64 MiB, indirme parçası 256 KiB olarak ayarlandı.
- Gzip, threaded HTTP ve HTTPS-only politikası eklendi.
- Dry-run Authorization başlığı redakte ediliyor.
- Provider, model, token kullanımı, finish reason, HTTP, latency, cache ve request metadata'sı sonuç sözleşmesine eklendi.
- 401/429 ve ağ hatalarında API anahtarı/Authorization redaksiyonu uygulanıyor.

### Canlı sağlayıcı kapısı

- Gerçek V4 Pro Max runner hazırlanmış ağ gövdesini ve gerçek yanıtı birlikte doğruluyor.
- Başarı için `V4_MAX_PROFILE_OK` ve `V4_LIVE_OK` işaretleri zorunlu.
- `DeepSeek V4 Pro Max Live Gate` GitHub Actions workflow'u `DEEPSEEK_API_KEY` repository secret kullanıyor.
- Canlı logda secret veya Authorization sızıntısı hard failure.

### Android ve dar ekran

- 360/480/720/1080 responsive profilleri eklendi.
- Ana dokunmatik hedefler en az 48 mantıksal piksele sabitlendi.
- AI Studio ve Workspace canlı yön/boyut değişimine bağlandı.
- Mobile renderer, HTTPS endpoint, embedded secret ve INTERNET izni readiness audit'i eklendi.

### Sürüm konsolidasyonu

- Makine-okunur release readiness manifesti ve doğrulayıcısı eklendi.
- Plugin metadata `1.1.0-rc.1` ve Godot 4.6.3 olarak güncellendi.
- Faz 1–8 dokümantasyonu, rollback ve tek konsolidasyon PR stratejisi kaydedildi.
- Açık dış kapılar varken `merge_ready=true` beyanı CI tarafından reddediliyor.

### Final otomatik doğrulama

- Ana contract: 872/872
- Mobile hardening: 12/12
- Gerçek repo Android audit: 2/2
- Release readiness: 10/10
- DeepSeek V4 Pro Max: 10/10
- **Toplam: 906/906**
- Gerçek masaüstü EditorUndoRedo smoke: **3/3**
- Kanıt run: `30747036616`
- Kanıt artifact: `8833211445`

### Release öncesi açık kapılar

- Gerçek anahtarlı DeepSeek V4 Pro Max canlı E2E
- Gerçek Android Godot 4.6.3 editör smoke
- Kullanıcı onaylı tek konsolidasyon PR birleşmesi

Bu kapılar tamamlanana kadar sürüm release candidate ve `merge_ready=false` kalır.
