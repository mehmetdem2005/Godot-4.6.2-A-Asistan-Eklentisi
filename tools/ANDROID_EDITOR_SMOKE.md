# Godot Android editörü — final cihaz smoke kapısı

Bu kapı gerçek Android cihazdaki Godot `4.6.3.stable` editörünü doğrular. Otomatik 12 mobil hardening ve 2 gerçek repo Android audit testi responsive kararları, HTTPS endpointlerini ve secret politikasını doğrular; bu prosedür ise gerçek dokunmatik, yazılım klavyesi ve yön değişimini kanıtlar.

Emülatör veya masaüstü headless koşusu bu kapının yerine geçmez.

## Ön koşullar

- Dal: `agent/phase-08-release-consolidation`
- Test edilen commit SHA kaydedilmeli
- Resmî Godot Android editörü: `4.6.3.stable`
- Eklentiler etkin:
  - `res://addons/ai_assistant/plugin.cfg`
  - `res://addons/ai_contract_tests/plugin.cfg`
- Gerçek DeepSeek anahtarı zorunlu değildir
- Anahtar `project.godot`, `export_presets.cfg`, ekran kaydı veya Output loguna yazılmamalıdır

## Kanıt başlığı

Test notunun başına şunları yazın:

```text
ANDROID_DEVICE_MODEL=<cihaz modeli>
ANDROID_VERSION=<Android sürümü>
GODOT_VERSION=4.6.3.stable
TEST_COMMIT=<tam commit SHA>
ORIENTATION_START=portrait
```

Ekran kaydı veya altı adımın ekran görüntüleri PR #28'e eklenmelidir. API anahtarı görünen kareler kanıt olarak yüklenmemelidir.

## 1. Açılış ve tam ekran

1. Projeyi açın.
2. Üst ana ekranlardan **AI Asistan** görünümüne geçin.
3. Panelin sol dock içine sıkışmadığını ve kullanılabilir alanı doldurduğunu doğrulayın.
4. Menü düğmesinin tek dokunuşla açıldığını doğrulayın.
5. Eklenti etkinleşirken parse/compile hatası oluşmadığını Output ekranında doğrulayın.

Kanıt satırı:

```text
ANDROID_SMOKE_1_OK full_screen_and_plugin_load
```

## 2. 360–480 sınıfı portre

1. Cihazı portre konumunda tutun.
2. **≡ Menü → Ayarlar** ekranını açın.
3. API anahtarı alanı ve **Anahtarı Kaydet** düğmesinin alt alta olduğunu doğrulayın.
4. Yatay taşma veya ekran dışına çıkan kontrol olmamalı.
5. Model alanı, sıfırlama düğmesi ve ayarlar içeriği tek dokunuşla erişilebilir olmalı.
6. Ayarlar ekranı dikey kaydırılabilmeli.

Kanıt satırı:

```text
ANDROID_SMOKE_2_OK portrait_360_480
```

## 3. Yazılım klavyesi

1. Sohbet ekranına dönün.
2. Metin alanına dokunup Android klavyesini açın.
3. En az 100 karakterlik Türkçe bir test metni girin.
4. Metin alanı ve **Gönder** düğmesi erişilebilir kalmalı.
5. Sohbet alanı tamamen kaybolmamalı; gerektiğinde dikey kaydırılabilmeli.
6. Klavyeyi kapatınca düzen önceki yüksekliğine dönmeli.

Kanıt satırı:

```text
ANDROID_SMOKE_3_OK software_keyboard
```

## 4. Yön değişimi

1. Portreden landscape yönüne dönün.
2. Giriş alanının daha kısa profile geçtiğini doğrulayın.
3. Menü ve Gönder düğmelerinin dokunmatik yüksekliği küçülmemeli.
4. Workspace veya ayarlar içeriği ekran dışına taşmamalı.
5. Tekrar portreye dönün; ayarlar yeniden tek kolona geçmeli.
6. Yön değişiminden sonra eklenti kapanmamalı veya state kaybetmemeli.

Kanıt satırı:

```text
ANDROID_SMOKE_4_OK orientation_round_trip
```

## 5. Workspace sekmeleri

1. **≡ Menü → Çalışma Alanı** ekranını açın.
2. Dokuz sekmenin dar ekranda yatay kaydırılabildiğini doğrulayın.
3. Sekme çubuğu parmakla rahat seçilebilir yükseklikte olmalı.
4. Kanban, Canlı Akış ve Iteration içeriklerinde metin ekran dışına taşmamalı.
5. En soldan en sağdaki sekmeye ve tekrar geri geçin.

Kanıt satırı:

```text
ANDROID_SMOKE_5_OK workspace_nine_tabs
```

## 6. Secret ve kalıcılık güvenliği

1. Geçici bir test anahtarı kullanılıyorsa Ayarlar ekranına girip kaydedin.
2. Kaydetme sonrasında giriş alanının temizlendiğini doğrulayın.
3. Godot Output/Debugger içinde anahtarın düz metin görünmediğini doğrulayın.
4. `project.godot` içinde anahtar bulunmamalı.
5. Projeyi kapatıp yeniden açın; eklenti parse hatası olmadan açılmalı.
6. Test anahtarını Ayarlar ekranından silin veya sağlayıcı tarafında iptal edin.

Gerçek anahtar kullanılmadıysa boş anahtarın reddedildiğini ve projede gömülü secret bulunmadığını kaydedin.

Kanıt satırı:

```text
ANDROID_SMOKE_6_OK secret_and_reopen
```

## Final sonuç

Altı kanıt birlikte bulunmalıdır:

```text
ANDROID_SMOKE_OK: 6/6
```

PR #28 kanıt notunda ayrıca şunlar bulunmalıdır:

```text
RESULT=PASS
TEST_COMMIT=<tam commit SHA>
NO_SECRET_IN_EVIDENCE=true
NO_PARSE_COMPILE_ERROR=true
```

Bu kanıt alınmadan `release/readiness_manifest.json` içindeki `android_editor` durumu `passed` yapılamaz ve `merge_ready` değeri `false` kalır.
