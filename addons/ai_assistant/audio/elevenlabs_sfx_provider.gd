@tool
class_name AIAudioElevenLabsProvider
extends AIAudioGenProviderBase

## ElevenLabsSfxProvider — ElevenLabs SFX stub (Madde 08 / ai_stubs).
##
## ElevenLabs metin tarifinden ses efekti üretir ("cam kırılması",
## "ejderha kükremesi"). Phase 2+ için stub — gerçek entegrasyon
## ElevenLabs API anahtarı + ağ ister.
##
## Phase 1'de bu stub dürüstçe "kullanılamıyor" der ve oyuncuyu
## procedural_synth'e yönlendirir. Sandbox'ta ağ yok — stub doğru
## davranıştır.
##
## "Mock yasak": sahte ses üretmez — NOT_AVAILABLE + fallback.


## Phase 2+'da gerçek API bağlantısı kurulunca true olur.
var _api_connected: bool = false


func provider_name() -> String:
	return "elevenlabs_sfx"


func is_available() -> bool:
	# Phase 1 — ElevenLabs API entegrasyonu yok
	return _api_connected


func generate(prompt: String) -> GenResult:
	# Tarif geçerli mi (ileride gerçek üretimde de gerekli)
	if not is_valid_prompt(prompt):
		return _invalid_prompt_result(prompt)
	# Phase 1 — gerçek üretim yok
	if not _api_connected:
		return _not_available_result(prompt)
	# Phase 2+ — gerçek ElevenLabs çağrısı buraya
	return _not_available_result(prompt)


## Phase 2+ — ElevenLabs API anahtarı ile bağlanma.
func attempt_connect(_api_key: String) -> bool:
	# Phase 1 — entegrasyon yok
	return false
