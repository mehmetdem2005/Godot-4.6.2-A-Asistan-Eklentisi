@tool
class_name AIOptimizationAdvisor
extends RefCounted

## OptimizationAdvisor — optimizasyon danışmanı (Layer 10 / Quality Gates).
##
## BudgetChecker "bu metrik aşıldı" der; bu sınıf "PEKİ NE YAPMALI" der.
## Her bütçe aşımı için somut, uygulanabilir öneri üretir.
##
## Örnek: "draw_calls 220, limit 150" -> öneriler:
##   - MultiMesh ile statik nesneleri grupla
##   - Materyal sayısını azalt (atlas kullan)
##   - Uzak nesneleri occlusion culling ile gizle
##
## Bu öneriler Pilot Cell'in PerformanceEngineer rolüne girdi olur;
## o rol önerileri uygulamak için Surgical Edit ile sahneyi düzenler.
##
## Mock policy: öneriler gerçek metrik aşımına göre seçilir.

## Bir öneri.
class Advice extends RefCounted:
	var metric: String = ""
	var severity: String = "warning"   ## "warning" | "critical"
	var problem: String = ""
	var suggestions: PackedStringArray = PackedStringArray()

	func to_dict() -> Dictionary:
		return {
			"metric": metric,
			"severity": severity,
			"problem": problem,
			"suggestions": suggestions,
		}


## Her metrik için optimizasyon önerileri (TR).
## Anahtar: metrik, değer: öneri listesi.
const METRIC_SUGGESTIONS: Dictionary = {
	"vertices": [
		"LOD zinciri ekle — uzak nesneler düşük detayda çizilsin",
		"Görünmeyen yüzeyleri (mesh iç kısımları) sil",
		"Yüksek-poly mesh'leri normal map'e bake et",
	],
	"draw_calls": [
		"MultiMesh ile aynı mesh'in çok kopyasını tek çağrıda çiz",
		"Statik nesneleri birleştir (mesh merge)",
		"Materyal sayısını azalt — her materyal ayrı draw call",
	],
	"lights": [
		"Statik ışıkları lightmap'e bake et",
		"Işık menzilini (range) daralt — etki alanı küçülsün",
		"Gerçek-zamanlı gölgeyi sadece ana ışıkta kullan",
	],
	"textures_mb": [
		"Texture çözünürlüğünü düşür (2048 -> 1024)",
		"Texture sıkıştırma kullan (ETC2 / ASTC, Android)",
		"Texture atlas ile küçük dokuları birleştir",
	],
	"bones": [
		"İskelet kemik sayısını azalt — parmak/yüz detayını düşür",
		"Uzak karakterlerde basit iskelet kullan",
	],
	"materials": [
		"Texture atlas ile materyalleri birleştir",
		"Benzer materyalleri tek shader parametresiyle birleştir",
	],
}

## Genel — birden çok metrik aşılınca yapısal öneriler.
const STRUCTURAL_SUGGESTIONS: Array = [
	"Occlusion culling aç — kameranın görmediği nesneler çizilmesin",
	"Sahneyi bölgelere ayır, uzak bölgeleri devre dışı bırak",
	"Hedef telefon profilini düşür (HIGH_END -> MID_RANGE)",
]


# ============================================================
# ÖNERİ ÜRETİMİ
# ============================================================

## Bir BudgetReport'tan optimizasyon önerileri üretir.
## report: AIBudgetChecker.BudgetReport.
## Dönen: {advices: Array[Advice], structural: PackedStringArray}
func advise(report: AIBudgetChecker.BudgetReport) -> Dictionary:
	var advices: Array = []

	# Her bulguya bak — FAIL ve WARN için öneri üret
	for finding in report.findings:
		var level: String = finding["level"]
		if level == "pass":
			continue
		var metric: String = finding["metric"]
		var advice := Advice.new()
		advice.metric = metric
		advice.severity = "critical" if level == "fail" else "warning"
		advice.problem = "%s: %d / limit %d" % [
			metric, finding["value"], finding["limit"]
		]
		var suggestions: Array = METRIC_SUGGESTIONS.get(metric, [])
		for s in suggestions:
			advice.suggestions.append(s)
		advices.append(advice)

	# Birden çok metrik sorunluysa yapısal öneriler de ekle
	var structural: PackedStringArray = PackedStringArray()
	var problem_count: int = report.violations.size() + report.warnings.size()
	if problem_count >= 2:
		for s in STRUCTURAL_SUGGESTIONS:
			structural.append(s)

	return {"advices": advices, "structural": structural}


## Tek bir metrik için doğrudan öneri listesi — hızlı erişim.
func suggestions_for(metric: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var suggestions: Array = METRIC_SUGGESTIONS.get(metric, [])
	for s in suggestions:
		result.append(s)
	return result


## Bir öneri raporunu insan-okunur metne çevirir.
func format_advice(advise_result: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var advices: Array = advise_result.get("advices", [])
	if advices.is_empty():
		return "Optimizasyon önerisi yok — sahne bütçe içinde."

	for advice in advices:
		var a: Advice = advice
		lines.append("[%s] %s" % [a.severity.to_upper(), a.problem])
		for suggestion in a.suggestions:
			lines.append("  - " + suggestion)

	var structural: PackedStringArray = advise_result.get(
		"structural", PackedStringArray()
	)
	if structural.size() > 0:
		lines.append("Yapısal öneriler:")
		for s in structural:
			lines.append("  - " + s)
	return "\n".join(lines)
