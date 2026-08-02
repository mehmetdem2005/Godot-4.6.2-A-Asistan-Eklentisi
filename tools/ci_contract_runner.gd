@tool
extends SceneTree

## Godot 4.6.3 CI kalite kapısı.
##
## Headless çalışır, motor sürümünü doğrular ve tüm contract/self-test
## paketini çalıştırır. Bir test bile başarısızsa süreç sıfır olmayan
## çıkış koduyla kapanır; CI sahte başarı üretemez.

const REQUIRED_MAJOR: int = 4
const REQUIRED_MINOR: int = 6
const REQUIRED_PATCH: int = 3


func _initialize() -> void:
	var version_result: Dictionary = _verify_engine_version()
	if not bool(version_result.get("ok", false)):
		printerr("CI_VERSION_FAIL: " + str(version_result.get("reason", "")))
		quit(20)
		return

	print("CI_ENGINE_OK: " + str(version_result.get("version", "unknown")))

	var report: Dictionary = AIContractSelfTest.run_all()
	var failed: int = int(report.get("failed", -1))
	var passed: int = int(report.get("passed", 0))

	if failed < 0:
		printerr("CI_CONTRACT_FAIL: self-test geçerli sonuç döndürmedi")
		quit(21)
		return

	if failed > 0:
		printerr(
			"CI_CONTRACT_FAIL: %d test başarısız, %d test geçti" % [
				failed,
				passed,
			]
		)
		quit(22)
		return

	print("CI_CONTRACT_OK: %d test geçti" % passed)
	quit(0)


func _verify_engine_version() -> Dictionary:
	var info: Dictionary = Engine.get_version_info()
	var major: int = int(info.get("major", -1))
	var minor: int = int(info.get("minor", -1))
	var patch: int = int(info.get("patch", -1))
	var version_string: String = str(info.get("string", ""))

	if major != REQUIRED_MAJOR or minor != REQUIRED_MINOR or patch != REQUIRED_PATCH:
		return {
			"ok": false,
			"version": version_string,
			"reason": (
				"Godot %d.%d.%d gerekli, çalışan sürüm: %s"
				% [REQUIRED_MAJOR, REQUIRED_MINOR, REQUIRED_PATCH, version_string]
			),
		}

	return {
		"ok": true,
		"version": version_string,
		"reason": "",
	}
