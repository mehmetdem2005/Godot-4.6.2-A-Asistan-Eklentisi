@tool
class_name AIReleaseReadinessTest
extends RefCounted

## Faz 8 — release manifesti ve gerçek repo konsolidasyon testleri.

const MANIFEST_PATH: String = "res://release/readiness_manifest.json"
const PLUGIN_PATH: String = "res://addons/ai_assistant/plugin.cfg"
const PHASE1_PATH: String = (
	"res://docs/phases/phase-01-godot-4.6.3-safety-audit.md"
)
const DOCUMENT_PATHS: Array = [
	"res://README.md",
	"res://CHANGELOG.md",
	"res://docs/RELEASE_READINESS.md",
	"res://docs/MIGRATION_DEEPSEEK_V4.md",
	"res://tools/FINAL_RELEASE_SMOKE.md",
]


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Release: Pending", _test_valid_pending_manifest()))
	results.append(_b("Release: Faz", _test_phase_count_rejected()))
	results.append(_b("Release: Faz", _test_phase_order_rejected()))
	results.append(_b("Release: Zincir", _test_dependency_chain_rejected()))
	results.append(_b("Release: Gate", _test_false_automatic_gate_rejected()))
	results.append(_b("Release: Dürüstlük", _test_dishonest_merge_ready_rejected()))
	results.append(_b("Release: Hazır", _test_all_manuals_passed_accepted()))
	results.append(_b("Release: Plugin", _test_plugin_version_mismatch()))
	results.append(_b("Release: Secret", _test_embedded_secret_rejected()))
	results.append(_b("Release: Repo", _test_actual_repository_consistency()))
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray()
	lines.append("=== Release Readiness Test Sonuçları ===")
	var current_batch: String = ""
	for result in results:
		if str(result["batch"]) != current_batch:
			current_batch = str(result["batch"])
			lines.append("--- %s ---" % current_batch)
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


static func _test_valid_pending_manifest() -> Dictionary:
	var name := "Yapısal olarak geçerli pending RC dürüstçe merge-ready değildir"
	var manifest: Dictionary = _manifest_fixture()
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if not bool(result["ok"]):
		return _fail(name, "geçerli pending manifest reddedildi: " + str(result["errors"]))
	if bool(result["merge_ready"]):
		return _fail(name, "pending manuel kapılarla merge_ready false olmalı")
	if not bool(result["automatic_ready"]):
		return _fail(name, "otomatik kapılar hazır olmalı")
	if bool(result["manuals_passed"]):
		return _fail(name, "pending kapılar passed sayılmamalı")
	return _ok(name)


static func _test_phase_count_rejected() -> Dictionary:
	var name := "Eksik faz listesi reddedilir"
	var manifest: Dictionary = _manifest_fixture()
	var phases: Array = manifest["phases"]
	phases.pop_back()
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if bool(result["ok"]):
		return _fail(name, "7 fazlı manifest kabul edilmemeli")
	if not _errors_contain(result, "tam 8 faz"):
		return _fail(name, "faz sayısı hatası açık raporlanmadı")
	return _ok(name)


static func _test_phase_order_rejected() -> Dictionary:
	var name := "Faz sıra veya tekrarlı branch/PR reddedilir"
	var manifest: Dictionary = _manifest_fixture()
	var phases: Array = manifest["phases"]
	(phases[3] as Dictionary)["number"] = 9
	(phases[4] as Dictionary)["branch"] = str((phases[3] as Dictionary)["branch"])
	(phases[4] as Dictionary)["pr"] = int((phases[3] as Dictionary)["pr"])
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if bool(result["ok"]):
		return _fail(name, "bozuk faz kimliği kabul edilmemeli")
	if not _errors_contain(result, "faz sırası"):
		return _fail(name, "faz sırası hatası raporlanmadı")
	return _ok(name)


static func _test_dependency_chain_rejected() -> Dictionary:
	var name := "Stacked PR base zinciri bozulursa reddedilir"
	var manifest: Dictionary = _manifest_fixture()
	var phases: Array = manifest["phases"]
	(phases[6] as Dictionary)["base"] = "agent/yanlis-base"
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if bool(result["ok"]):
		return _fail(name, "yanlış base zinciri kabul edilmemeli")
	if not _errors_contain(result, "base zinciri yanlış"):
		return _fail(name, "base hatası açık raporlanmadı")
	return _ok(name)


static func _test_false_automatic_gate_rejected() -> Dictionary:
	var name := "Başarısız otomatik gate release manifestini kırar"
	var manifest: Dictionary = _manifest_fixture()
	var automatic: Dictionary = manifest["automatic"]
	var gates: Dictionary = automatic["gates"]
	gates["runtime_hygiene"] = false
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if bool(result["ok"]):
		return _fail(name, "false runtime hygiene gate kabul edilmemeli")
	if not _errors_contain(result, "runtime_hygiene"):
		return _fail(name, "başarısız gate adı raporlanmadı")
	return _ok(name)


static func _test_dishonest_merge_ready_rejected() -> Dictionary:
	var name := "Pending kapılar varken merge_ready=true sahte beyanı reddedilir"
	var manifest: Dictionary = _manifest_fixture()
	var release_data: Dictionary = manifest["release"]
	release_data["merge_ready"] = true
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if bool(result["ok"]):
		return _fail(name, "sahte merge_ready beyanı kabul edilmemeli")
	if not _errors_contain(result, "merge_ready dürüst değil"):
		return _fail(name, "dürüstlük hatası açık raporlanmadı")
	return _ok(name)


static func _test_all_manuals_passed_accepted() -> Dictionary:
	var name := "Tüm otomatik ve manuel kapılar geçince merge_ready=true kabul edilir"
	var manifest: Dictionary = _manifest_fixture()
	for gate_value in manifest["manual_gates"]:
		(gate_value as Dictionary)["status"] = "passed"
	(manifest["release"] as Dictionary)["merge_ready"] = true
	var result: Dictionary = _audit(manifest, _valid_plugin_text())
	if not bool(result["ok"]):
		return _fail(name, "tam hazır manifest reddedildi: " + str(result["errors"]))
	if not bool(result["merge_ready"]):
		return _fail(name, "hesaplanan merge_ready true olmalı")
	if not bool(result["manuals_passed"]):
		return _fail(name, "manuel kapılar passed olmalı")
	return _ok(name)


static func _test_plugin_version_mismatch() -> Dictionary:
	var name := "Plugin sürümü manifest ile eşleşmezse reddedilir"
	var result: Dictionary = _audit(
		_manifest_fixture(),
		_valid_plugin_text().replace("1.1.0-rc.1", "9.9.9")
	)
	if bool(result["ok"]):
		return _fail(name, "plugin sürüm drift'i kabul edilmemeli")
	if not _errors_contain(result, "plugin.cfg version"):
		return _fail(name, "plugin version hatası raporlanmadı")
	return _ok(name)


static func _test_embedded_secret_rejected() -> Dictionary:
	var name := "Manifest veya release belgesindeki gömülü anahtar reddedilir"
	var docs: Array = ["örnek olmayan gerçek değer: sk-1234567890ABCDEFGH"]
	var result: Dictionary = AIReleaseReadinessAudit.audit(
		_manifest_fixture(), _valid_plugin_text(), true, docs
	)
	if bool(result["ok"]):
		return _fail(name, "gömülü secret kabul edilmemeli")
	if not _errors_contain(result, "gizli anahtar"):
		return _fail(name, "secret hatası açık raporlanmadı")
	return _ok(name)


static func _test_actual_repository_consistency() -> Dictionary:
	var name := "Gerçek manifest/plugin/Faz1/docs release audit'inden geçer"
	var manifest: Dictionary = _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		return _fail(name, "gerçek readiness manifest okunamadı")
	var plugin_text: String = _read_text(PLUGIN_PATH)
	if plugin_text.is_empty():
		return _fail(name, "gerçek plugin.cfg okunamadı")
	var docs: Array = []
	for path_value in DOCUMENT_PATHS:
		var path: String = str(path_value)
		var text: String = _read_text(path)
		if text.is_empty():
			return _fail(name, "release belgesi yok/boş: " + path)
		docs.append(text)
	var result: Dictionary = AIReleaseReadinessAudit.audit(
		manifest,
		plugin_text,
		FileAccess.file_exists(PHASE1_PATH),
		docs
	)
	if not bool(result["ok"]):
		return _fail(name, "gerçek repo audit başarısız: " + str(result["errors"]))
	if bool(result["merge_ready"]):
		return _fail(name, "manuel kapılar açıkken gerçek repo merge-ready olmamalı")
	return _ok(name)


static func _manifest_fixture() -> Dictionary:
	var manifest: Dictionary = _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		return {}
	return _deep_copy(manifest)


static func _valid_plugin_text() -> String:
	return (
		"[plugin]\n\n"
		+ "name=\"AI Asistan\"\n"
		+ "description=\"Godot 4.6.3 için tam ekran DeepSeek V4 asistanı.\"\n"
		+ "author=\"AI Assistant\"\n"
		+ "version=\"1.1.0-rc.1\"\n"
		+ "script=\"plugin.gd\"\n"
	)


static func _audit(manifest: Dictionary, plugin_text: String) -> Dictionary:
	return AIReleaseReadinessAudit.audit(manifest, plugin_text, true, [])


static func _deep_copy(value: Variant) -> Variant:
	var json_text: String = JSON.stringify(value)
	var parsed: Variant = JSON.parse_string(json_text)
	return parsed


static func _load_json(path: String) -> Dictionary:
	var text: String = _read_text(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


static func _errors_contain(result: Dictionary, fragment: String) -> bool:
	for error_value in result.get("errors", []):
		if str(error_value).contains(fragment):
			return true
	return false


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


static func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
