# DeepSeek V4 Pro Max canlı doğrulama

Bu kapı, uygulamanın gerçek Router → HTTPTransport → Adapter → AgentLiveBridge hattında **DeepSeek V4 Pro maksimum üretim profilini** doğrular.

## Zorunlu profil

Runner ağ çağrısından önce hazırlanmış istek gövdesinde şunları ister:

```text
model=deepseek-v4-pro
thinking.type=enabled
reasoning_effort=max
max_tokens=384000
temperature alanı yok
HTTPS endpoint
```

Ardından gerçek sağlayıcı yanıtında model, HTTP, usage, finish reason, gecikme, request kimliği, içerik ve secret redaksiyonu birlikte doğrulanır. Yalnız HTTP 200 başarı kabul edilmez.

## Ön koşullar

- Godot `4.6.3.stable`
- Geçerli DeepSeek API anahtarı
- İnternet bağlantısı
- Proje kök dizininde terminal veya GitHub repository secret

Anahtar repoya, `.env` dosyasına, issue/PR yorumuna veya komut çıktısına yazılmamalıdır.

## GitHub Actions — önerilen yol

Repository secret oluşturun:

```text
DEEPSEEK_API_KEY
```

Ardından Actions ekranından:

```text
DeepSeek V4 Pro Max Live Gate
```

workflow'unu çalıştırın. Workflow:

- resmî Godot 4.6.3 binary digest'ini doğrular,
- gerçek V4 Pro isteğini çalıştırır,
- `V4_MAX_PROFILE_OK` ve `V4_LIVE_OK` işaretlerini zorunlu tutar,
- logda secret/Authorization sızıntısını reddeder,
- yalnız sanitize edilmiş kanıt logunu artifact olarak saklar.

## Linux / macOS

```bash
DEEPSEEK_API_KEY='anahtar-buraya' godot --headless --path . \
  --script res://tools/deepseek_v4_live_runner.gd
```

`DEEPSEEK_KEY` ortam değişkeni de desteklenir.

## PowerShell

```powershell
$env:DEEPSEEK_API_KEY = "anahtar-buraya"
godot --headless --path . --script res://tools/deepseek_v4_live_runner.gd
Remove-Item Env:DEEPSEEK_API_KEY
```

## Başarılı sonuç

Çıkış kodu `0` ve şu iki işaret:

```text
V4_MAX_PROFILE_OK
V4_LIVE_OK
```

Runner şu kanıtları birlikte ister:

- sağlayıcı `deepseek`,
- model `deepseek-v4-pro`,
- hazırlanmış gövdede thinking açık,
- hazırlanmış gövdede `reasoning_effort=max`,
- hazırlanmış gövdede `max_tokens=384000`,
- HTTP `2xx`,
- gerçek LLM çağrısı,
- boş olmayan ve beklenen canlı işareti taşıyan içerik,
- pozitif input/output token kullanımı,
- tutarlı toplam token,
- boş olmayan `finish_reason`,
- pozitif gecikme,
- request kimliği,
- cache dışı ilk canlı yanıt,
- sonuç/log içinde API anahtarı bulunmaması.

## Hata kodları

- `1`: sağlayıcı yanıtı veya metadata doğrulaması başarısız,
- `2`: API anahtarı ortam değişkeninde yok,
- `3`: istek profili veya canlı istek başlatılamadı,
- `4`: 1.800 saniye zaman aşımı.

## Android notu

Godot Android editörü içinden ortam değişkeni geçirmek güvenilir değildir. Anahtarı proje dosyasına yazmayın. Canlı sağlayıcı kapısını güvenli masaüstü/CI ortamında çalıştırın; Android editörde UI, klavye, yön değişimi, ağ izni ve gerçek görev akışını ayrı cihaz smoke kapısıyla doğrulayın.
