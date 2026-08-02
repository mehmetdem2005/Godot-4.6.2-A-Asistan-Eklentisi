# DeepSeek V4 geçiş rehberi

## Kapsam

AI Asistan'ın eski `deepseek-chat` / `deepseek-reasoner` seçimlerinden DeepSeek V4 model ailesine geçiş sözleşmesi.

## Yeni model politikası

| Yerel seçim | Ağ isteğindeki model | Düşünme modu | Kullanım |
|---|---|---|---|
| `deepseek-v4-pro` | `deepseek-v4-pro` | amaca göre | varsayılan kalite modeli |
| `deepseek-v4-flash` | `deepseek-v4-flash` | amaca göre | hızlı/düşük maliyetli model |
| `deepseek-chat` | `deepseek-v4-pro` | kapalı | legacy geriye uyumluluk |
| `deepseek-reasoner` | `deepseek-v4-pro` | açık | legacy geriye uyumluluk |

Legacy kimlikler yalnız yerel ayar veya eski çağrı girdisi olarak kabul edilir. HTTP istek gövdesine eski model adı çıkmaz.

## Amaç tabanlı düşünme

- `CODE`: düşünme kapalı
- `SUMMARY`: düşünme kapalı
- `REASONING`: düşünme açık, `reasoning_effort=max`
- `VALIDATION`: düşünme açık, `reasoning_effort=max`
- `EMBEDDING`: mevcut chat adapter akışının dışında değerlendirilmelidir

Düşünme açıkken etkisiz `temperature` alanı gönderilmez. Düşünme kapalıyken istek sıcaklığı korunur.

## Çıktı token sınırı

- Ortak request varsayılanı yapay küçük bir tavana zorlanmaz.
- DeepSeek V4 adapter üst sınırı `384000` token olarak uygular.
- Tavan altındaki değerler aynen korunur.
- Çok uzun kod çıktılarında mevcut sınırlı continuation/parça birleştirme hattı korunur.

## Cache değişikliği

Cache kimliği artık şunları ayırır:

- sağlayıcı
- kanonik V4 model kimliği
- purpose
- düşünme açık/kapalı
- system prompt
- mesajlar
- temperature

Sonuç: Aynı mesajın kod üretimi ve reasoning çağrısı birbirinin cache sonucunu kullanamaz. Geçişten önceki cache kayıtlarının ıska olması beklenen ve güvenli davranıştır.

## Yanıt metadata'sı

Canlı sonuç sözleşmesi şu alanları taşır:

- `provider`
- `provider_name`
- `model`
- `input_tokens`
- `output_tokens`
- `total_tokens`
- `finish_reason`
- `http_status`
- `latency_ms`
- `from_cache`
- `request_ref`

API anahtarı, Authorization başlığı ve ham hassas istek/yanıt gövdesi bu sözleşmeye dahil edilmez.

## Kod uyumluluğu

Eski kod şu şekilde çalışmaya devam eder:

```gdscript
request.model = "deepseek-chat"
```

Adapter bunu ağ isteğinden önce V4 Pro + düşünme kapalıya dönüştürür. Yeni kodun doğrudan kanonik sabitleri kullanması tercih edilir:

```gdscript
request.model = AIDeepSeekModelPolicy.MODEL_PRO
```

## Canlı doğrulama

Güvenli ortam değişkeniyle:

```bash
DEEPSEEK_KEY='<KEY>' godot --headless --path . \
  --script res://tools/deepseek_v4_live_runner.gd
```

Başarılı ölçüt:

```text
V4_LIVE_OK
```

Runner model kimliği, HTTP durumu, token kullanımı, finish reason, gecikme, request kimliği ve secret redaksiyonunu birlikte doğrular. Yalnız HTTP 200 alınması başarı kabul edilmez.

## Geri dönüş

V4 geçişi tek başına geri alınmamalıdır; router, cache ve metadata sözleşmeleri birlikte değişmiştir. Release rollback gerekiyorsa `docs/RELEASE_READINESS.md` içindeki konsolidasyon rollback prosedürü kullanılmalıdır.
