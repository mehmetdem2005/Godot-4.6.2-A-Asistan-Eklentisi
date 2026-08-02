@tool
class_name AIAgentOrganizationTest
extends RefCounted

## Faz 9 — gerçek şirket tipi ajan ağacı ve görev yönlendirme testleri.
## Tamamen sahnesiz/deterministik; ağ veya dosya mutasyonu yapmaz.


static func run_all() -> Array:
	var chart := AIAgentOrgChart.new()
	var router := AIAgentTaskRouter.new(chart)
	var results: Array = []
	results.append(_b("Ağaç", _check("25 rol kayıtlı", chart.role_count() == 25)))
	results.append(_b("Ağaç", _check("Kanonik ağaç geçerli", bool(chart.validate()["ok"]), str(chart.validate()["errors"]))))
	results.append(_b("Ağaç", _check("Kök Chief Orchestrator", chart.has_role(AIAgentOrgChart.ROOT_ID))))
	results.append(_b("Ağaç", _check("Beş departman yöneticisi", chart.children_of(AIAgentOrgChart.ROOT_ID).size() == 5)))
	results.append(_b("Ağaç", _check("Bütün roller köke bağlı", _all_paths_reach_root(chart))))
	results.append(_b("Yetki", _check("Yöneticiler mutasyon yapamaz", _managers_cannot_execute(chart))))
	results.append(_b("Yetki", _check("Uygulayıcı kendi işini onaylayamaz", _executors_cannot_approve(chart))))
	results.append(_b("Yetki", _check("Release rolleri kod yazamaz", _release_cannot_write_code(chart))))
	results.append(_b("Routing", _route_check(router, "Gameplay GDScript üret", "res://game/player.gd", "gameplay_engineer")))
	results.append(_b("Routing", _route_check(router, "Mobil responsive HUD paneli yap", "res://game/ui/hud.gd", "ui_ux_engineer")))
	results.append(_b("Routing", _route_check(router, "Sahneye child node ekle", "res://game/main.tscn", "scene_implementer")))
	results.append(_b("Routing", _route_check(router, "Multiplayer RPC ve server authority kur", "res://game/net.gd", "multiplayer_engineer")))
	results.append(_b("Routing", _route_check(router, "FPS optimizasyonu ve profiler analizi", "res://game/world.gd", "performance_engineer")))
	results.append(_b("Routing", _route_check(router, "Texture ve shader import et", "res://game/art.tres", "asset_integration_engineer")))
	results.append(_b("Routing", _route_check(router, "Android APK export workflow hazırla", "", "android_release_engineer")))
	results.append(_b("Routing", _route_check(router, "Gereksinim ve kabul kriterleri yaz", "", "requirements_analyst")))
	results.append(_b("Güvenlik", _check("Yüksek risk güvenlik denetçisi alır", _high_risk_has_security(router))))
	results.append(_b("Güvenlik", _check("Birincil ajan kendi denetçisi değildir", _no_self_review(router))))
	results.append(_b("Sözleşme", _check("İş emri doğrulamadan geçer", _work_order_valid(chart, router))))
	results.append(_b("Sözleşme", _check("Prompt Executor/HITL sınırını taşır", _prompt_has_boundary(chart, router))))
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray(["=== Agent Organization Test Sonuçları ==="])
	var batch: String = ""
	for result in results:
		if str(result["batch"]) != batch:
			batch = str(result["batch"])
			lines.append("--- %s ---" % batch)
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append("--- %d geçti, %d başarısız (toplam %d) ---" % [passed, failed, results.size()])
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _route_check(
	router: AIAgentTaskRouter, title: String, target: String, expected: String
) -> Dictionary:
	var order := router.route({"title": title, "target_file": target})
	return _check(
		"%s → %s" % [title, expected],
		order.primary_role_id == expected,
		"gerçek: " + order.primary_role_id
	)


static func _all_paths_reach_root(chart: AIAgentOrgChart) -> bool:
	for data in chart.all_roles():
		var path: PackedStringArray = chart.path_to_root(str(data["role_id"]))
		if path.is_empty() or path.has("<cycle>") or path[-1] != AIAgentOrgChart.ROOT_ID:
			return false
	return true


static func _managers_cannot_execute(chart: AIAgentOrgChart) -> bool:
	for data in chart.all_roles():
		if str(data["role_kind"]) in ["executive", "director"]:
			if bool(data["can_execute"]):
				return false
			for tool_id in AIAgentOrgChart.PRIVILEGED_TOOLS:
				if (data["allowed_tools"] as Array).has(tool_id):
					return false
	return true


static func _executors_cannot_approve(chart: AIAgentOrgChart) -> bool:
	for data in chart.all_roles():
		if bool(data["can_execute"]) and bool(data["can_approve"]):
			return false
	return true


static func _release_cannot_write_code(chart: AIAgentOrgChart) -> bool:
	for data in chart.all_roles():
		if str(data["department"]) == "release":
			if (data["allowed_tools"] as Array).has("code.write"):
				return false
	return true


static func _high_risk_has_security(router: AIAgentTaskRouter) -> bool:
	var order := router.route({
		"title": "Eski gameplay scriptini sil",
		"target_file": "res://game/legacy.gd",
	})
	return (
		order.high_risk
		and order.reviewer_ids.has("security_reviewer")
		and not order.escalation_role_id.is_empty()
	)


static func _no_self_review(router: AIAgentTaskRouter) -> bool:
	var samples: Array = [
		{"title": "API key güvenliğini incele"},
		{"title": "Network RPC sistemi yaz", "target_file": "res://game/net.gd"},
		{"title": "UI panel yap", "target_file": "res://game/ui.gd"},
	]
	for sample in samples:
		var order := router.route(sample)
		if order.reviewer_ids.has(order.primary_role_id):
			return false
	return true


static func _work_order_valid(
	chart: AIAgentOrgChart, router: AIAgentTaskRouter
) -> bool:
	var samples: Array = [
		{"title": "Inventory gameplay kodu", "target_file": "res://game/inventory.gd"},
		{"title": "Sahne node ağacı", "target_file": "res://game/test.tscn"},
		{"title": "API key permission audit"},
	]
	for sample in samples:
		var result: Dictionary = router.route(sample).validate(chart)
		if not bool(result["ok"]):
			return false
	return true


static func _prompt_has_boundary(
	chart: AIAgentOrgChart, router: AIAgentTaskRouter
) -> bool:
	var order := router.route({
		"title": "Player state machine yaz",
		"target_file": "res://game/player.gd",
	})
	var text: String = order.prompt_context(chart)
	return text.contains("Executor") and text.contains("HITL") and text.contains("Bağımsız denetçiler")


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _check(name: String, ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "name": name, "reason": reason if not ok else ""}
