@tool
class_name AIQualityGatesTest
extends RefCounted

## Phase 13 / Layer 10 — Quality Gates Self-Test
##
## Sıkı testler: MobileBudget (donanım sınırları), BudgetChecker (sahne
## denetimi), LODPolicy (detay seviyesi), OptimizationAdvisor (öneriler),
## QualityGate (mobil-uygunluk kapısı).


static func run_all() -> Array:
	var results: Array = []

	# MobileBudget
	results.append(_b("Quality: Budget", _test_budget_tiers()))
	results.append(_b("Quality: Budget", _test_budget_limit_lookup()))
	results.append(_b("Quality: Budget", _test_budget_check_value()))
	results.append(_b("Quality: Budget", _test_budget_warn_zone()))

	# BudgetChecker
	results.append(_b("Quality: Checker", _test_checker_clean_scene()))
	results.append(_b("Quality: Checker", _test_checker_over_budget()))
	results.append(_b("Quality: Checker", _test_checker_warn_scene()))
	results.append(_b("Quality: Checker", _test_checker_partial_metrics()))
	results.append(_b("Quality: Checker", _test_checker_compare()))

	# LODPolicy
	results.append(_b("Quality: LOD", _test_lod_distance_levels()))
	results.append(_b("Quality: LOD", _test_lod_worthwhile()))
	results.append(_b("Quality: LOD", _test_lod_vertex_reduction()))
	results.append(_b("Quality: LOD", _test_lod_chain()))

	# OptimizationAdvisor
	results.append(_b("Quality: Advisor", _test_advisor_suggests()))
	results.append(_b("Quality: Advisor", _test_advisor_structural()))
	results.append(_b("Quality: Advisor", _test_advisor_clean_scene()))

	# QualityGate
	results.append(_b("Quality: Gate", _test_gate_pass()))
	results.append(_b("Quality: Gate", _test_gate_fail()))
	results.append(_b("Quality: Gate", _test_gate_lod_recommend()))
	results.append(_b("Quality: Gate", _test_gate_improvement()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# MOBILE BUDGET
# ============================================================

static func _test_budget_tiers() -> Dictionary:
	var name := "Budget profiller sıralı"
	var low := AIMobileBudget.new(AIMobileBudget.Tier.LOW_END)
	var mid := AIMobileBudget.new(AIMobileBudget.Tier.MID_RANGE)
	var high := AIMobileBudget.new(AIMobileBudget.Tier.HIGH_END)
	# HIGH_END her metrikte LOW_END'den cömert olmalı
	if high.limit_for("vertices") <= low.limit_for("vertices"):
		return _fail(name, "HIGH_END LOW_END'den fazla vertex bütçesi olmalı")
	if mid.limit_for("draw_calls") <= low.limit_for("draw_calls"):
		return _fail(name, "MID_RANGE LOW_END'den fazla draw call bütçesi olmalı")
	return _ok(name)


static func _test_budget_limit_lookup() -> Dictionary:
	var name := "Budget limit sorgusu"
	var budget := AIMobileBudget.new(AIMobileBudget.Tier.MID_RANGE)
	if budget.limit_for("vertices") <= 0:
		return _fail(name, "vertices limiti pozitif olmalı")
	# Bilinmeyen kaynak -1
	if budget.limit_for("bilinmeyen") != -1:
		return _fail(name, "bilinmeyen kaynak -1 dönmeli")
	return _ok(name)


static func _test_budget_check_value() -> Dictionary:
	var name := "Budget değer kontrolü"
	var budget := AIMobileBudget.new(AIMobileBudget.Tier.MID_RANGE)
	var limit: int = budget.limit_for("draw_calls")
	# Limit altı — içinde
	var under: Dictionary = budget.check_value("draw_calls", limit - 10)
	if not under["within"]:
		return _fail(name, "limit altı değer içinde olmalı")
	# Limit üstü — dışında
	var over: Dictionary = budget.check_value("draw_calls", limit + 10)
	if over["within"]:
		return _fail(name, "limit üstü değer dışında olmalı")
	return _ok(name)


static func _test_budget_warn_zone() -> Dictionary:
	var name := "Budget uyarı bölgesi"
	var budget := AIMobileBudget.new(AIMobileBudget.Tier.MID_RANGE)
	var limit: int = budget.limit_for("lights")
	# Limitin %90'ı — uyarı bölgesinde (eşik %80)
	var high_value: int = int(float(limit) * 0.9)
	if not budget.is_in_warn_zone("lights", high_value):
		return _fail(name, "limitin %90'ı uyarı bölgesinde olmalı")
	# Limitin %30'u — uyarı bölgesi dışında
	var low_value: int = int(float(limit) * 0.3)
	if budget.is_in_warn_zone("lights", low_value):
		return _fail(name, "limitin %30'u uyarı bölgesinde olmamalı")
	return _ok(name)


# ============================================================
# BUDGET CHECKER
# ============================================================

static func _test_checker_clean_scene() -> Dictionary:
	var name := "Checker temiz sahne PASS"
	var checker := AIBudgetChecker.new()
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"vertices": 30000, "draw_calls": 40, "lights": 2,
	})
	if report.level != AIBudgetChecker.CheckLevel.PASS:
		return _fail(name, "düşük metrikli sahne PASS olmalı")
	if not report.is_acceptable():
		return _fail(name, "temiz sahne kabul edilebilir olmalı")
	return _ok(name)


static func _test_checker_over_budget() -> Dictionary:
	var name := "Checker bütçe aşımı FAIL"
	var checker := AIBudgetChecker.new()
	# draw_calls çok yüksek — kesin aşım
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"draw_calls": 9999,
	})
	if report.level != AIBudgetChecker.CheckLevel.FAIL:
		return _fail(name, "aşan sahne FAIL olmalı")
	if report.is_acceptable():
		return _fail(name, "aşan sahne kabul edilemez olmalı")
	if not report.violations.has("draw_calls"):
		return _fail(name, "ihlal eden metrik kaydedilmeli")
	return _ok(name)


static func _test_checker_warn_scene() -> Dictionary:
	var name := "Checker uyarı bölgesi WARN"
	var checker := AIBudgetChecker.new()
	var limit: int = checker.budget().limit_for("draw_calls")
	# Limitin %90'ı — WARN ama FAIL değil
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"draw_calls": int(float(limit) * 0.9),
	})
	if report.level != AIBudgetChecker.CheckLevel.WARN:
		return _fail(name, "uyarı bölgesindeki sahne WARN olmalı")
	if not report.is_acceptable():
		return _fail(name, "WARN sahne hâlâ kabul edilebilir olmalı")
	return _ok(name)


static func _test_checker_partial_metrics() -> Dictionary:
	var name := "Checker eksik metrik atlanır"
	var checker := AIBudgetChecker.new()
	# Sadece bir metrik verildi — diğerleri denetlenmez
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"vertices": 20000,
	})
	if report.level != AIBudgetChecker.CheckLevel.PASS:
		return _fail(name, "tek düşük metrik PASS olmalı")
	if report.findings.size() != 1:
		return _fail(name, "sadece verilen metrik denetlenmeli")
	return _ok(name)


static func _test_checker_compare() -> Dictionary:
	var name := "Checker sahne karşılaştırma"
	var checker := AIBudgetChecker.new()
	var comparison: Dictionary = checker.compare(
		{"vertices": 100000}, {"vertices": 60000}
	)
	if not comparison["improved"]:
		return _fail(name, "vertex azalması iyileşme sayılmalı")
	return _ok(name)


# ============================================================
# LOD POLICY
# ============================================================

static func _test_lod_distance_levels() -> Dictionary:
	var name := "LOD mesafe seviyeleri"
	var lod := AILODPolicy.new()
	# Yakın — LOD0
	if lod.level_for_distance(5.0) != AILODPolicy.LODLevel.LOD0_FULL:
		return _fail(name, "yakın mesafe LOD0 olmalı")
	# Çok uzak — LOD4
	if lod.level_for_distance(200.0) != AILODPolicy.LODLevel.LOD4_IMPOSTOR:
		return _fail(name, "çok uzak mesafe LOD4 olmalı")
	return _ok(name)


static func _test_lod_worthwhile() -> Dictionary:
	var name := "LOD değerlilik eşiği"
	var lod := AILODPolicy.new()
	# Basit mesh — LOD'a değmez
	if lod.is_lod_worthwhile(100):
		return _fail(name, "100 vertex'lik mesh LOD'a değmemeli")
	# Karmaşık mesh — LOD'a değer
	if not lod.is_lod_worthwhile(10000):
		return _fail(name, "10000 vertex'lik mesh LOD'a değmeli")
	return _ok(name)


static func _test_lod_vertex_reduction() -> Dictionary:
	var name := "LOD vertex azaltma"
	var lod := AILODPolicy.new()
	# LOD0 tam detay
	if lod.vertices_at_level(10000, AILODPolicy.LODLevel.LOD0_FULL) != 10000:
		return _fail(name, "LOD0 tam vertex korumalı")
	# LOD4 impostor — minimal
	var lod4: int = lod.vertices_at_level(10000, AILODPolicy.LODLevel.LOD4_IMPOSTOR)
	if lod4 >= 10000 or lod4 <= 0:
		return _fail(name, "LOD4 vertex'i ciddi azaltmalı")
	# Seviye arttıkça vertex azalmalı
	var lod1: int = lod.vertices_at_level(10000, AILODPolicy.LODLevel.LOD1_HIGH)
	var lod2: int = lod.vertices_at_level(10000, AILODPolicy.LODLevel.LOD2_MEDIUM)
	if not (lod1 > lod2 and lod2 > lod4):
		return _fail(name, "yüksek LOD seviyesi daha az vertex olmalı")
	return _ok(name)


static func _test_lod_chain() -> Dictionary:
	var name := "LOD zinciri kurma"
	var lod := AILODPolicy.new()
	# Karmaşık mesh — tam zincir
	var chain: Array = lod.build_lod_chain(10000)
	if chain.size() != 5:
		return _fail(name, "karmaşık mesh 5 seviyeli zincir olmalı")
	# Basit mesh — tek seviye
	var simple: Array = lod.build_lod_chain(100)
	if simple.size() != 1:
		return _fail(name, "basit mesh tek seviye olmalı")
	return _ok(name)


# ============================================================
# OPTIMIZATION ADVISOR
# ============================================================

static func _test_advisor_suggests() -> Dictionary:
	var name := "Advisor aşımda öneri üretir"
	var checker := AIBudgetChecker.new()
	var advisor := AIOptimizationAdvisor.new()
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"draw_calls": 9999,
	})
	var advice: Dictionary = advisor.advise(report)
	var advices: Array = advice["advices"]
	if advices.is_empty():
		return _fail(name, "aşım için öneri üretilmeli")
	# draw_calls önerisi olmalı
	if (advices[0] as AIOptimizationAdvisor.Advice).metric != "draw_calls":
		return _fail(name, "öneri draw_calls metriği için olmalı")
	if (advices[0] as AIOptimizationAdvisor.Advice).suggestions.is_empty():
		return _fail(name, "öneri somut tavsiye içermeli")
	return _ok(name)


static func _test_advisor_structural() -> Dictionary:
	var name := "Advisor çoklu aşımda yapısal öneri"
	var checker := AIBudgetChecker.new()
	var advisor := AIOptimizationAdvisor.new()
	# Birden çok metrik aşılıyor
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"draw_calls": 9999, "vertices": 9999999,
	})
	var advice: Dictionary = advisor.advise(report)
	var structural: PackedStringArray = advice["structural"]
	if structural.is_empty():
		return _fail(name, "çoklu aşımda yapısal öneri olmalı")
	return _ok(name)


static func _test_advisor_clean_scene() -> Dictionary:
	var name := "Advisor temiz sahnede öneri yok"
	var checker := AIBudgetChecker.new()
	var advisor := AIOptimizationAdvisor.new()
	var report: AIBudgetChecker.BudgetReport = checker.check_scene({
		"draw_calls": 20, "vertices": 10000,
	})
	var advice: Dictionary = advisor.advise(report)
	if not (advice["advices"] as Array).is_empty():
		return _fail(name, "temiz sahnede öneri olmamalı")
	return _ok(name)


# ============================================================
# QUALITY GATE
# ============================================================

static func _test_gate_pass() -> Dictionary:
	var name := "Gate temiz sahne geçer"
	var gate := AIQualityGate.new()
	var result: AIQualityGate.GateResult = gate.evaluate_scene({
		"vertices": 30000, "draw_calls": 40, "lights": 2,
	})
	if not result.passed:
		return _fail(name, "temiz sahne kapıdan geçmeli")
	if result.retry_suggested:
		return _fail(name, "temiz sahne retry istememeli")
	return _ok(name)


static func _test_gate_fail() -> Dictionary:
	var name := "Gate aşan sahne geçmez"
	var gate := AIQualityGate.new()
	var result: AIQualityGate.GateResult = gate.evaluate_scene({
		"draw_calls": 9999,
	})
	if result.passed:
		return _fail(name, "aşan sahne kapıdan geçmemeli")
	if not result.retry_suggested:
		return _fail(name, "aşan sahne retry önermeli")
	# Optimizasyon önerisi üretilmiş olmalı
	if result.advice_text.is_empty():
		return _fail(name, "FAIL durumunda öneri metni olmalı")
	return _ok(name)


static func _test_gate_lod_recommend() -> Dictionary:
	var name := "Gate yüksek vertex LOD önerir"
	var gate := AIQualityGate.new()
	var v_limit: int = gate.budget.limit_for("vertices")
	# Limitin yarısından fazla vertex — LOD önerilmeli
	var result: AIQualityGate.GateResult = gate.evaluate_scene({
		"vertices": int(float(v_limit) * 0.75),
	})
	if not result.lod_recommended:
		return _fail(name, "yüksek vertex sayısında LOD önerilmeli")
	return _ok(name)


static func _test_gate_improvement() -> Dictionary:
	var name := "Gate optimizasyon sonrası düzelme"
	var gate := AIQualityGate.new()
	# Önce FAIL, sonra düzeltilmiş
	var improvement: Dictionary = gate.evaluate_improvement(
		{"draw_calls": 9999}, {"draw_calls": 50}
	)
	if not improvement["now_passes"]:
		return _fail(name, "düzeltilmiş sahne geçmeli")
	if not improvement["fixed"]:
		return _fail(name, "FAIL'den PASS'e geçiş 'fixed' olmalı")
	return _ok(name)
