@tool
extends SceneTree

## Canlı API koşturucu — ADIM 1.
##
## API anahtarı ortam değişkeninden (DEEPSEEK_KEY) okunur — asla
## kaynak koda yazılmaz. AILiveConnectionTest ile şifreli diske
## yazılır, gerçek DeepSeek POST atılır, sonuç beklenir.
##
## Çalıştırma:
##   DEEPSEEK_KEY=... godot --headless --path . \
##     --script res://tools/live_api_runner.gd

const LiveTest := preload(
	"res://addons/ai_assistant/router/live_connection_test.gd"
)

var _node: Node = null
var _done: bool = false
var _started: bool = false
var _elapsed: float = 0.0


func _initialize() -> void:
	var key: String = OS.get_environment("DEEPSEEK_KEY")
	if key.is_empty():
		print("HATA: DEEPSEEK_KEY ortam değişkeni boş")
		quit(2)
		return

	_node = LiveTest.new()
	get_root().add_child(_node)
	_node.test_progress.connect(func(step: String) -> void:
		print("  [adım] " + step)
	)
	_node.test_finished.connect(_on_finished)


func _begin() -> void:
	var key: String = OS.get_environment("DEEPSEEK_KEY")
	var saved: Dictionary = _node.save_api_key(key)
	print("=== ANAHTAR KAYDI ===")
	print("  saved=" + str(saved.get("saved", false))
		+ "  reason=" + str(saved.get("reason", "")))
	if not bool(saved.get("saved", false)):
		quit(3)
		return
	print("=== CANLI DEEPSEEK ÇAĞRISI BAŞLIYOR ===")
	var started: bool = _node.run_test()
	if not started:
		print("HATA: run_test() başlatılamadı")


func _on_finished(result: Dictionary) -> void:
	print("=== SONUÇ ===")
	print("  ok=" + str(result.get("ok", false)))
	print("  message=" + str(result.get("message", "")))
	print("  latency_ms=" + str(result.get("latency_ms", 0)))
	print("  reply=" + str(result.get("reply", "")))
	if bool(result.get("ok", false)):
		print("SONUC: CANLI_API_TAMAM")
	else:
		print("SONUC: CANLI_API_BASARISIZ")
	_done = true


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _started:
		_started = true
		_begin()
		return false
	if _done:
		quit(0)
		return true
	if _elapsed > 45.0:
		print("HATA: 45s zaman aşımı — yanıt gelmedi")
		print("SONUC: CANLI_API_ZAMAN_ASIMI")
		quit(4)
		return true
	return false
