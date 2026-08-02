@tool
extends SceneTree

## Godot 4.6.3 CI kalite kapısı.
##
## Headless çalışır, motor sürümünü doğrular ve tüm contract/self-test
## paketini çalıştırır. Bir test bile başarısızsa süreç sıfır olmayan
## çıkış koduyla kapanır; CI sahte başarı üretemez.
##
## Paketler:
##   - ana contract paketi
##   - mobil hardening
##   - gerçek repo Android audit
##   - release readiness manifest/audit
##   - DeepSeek V4 Pro maksimum üretim profili
##   - hiyerarşik AAA ajan organizasyonu
##   - canlı görev kuyruğu ajan routing entegrasyonu
##   - ajan mailbox/event/memory/lock coordination runtime
##   - 13–21 katmanlı adaptif paralel deliberation graph

const REQUIRED_MAJOR: int = 4
const REQUIRED_MINOR: int = 6
const REQUIRED_PATCH: int = 3

var _planned_exit_code: int = 0


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_planned_exit_code = _execute_validation()
	call_deferred("_drain_and_quit")


func _drain_and_quit() -> void:
	await process_frame
	await process_frame
	quit(_planned_exit_code)


func _execute_validation() -> int:
	var version_result: Dictionary = _verify_engine_version()
	if not bool(version_result.get("ok", false)):
		printerr("CI_VERSION_FAIL: " + str(version_result.get("reason", "")))
		return 20

	print("CI_ENGINE_OK: " + str(version_result.get("version", "unknown")))

	var core_report: Dictionary = AIContractSelfTest.run_all()
	var mobile_report: Dictionary = AIMobileHardeningTest.build_report()
	var android_repo_report: Dictionary = AIAndroidRepoAuditTest.build_report()
	var release_report: Dictionary = AIReleaseReadinessTest.build_report()
	var deepseek_pro_report: Dictionary = AIDeepSeekProMaxTest.build_report()
	var organization_report: Dictionary = AIAgentOrganizationTest.build_report()
	var live_routing_report: Dictionary = AILiveAgentRoutingTest.build_report()
	var coordination_report: Dictionary = AIAgentCoordinationRuntimeTest.build_report()
	var deep_deliberation_report: Dictionary = AIAdaptiveDeepDeliberationTest.build_report()
	var reports: Array = [
		core_report,
		mobile_report,
		android_repo_report,
		release_report,
		deepseek_pro_report,
		organization_report,
		live_routing_report,
		coordination_report,
		deep_deliberation_report,
	]
	var failed: int = 0
	var passed: int = 0
	for report in reports:
		var report_failed: int = int(report.get("failed", -1))
		if report_failed < 0:
			printerr("CI_CONTRACT_FAIL: test paketi geçerli sonuç döndürmedi")
			return 21
		failed += report_failed
		passed += int(report.get("passed", 0))

	var manifest: Dictionary = _read_release_manifest()
	var expected_count: int = int(
		(manifest.get("automatic", {}) as Dictionary).get(
			"expected_test_count", 0
		)
	)
	if expected_count <= 0:
		printerr("CI_RELEASE_FAIL: expected_test_count okunamadı")
		return 23
	if passed + failed != expected_count:
		printerr(
			"CI_RELEASE_FAIL: manifest test sayısı %d, gerçek toplam %d" % [
				expected_count,
				passed + failed,
			]
		)
		return 24

	if failed > 0:
		printerr(
			"CI_CONTRACT_FAIL: %d test başarısız, %d test geçti" % [
				failed,
				passed,
			]
		)
		return 22

	print("CI_RELEASE_MANIFEST_OK: %d test bekleniyor ve çalıştı" % expected_count)
	print("CI_CONTRACT_OK: %d test geçti" % passed)
	return 0


func _read_release_manifest() -> Dictionary:
	var file := FileAccess.open(
		"res://release/readiness_manifest.json", FileAccess.READ
	)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


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
