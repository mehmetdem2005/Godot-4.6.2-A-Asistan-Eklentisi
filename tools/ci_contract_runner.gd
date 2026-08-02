@tool
extends SceneTree

## Godot 4.6.3 CI kalite kapısı.
##
## Headless çalışır, motor sürümünü doğrular ve tüm contract/self-test
## paketini çalıştırır. Bir test bile başarısızsa süreç sıfır olmayan
## çıkış koduyla kapanır; CI sahte başarı üretemez.
##
## Faz 7 mobil sertleştirme ve gerçek-repo Android audit paketleri ayrı
## rapor üretir ama ana contract toplamına eklenir. Böylece responsive
## veya Android yapılandırma regresyonu aynı zorunlu kapıyı kırar.
##
## Runtime hygiene: test raporu ve geçici nesneler stack'ten çıktıktan
## sonra iki process frame beklenir. Böylece queue_free/deferred cleanup
## işlemleri tamamlanmadan motor zorla kapatılmaz.

const REQUIRED_MAJOR: int = 4
const REQUIRED_MINOR: int = 6
const REQUIRED_PATCH: int = 3

var _planned_exit_code: int = 0


func _initialize() -> void:
	# _initialize içinde doğrudan ağır test + quit yapmak, geçici Resource
	# referansları hâlâ stack'teyken motoru kapatabilir. Ayrı çağrı scope'u.
	call_deferred("_run_validation")


func _run_validation() -> void:
	_planned_exit_code = _execute_validation()
	# Bu fonksiyon döndükten sonra report ve diğer lokaller serbest kalır.
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
	var repo_report: Dictionary = AIAndroidRepoAuditTest.build_report()
	var reports: Array = [core_report, mobile_report, repo_report]
	var failed: int = 0
	var passed: int = 0
	for report in reports:
		var report_failed: int = int(report.get("failed", -1))
		if report_failed < 0:
			printerr("CI_CONTRACT_FAIL: test paketi geçerli sonuç döndürmedi")
			return 21
		failed += report_failed
		passed += int(report.get("passed", 0))

	if failed > 0:
		printerr(
			"CI_CONTRACT_FAIL: %d test başarısız, %d test geçti" % [
				failed,
				passed,
			]
		)
		return 22

	print("CI_CONTRACT_OK: %d test geçti" % passed)
	return 0


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
