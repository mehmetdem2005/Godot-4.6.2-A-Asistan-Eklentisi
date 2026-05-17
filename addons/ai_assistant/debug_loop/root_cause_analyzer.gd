@tool
class_name AIDebugRootCauseAnalyzer
extends RefCounted

## RootCauseAnalyzer — kök neden analizci (Madde 02 / Debug Loop).
##
## Bir hata yüzeysel belirtidir; asıl soru "NEDEN oldu". "null instance"
## hatası belirtiledir — kök neden, bir node'un sahneye eklenmemiş
## olması olabilir. Yanlış kök neden = yanlış düzeltme = Mehmet'in
## "sürekli başka hata" döngüsü.
##
## Bu sınıf iki yol izler:
##   1. DETERMİNİSTİK — bilinen örüntüler (API hatası -> mapper'dan
##      kök neden bellidir, LLM gerekmez)
##   2. LLM + RAG — örüntü eşleşmezse, LLM analizi gerekir
##
## "Mock yasak": LLM yoksa ve örüntü eşleşmezse sahte kök neden
## uydurmaz — NEEDS_LLM döner, dürüstçe "analiz edemiyorum" der.
##
## Mock policy: kök neden ya deterministik kanıttan ya LLM'den;
## tahmin yok.

## Analiz güven seviyesi.
enum Confidence { HIGH, MEDIUM, LOW, NEEDS_LLM }

const CONFIDENCE_NAMES: Dictionary = {
	Confidence.HIGH: "high",
	Confidence.MEDIUM: "medium",
	Confidence.LOW: "low",
	Confidence.NEEDS_LLM: "needs_llm",
}


## Bir kök neden analizi sonucu.
class RootCause extends RefCounted:
	var confidence: int = AIDebugRootCauseAnalyzer.Confidence.NEEDS_LLM
	var cause: String = ""             ## Kök neden açıklaması
	var category: String = ""          ## Hata kategorisi
	var deterministic: bool = false    ## LLM'siz mi bulundu

	func is_actionable() -> bool:
		# NEEDS_LLM dışındaki her şey üzerine işlem yapılabilir
		return confidence != AIDebugRootCauseAnalyzer.Confidence.NEEDS_LLM

	func to_dict() -> Dictionary:
		return {
			"confidence": AIDebugRootCauseAnalyzer.CONFIDENCE_NAMES.get(
				confidence, "?"
			),
			"cause": cause,
			"category": category,
			"deterministic": deterministic,
		}


## Godot 3→4 API haritalayıcı — deterministik analiz için.
var _api_mapper: AIDebugGodot4APIMapper


func _init(api_mapper: AIDebugGodot4APIMapper = null) -> void:
	if api_mapper != null:
		_api_mapper = api_mapper
	else:
		_api_mapper = AIDebugGodot4APIMapper.new()


# ============================================================
# ANALİZ
# ============================================================

## Sınıflandırılmış bir hatanın kök nedenini analiz eder.
## error_class: ErrorClassifier'dan gelen sınıflandırma.
## Dönen: RootCause.
func analyze(error_class: AIDebugErrorClassifier.ErrorClass) -> RootCause:
	var result := RootCause.new()
	result.category = error_class.category_name()

	match error_class.category:
		AIDebugErrorClassifier.ErrorCategory.API_ERROR:
			return _analyze_api_error(error_class, result)
		AIDebugErrorClassifier.ErrorCategory.PARSE_ERROR:
			return _analyze_parse_error(error_class, result)
		AIDebugErrorClassifier.ErrorCategory.NULL_ERROR:
			return _analyze_null_error(result)
		AIDebugErrorClassifier.ErrorCategory.TYPE_ERROR:
			return _analyze_type_error(result)
		_:
			# RUNTIME / UNKNOWN — deterministik analiz yok
			result.confidence = Confidence.NEEDS_LLM
			result.cause = "Örüntü eşleşmedi — LLM analizi gerekli"
			return result


## API hatası — Godot 3→4 mapper ile kök neden.
func _analyze_api_error(
	error_class: AIDebugErrorClassifier.ErrorClass, result: RootCause
) -> RootCause:
	var symbol: String = error_class.symbol
	# Mapper bilinen bir 3→4 değişimi mi diyor?
	if not symbol.is_empty() and _api_mapper.is_known_migration(symbol):
		var fix: Dictionary = _api_mapper.suggest_fix(symbol)
		result.confidence = Confidence.HIGH
		result.deterministic = true
		result.cause = "Godot 3 API'si Godot 4'te değişti: " \
			+ str(fix["suggestion"])
		return result
	# Bilinmeyen API hatası — LLM gerekli
	result.confidence = Confidence.NEEDS_LLM
	result.cause = "Bilinmeyen API hatası — LLM analizi gerekli"
	return result


## Parse hatası — sözdizimi, satır numarası kesin.
func _analyze_parse_error(
	error_class: AIDebugErrorClassifier.ErrorClass, result: RootCause
) -> RootCause:
	result.confidence = Confidence.HIGH
	result.deterministic = true
	if error_class.line > 0:
		result.cause = "Sözdizimi hatası — satır %d" % error_class.line
	else:
		result.cause = "Sözdizimi hatası — kaynak ayrıştırılamadı"
	return result


## Null hatası — kök neden genelde başlatma eksikliği.
func _analyze_null_error(result: RootCause) -> RootCause:
	result.confidence = Confidence.MEDIUM
	result.cause = "Null nesneye erişim — değişken başlatılmamış " \
		+ "veya node sahnede yok olabilir"
	return result


## Tip hatası — argüman/dönüş tipi uyuşmazlığı.
func _analyze_type_error(result: RootCause) -> RootCause:
	result.confidence = Confidence.MEDIUM
	result.cause = "Tip uyuşmazlığı — beklenen ve verilen tip farklı"
	return result


# ============================================================
# SORGULAMA
# ============================================================

## Bir hata deterministik olarak (LLM'siz) analiz edilebilir mi?
func can_analyze_deterministically(
	error_class: AIDebugErrorClassifier.ErrorClass
) -> bool:
	var result: RootCause = analyze(error_class)
	return result.deterministic
