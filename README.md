# AI Asistan — Godot 4.6.3

Godot editörü içinde çalışan, DeepSeek V4 destekli otonom oyun geliştirme asistanı.

Bu dal bir **release candidate**'dır: otomatik kalite kapıları uygulanmıştır ancak gerçek editör, gerçek sağlayıcı ve Android cihaz smoke kanıtları tamamlanmadan üretim sürümü veya birleşmeye hazır kabul edilmez.

## Temel yetenekler

- Tam ekran Godot editör ana görünümü
- Doğal sohbet ile üretim görevlerini otomatik ayırma
- Çok-adımlı planlama ve çoklu rol zinciri
- Dinamik görev grafiği ve sınırlı otomatik onarım
- Godot 4.6 API sözleşmeli kod üretimi
- GDScript doğrulama, HITL kapısı ve güvenli Executor
- Scene/node/property/script işlemlerinde `EditorUndoRedoManager`
- SEARCH/REPLACE tabanlı cerrahi kod düzenleme
- DeepSeek V4 Pro ve V4 Flash model politikası
- Canlı sağlayıcı metadata'sı, maliyet ve hata gözlemlenebilirliği
- 360 px portreden geniş masaüstüne responsive editör arayüzü
- Şifreli yerel API anahtarı saklama ve secret leakage kapıları

## Sistem gereksinimleri

- Godot `4.6.3.stable`
- Eklentinin canlı LLM özellikleri için geçerli DeepSeek API anahtarı
- Sağlayıcı çağrıları için HTTPS internet bağlantısı

## Kurulum

1. Depoyu bir Godot projesi olarak açın.
2. **Project → Project Settings → Plugins** bölümünden `AI Asistan` eklentisini etkinleştirin.
3. Üst editör ana ekranındaki **AI Asistan** sekmesini açın.
4. **≡ Menü → Ayarlar** bölümünden DeepSeek anahtarını girip kaydedin.

Anahtarı kaynak koda, `project.godot`, `export_presets.cfg`, doküman veya CI loguna yazmayın.

## DeepSeek V4 davranışı

- Kod üretimi: V4 Pro veya seçilen V4 Flash, düşünme kapalı
- Planlama ve doğrulama: V4 Pro/Flash, düşünme açık
- Eski `deepseek-chat` seçimi: V4 Pro + düşünme kapalıya normalize edilir
- Eski `deepseek-reasoner` seçimi: V4 Pro + düşünme açığa normalize edilir
- Sağlayıcı çıktı üst sınırı: 384K token

Detaylı geçiş sözleşmesi: `docs/MIGRATION_DEEPSEEK_V4.md`

## Otomatik doğrulama

Godot 4.6.3 kalite koşucusu:

```bash
godot --headless --path . --script res://tools/ci_contract_runner.gd
```

Kalite kapıları:

- exact Godot 4.6.3 sürüm doğrulaması
- plugin import/parse/compile
- contract ve release-readiness testleri
- runtime hygiene
- secret leakage taraması
- editör mutasyon mimari invariant'ları
- Android repo readiness audit'i

## Release durumu

Makine tarafından okunan kaynak:

- `release/readiness_manifest.json`

İnsan tarafından okunabilir release raporu:

- `docs/RELEASE_READINESS.md`

Açık gerçek kullanım kapıları:

1. Masaüstü editör Undo/Redo: `tools/editor_smoke/README.md`
2. DeepSeek V4 canlı çağrı: `tools/DEEPSEEK_V4_LIVE_TEST.md`
3. Android Godot editörü: `tools/ANDROID_EDITOR_SMOKE.md`
4. Final konsolidasyon: `tools/FINAL_RELEASE_SMOKE.md`

Bu kapılar tamamlanmadan manifestte `merge_ready=false` kalmalıdır.

## Birleşme modeli

Faz 2–8 dalları kümülatif stacked PR'lardır. Ara PR'ları tek tek varsayılan dala birleştirmek yerine, manuel kapılar tamamlandıktan sonra Faz 8 konsolidasyon PR'ı varsayılan dala retarget edilip tek squash release PR'ı olarak incelenmelidir.

Otomatik merge uygulanmaz. Son birleşme kararı kullanıcıya aittir.

## Lisans ve dağıtım

Bu repoda açık bir lisans dosyası bulunmuyorsa yeniden dağıtım veya üçüncü taraf kullanımı için otomatik lisans varsayımı yapılmamalıdır.
