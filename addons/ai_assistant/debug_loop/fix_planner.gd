@tool
class_name AIDebugFixPlanner
extends RefCounted

## FixPlanner — düzeltme planlayıcı (Madde 02 / Debug Loop / intelligence).
##
## Kök neden bulundu — şimdi NE YAPILACAK? Bu sınıf kök nedeni somut
## bir düzeltme planına çevirir. Plan, sistemin başka katmanlarının
## (Surgical Edit, Executor) anlayacağı biçimdedir.
##
## Düzeltme tipi kök nedene bağlı:
##   API değişimi  -> SURGICAL_REPLACE (eski API'yi yenisiyle değiştir)
##   Parse hatası  -> SURGICAL_EDIT (belirli satırı düzelt)
##   Null hatası   -> NEEDS_LLM (başlatma kodu üretmek LLM ister)
##
## "Mock yasak": her kök neden için sahte plan üretmez. Deterministik
## düzeltilebilir olanlara somut plan, ötekilere NEEDS_LLM.
##
## Mock policy: plan gerçek kök nedenden türetilir.

## Düzeltme stratejisi.
enum FixStrategy { SURGICAL_REPLACE, SURGICAL_EDIT, REGENERATE, NEEDS_LLM, NO_FIX }

const STRATEGY_NAMES: Dictionary = {
	FixStrategy.SURGICAL_REPLACE: "surgical_replace",
	FixStrategy.SURGICAL_EDIT: "surgical_edit",
	FixStrategy.REGENERATE: "regenerate",
	FixStrategy.NEEDS_LLM: "needs_llm",
	FixStrategy.NO_FIX: "no_fix",
}


## Bir düzeltme planı.
class FixPlan extends RefCounted:
	var strategy: int = AIDebugFixPlanner.FixStrategy.NEEDS_LLM
	var target_line: int = -1          ## Düzeltilecek satır (-1 = belirsiz)
	var description: String = ""       ## İnsan-okunur plan
	var deterministic: bool = false    ## LLM'siz uygulanabilir mi
	var search_text: String = ""       ## SURGICAL_REPLACE için
	var replace_text: String = ""

	func is_applicable() -> bool:
		return strategy != AIDebugFixPlanner.FixStrategy.NO_FIX \
			and strategy != AIDebugFixPlanner.FixStrategy.NEEDS_LLM

	func strategy_name() -> String:
		return AIDebugFixPlanner.STRATEGY_NAMES.get(strategy, "?")

	func to_dict() -> Dictionary:
		return {
			"strategy": strategy_name(),
			"target_line": target_line,
			"description": description,
			"deterministic": deterministic,
		}


## Godot 3→4 API haritalayıcı — deterministik düzeltme için.
var _api_mapper: AIDebugGodot4APIMapper


func _init(api_mapper: AIDebugGodot4APIMapper = null) -> void:
	if api_mapper != null:
		_api_mapper = api_mapper
	else:
		_api_mapper = AIDebugGodot4APIMapper.new()


# ============================================================
# PLANLAMA
# ============================================================

## Bir kök nedenden düzeltme planı üretir.
## root_cause: RootCauseAnalyzer'dan gelen analiz.
## error_class: orijinal hata sınıflandırması (sembol/satır için).
## Dönen: FixPlan.
func plan_fix(
	root_cause: AIDebugRootCauseAnalyzer.RootCause,
	error_class: AIDebugErrorClassifier.ErrorClass
) -> FixPlan:
	var plan := FixPlan.new()

	# Kök neden analiz edilemediyse — plan da yapılamaz
	if not root_cause.is_actionable():
		plan.strategy = FixStrategy.NEEDS_LLM
		plan.description = "Kök neden belirsiz — LLM analizi gerekli"
		return plan

	match error_class.category:
		AIDebugErrorClassifier.ErrorCategory.API_ERROR:
			return _plan_api_fix(error_class, plan)
		AIDebugErrorClassifier.ErrorCategory.PARSE_ERROR:
			return _plan_parse_fix(error_class, plan)
		AIDebugErrorClassifier.ErrorCategory.NULL_ERROR, \
		AIDebugErrorClassifier.ErrorCategory.TYPE_ERROR:
			# Bu hatalar somut düzeltme için LLM ister
			plan.strategy = FixStrategy.NEEDS_LLM
			plan.description = "Düzeltme için kod üretimi gerekli — LLM"
			return plan
		_:
			plan.strategy = FixStrategy.NEEDS_LLM
			plan.description = "Bilinmeyen hata — LLM gerekli"
			return plan


## API hatası için düzeltme planı — mapper ile deterministik.
func _plan_api_fix(
	error_class: AIDebugErrorClassifier.ErrorClass, plan: FixPlan
) -> FixPlan:
	var symbol: String = error_class.symbol
	var fix: Dictionary = _api_mapper.suggest_fix(symbol)

	if bool(fix["fixable"]):
		plan.strategy = FixStrategy.SURGICAL_REPLACE
		plan.deterministic = true
		plan.target_line = error_class.line
		plan.search_text = symbol
		# Metod haritasından yeni adı al
		var mapping: Dictionary = _api_mapper.map_method(symbol)
		if bool(mapping["found"]):
			plan.replace_text = str(mapping["new_name"])
		plan.description = "Godot 3→4 API düzeltmesi: " \
			+ str(fix["suggestion"])
		return plan

	# Bilinmeyen API — LLM gerekli
	plan.strategy = FixStrategy.NEEDS_LLM
	plan.description = "Bilinmeyen API hatası — LLM gerekli"
	return plan


## Parse hatası için düzeltme planı.
func _plan_parse_fix(
	error_class: AIDebugErrorClassifier.ErrorClass, plan: FixPlan
) -> FixPlan:
	if error_class.line > 0:
		plan.strategy = FixStrategy.SURGICAL_EDIT
		plan.target_line = error_class.line
		plan.description = "Satır %d'deki sözdizimi hatası düzeltilecek" \
			% error_class.line
		# Sözdizimi düzeltmesi LLM ister ama satır kesin
		plan.deterministic = false
	else:
		plan.strategy = FixStrategy.NEEDS_LLM
		plan.description = "Sözdizimi hatası — satır belirsiz, LLM gerekli"
	return plan


# ============================================================
# SORGULAMA
# ============================================================

## Bir kök neden için deterministik (LLM'siz) düzeltme mümkün mü?
func has_deterministic_fix(
	root_cause: AIDebugRootCauseAnalyzer.RootCause,
	error_class: AIDebugErrorClassifier.ErrorClass
) -> bool:
	var plan: FixPlan = plan_fix(root_cause, error_class)
	return plan.deterministic
