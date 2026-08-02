@tool
class_name AILiveAgentRoutingTest
extends RefCounted

## Faz 10 — hiyerarşik WorkOrder'ın gerçek pipeline görev hazırlama
## yoluna bağlandığını doğrular. Ağ veya Executor mutasyonu yapmaz.


static func run_all() -> Array:
	var o := AIPipelineOrchestrator.new()
	var results: Array = []
	results.append(_check(
		"Orkestratör 25 rollü organizasyonu taşıyor",
		o.organization_chart().role_count() == 25
	))
	results.append(_check(
		"Pipeline status organizasyon sayısını yayımlar",
		int(o.pipeline_status().get("organization_roles", 0)) == 25
	))
	var gameplay: Dictionary = o.route_task_preview({
		"id": "7",
		"title": "Player combat state machine yaz",
		"target_file": "res://game/player_combat.gd",
	})
	results.append(_check(
		"Gameplay işi doğru uzmana gider",
		str(gameplay.get("primary_role_id", "")) == "gameplay_engineer"
	))
	results.append(_check(
		"Gameplay işi bağımsız reviewer taşır",
		(gameplay.get("reviewer_ids", []) as Array).has("code_reviewer")
		and (gameplay.get("reviewer_ids", []) as Array).has("test_engineer")
	))
	var scene: Dictionary = o.route_task_preview({
		"title": "Sahneye child node ekle",
		"target_file": "res://game/main.tscn",
	})
	results.append(_check(
		"Scene işi Scene Implementer'a gider",
		str(scene.get("primary_role_id", "")) == "scene_implementer"
	))
	var risky: Dictionary = o.route_task_preview({
		"title": "Eski dosyayı sil ve project settings değiştir",
		"target_file": "res://game/legacy.gd",
	})
	results.append(_check(
		"Yüksek riskli canlı iş güvenlik reviewer taşır",
		bool(risky.get("high_risk", false))
		and (risky.get("reviewer_ids", []) as Array).has("security_reviewer")
	))
	var prepared: Dictionary = o._prepare_task_assignment(
		11, "Responsive HUD kur", "res://game/ui/hud.gd", "gen", 0, "", ""
	)
	results.append(_check(
		"Görev hazırlama aynı WorkOrder router'ını kullanır",
		bool(prepared.get("ok", false))
		and str((prepared.get("entry", {}) as Dictionary).get(
			"primary_role_id", ""
		)) == "ui_ux_engineer"
	))
	var entry: Dictionary = prepared.get("entry", {}) as Dictionary
	results.append(_check(
		"Registry girdisi ajan/departman/reviewer metadata'sı taşır",
		entry.has("primary_role_title")
		and entry.has("department")
		and entry.has("reviewer_ids")
		and entry.has("work_order")
	))
	results.append(_check(
		"Registry WorkOrder prompt sınırını taşır",
		str(entry.get("work_order_context", "")).contains("Executor")
		and str(entry.get("work_order_context", "")).contains("HITL")
	))
	results.append(_check(
		"Uygulama actor adı atanmış uzman başlığıdır",
		str(entry.get("primary_role_title", "")) == "UI/UX Engineer"
	))
	o.free()
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray(["=== Live Agent Routing Test Sonuçları ==="])
	for result in results:
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append("--- %d geçti, %d başarısız (toplam %d) ---" % [
		passed, failed, results.size()
	])
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _check(name: String, ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "name": name, "reason": reason if not ok else ""}
