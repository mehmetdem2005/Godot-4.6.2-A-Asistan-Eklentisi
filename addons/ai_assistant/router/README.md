# Layer 7 — Multi-Provider Router (Çoklu Sağlayıcı Yönlendirme)

Sistemin gerçek LLM sağlayıcılarına bağlandığı katman. Devin-benzeri
bir kod üreten sistem için bu kritik — yapay zekâ buradan gelir.

## Dosyalar

- provider_response.gd — LLM yanıtının ortak taşıyıcısı (her
  sağlayıcının ham formatı buraya çevrilir).
- provider_adapter_base.gd — Adapter temel sınıfı.
- deepseek_adapter.gd — DeepSeek (OpenAI-uyumlu API).
- openai_adapter.gd — OpenAI Chat Completions.
- anthropic_adapter.gd — Anthropic Messages (system ayrı, x-api-key).
- gemini_adapter.gd — Google Gemini (contents/parts, anahtar URL'de).
- http_transport.gd — Gerçek HTTP katmanı (Node — HTTPRequest sarmalar).
- prompt_cache.gd — İstem önbelleği (LRU, disk kalıcı, para tasarrufu).
- mode_controller.gd — Eco/Balanced/Quality + Single/Professional mod.
- fallback_chain.gd — Sağlayıcı çökerse sıradakine geçiş zinciri.
- provider_router.gd — Layer 7 ana motoru, hepsini birleştirir.
- _router_test.gd — 23 sıkı test.

## İstek akışı

1. Cache'e bak — varsa cache yanıtı dön (maliyet 0)
2. Mode'a göre sağlayıcı + parametre belirle
3. Adapter ile sağlayıcı-özel istek hazırla
4. HTTPTransport ile gönder
5. Yanıtı adapter ile çöz
6. Geçici hata + fallback gerekiyorsa sıradaki sağlayıcı
7. Başarılı yanıtı cache'e yaz

## Modlar

- ECO/BALANCED/QUALITY — kalite-maliyet dengesi (token, sıcaklık)
- SINGLE/PROFESSIONAL — SINGLE sadece DeepSeek (bütçe dostu),
  PROFESSIONAL tüm sağlayıcılar açık

## ÖNEMLİ — gerçek ağ ve API anahtarı

- HTTPTransport bir Node — sahne ağacına eklenmesi gerekir.
- Router API anahtarını SAKLAMAZ — dışarıdan set_api_key ile alır.
  Anahtar yönetimi ayrı bir güvenlik katmanının işi.
- Anahtar yoksa: router AÇIK HATA döner — sahte başarı YOK.
- HTTPTransport.live_mode=false iken dry-run: istek hazırlanır ama
  gönderilmez. Gerçek çağrı için live_mode=true + geçerli anahtar.

## Fallback politikası

- Ağ hatası, 5xx, 429 -> fallback (geçici sorun, sıradakini dene)
- 401, 400, 403 -> fallback YOK (yapılandırma sorunu — sağlayıcı
  değiştirmek çözmez)

## Kalite

gdlint.py R01-R13 + stress test (router logic 33/33).
HTTPTransport'un gerçek ağ davranışı sahnede, API anahtarıyla test edilir.
