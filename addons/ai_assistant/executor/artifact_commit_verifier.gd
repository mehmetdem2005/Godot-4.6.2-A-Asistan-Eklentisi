@tool
class_name AIArtifactCommitVerifier
extends RefCounted

## Executor yazımından sonra artefaktın yalnız diskte bulunmasını değil,
## Godot tarafından gerçekten okunabilir/yüklenebilir olmasını doğrular.


static func verify(
	path: String,
	expected_content: String = "",
	refresh_editor: bool = true
) -> Dictionary:
	var normalized: String = path.strip_edges()
	var guard: Dictionary = AIPathGuard.check_read(normalized)
	if not bool(guard.get("allowed", false)):
		return _fail("Path guard reddi: " + str(guard.get("reason", "")))
	if not FileAccess.file_exists(normalized):
		return _fail("Dosya fiziksel olarak yok: " + normalized)

	var file := FileAccess.open(normalized, FileAccess.READ)
	if file == null:
		return _fail(
			"Dosya okunamadı (kod %d): %s" % [
				FileAccess.get_open_error(), normalized,
			]
		)
	var actual: String = file.get_as_text()
	file.close()
	if actual.is_empty():
		return _fail("Dosya boş: " + normalized)
	if not expected_content.is_empty() and actual != expected_content:
		return _fail("Disk içeriği Executor çıktısıyla birebir eşleşmiyor")

	var editor_refreshed: bool = false
	if refresh_editor and Engine.is_editor_hint():
		editor_refreshed = _refresh_editor_filesystem(normalized)

	var extension: String = normalized.get_extension().to_lower()
	var resource_type: String = "text"
	var instantiated: bool = false
	if extension == "gd":
		var compile_result: Dictionary = _compile_script(actual)
		if not bool(compile_result.get("ok", false)):
			return _fail(str(compile_result.get("reason", "Script derlenemedi")))
		var script_resource: Resource = ResourceLoader.load(
			normalized, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		if script_resource == null or not script_resource is Script:
			return _fail("GDScript ResourceLoader ile yüklenemedi: " + normalized)
		resource_type = "Script"
	elif extension == "tscn":
		var scene_resource: Resource = ResourceLoader.load(
			normalized, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		if scene_resource == null or not scene_resource is PackedScene:
			return _fail("Sahne PackedScene olarak yüklenemedi: " + normalized)
		var packed: PackedScene = scene_resource as PackedScene
		var instance: Node = packed.instantiate()
		if instance == null:
			return _fail("PackedScene instantiate edilemedi: " + normalized)
		instance.free()
		resource_type = "PackedScene"
		instantiated = true
	elif extension in ["tres", "res"]:
		var generic: Resource = ResourceLoader.load(
			normalized, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		if generic == null:
			return _fail("Godot resource yüklenemedi: " + normalized)
		resource_type = generic.get_class()

	return {
		"ok": true,
		"reason": "",
		"path": normalized,
		"bytes": actual.to_utf8_buffer().size(),
		"sha256": actual.sha256_text(),
		"resource_type": resource_type,
		"instantiated": instantiated,
		"editor_refreshed": editor_refreshed,
	}


static func _compile_script(source: String) -> Dictionary:
	var script := GDScript.new()
	script.source_code = source
	var error: int = script.reload()
	if error != OK:
		return {
			"ok": false,
			"reason": "GDScript motor derlemesi başarısız (kod %d)" % error,
		}
	return {"ok": true, "reason": ""}


static func _refresh_editor_filesystem(path: String) -> bool:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem == null:
		return false
	filesystem.update_file(path)
	if not filesystem.is_scanning() and not filesystem.is_importing():
		filesystem.scan()
	return true


static func _fail(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"path": "",
		"bytes": 0,
		"sha256": "",
		"resource_type": "",
		"instantiated": false,
		"editor_refreshed": false,
	}
