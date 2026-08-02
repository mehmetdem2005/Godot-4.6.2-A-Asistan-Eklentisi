# Godot Android editör — Faz 7 smoke kapısı

Bu kontrol gerçek Android cihazda Godot `4.6.3.stable` editörüyle yapılır. Otomatik contract testleri responsive kararları doğrular; bu smoke ise klavye, dokunmatik ve editör ana-ekran entegrasyonunu gözle kanıtlar.

## Ön koşullar

- Repo Faz 7 dalında olmalı: `agent/phase-07-android-mobile-hardening`
- Godot Android editörü: `4.6.3.stable`
- Eklentiler etkin:
  - `res://addons/ai_assistant/plugin.cfg`
  - `res://addons/ai_contract_tests/plugin.cfg`
- Gerçek API anahtarı smoke için zorunlu değildir. Anahtar proje dosyasına yazılmamalıdır.

## 1. Açılış ve tam ekran

1. Projeyi aç.
2. Üst ana ekranlardan **AI Asistan** görünümüne geç.
3. Panelin sol dock içine sıkışmadığını ve kullanılabilir alanı doldurduğunu doğrula.
4. Menü düğmesinin tek dokunuşla açıldığını doğrula.

Beklenen:

```text
ANDROID_SMOKE_1_OK
```

## 2. 360–480 sınıfı portre

Cihazı portre konumunda tut:

1. **≡ Menü → Ayarlar** aç.
2. API anahtarı alanı ve **Anahtarı Kaydet** düğmesinin alt alta olduğunu doğrula.
3. Yatay taşma veya ekran dışına çıkan düğme olmamalı.
4. Model seçici ve sıfırlama düğmesine tek dokunuşla ulaşılmalı.
5. Ayarlar ekranı dikey kaydırılabilmeli.

Beklenen:

```text
ANDROID_SMOKE_2_OK
```

## 3. Klavye güvenliği

1. Sohbet ekranına dön.
2. Metin alanına dokunup Android klavyesini aç.
3. Metin alanı ve **Gönder** düğmesi erişilebilir kalmalı.
4. Sohbet kaydı tamamen kaybolmamalı; ekran dikey kaydırılabilmeli.
5. Klavyeyi kapatınca düzen eski yüksekliğine dönmeli.

Beklenen:

```text
ANDROID_SMOKE_3_OK
```

## 4. Yön değişimi

1. Portreden landscape yönüne dön.
2. Giriş alanının daha kısa profile geçtiğini doğrula.
3. Menü ve Gönder düğmelerinin dokunmatik yüksekliği küçülmemeli.
4. Tekrar portreye dön; ayarlar yeniden tek kolona geçmeli.

Beklenen:

```text
ANDROID_SMOKE_4_OK
```

## 5. Workspace sekmeleri

1. **≡ Menü → Çalışma Alanı** aç.
2. Dokuz sekmenin dar ekranda yatay kaydırılabildiğini doğrula.
3. Sekme çubuğunun parmakla rahat seçilebilir yükseklikte olduğunu doğrula.
4. Kanban, Canlı Akış ve Iteration içeriklerinde metin ekran dışına taşmamalı.

Beklenen:

```text
ANDROID_SMOKE_5_OK
```

## 6. Güvenlik

1. API anahtarını Ayarlar ekranına girip kaydet.
2. Alanın temizlendiğini doğrula.
3. Godot Output/Debugger içinde anahtarın düz metin görünmediğini doğrula.
4. `project.godot` ve `export_presets.cfg` içinde anahtar bulunmamalı.

Beklenen:

```text
ANDROID_SMOKE_6_OK
```

## Faz 7 geçiş ölçütü

Altı sonuç birlikte alınmalıdır:

```text
ANDROID_SMOKE_OK: 6/6
```

Ekran görüntüsü veya cihaz kayıt notu PR #26'ya eklenmeden Faz 7 taslaktan çıkarılmamalıdır.
