@tool
class_name AIVerifierEngine
extends RefCounted

## VerifierEngine — doğrulama motoru (Layer 5).
##
## Executor (Layer 4) bir GDScript dosyası yazdı. Bu motor o kodun
## DOĞRU olduğunu kanıtlar — seviyeleri sırayla koşturur:
##   SYNTACTIC  -> SEMANTIC  -> (RUNTIME, BEHAVIORAL, PERFORMANCE sonra)
##
## Kademeli (cascading) doğrulama: bir seviye FAIL verirse, sonraki
## seviyeler çalıştırılmaz — bozuk kodu çalıştırmanın anlamı yok.
## Örnek: syntax hatası varsa semantic analiz anlamsızdır.
##
## Mock policy: uygulanmamış seviyeler SKIP/NOT_IMPLEMENTED raporlar.
## Sonuç her zaman kanıt-temelli (AIVerificationResult).

## Aktif doğrulayıcılar — sıralı.
var _syntactic: AISyntacticVerifier
var _semantic: AISemanticVerifier
var _runtime: AIRuntimeVerifier

## Bir seviye FAIL verince sonrakiler atlansın mı? Varsayılan: EVET.
## (Kademeli doğrulama — bozuk kodu derinlemesine incelemek boşa iş.)
var cascade_stop_on_fail: bool = true


func _init() -> void:
	_syntactic = AISyntacticVerifier.new()
	_semantic = AISemanticVerifier.new()
	_runtime = AIRuntimeVerifier.new()


# ============================================================
# DOĞRULAMA
# ============================================================

## Bir GDScript kaynağını tüm aktif seviyelerde doğrular.
## source_code: doğrulanacak kod. context: {task_ref, file_path...}.
## Dönen: {
##   passed: bool,            tüm seviyeler geçti mi
##   results: Array,          her seviyenin AIVerificationResult'ı
##   failed_level: String,    ilk başarısız seviye adı ("" = hepsi geçti)
##   levels_run: int,         kaç seviye çalıştırıldı
## }
func verify(source_code: String, context: Dictionary = {}) -> Dictionary:
	var results: Array = []
	var failed_level: String = ""

	# Sıralı seviye listesi — sıra önemli (syntactic önce)
	# Sıra önemli: syntactic → semantic → runtime. Kademeli durma
	# (cascade_stop_on_fail) sayesinde runtime YALNIZ derlenmiş +
	# anlamsal temiz kodda çalışır (güvenli — bozuk kod örneklenmez).
	var levels: Array = [
		{"name": "syntactic", "verifier": _syntactic},
		{"name": "semantic", "verifier": _semantic},
		{"name": "runtime", "verifier": _runtime},
	]

	for level_info in levels:
		var verifier: AIVerifyLevelBase = level_info["verifier"]
		var result: AIVerificationResult = verifier.verify(source_code, context)
		results.append(result)

		# Bu seviye başarısız mı
		if result.outcome == AIVerificationResult.Outcome.FAIL:
			failed_level = level_info["name"]
			if cascade_stop_on_fail:
				# Kademeli durdurma — kalan seviyeleri çalıştırma
				break

	var passed: bool = failed_level.is_empty()
	return {
		"passed": passed,
		"results": results,
		"failed_level": failed_level,
		"levels_run": results.size(),
	}


## Tek bir seviyede doğrular — belirli bir seviyeyi izole test etmek için.
## level: AIVerificationResult.VerifyLevel enum değeri.
## Dönen: AIVerificationResult. Bilinmeyen/uygulanmamış seviye -> SKIP.
func verify_single_level(
	source_code: String, level: int, context: Dictionary = {}
) -> AIVerificationResult:
	match level:
		AIVerificationResult.VerifyLevel.SYNTACTIC:
			return _syntactic.verify(source_code, context)
		AIVerificationResult.VerifyLevel.SEMANTIC:
			return _semantic.verify(source_code, context)
		AIVerificationResult.VerifyLevel.RUNTIME:
			return _runtime.verify(source_code, context)
		_:
			# BEHAVIORAL / PERFORMANCE — henüz uygulanmadı
			var result := AIVerificationResult.create(
				level, context.get("task_ref", "?")
			)
			result.outcome = AIVerificationResult.Outcome.SKIP
			result.message = (
				"Seviye %d henüz uygulanmadı (NOT_IMPLEMENTED)" % level
			)
			return result


## Bir Executor sonucu (yazılan dosya) doğrudan doğrulanır.
## exec_result: ExecutorEngine'in döndürdüğü AIVerificationResult.
## file_op: dosyayı geri okumak için AISandboxedFileOp.
## Executor bir dosya yazdıktan SONRA, o dosyanın içeriği doğrulanır.
## Dönen: verify() ile aynı yapı.
func verify_executor_output(
	exec_result: AIVerificationResult, file_op: AISandboxedFileOp
) -> Dictionary:
	# Executor başarısızsa doğrulanacak bir şey yok
	if exec_result.outcome != AIVerificationResult.Outcome.PASS:
		return {
			"passed": false,
			"results": [],
			"failed_level": "executor",
			"levels_run": 0,
		}

	# Yazılan dosyanın yolunu evidence'tan al
	var path: String = exec_result.evidence.get("path", "")
	if path.is_empty():
		return {
			"passed": false,
			"results": [],
			"failed_level": "no_path",
			"levels_run": 0,
		}

	# Sadece .gd dosyaları kod doğrulamasına tabi
	if not path.ends_with(".gd"):
		return {
			"passed": true,
			"results": [],
			"failed_level": "",
			"levels_run": 0,
		}

	# Dosyayı geri oku, içeriğini doğrula
	var read: Dictionary = file_op.read_file(path)
	if not read["ok"]:
		return {
			"passed": false,
			"results": [],
			"failed_level": "read_back",
			"levels_run": 0,
		}

	return verify(read["content"], {"task_ref": exec_result.task_ref})


# ============================================================
# RAPORLAMA
# ============================================================

## Bir verify() sonucundan insan-okunur özet üretir.
func summarize(verify_result: Dictionary) -> String:
	if verify_result["passed"]:
		return "Doğrulama GEÇTİ — %d seviye temiz" % verify_result["levels_run"]
	return "Doğrulama BAŞARISIZ — '%s' seviyesinde takıldı" % (
		verify_result["failed_level"]
	)


## Hangi seviyelerin gerçekten uygulandığını döndürür.
func implemented_levels() -> PackedStringArray:
	return PackedStringArray(["syntactic", "semantic", "runtime"])
