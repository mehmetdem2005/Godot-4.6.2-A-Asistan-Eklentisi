@tool
class_name AIDeepSeekModelPolicy
extends RefCounted

## DeepSeek V4 model policy.
##
## DeepSeek V4'te model kimliği, düşünme modu ve çıktı bütçesi ayrı
## parametrelerdir. Bu sınıf eski UI/ayar değerlerini geriye uyumlu
## biçimde tanır; canlı üretim router'ı ise PRO_MAX profilini uygular.
##
## ProviderRequest bu sınıfı cache kimliği için kullandığından burada
## AIProviderRequest sınıfına geri referans verilmez; enum değerleriyle
## aynı kararlı amaç sabitleri tutulur ve parse bağımlılık döngüsü önlenir.

const MODEL_PRO: String = "deepseek-v4-pro"
const MODEL_FLASH: String = "deepseek-v4-flash"
const LEGACY_CHAT: String = "deepseek-chat"
const LEGACY_REASONER: String = "deepseek-reasoner"

const DEFAULT_MODEL: String = MODEL_PRO
const PRODUCTION_MODEL: String = MODEL_PRO
const MAX_CONTEXT_TOKENS: int = 1000000
const MAX_OUTPUT_TOKENS: int = 384000
const CONTEXT_SAFETY_TOKENS: int = 8192

const PURPOSE_REASONING: int = 0
const PURPOSE_CODE: int = 1
const PURPOSE_VALIDATION: int = 2
const PURPOSE_EMBEDDING: int = 3
const PURPOSE_SUMMARY: int = 4

const CANONICAL_MODELS: Array = [MODEL_PRO, MODEL_FLASH]
const LEGACY_MODELS: Array = [LEGACY_CHAT, LEGACY_REASONER]


## Boş/bilinmeyen/legacy model kimliğini güvenli V4 kimliğine çevirir.
## Legacy seçimler kalite kaybı yaratmasın diye V4 Pro'ya taşınır.
static func canonical_model(requested_model: String) -> String:
	var model_id: String = requested_model.strip_edges()
	if CANONICAL_MODELS.has(model_id):
		return model_id
	if LEGACY_MODELS.has(model_id):
		return MODEL_PRO
	return DEFAULT_MODEL


## Canlı üretim profilinin ağda kullanacağı tek model.
## Kullanıcının eski ayarları veya Flash seçimi bu profili düşüremez.
static func production_model(_requested_model: String = "") -> String:
	return PRODUCTION_MODEL


## Legacy değer yalnız yerel geriye uyumluluk girdisi mi?
static func is_legacy(requested_model: String) -> bool:
	return LEGACY_MODELS.has(requested_model.strip_edges())


## Düşünme modu politikası.
## - V4 Pro her amaçta düşünmeli çalışır (PRO_MAX üretim profili).
## - Eski chat ve doğrudan Flash CODE/SUMMARY davranışı, yalnız geriye
##   uyumlu düşük seviye adapter çağrıları için korunur.
static func thinking_enabled(requested_model: String, purpose: int) -> bool:
	var model_id: String = requested_model.strip_edges()
	if model_id == MODEL_PRO or model_id.is_empty():
		return true
	if model_id == LEGACY_CHAT:
		return false
	if model_id == LEGACY_REASONER:
		return true
	return purpose in [PURPOSE_REASONING, PURPOSE_VALIDATION]


## PRO_MAX profilinde bütün düşünmeli çağrılar maksimum efor kullanır.
static func reasoning_effort(_purpose: int) -> String:
	return "max"


## 1M toplam bağlamı aşmadan kullanılabilecek en yüksek çıktı bütçesi.
## Normal isteklerde 384K döner; çok büyük girdilerde yalnız bağlamın
## kalan kısmına iner. Sıfır, isteğin güvenli biçimde reddedilmesi demektir.
static func max_output_for_context(estimated_input_tokens: int) -> int:
	var input_tokens: int = maxi(0, estimated_input_tokens)
	var available: int = (
		MAX_CONTEXT_TOKENS - CONTEXT_SAFETY_TOKENS - input_tokens
	)
	return clampi(available, 0, MAX_OUTPUT_TOKENS)


## Cache anahtarında model/düşünme/efor ayrımını kararlı biçimde taşır.
static func cache_discriminator(requested_model: String, purpose: int) -> String:
	var thinking: bool = thinking_enabled(requested_model, purpose)
	return "%s|thinking:%s|effort:%s" % [
		canonical_model(requested_model),
		("enabled" if thinking else "disabled"),
		(reasoning_effort(purpose) if thinking else "none"),
	]
