@tool
class_name AIDebugSandboxResult
extends RefCounted

## SandboxRunResult — sandbox çalıştırma sonucu (Madde 02 / Debug Loop).
##
## sandbox_runner.gd gerçek bir SubViewport'ta kod çalıştırır — bu
## Node işidir, sahnesiz test edilemez. AMA çalıştırmanın SONUCU bir
## veri yapısıdır ve burada modellenir: çalışma başarılı mıydı, hangi
## hatalar/uyarılar çıktı, stdout/stderr ne oldu.
##
## Debug Loop'un geri kalanı (classifier, analyzer, orchestrator)
## bu modeli tüketir. Runner'ın kendisi sahnede; sonuç burada
## test edilebilir.
##
## Mock policy: sonuç gerçek çalıştırmadan dolar; sahte "başarılı"
## yok — parse hatası varsa açıkça başarısız.

## Çalıştırma sonucu durumu.
enum RunStatus { SUCCESS, PARSE_FAILED, RUNTIME_FAILED, TIMEOUT, CRASHED }

const STATUS_NAMES: Dictionary = {
	RunStatus.SUCCESS: "success",
	RunStatus.PARSE_FAILED: "parse_failed",
	RunStatus.RUNTIME_FAILED: "runtime_failed",
	RunStatus.TIMEOUT: "timeout",
	RunStatus.CRASHED: "crashed",
}


## Çalıştırma durumu.
var status: int = RunStatus.SUCCESS

## Yakalanan hata satırları (Godot stderr'den).
var errors: PackedStringArray = PackedStringArray()

## Yakalanan uyarı satırları.
var warnings: PackedStringArray = PackedStringArray()

## Standart çıktı.
var stdout_text: String = ""

## Çalışma süresi (ms).
var duration_ms: int = 0


# ============================================================
# SONUÇ KURMA
# ============================================================

## Bir hata satırı ekler.
func add_error(error_line: String) -> void:
	if not error_line.strip_edges().is_empty():
		errors.append(error_line)


## Bir uyarı satırı ekler.
func add_warning(warning_line: String) -> void:
	if not warning_line.strip_edges().is_empty():
		warnings.append(warning_line)


## Durumu ayarlar.
func set_status(p_status: int) -> void:
	if STATUS_NAMES.has(p_status):
		status = p_status


# ============================================================
# SORGULAMA
# ============================================================

## Çalıştırma başarılı mı?
func is_success() -> bool:
	return status == RunStatus.SUCCESS and errors.is_empty()


## Çalıştırma başarısız mı (herhangi bir sebepten)?
func is_failure() -> bool:
	return not is_success()


## Parse (sözdizimi) aşamasında mı başarısız oldu?
func failed_at_parse() -> bool:
	return status == RunStatus.PARSE_FAILED


## Durum adı.
func status_name() -> String:
	return STATUS_NAMES.get(status, "?")


## Hata sayısı.
func error_count() -> int:
	return errors.size()


## Uyarı sayısı.
func warning_count() -> int:
	return warnings.size()


## İlk hata satırı — debug loop'un düzeltmeye odaklanacağı.
## Hata yoksa boş string.
func primary_error() -> String:
	if errors.is_empty():
		return ""
	return errors[0]


## Tam sonuç sözlüğü.
func to_dict() -> Dictionary:
	return {
		"status": status_name(),
		"is_success": is_success(),
		"error_count": errors.size(),
		"warning_count": warnings.size(),
		"duration_ms": duration_ms,
	}


# ============================================================
# FABRİKA
# ============================================================

## Başarılı bir sonuç oluşturur.
static func make_success(p_duration_ms: int = 0) -> AIDebugSandboxResult:
	var result := AIDebugSandboxResult.new()
	result.status = RunStatus.SUCCESS
	result.duration_ms = p_duration_ms
	return result


## Parse hatalı bir sonuç oluşturur.
static func make_parse_failure(
	error_line: String
) -> AIDebugSandboxResult:
	var result := AIDebugSandboxResult.new()
	result.status = RunStatus.PARSE_FAILED
	result.add_error(error_line)
	return result
