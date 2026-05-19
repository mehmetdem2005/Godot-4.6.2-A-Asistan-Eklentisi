@tool
class_name AIAutonomousRepairRouter
extends RefCounted

## AutonomousRepairRouter — yakalanan hatayı LLM ONARIM isteğine
## çevirir, döngü/maliyet kontrolünü uygular (Parça 4).
##
## Kullanıcı: "outbot/script loglarında hata olursa bana sormadan
## düzelt". Bu sınıf "sormadan"ın güvenli halkası:
##   - Per-dosya AIDebugRetryOrchestrator (MAX_RETRIES=3, aynı imza
##     iki kez = circuit OPEN → dur, sonsuz/maliyetli döngü yok).
##   - Onarım talimatı pipeline'ın repair şablonuyla aynı dil ve
##     kısıtları kullanır (Godot 4.6 + hatalı kod + minimal düzeltme).
##   - Hedef YOLDA sandbox: yalnız res://game/ altı (AAA güvenli).
##
## SAF: ağ çağırmaz, dosya yazmaz; "onar mı, ne söylenmeli?" kararı
## verir. Pipeline çağrıyı yapar. Headless TAM test edilebilir.
##
## Mock policy: kod okunamazsa / yol sandbox dışındaysa / circuit
## açıksa SAHTE onarım YOK — açıkça reddeder.

const SAFE_PREFIX: String = "res://game/"

var _orchestrators: Dictionary = {}


## Bu hata için onarım denenmeli mi?
## Dönen: {ok, reason, attempt, circuit_open}
func should_repair(file_path: String, signature: String) -> Dictionary:
	if not file_path.begins_with(SAFE_PREFIX):
		return _no(
			"Sandbox dışı yol — otonom onarım yalnız %s altı" % SAFE_PREFIX
		)
	if signature.strip_edges().is_empty():
		return _no("Hata imzası boş — sınıflandırılamamış, atla")
	var orch: AIDebugRetryOrchestrator = _get_orch(file_path)
	if orch.is_circuit_open():
		return _no("Aynı hata tekrar — devre kesici AÇIK, döngü durdu")
	if not orch.can_retry():
		return _no("Bu dosya için onarım hakkı tükendi (MAX_RETRIES)")
	var report: Dictionary = orch.report_attempt(signature)
	if str(report.get("outcome", "")) == "gave_up":
		# Orkestratör'un sebebini KORU (devre kesici / max retry farkı
		# kullanıcı için anlamlı).
		return _no(str(report.get("reason", "Onarım hakkı tükendi")))
	return {
		"ok": true,
		"reason": "",
		"attempt": orch.attempt_count,
		"circuit_open": orch.is_circuit_open(),
	}


## Bir dosya için sayaçları sıfırla (örn. başarılı onarım sonrası).
func reset(file_path: String) -> void:
	if _orchestrators.has(file_path):
		(_orchestrators[file_path] as AIDebugRetryOrchestrator).reset()


## Pipeline'a verilecek onarım talimatını üretir. pipeline'ın repair
## şablonuyla uyumlu — aynı dil/kısıtlar (Godot 4.6, derlenebilir, tek
## parça TAM dosya).
func build_instruction(
	file_path: String, current_code: String, error_text: String
) -> String:
	return (
		"OTONOM ONARIM. Bu dosya çalışırken Godot şu hatayı verdi.\n"
		+ "HEDEF DOSYA: " + file_path + "\n"
		+ "HATA: " + error_text + "\n"
		+ "MEVCUT KOD:\n```\n" + current_code + "\n```\n"
		+ "Godot 4.6 API kurallarına UYARAK hatayı gider; TAM, "
		+ "derlenebilir düzeltilmiş dosyayı tek parça ver. Yorum/"
		+ "açıklama yazma."
	)


# ============================================================
# DAHİLİ
# ============================================================

func _get_orch(file_path: String) -> AIDebugRetryOrchestrator:
	if not _orchestrators.has(file_path):
		_orchestrators[file_path] = AIDebugRetryOrchestrator.new()
	return _orchestrators[file_path]


func _no(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"attempt": 0,
		"circuit_open": false,
	}
