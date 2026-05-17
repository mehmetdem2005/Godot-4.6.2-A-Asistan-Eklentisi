@tool
class_name AIAudioStableAudioProvider
extends AIAudioGenProviderBase

## StableAudioProvider — Stable Audio stub (Madde 08 / ai_stubs).
##
## Stable Audio metin tarifinden müzik/ortam sesi üretir ("sakin
## orman ambiyansı", "epik savaş müziği"). Phase 2+ için stub —
## gerçek entegrasyon Stability AI API'si + ağ ister.
##
## Phase 1'de bu stub dürüstçe "kullanılamıyor" der. Müzik için
## Phase 1 yaklaşımı: music_layering ile hazır stem'leri katmanla.
## AI müzik üretimi onun üstüne gelecek bir genişleme.
##
## "Mock yasak": sahte müzik üretmez — NOT_AVAILABLE + fallback.


## Phase 2+'da gerçek API bağlantısı kurulunca true olur.
var _api_connected: bool = false


func provider_name() -> String:
	return "stable_audio"


func is_available() -> bool:
	# Phase 1 — Stable Audio API entegrasyonu yok
	return _api_connected


func generate(prompt: String) -> GenResult:
	if not is_valid_prompt(prompt):
		return _invalid_prompt_result(prompt)
	# Phase 1 — gerçek üretim yok
	if not _api_connected:
		var result: GenResult = _not_available_result(prompt)
		# Müzik için özel fallback önerisi
		result.fallback_suggestion = "music_layering + hazır stem'ler"
		return result
	# Phase 2+ — gerçek Stable Audio çağrısı buraya
	return _not_available_result(prompt)


## Phase 2+ — Stability AI API anahtarı ile bağlanma.
func attempt_connect(_api_key: String) -> bool:
	# Phase 1 — entegrasyon yok
	return false
