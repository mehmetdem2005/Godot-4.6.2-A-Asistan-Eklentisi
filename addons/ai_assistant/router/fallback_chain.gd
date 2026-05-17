@tool
class_name AIFallbackChain
extends RefCounted

## FallbackChain — yedekleme zinciri (Layer 7).
##
## Bir sağlayıcı çökebilir: 500 hatası, zaman aşımı, hız limiti.
## Sistem o anda durmamalı — sıradaki sağlayıcıya geçmeli.
##
## Bu sınıf bir sağlayıcı sırası tutar ve "hangi sağlayıcı denenmeli,
## sonra hangisi" sorusunu yönetir. Router her sağlayıcı başarısız
## olduğunda next() ile sıradakini alır.
##
## Hangi hataların fallback tetiklediği önemli:
##   - Ağ hatası, zaman aşımı, 5xx, 429  -> FALLBACK (geçici sorun)
##   - 401 (kötü anahtar), 400 (kötü istek) -> FALLBACK ETME
##     (sağlayıcı değiştirmek bu hatayı çözmez — yapılandırma sorunu)
##
## Mock policy: zincir gerçek sağlayıcı denemelerini yönetir.

## Fallback tetikleyen HTTP durum kodları.
const FALLBACK_HTTP_CODES: Array = [429, 500, 502, 503, 504]


## Sağlayıcı sırası — AIProviderRequest.Provider enum değerleri.
## İlk eleman birincil, sonrakiler yedek.
var _chain: Array = []

## Şu anki deneme indeksi.
var _current_index: int = 0

## Denenmiş sağlayıcılar — tekrar denenmez.
var _attempted: Array = []


## Zinciri kurar — provider listesi sırayla denenir.
func configure(provider_order: Array) -> void:
	_chain = provider_order.duplicate()
	reset()


## Zinciri başa sarar — yeni bir istek için.
func reset() -> void:
	_current_index = 0
	_attempted.clear()


## Zincirdeki sağlayıcı sayısı.
func size() -> int:
	return _chain.size()


# ============================================================
# ZİNCİR YÜRÜTME
# ============================================================

## Şu an denenecek sağlayıcıyı döndürür.
## Zincir tükendiyse -1.
func current() -> int:
	if _current_index < 0 or _current_index >= _chain.size():
		return -1
	return _chain[_current_index]


## Sıradaki sağlayıcıya geçer ve onu döndürür.
## Zincir tükendiyse -1 (artık denenecek sağlayıcı yok).
func advance() -> int:
	# Mevcut sağlayıcıyı denenmiş işaretle
	var cur: int = current()
	if cur >= 0 and not _attempted.has(cur):
		_attempted.append(cur)
	_current_index += 1
	return current()


## Daha denenecek sağlayıcı var mı?
func has_next() -> bool:
	return _current_index + 1 < _chain.size()


## Bir yanıtın fallback gerektirip gerektirmediğine karar verir.
## response: AIProviderResponse.
## Dönen: true ise sıradaki sağlayıcı denenmeli.
##
## Mantık: geçici/sunucu-taraflı hatalar fallback tetikler;
## yapılandırma hataları (kötü anahtar, kötü istek) tetiklemez —
## çünkü sağlayıcı değiştirmek o sorunu çözmez.
static func should_fallback(response: AIProviderResponse) -> bool:
	if response == null:
		return true  # yanıt yok — kesin sorun, dene
	if response.ok:
		return false  # başarılı — fallback gereksiz

	# http_status 0 = ağa hiç çıkamadı / ağ hatası -> fallback
	if response.http_status == 0:
		return true
	# 5xx ve 429 -> geçici, fallback
	if FALLBACK_HTTP_CODES.has(response.http_status):
		return true
	# 401, 403, 400, 404 -> yapılandırma sorunu, fallback ETME
	return false


# ============================================================
# DURUM
# ============================================================

## Zincirin mevcut durumu.
func status() -> Dictionary:
	return {
		"chain": _chain,
		"current_index": _current_index,
		"current_provider": current(),
		"attempted": _attempted,
		"has_next": has_next(),
		"exhausted": current() == -1,
	}
