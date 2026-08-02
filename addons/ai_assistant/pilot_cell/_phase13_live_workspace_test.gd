@tool
class_name AIPhase13LiveWorkspaceTest
extends RefCounted

const TEST_DIR: String = "res://game/phase13_contract"
const SCRIPT_PATH: String = TEST_DIR + "/valid_script.gd"
const BROKEN_SCRIPT_PATH: String = TEST_DIR + "/broken_script.gd"
const SCENE_PATH: String = TEST_DIR + "/valid_scene.tscn"
const TEXT_PATH: String = TEST_DIR + "/plain.txt"


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("LiveEvent", _test_valid_event()))
	results.append(_b("LiveEvent", _test_invalid_type_rejected()))
	results.append(_b("LiveEvent", _test_confidence_clamped()))
	results.append(_b("LiveEvent", _test_long_text_truncated()))
	results.append(_b("LiveEvent", _test_api_key_redacted()))
	results.append(_b("LiveEvent", _test_authorization_redacted()))
	results.append(_b("LiveEvent", _test_secret_metadata_dropped()))
	results.append(_b("Artifact", _test_missing_file_fails()))
	results.append(_b("Artifact", _test_content_mismatch_fails()))
	results.append(_b("Artifact", _test_valid_gdscript_loads()))
	results.append(_b("Artifact", _test_broken_gdscript_fails()))
	results.append(_b("Artifact", _test_valid_scene_instantiates()))
	_cleanup()
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray()
	lines.append("=== Phase 13 Live Workspace Test Sonuçları ===")
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
			passed, failed, results.size(),
		]
	)
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _test_valid_event() -> Dictionary:
	var name := "Başlıklı ajan başlangıç olayı geçerlidir"
	var event: Dictionary = AILiveAgentEvent.create(
		AILiveAgentEvent.TYPE_STARTED,
		"node_1",
		3,
		"Architect",
		"Mimari bağlam",
		"Başladı",
		0.0,
		1
	)
	var validation: Dictionary = AILiveAgentEvent.validate(event)
	if not bool(validation.get("ok", false)):
		return _fail(name, str(validation.get("errors", [])))
	if int(event["layer"]) != 3 or str(event["role_name"]) != "Architect":
		return _fail(name, "katman veya rol kayboldu")
	return _ok(name)


static func _test_invalid_type_rejected() -> Dictionary:
	var name := "Bilinmeyen ajan olay tipi reddedilir"
	var event: Dictionary = AILiveAgentEvent.create(
		"unknown", "node_2", 1, "Reviewer", "Test", "x"
	)
	if bool(AILiveAgentEvent.validate(event).get("ok", true)):
		return _fail(name, "unknown tipi kabul edildi")
	return _ok(name)


static func _test_confidence_clamped() -> Dictionary:
	var name := "Ajan güven skoru 0-1 aralığına sıkıştırılır"
	var high: Dictionary = AILiveAgentEvent.create(
		AILiveAgentEvent.TYPE_COMPLETED,
		"node_3", 2, "QAEngineer", "QA", "PASS", 4.0
	)
	var low: Dictionary = AILiveAgentEvent.create(
		AILiveAgentEvent.TYPE_COMPLETED,
		"node_4", 2, "QAEngineer", "QA", "FAIL", -2.0
	)
	if float(high["confidence"]) != 1.0 or float(low["confidence"]) != 0.0:
		return _fail(name, "clamp uygulanmadı")
	return _ok(name)


static func _test_long_text_truncated() -> Dictionary:
	var name := "Uzun ajan çıktısı mobil akış için sınırlanır"
	var raw: String = "x".repeat(AILiveAgentEvent.MAX_TEXT_CHARS + 300)
	var excerpt: String = AILiveAgentEvent.safe_excerpt(raw)
	if excerpt.length() <= AILiveAgentEvent.MAX_TEXT_CHARS:
		return _fail(name, "kırpma işareti eklenmedi")
	if excerpt.length() > AILiveAgentEvent.MAX_TEXT_CHARS + 40:
		return _fail(name, "çıktı sınırı aşıldı")
	if not excerpt.contains("kırpıldı"):
		return _fail(name, "kırpma kullanıcıya açıklanmadı")
	return _ok(name)


static func _test_api_key_redacted() -> Dictionary:
	var name := "sk- biçimli API anahtarı canlı olaydan redakte edilir"
	var excerpt: String = AILiveAgentEvent.safe_excerpt(
		"istek sk-1234567890ABCDEFG tamamlandı"
	)
	if excerpt.contains("sk-1234567890ABCDEFG"):
		return _fail(name, "anahtar sızdı")
	if not excerpt.contains("REDACTED_KEY"):
		return _fail(name, "redaksiyon işareti yok")
	return _ok(name)


static func _test_authorization_redacted() -> Dictionary:
	var name := "Authorization Bearer başlığı canlı olaydan redakte edilir"
	var excerpt: String = AILiveAgentEvent.safe_excerpt(
		"Authorization: Bearer super-secret-token"
	)
	if excerpt.contains("super-secret-token"):
		return _fail(name, "Bearer token sızdı")
	if not excerpt.contains("REDACTED"):
		return _fail(name, "redaksiyon işareti yok")
	return _ok(name)


static func _test_secret_metadata_dropped() -> Dictionary:
	var name := "Gizli metadata alanları olay sözleşmesinden çıkarılır"
	var event: Dictionary = AILiveAgentEvent.create(
		AILiveAgentEvent.TYPE_PROGRESS,
		"node_5", 4, "CodeEngineer", "Kod", "bağlanıyor", 0.2, 0,
		{
			"api_key": "sk-1234567890ABCDEFG",
			"authorization": "Bearer secret",
			"latency_ms": 50,
		}
	)
	var metadata: Dictionary = event["metadata"]
	if metadata.has("api_key") or metadata.has("authorization"):
		return _fail(name, "gizli metadata kaldı")
	if int(metadata.get("latency_ms", 0)) != 50:
		return _fail(name, "güvenli metadata kayboldu")
	return _ok(name)


static func _test_missing_file_fails() -> Dictionary:
	var name := "Olmayan artefakt dürüstçe başarısız olur"
	_cleanup()
	var result: Dictionary = AIArtifactCommitVerifier.verify(
		TEST_DIR + "/missing.gd", "", false
	)
	if bool(result.get("ok", true)):
		return _fail(name, "olmayan dosya başarı sayıldı")
	return _ok(name)


static func _test_content_mismatch_fails() -> Dictionary:
	var name := "Disk içeriği Executor çıktısıyla uyuşmazsa reddedilir"
	_prepare_dir()
	if not _write(TEXT_PATH, "gerçek"):
		return _fail(name, "fixture yazılamadı")
	var result: Dictionary = AIArtifactCommitVerifier.verify(
		TEXT_PATH, "beklenen", false
	)
	if bool(result.get("ok", true)):
		return _fail(name, "içerik farkı kabul edildi")
	_cleanup_file(TEXT_PATH)
	return _ok(name)


static func _test_valid_gdscript_loads() -> Dictionary:
	var name := "Geçerli GDScript motorla derlenir ve Script olarak yüklenir"
	_prepare_dir()
	var source := "extends RefCounted\n\nfunc value() -> int:\n\treturn 42\n"
	if not _write(SCRIPT_PATH, source):
		return _fail(name, "script fixture yazılamadı")
	var result: Dictionary = AIArtifactCommitVerifier.verify(
		SCRIPT_PATH, source, false
	)
	_cleanup_file(SCRIPT_PATH)
	if not bool(result.get("ok", false)):
		return _fail(name, str(result.get("reason", "?")))
	if str(result.get("resource_type", "")) != "Script":
		return _fail(name, "resource_type Script değil")
	return _ok(name)


static func _test_broken_gdscript_fails() -> Dictionary:
	var name := "Parse hatalı GDScript artefakt başarısı sayılmaz"
	_prepare_dir()
	var source := "extends RefCounted\nfunc broken( -> void:\n\tpass\n"
	if not _write(BROKEN_SCRIPT_PATH, source):
		return _fail(name, "broken fixture yazılamadı")
	var result: Dictionary = AIArtifactCommitVerifier.verify(
		BROKEN_SCRIPT_PATH, source, false
	)
	_cleanup_file(BROKEN_SCRIPT_PATH)
	if bool(result.get("ok", true)):
		return _fail(name, "bozuk script kabul edildi")
	return _ok(name)


static func _test_valid_scene_instantiates() -> Dictionary:
	var name := "Geçerli tscn PackedScene olarak yüklenir ve instantiate edilir"
	_prepare_dir()
	var source := (
		"[gd_scene format=3]\n\n"
		+ "[node name=\"Phase13Root\" type=\"Node\"]\n"
	)
	if not _write(SCENE_PATH, source):
		return _fail(name, "scene fixture yazılamadı")
	var result: Dictionary = AIArtifactCommitVerifier.verify(
		SCENE_PATH, source, false
	)
	_cleanup_file(SCENE_PATH)
	if not bool(result.get("ok", false)):
		return _fail(name, str(result.get("reason", "?")))
	if str(result.get("resource_type", "")) != "PackedScene":
		return _fail(name, "resource_type PackedScene değil")
	if not bool(result.get("instantiated", false)):
		return _fail(name, "sahne instantiate edilmedi")
	return _ok(name)


static func _prepare_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.make_dir_recursive_absolute(TEST_DIR)


static func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true


static func _cleanup() -> void:
	for path in [SCRIPT_PATH, BROKEN_SCRIPT_PATH, SCENE_PATH, TEXT_PATH]:
		_cleanup_file(path)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR)


static func _cleanup_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


static func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
