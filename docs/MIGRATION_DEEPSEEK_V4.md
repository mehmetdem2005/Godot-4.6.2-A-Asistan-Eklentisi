# DeepSeek V4 Pro Max geçiş rehberi

## Üretim profili

AI Asistan'ın canlı DeepSeek trafiği tek bir üretim profiline sabitlenmiştir:

| Alan | Üretim değeri |
|---|---|
| Model | `deepseek-v4-pro` |
| Bağlam penceresi | `1.000.000` token |
| Maksimum çıktı | `384.000` token |
| Düşünme | `thinking.type=enabled` |
| Akıl yürütme eforu | `reasoning_effort=max` |
| Sıcaklık | düşünmeli istekte gönderilmez |
| Taşıma zaman aşımı | 1.800 saniye |
| Yanıt gövdesi sınırı | 64 MiB |
| Ağ | yalnız HTTPS, gzip ve threaded HTTP |

Bu profil `AIProviderRouter` içinde ağ isteği hazırlanırken zorlanır. UI, eski ayar dosyası veya doğrudan çağrı `deepseek-chat`, `deepseek-reasoner` ya da `deepseek-v4-flash` gönderse bile canlı DeepSeek isteği `deepseek-v4-pro` olarak hazırlanır. Böylece eski kayıtlar üretim kalitesini düşüremez.

## Bağlam ve çıktı bütçesi

Normal girdide istek:

```json
{
  "model": "deepseek-v4-pro",
  "max_tokens": 384000,
  "thinking": {"type": "enabled"},
  "reasoning_effort": "max"
}
```

Toplam bağlam sınırına yaklaşan girdilerde çıktı bütçesi şu kuralla azaltılır:

```text
çıktı = min(384000, 1000000 - 8192 güvenlik payı - tahmini girdi tokenı)
```

Kalan güvenli çıktı bütçesi sıfırsa router ağ çağrısı yapmaz ve açık bir bağlam bütçesi hatası döndürür. Bu koruma 1M bağlam taşmasını önler; hiçbir zaman sessiz kırpma veya sahte başarı üretmez.

## Geriye uyumluluk

Eski kod çalışmaya devam eder:

```gdscript
request.model = "deepseek-chat"
```

Ancak bu değer yalnız yerel uyumluluk alias'ıdır. Canlı ağ gövdesindeki model her zaman:

```gdscript
AIDeepSeekModelPolicy.MODEL_PRO
```

olur. Yeni kod doğrudan kanonik sabiti kullanmalıdır.

## Cache kimliği

Cache anahtarı şunları ayırır:

- sağlayıcı
- kanonik model
- purpose
- düşünme modu
- reasoning effort
- system prompt
- mesajlar
- sıcaklık

Böylece farklı görev/politika çağrıları birbirinin sonucunu kullanamaz. Geçiş öncesindeki cache kayıtlarının ıska olması beklenen ve güvenli davranıştır.

## Taşıma sertleştirmesi

`AIHTTPTransport` uzun V4 Pro üretimleri için:

- 30 dakika zaman aşımı,
- 64 MiB güvenli yanıt gövdesi limiti,
- 256 KiB indirme parçaları,
- gzip kabulü,
- threaded HTTP,
- yalnız HTTPS,
- dry-run Authorization redaksiyonu

uygular. API anahtarı sonuç sözlüğüne, loga veya dry-run tanısına yazılmaz.

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

API anahtarı, Authorization başlığı ve ham hassas istek gövdesi bu sözleşmenin parçası değildir.

## Otomatik kanıt

`AIDeepSeekProMaxTest` şu 10 sözleşmeyi doğrular:

1. boş model seçiminin V4 Pro'ya zorlanması,
2. legacy/Flash değerlerinin üretim profilini düşürememesi,
3. bütün üretim amaçlarında thinking açık olması,
4. reasoning effort değerinin `max` olması,
5. normal girdide `max_tokens=384000`,
6. 1M bağlama yaklaşınca güvenli çıktı azaltımı,
7. tükenmiş bağlamın ağdan önce reddedilmesi,
8. thinking gövdesinde temperature bulunmaması,
9. uzun üretime uygun HTTP taşıma profili,
10. HTTPS zorlaması ve Authorization redaksiyonu.

Final otomatik paket: **906/906**.

## Canlı doğrulama

Güvenli yerel çalıştırma:

```bash
DEEPSEEK_API_KEY='<KEY>' godot --headless --path . \
  --script res://tools/deepseek_v4_live_runner.gd
```

GitHub Actions üzerinden çalıştırmak için repository secret adı:

```text
DEEPSEEK_API_KEY
```

Workflow:

```text
DeepSeek V4 Pro Max Live Gate
```

Başarı için iki işaret birlikte gerekir:

```text
V4_MAX_PROFILE_OK
V4_LIVE_OK
```

Yalnız HTTP 200 başarı sayılmaz. Runner hazırlanmış ağ gövdesini, gerçek model kimliğini, usage, finish reason, gecikme, request kimliği, cache durumunu ve secret redaksiyonunu birlikte doğrular.

## Geri dönüş

V4 Pro Max geçişi tek dosya olarak geri alınmamalıdır; model politikası, router, taşıma, cache ve metadata sözleşmeleri birlikte değişmiştir. Release rollback gerekiyorsa `docs/RELEASE_READINESS.md` içindeki tek squash revert prosedürü kullanılmalıdır.
