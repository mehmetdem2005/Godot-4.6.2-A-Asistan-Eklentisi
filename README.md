# AI Asistan — Godot 4.6.3

Godot editörü içinde çalışan, güvenli editör mutasyonu ve **DeepSeek V4 Pro Max** profili kullanan otonom oyun geliştirme asistanı.

Bu dal bir **release candidate**'dır. Otomatik kalite kapıları ve gerçek masaüstü EditorUndoRedo smoke tamamlanmıştır; gerçek DeepSeek sağlayıcı ve gerçek Android Godot editörü kanıtları tamamlanmadan üretim sürümü veya birleşmeye hazır kabul edilmez.

## Temel yetenekler

- Tam ekran Godot editör ana görünümü
- Doğal sohbet ile üretim görevlerini otomatik ayırma
- Çok-adımlı planlama ve çoklu rol zinciri
- Dinamik görev grafiği ve sınırlı otomatik onarım
- Godot 4.6 API sözleşmeli kod üretimi
- GDScript doğrulama, HITL kapısı ve güvenli Executor
- Scene/node/property/script işlemlerinde gerçek `EditorUndoRedoManager`
- SEARCH/REPLACE tabanlı cerrahi kod düzenleme
- DeepSeek V4 Pro Max üretim politikası
- Canlı sağlayıcı metadata'sı, maliyet ve hata gözlemlenebilirliği
- 360 px portreden geniş masaüstüne responsive editör arayüzü
- Şifreli yerel API anahtarı saklama ve secret leakage kapıları

## DeepSeek V4 Pro Max profili

Canlı DeepSeek trafiği şu profile zorlanır:

- model: `deepseek-v4-pro`
- bağlam: `1.000.000` token
- maksimum çıktı: `384.000` token
- düşünme: `thinking.type=enabled`
- reasoning effort: `max`
- taşıma timeout: 1.800 saniye
- maksimum yanıt gövdesi: 64 MiB
- yalnız HTTPS, gzip ve threaded HTTP

Eski `deepseek-chat`, `deepseek-reasoner` ve Flash seçimleri yalnız geriye uyumluluk girdisidir; canlı router bunları V4 Pro Max profiline yükseltir. 1M toplam bağlama yaklaşan girdilerde çıktı bütçesi güvenli kalan alana indirilir; bağlam tükenirse ağ çağrısı yapılmadan açık hata döner.

Detay: `docs/MIGRATION_DEEPSEEK_V4.md`

## Sistem gereksinimleri

- Godot `4.6.3.stable`
- Canlı LLM özellikleri için geçerli DeepSeek API anahtarı
- Sağlayıcı çağrıları için HTTPS internet bağlantısı
- Android cihaz kapısı için Android üzerinde Godot 4.6.3 editörü

## Kurulum

1. Depoyu bir Godot projesi olarak açın.
2. **Project → Project Settings → Plugins** bölümünden `AI Asistan` eklentisini etkinleştirin.
3. Üst editör ana ekranındaki **AI Asistan** sekmesini açın.
4. **≡ Menü → Ayarlar** bölümünden DeepSeek anahtarını girip kaydedin.

Anahtarı kaynak koda, `project.godot`, `export_presets.cfg`, doküman, issue/PR veya CI loguna yazmayın.

## Otomatik doğrulama

Godot 4.6.3 kalite koşucusu:

```bash
godot --headless --path . --script res://tools/ci_contract_runner.gd
```

Final otomatik paket: **906/906**.

Kalite kapıları:

- exact Godot 4.6.3 sürüm ve resmî binary digest doğrulaması
- plugin import/parse/compile
- 872 ana contract testi
- 12 mobil hardening testi
- 2 gerçek repo Android audit testi
- 10 release-readiness testi
- 10 DeepSeek V4 Pro Max testi
- runtime hygiene
- secret leakage taraması
- editör mutasyon mimari invariant'ları
- izole gerçek masaüstü `EditorUndoRedoManager` smoke
- production proje dosyalarının test sırasında değişmezliği

Masaüstü editör sonucu:

```text
SMOKE_OK: 3/3 smoke testi geçti
```

## Gerçek sağlayıcı kapısı

Repository secret:

```text
DEEPSEEK_API_KEY
```

Workflow:

```text
DeepSeek V4 Pro Max Live Gate
```

Başarı işaretleri:

```text
V4_MAX_PROFILE_OK
V4_LIVE_OK
```

Detay: `tools/DEEPSEEK_V4_LIVE_TEST.md`

## Release durumu

Makine kaynağı:

- `release/readiness_manifest.json`

İnsan tarafından okunabilir rapor:

- `docs/RELEASE_READINESS.md`

Kapanan dış kapı:

- masaüstü EditorUndoRedo: geçti, gerçek run/artifact kanıtı manifestte kayıtlı

Açık dış kapılar:

1. gerçek anahtarlı DeepSeek V4 Pro Max çağrısı
2. gerçek Android Godot editörü: `tools/ANDROID_EDITOR_SMOKE.md`
3. final kullanıcı onaylı konsolidasyon: `tools/FINAL_RELEASE_SMOKE.md`

Bu kapılar tamamlanmadan manifestte `merge_ready=false` kalmalıdır.

## Birleşme modeli

Faz 2–8 dalları kümülatif stacked PR'lardır. Ara PR'lar tek tek varsayılan dala birleştirilmemelidir. Dış kapılar tamamlandıktan sonra Faz 8 konsolidasyon PR'ı varsayılan dala retarget edilip tek squash release PR'ı olarak incelenmelidir.

Otomatik merge uygulanmaz. Son birleşme kararı kullanıcıya aittir.

## Lisans ve dağıtım

Bu repoda açık lisans dosyası bulunmuyorsa yeniden dağıtım veya üçüncü taraf kullanımı için otomatik lisans varsayımı yapılmamalıdır.
