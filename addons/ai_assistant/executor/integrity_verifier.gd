@tool
class_name AIIntegrityVerifier
extends RefCounted

## Yazım sonrası bütünlük + gerçek Godot artefakt doğrulaması.
## Başarı için dosyanın diskte bulunması, bit-bit eşleşmesi ve .gd/.tscn
## ise motor tarafından yüklenebilir olması gerekir.


static func verify_written(path: String, expected_content: String) -> Dictionary:
	var checks: Dictionary = {
		"exists": false,
		"hash_match": false,
		"size_match": false,
		"resource_load": false,
		"scene_instantiate": false,
	}

	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: dosya yazılmamış — %s" % path,
			"checks": checks,
		}
	checks["exists"] = true

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: dosya okunamadı — %s" % path,
			"checks": checks,
		}
	var actual_content: String = file.get_as_text()
	file.close()

	var expected_hash: String = expected_content.md5_text()
	var actual_hash: String = actual_content.md5_text()
	checks["hash_match"] = expected_hash == actual_hash

	var expected_size: int = expected_content.to_utf8_buffer().size()
	var actual_size: int = actual_content.to_utf8_buffer().size()
	checks["size_match"] = expected_size == actual_size

	if not bool(checks["hash_match"]):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: içerik bozuk (hash uyuşmuyor) — %s" % path,
			"checks": checks,
		}
	if not bool(checks["size_match"]):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: boyut uyuşmuyor (%d != %d) — %s" % [
				actual_size, expected_size, path,
			],
			"checks": checks,
		}

	var artifact: Dictionary = AIArtifactCommitVerifier.verify(
		path, expected_content, true
	)
	if not bool(artifact.get("ok", false)):
		return {
			"ok": false,
			"reason": "Artefakt doğrulaması başarısız: " + str(artifact.get("reason", "?")),
			"checks": checks,
			"artifact": artifact,
		}
	checks["resource_load"] = true
	checks["scene_instantiate"] = bool(artifact.get("instantiated", false))

	return {
		"ok": true,
		"reason": "",
		"checks": checks,
		"artifact": artifact,
	}


static func verify_deleted(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: dosya hâlâ var (silinmemiş) — %s" % path,
		}
	return {"ok": true, "reason": ""}


static func verify_moved(from_path: String, to_path: String) -> Dictionary:
	if FileAccess.file_exists(from_path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: kaynak hâlâ var — %s" % from_path,
		}
	if not FileAccess.file_exists(to_path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: hedef oluşmamış — %s" % to_path,
		}
	return {"ok": true, "reason": ""}


static func file_signature(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)
