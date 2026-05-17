@tool
class_name AIQualityGate
extends RefCounted

## QualityGate — kalite kapısı (Layer 10 ana motoru).
##
## Layer 10'un tek giriş noktası. Bir sahne üretildiğinde, telefonda
## çalışıp çalışmayacağına KARAR VEREN kapı. Dört bileşeni birleştirir:
##   budget   — AIMobileBudget        (telefon donanım sınırları)
##   checker  — AIBudgetChecker       (sahne bütçeye uyuyor mu)
##   lod      — AILODPolicy           (detay seviyesi kuralları)
##   advisor  — AIOptimizationAdvisor (aşımda ne yapmalı)
##
## Pilot Cell'in PerformanceEngineer rolü bu kapıyı kullanır:
##   1. Ürettiği sahnenin metriklerini verir
##   2. Kapı PASS/WARN/FAIL der
##   3. FAIL ise advisor önerilerini alır, Surgical Edit ile düzeltir
##   4. Tekrar dener (kapıdan geçene kadar)
##
## Master plan çıkış kapısı: üretilen sahne mobil bütçeye uymalı.
##
## Mock policy: kapı gerçek metriklerden karar verir — sahte PASS yok.

## Bir kalite kapısı değerlendirmesinin sonucu.
class GateResult extends RefCounted:
	var passed: bool = false           ## Kapıdan geçti mi (FAIL yok)
	var level: String = "pass"         ## pass | warn | fail
	var budget_report: AIBudgetChecker.BudgetReport = null
	var advice_text: String = ""       ## Optimizasyon önerileri (varsa)
	var lod_recommended: bool = false  ## LOD eklemek faydalı mı
	var retry_suggested: bool = false  ## Düzeltip tekrar denemeli mi

	func to_dict() -> Dictionary:
		return {
			"passed": passed,
			"level": level,
			"lod_recommended": lod_recommended,
			"retry_suggested": retry_suggested,
			"summary": budget_report.summary() if budget_report != null else "",
		}


## Bileşenler.
var budget: AIMobileBudget
var checker: AIBudgetChecker
var lod: AILODPolicy
var advisor: AIOptimizationAdvisor


func _init(tier: int = AIMobileBudget.Tier.MID_RANGE) -> void:
	budget = AIMobileBudget.new(tier)
	checker = AIBudgetChecker.new(budget)
	lod = AILODPolicy.new()
	advisor = AIOptimizationAdvisor.new()


# ============================================================
# KALİTE KAPISI — ana değerlendirme
# ============================================================

## Bir sahnenin mobil-uygunluğunu değerlendirir.
## metrics: {vertices, draw_calls, lights, textures_mb, bones, materials}.
## Dönen: GateResult.
func evaluate_scene(metrics: Dictionary) -> GateResult:
	var result := GateResult.new()

	# --- Bütçe denetimi ---
	var report: AIBudgetChecker.BudgetReport = checker.check_scene(metrics)
	result.budget_report = report
	result.level = AIBudgetChecker.CHECK_LEVEL_NAMES.get(report.level, "?")
	result.passed = report.is_acceptable()

	# --- Aşım varsa optimizasyon önerileri ---
	if report.level != AIBudgetChecker.CheckLevel.PASS:
		var advice: Dictionary = advisor.advise(report)
		result.advice_text = advisor.format_advice(advice)

	# --- FAIL ise düzeltip tekrar denenmeli ---
	if report.level == AIBudgetChecker.CheckLevel.FAIL:
		result.retry_suggested = true

	# --- Vertex yüksekse LOD öner ---
	var vertex_count: int = int(metrics.get("vertices", 0))
	if lod.is_lod_worthwhile(vertex_count):
		# Vertex bütçenin yarısını aşıyorsa LOD ciddi öneri
		var v_limit: int = budget.limit_for("vertices")
		if v_limit > 0 and vertex_count > v_limit / 2:
			result.lod_recommended = true

	return result


## Bir sahnenin sadece geçip geçmediğini döndürür — hızlı kontrol.
func does_scene_pass(metrics: Dictionary) -> bool:
	return checker.check_scene(metrics).is_acceptable()


## Optimizasyon sonrası iyileşmeyi değerlendirir.
## before / after: metrik sözlükleri.
## Dönen: {improved, now_passes, comparison}
func evaluate_improvement(before: Dictionary, after: Dictionary) -> Dictionary:
	var comparison: Dictionary = checker.compare(before, after)
	var after_passes: bool = does_scene_pass(after)
	var before_passes: bool = does_scene_pass(before)
	return {
		"improved": comparison["improved"],
		"now_passes": after_passes,
		"fixed": (not before_passes) and after_passes,
		"comparison": comparison,
	}


# ============================================================
# YAPILANDIRMA
# ============================================================

## Hedef telefon profilini ayarlar.
func set_tier(tier: int) -> void:
	budget.set_tier(tier)


## Aktif profil adı.
func tier_name() -> String:
	return budget.tier_name()


# ============================================================
# DURUM
# ============================================================

## Layer 10 durum özeti.
func status() -> Dictionary:
	return {
		"tier": budget.tier_name(),
		"budget": budget.current_budget(),
		"components": ["mobile_budget", "budget_checker",
			"lod_policy", "optimization_advisor"],
	}
