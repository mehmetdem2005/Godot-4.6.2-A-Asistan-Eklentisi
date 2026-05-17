@tool
class_name AIAudioGenProviderBase
extends RefCounted

## AIAudioGenProviderBase — AI ses üretim arayüzü (Madde 08).
##
## Phase 2+'da metin tarifinden ses üretimi: "ağır demir kapı gıcırtısı"
## yaz, AI ses üretsin. ElevenLabs SFX, Stable Audio gibi servisler
## bunu yapar.
##
## Phase 1'de gerçek AI ses üretimi YOK — bu arayüz + stub'lar
## gelecekteki entegrasyonun takılacağı yeri tanımlar. procedural_synth
## zaten Phase 1 için LLM'siz ses üretiyor; AI üretim onun üstüne
## gelecek bir genişleme.
##
## "Mock yasak": stub'lar sahte ses üretmez — dürüstçe NOT_AVAILABLE
## der ve procedural_synth'e yönlendirir.
##
## Mock policy: stub her zaman kullanılamaz; gerçek üretim Phase 2+.

## AI üretim sonucu durumu.
enum GenStatus { GENERATED, NOT_AVAILABLE, INVALID_PROMPT, QUOTA_EXCEEDED }

const STATUS_NAMES: Dictionary = {
	GenStatus.GENERATED: "generated",
	GenStatus.NOT_AVAILABLE: "not_available",
	GenStatus.INVALID_PROMPT: "invalid_prompt",
	GenStatus.QUOTA_EXCEEDED: "quota_exceeded",
}


## Bir AI ses üretim sonucu.
class GenResult extends RefCounted:
	var status: int = AIAudioGenProviderBase.GenStatus.NOT_AVAILABLE
	var provider: String = ""
	var prompt: String = ""
	var fallback_suggestion: String = ""  ## Üretilemezse alternatif
	var reason: String = ""

	func is_generated() -> bool:
		return status == AIAudioGenProviderBase.GenStatus.GENERATED

	func status_name() -> String:
		return AIAudioGenProviderBase.STATUS_NAMES.get(status, "?")

	func to_dict() -> Dictionary:
		return {
			"status": status_name(),
			"provider": provider,
			"fallback": fallback_suggestion,
		}


# ============================================================
# ARAYÜZ SÖZLEŞMESİ — alt sınıflar uygular
# ============================================================

## Sağlayıcı adı. Alt sınıf override eder.
func provider_name() -> String:
	return "base"


## AI ses üretimi kullanılabilir mi? Phase 1 — hayır.
func is_available() -> bool:
	return false


## Bir metin tarifinden ses üretir.
## prompt: ses tarifi (örn. "ağır kapı gıcırtısı").
## Alt sınıf override eder.
func generate(_prompt: String) -> GenResult:
	return _not_available_result(_prompt)


# ============================================================
# ORTAK YARDIMCILAR
# ============================================================

## "Kullanılamaz" sonucu — procedural_synth'e yönlendirir.
## Phase 1'de AI yok ama procedural_synth ses üretebilir.
func _not_available_result(prompt: String) -> GenResult:
	var result := GenResult.new()
	result.status = GenStatus.NOT_AVAILABLE
	result.provider = provider_name()
	result.prompt = prompt
	result.fallback_suggestion = "procedural_synth + sfxr_presets kullan"
	result.reason = "AI ses üretimi Phase 2+ — şu an kullanılamıyor"
	return result


## Geçersiz tarif sonucu.
func _invalid_prompt_result(prompt: String) -> GenResult:
	var result := GenResult.new()
	result.status = GenStatus.INVALID_PROMPT
	result.provider = provider_name()
	result.prompt = prompt
	result.reason = "Ses tarifi boş veya geçersiz"
	return result


## Bir tarif geçerli mi (boş değil, makul uzunlukta)?
func is_valid_prompt(prompt: String) -> bool:
	var trimmed: String = prompt.strip_edges()
	return not trimmed.is_empty() and trimmed.length() <= 500
