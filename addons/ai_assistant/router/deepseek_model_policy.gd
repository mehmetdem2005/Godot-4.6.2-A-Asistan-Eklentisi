@tool
class_name AIDeepSeekModelPolicy
extends RefCounted

## DeepSeek V4 model policy.
##
## DeepSeek V4'te model kimliği ile düşünme modu birbirinden ayrıdır.
## Bu sınıf eski UI/ayar değerlerini geriye uyumlu biçimde kabul eder,
## fakat legacy kimliklerin ağ isteğine çıkmasını engeller.
##
## ProviderRequest bu sınıfı cache kimliği için kullandığından burada
## AIProviderRequest sınıfına geri referans verilmez; enum değerleriyle
## aynı kararlı amaç sabitleri tutulur ve parse bağımlılık döngüsü önlenir.

const MODEL_PRO: String = "deepseek-v4-pro"
const MODEL_FLASH: String = "deepseek-v4-flash"
const LEGACY_CHAT: String = "deepseek-chat"
const LEGACY_REASONER: String = "deepseek-reasoner"

const DEFAULT_MODEL: String = MODEL_PRO
const MAX_OUTPUT_TOKENS: int = 384000

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


## Legacy değer yalnız yerel geriye uyumluluk girdisi mi?
static func is_legacy(requested_model: String) -> bool:
	return LEGACY_MODELS.has(requested_model.strip_edges())


## Düşünme modu politikası.
## - Eski chat/reasoner seçimlerinin eski anlamı korunur.
## - Yeni V4 kimliklerinde CODE/SUMMARY düşünmesiz; plan/inceleme düşünmeli.
static func thinking_enabled(requested_model: String, purpose: int) -> bool:
	var model_id: String = requested_model.strip_edges()
	if model_id == LEGACY_CHAT:
		return false
	if model_id == LEGACY_REASONER:
		return true
	return purpose in [PURPOSE_REASONING, PURPOSE_VALIDATION]


## V4 düşünme eforu. Planlama ve doğrulama ajan işlerinde maksimum,
## diğer düşünmeli kullanımlarda yüksek efor yeterlidir.
static func reasoning_effort(purpose: int) -> String:
	if purpose in [PURPOSE_REASONING, PURPOSE_VALIDATION]:
		return "max"
	return "high"


## Cache anahtarında aynı modelin düşünmeli/düşünmesiz sonuçları
## birbirine karışmasın diye kararlı ayırıcı üretir.
static func cache_discriminator(requested_model: String, purpose: int) -> String:
	return "%s|thinking:%s" % [
		canonical_model(requested_model),
		("enabled" if thinking_enabled(requested_model, purpose) else "disabled"),
	]
