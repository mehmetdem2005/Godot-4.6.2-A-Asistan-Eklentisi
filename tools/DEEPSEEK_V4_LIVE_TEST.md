# DeepSeek V4 canlı doğrulama

Bu test, DeepSeek V4 Pro bağlantısını uygulamanın canlı Router → HTTPTransport → Adapter → AgentLiveBridge hattında doğrular.

## Ön koşullar

- Godot `4.6.3.stable`
- Geçerli DeepSeek API anahtarı
- İnternet bağlantısı
- Proje kök dizininde terminal

Anahtar repoya, `.env` dosyasına veya komut çıktısına yazılmamalıdır.

## Linux / macOS

```bash
DEEPSEEK_KEY='anahtar-buraya' godot --headless --path . \
  --script res://tools/deepseek_v4_live_runner.gd
```

`DEEPSEEK_API_KEY` ortam değişkeni de desteklenir.

## PowerShell

```powershell
$env:DEEPSEEK_KEY = "anahtar-buraya"
godot --headless --path . --script res://tools/deepseek_v4_live_runner.gd
Remove-Item Env:DEEPSEEK_KEY
```

## Başarılı sonuç

Çıkış kodu `0` ve son satır:

```text
V4_LIVE_OK
```

Runner şu kanıtları birlikte ister:

- sağlayıcı `deepseek`
- model `deepseek-v4-pro`
- HTTP `2xx`
- gerçek LLM çağrısı
- boş olmayan içerik
- pozitif input/output token kullanımı
- tutarlı toplam token
- boş olmayan `finish_reason`
- pozitif gecikme
- request kimliği
- cache dışı ilk canlı yanıt
- sonuç sözlüğünde API anahtarı bulunmaması

## Hata kodları

- `1`: sağlayıcı yanıtı veya metadata doğrulaması başarısız
- `2`: API anahtarı ortam değişkeninde yok
- `3`: canlı istek başlatılamadı
- `4`: 120 saniye zaman aşımı

## Android notu

Godot Android editörü içinden ortam değişkeni geçirmek güvenilir değildir. Android smoke testi için anahtarı proje dosyasına yazmayın. Canlı sağlayıcı doğrulamasını güvenli bir masaüstü/CI terminalinde çalıştırın; Android editörde ise UI, ağ izinleri ve gerçek görev akışını ayrı manuel smoke kapısı olarak doğrulayın.
