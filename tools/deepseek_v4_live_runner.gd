@tool
extends SceneTree

## DeepSeek V4 canlı sağlayıcı doğrulayıcısı — Faz 6.
##
## Amaç: yalnız HTTP 200 görmek değil; V4 Pro model kimliği, token
## kullanımı, finish_reason, gecikme, request eşlemesi ve içerik bütünlüğünü
## aynı gerçek çağrıda doğrulamak.
##
## Çalıştırma:
##   DEEPSEEK_KEY=... godot --headless --path . \
##     --script res://tools/deepseek_v4_live_runner.gd
##
## Alternatif ortam değişkeni: DEEPSEEK_API_KEY
##
## Güvenlik: anahtar hiçbir zaman yazdırılmaz, dosyaya kaydedilmez veya
## sonuç sözlüğüne eklenmez. Başarı raporu yalnız güvenli metadata içerir.

const TIMEOUT_SECONDS: float = 120.0

var _bridge: AIAgentLiveBridge = null
var _secret_key: String = ""
var _started: bool = false
var _finished: bool = false
var _exit_code: int = 1
var _elapsed: float = 0.0


func _initialize() -> void:
	_secret_key = OS.get_environment("DEEPSEEK_KEY").strip_edges()
	if _secret_key.is_empty():
		_secret_key = OS.get_environment("DEEPSEEK_API_KEY").strip_edges()
	if _secret_key.is_empty():
		print("V4_LIVE_MISSING_KEY: DEEPSEEK_KEY veya DEEPSEEK_API_KEY gerekli")
		quit(2)
		return

	var router := AIProviderRouter.new()
	router.set_api_key(AIProviderRequest.Provider.DEEPSEEK, _secret_key)

	_bridge = AIAgentLiveBridge.new()
	_bridge.name = "DeepSeekV4LiveBridge"
	get_root().add_child(_bridge)
	_bridge.attach_router(router)
	_bridge.thought_progress.connect(_on_progress)
	_bridge.thought_completed.connect(_on_completed)


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _started:
		_started = true
		_begin_live_request()
		return false

	if _finished:
		_secret_key = ""
		quit(_exit_code)
		return true

	if _elapsed > TIMEOUT_SECONDS:
		print("V4_LIVE_TIMEOUT: %.1f saniye içinde yanıt alınamadı" % TIMEOUT_SECONDS)
		_secret_key = ""
		quit(4)
		return true
	return false


func _begin_live_request() -> void:
	print("=== DEEPSEEK V4 PRO CANLI DOĞRULAMA ===")
	print("Beklenen model: " + AIDeepSeekModelPolicy.MODEL_PRO)
	print("Beklenen politika: CODE amacı, thinking=disabled")
	var started: bool = _bridge.think_live(
		AICellRoles.Role.CODE_ENGINEER,
		"Sadece tek satır düz metin olarak V4_CANLI_TAMAM yaz. "
		+ "Markdown, açıklama veya ek karakter kullanma.",
		{},
		AIDeepSeekModelPolicy.MODEL_PRO
	)
	if not started:
		print("V4_LIVE_START_FAILED: canlı istek başlatılamadı")
		_exit_code = 3
		_finished = true


func _on_progress(step: String) -> void:
	print("  [adım] " + step)


func _on_completed(result: Dictionary) -> void:
	var failures: Array[String] = []
	var content: String = str(result.get("content", "")).strip_edges()
	var provider: int = int(result.get("provider", -1))
	var provider_name: String = str(result.get("provider_name", ""))
	var model: String = str(result.get("model", ""))
	var input_tokens: int = int(result.get("input_tokens", 0))
	var output_tokens: int = int(result.get("output_tokens", 0))
	var total_tokens: int = int(result.get("total_tokens", 0))
	var finish_reason: String = str(result.get("finish_reason", ""))
	var http_status: int = int(result.get("http_status", 0))
	var latency_ms: int = int(result.get("latency_ms", 0))
	var request_ref: String = str(result.get("request_ref", ""))
	var from_cache: bool = bool(result.get("from_cache", false))

	if not bool(result.get("ok", false)):
		failures.append("çağrı başarısız: " + str(result.get("status_note", "?")))
	if not bool(result.get("llm_called", false)):
		failures.append("gerçek LLM çağrısı işaretlenmedi")
	if provider != AIProviderRequest.Provider.DEEPSEEK:
		failures.append("provider DeepSeek değil")
	if provider_name != "deepseek":
		failures.append("provider_name 'deepseek' değil")
	if model != AIDeepSeekModelPolicy.MODEL_PRO:
		failures.append("gerçek model V4 Pro değil: " + model)
	if http_status < 200 or http_status >= 300:
		failures.append("HTTP başarı durumu yok: %d" % http_status)
	if content.is_empty():
		failures.append("yanıt içeriği boş")
	if input_tokens <= 0:
		failures.append("input_tokens raporlanmadı")
	if output_tokens <= 0:
		failures.append("output_tokens raporlanmadı")
	if total_tokens != input_tokens + output_tokens:
		failures.append("total_tokens tutarsız")
	if finish_reason.is_empty():
		failures.append("finish_reason raporlanmadı")
	if latency_ms <= 0:
		failures.append("latency_ms raporlanmadı")
	if request_ref.is_empty():
		failures.append("request_ref raporlanmadı")
	if from_cache:
		failures.append("ilk canlı doğrulama cache sonucu olamaz")
	if not _secret_key.is_empty() and str(result).contains(_secret_key):
		failures.append("API anahtarı sonuç sözlüğüne sızdı")

	print("=== GÜVENLİ SAĞLAYICI METADATA ===")
	print("  provider=" + provider_name)
	print("  model=" + model)
	print("  http_status=" + str(http_status))
	print("  input_tokens=" + str(input_tokens))
	print("  output_tokens=" + str(output_tokens))
	print("  total_tokens=" + str(total_tokens))
	print("  finish_reason=" + finish_reason)
	print("  latency_ms=" + str(latency_ms))
	print("  request_ref_present=" + str(not request_ref.is_empty()))
	print("  content_length=" + str(content.length()))

	if failures.is_empty():
		print("V4_LIVE_OK")
		_exit_code = 0
	else:
		for failure in failures:
			print("  HATA: " + failure)
		print("V4_LIVE_FAILED")
		_exit_code = 1
	_finished = true
