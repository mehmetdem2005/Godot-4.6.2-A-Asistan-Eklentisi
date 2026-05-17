@tool
class_name AIBudgetChecker
extends RefCounted

## BudgetChecker — bütçe denetleyicisi (Layer 10 / Quality Gates).
##
## MobileBudget sınırları tanımlar; bu sınıf BİR SAHNENİN o sınırlara
## uyup uymadığını denetler. Pilot Cell'in PerformanceEngineer rolü
## ürettiği sahnenin metriklerini buraya verir, "mobilde çalışır mı"
## cevabını alır.
##
## Denetlenen metrikler (kare başına):
##   vertices, draw_calls, lights, textures_mb, bones, materials
##
## Sonuç üç seviye:
##   PASS  — tüm metrikler bütçe içinde
##   WARN  — bazıları uyarı bölgesinde (limitin %80+'i)
##   FAIL  — en az biri bütçeyi aşıyor
##
## Mock policy: denetim gerçek metriklerden hesaplanır.

## Denetim sonucu seviyesi.
enum CheckLevel { PASS, WARN, FAIL }

const CHECK_LEVEL_NAMES: Dictionary = {
	CheckLevel.PASS: "pass",
	CheckLevel.WARN: "warn",
	CheckLevel.FAIL: "fail",
}

## Denetlenen metrik anahtarları.
const METRIC_KEYS: Array = [
	"vertices", "draw_calls", "lights", "textures_mb", "bones", "materials",
]


## Bir bütçe denetiminin sonucu.
class BudgetReport extends RefCounted:
	var level: int = AIBudgetChecker.CheckLevel.PASS
	var findings: Array = []           ## Her metrik için {metric, level, value, limit, ratio}
	var violations: PackedStringArray = PackedStringArray()  ## FAIL eden metrikler
	var warnings: PackedStringArray = PackedStringArray()    ## WARN eden metrikler

	## Sahne mobilde çalışır mı (FAIL yoksa)?
	func is_acceptable() -> bool:
		return level != AIBudgetChecker.CheckLevel.FAIL

	## İnsan-okunur özet.
	func summary() -> String:
		match level:
			AIBudgetChecker.CheckLevel.PASS:
				return "Tüm metrikler bütçe içinde"
			AIBudgetChecker.CheckLevel.WARN:
				return "%d metrik uyarı bölgesinde" % warnings.size()
			_:
				return "%d metrik bütçeyi aşıyor" % violations.size()

	func to_dict() -> Dictionary:
		return {
			"level": AIBudgetChecker.CHECK_LEVEL_NAMES.get(level, "?"),
			"acceptable": is_acceptable(),
			"findings": findings,
			"violations": violations,
			"warnings": warnings,
		}


## Bağlı bütçe.
var _budget: AIMobileBudget


func _init(budget: AIMobileBudget = null) -> void:
	if budget != null:
		_budget = budget
	else:
		_budget = AIMobileBudget.new()


## Bağlı bütçeyi döndürür.
func budget() -> AIMobileBudget:
	return _budget


# ============================================================
# DENETİM
# ============================================================

## Bir sahnenin metriklerini bütçeye karşı denetler.
## metrics: {vertices: int, draw_calls: int, ...} — kısmi olabilir.
## Dönen: BudgetReport.
func check_scene(metrics: Dictionary) -> BudgetReport:
	var report := BudgetReport.new()
	var worst: int = CheckLevel.PASS

	for metric in METRIC_KEYS:
		if not metrics.has(metric):
			continue  # verilmeyen metrik denetlenmez
		var value: int = int(metrics[metric])
		var check: Dictionary = _budget.check_value(metric, value)

		var metric_level: int = CheckLevel.PASS
		if not check["within"]:
			metric_level = CheckLevel.FAIL
			report.violations.append(metric)
		elif _budget.is_in_warn_zone(metric, value):
			metric_level = CheckLevel.WARN
			report.warnings.append(metric)

		report.findings.append({
			"metric": metric,
			"level": CHECK_LEVEL_NAMES.get(metric_level, "?"),
			"value": value,
			"limit": check["limit"],
			"ratio": check.get("ratio", 0.0),
		})
		worst = maxi(worst, metric_level)

	report.level = worst
	return report


## Tek bir metriği denetler — hızlı kontrol.
## Dönen: BudgetReport (tek bulgu).
func check_metric(metric: String, value: int) -> BudgetReport:
	return check_scene({metric: value})


## İki sahne metriğini karşılaştırır — optimizasyon sonrası iyileşme.
## before / after: metrik sözlükleri.
## Dönen: {improved: bool, deltas: Dictionary}
func compare(before: Dictionary, after: Dictionary) -> Dictionary:
	var deltas: Dictionary = {}
	var total_before: int = 0
	var total_after: int = 0
	for metric in METRIC_KEYS:
		var b: int = int(before.get(metric, 0))
		var a: int = int(after.get(metric, 0))
		deltas[metric] = a - b
		total_before += b
		total_after += a
	return {
		"improved": total_after < total_before,
		"deltas": deltas,
		"total_before": total_before,
		"total_after": total_after,
	}
