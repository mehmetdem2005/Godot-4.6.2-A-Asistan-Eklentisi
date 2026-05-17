@tool
extends SceneTree

## Canlı AJAN koşturucu — Aşama 4a kanıtı.
##
## AIAgentLiveBridge ile bir Pilot Cell ajanını GERÇEK DeepSeek'e
## bağlar: rol promptu + görev → router → asenkron POST → cevap.
## ADIM 1'in ajan seviyesindeki karşılığı.
##
## DEEPSEEK_KEY=... godot --headless --path . \
##   --script res://tools/agent_live_runner.gd

const Bridge := preload(
	"res://addons/ai_assistant/pilot_cell/agent_live_bridge.gd"
)
const KeyStore := preload(
	"res://addons/ai_assistant/router/api_key_store.gd"
)

var _bridge: Node = null
var _done: bool = false
var _started: bool = false
var _elapsed: float = 0.0


func _initialize() -> void:
	var key: String = OS.get_environment("DEEPSEEK_KEY")
	if key.is_empty():
		print("HATA: DEEPSEEK_KEY boş")
		quit(2)
		return

	var store := KeyStore.new()
	store.load_from_disk()
	store.store_key("deepseek", key)

	var router := AIProviderRouter.new()
	router.set_api_key(AIProviderRequest.Provider.DEEPSEEK, key)

	_bridge = Bridge.new()
	get_root().add_child(_bridge)
	_bridge.attach_router(router)
	_bridge.thought_progress.connect(func(s: String) -> void:
		print("  [adım] " + s)
	)
	_bridge.thought_completed.connect(_on_done)


func _begin() -> void:
	print("=== AJAN CANLI DÜŞÜNME BAŞLIYOR (CodeEngineer) ===")
	var ok: bool = _bridge.think_live(
		AICellRoles.Role.CODE_ENGINEER,
		"Godot 4 GDScript: ekrana 'merhaba' yazan kısa bir _ready yaz."
	)
	if not ok:
		print("HATA: think_live başlatılamadı")


func _on_done(result: Dictionary) -> void:
	print("=== SONUÇ ===")
	print("  ok=" + str(result.get("ok", false)))
	print("  role=" + str(result.get("role_name", "")))
	print("  llm_called=" + str(result.get("llm_called", false)))
	print("  latency_ms=" + str(result.get("latency_ms", 0)))
	print("  status=" + str(result.get("status_note", "")))
	var content: String = str(result.get("content", ""))
	print("  --- LLM ÇIKTISI (ilk 400) ---")
	print(content.left(400))
	if bool(result.get("ok", false)) and not content.is_empty():
		print("SONUC: AJAN_CANLI_TAMAM")
	else:
		print("SONUC: AJAN_CANLI_BASARISIZ")
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
	if _elapsed > 60.0:
		print("HATA: 60s zaman aşımı")
		print("SONUC: AJAN_CANLI_ZAMAN_ASIMI")
		quit(4)
		return true
	return false
