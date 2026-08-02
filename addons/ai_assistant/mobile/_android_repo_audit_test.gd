@tool
class_name AIAndroidRepoAuditTest
extends RefCounted

## Faz 7 — repodaki gerçek Android yapılandırmasını denetler.


static func run_all() -> Array:
	return [
		_b("Android: Repo", _test_actual_project_settings()),
		_b("Android: Repo", _test_actual_provider_endpoints()),
	]


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray()
	lines.append("=== Android Repo Audit Sonuçları ===")
	for result in results:
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append(
		"--- %d geçti, %d başarısız (toplam %d) ---" % [
			passed, failed, results.size()
		]
	)
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _test_actual_project_settings() -> Dictionary:
	var name := "Gerçek project.godot Mobile renderer ve secret denetimi"
	var project_text: String = _read_text("res://project.godot")
	if project_text.is_empty():
		return _fail(name, "project.godot okunamadı")
	var export_text: String = ""
	if FileAccess.file_exists("res://export_presets.cfg"):
		export_text = _read_text("res://export_presets.cfg")
	var result: Dictionary = AIAndroidReadinessAudit.audit(
		project_text, _actual_endpoints(), export_text
	)
	if not bool(result["ok"]):
		return _fail(name, str(result["errors"]))
	return _ok(name)


static func _test_actual_provider_endpoints() -> Dictionary:
	var name := "Gerçek provider adapter endpointleri yalnız HTTPS"
	var endpoints: Array = _actual_endpoints()
	if endpoints.size() != 4:
		return _fail(name, "4 sağlayıcı endpointi beklenir")
	for endpoint_value in endpoints:
		var endpoint: String = str(endpoint_value)
		if not endpoint.begins_with("https://"):
			return _fail(name, "HTTPS olmayan endpoint: " + endpoint)
	return _ok(name)


static func _actual_endpoints() -> Array:
	return [
		AIDeepSeekV4Adapter.new().endpoint_url,
		AIOpenAIAdapter.new().endpoint_url,
		AIAnthropicAdapter.new().endpoint_url,
		AIGeminiAdapter.ENDPOINT_BASE,
	]


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


static func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
