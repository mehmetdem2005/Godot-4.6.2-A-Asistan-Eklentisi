@tool
class_name AIMainPanelController
extends RefCounted

## MainPanelController — ana panelin BEYNİ (Aşama 5).
##
## SORUN (yapısal eksik): ana eklentinin plugin.cfg'si yoktu, hiç
## görünür panel yoktu. View-model'ler hazırdı ama hiçbiri editöre
## bağlı değildi. "Eklenti açılır / izlenebilir / yönetilebilir /
## ayarlar çalışır" maddeleri yapısal olarak imkânsızdı.
##
## ÇÖZÜM: Panelin tüm KARAR mantığını tutan saf RefCounted kontrolcü.
## Görsel Control (ai_studio_screen.gd) ince kabuktur, mantık burada —
## böylece panel davranışı sahnesiz test edilebilir (proje disiplini:
## her şey taranır/test edilir).
##
## Sorumluluk:
##   - Ayarlar (SettingsModel) + API anahtarı (api_key_store) — gerçek
##     etki, "Ayarlar sekmesi çalışır" (#5).
##   - Görev gönderme ön koşulları — boş görev / anahtarsız / canlı
##     kapalı reddedilir (mock policy: sahte "başladı" yok).
##   - Sekme durumu (9 sekme erişimi, #4) + durum metni (#2).
##
## Gerçek çalıştırma AIPipelineOrchestrator (Aşama 4c, kanıtlandı)
## ile dock tarafında yapılır; bu kontrolcü onu YÖNETİR, ASENKRON
## ağ adımını içermez (test edilebilir kalır).

const PROVIDER: String = "deepseek"

## Kullanıcının seçebileceği DeepSeek modelleri (Ayarlar görünümü).
const ALLOWED_MODELS: Array = ["deepseek-chat", "deepseek-reasoner"]

var settings: AISettingsModel = null
var state: AIWorkspaceState = null
var memory_manager: AIMemoryManager = null
var sync_queue: AIOfflineSyncQueue = null
var _key_store: AIAPIKeyStore = null
var _status: String = "Hazır"
var _last_result: Dictionary = {}
var _model: String = "deepseek-chat"
var _feed: AIFeedEmitter = null
var _feed_model: AILiveFeedModel = null


func _init() -> void:
	settings = AISettingsModel.new()
	state = AIWorkspaceState.new()
	memory_manager = AIMemoryManager.new()
	sync_queue = AIOfflineSyncQueue.new()
	_key_store = AIAPIKeyStore.new()
	_key_store.load_from_disk()
	# Anahtar varsa canlı mod kendiliğinden açık — ayrı bir "canlı mod"
	# kavramı kullanıcıya gösterilmez (anahtar = gerçekten çalış demek).
	settings.set_live_mode(_key_store.has_key(PROVIDER))
	_feed = AIFeedEmitter.new()
	_feed_model = AILiveFeedModel.new()
	_feed_model.attach_to(_feed)


# ============================================================
# AYARLAR — gerçek etki (#5)
# ============================================================

## API anahtarını şifreli olarak kaydeder. Boş anahtar reddedilir.
## Dönen: {ok, reason}
func save_api_key(plaintext: String) -> Dictionary:
	if plaintext.strip_edges().is_empty():
		return {"ok": false, "reason": "API anahtarı boş olamaz"}
	var res: Dictionary = _key_store.store_key(PROVIDER, plaintext)
	var ok: bool = bool(res["saved"])
	if ok:
		# Anahtar kaydedildi → canlı mod otomatik açılır (ayrı anahtar yok).
		settings.set_live_mode(true)
	return {"ok": ok, "reason": str(res["reason"])}


## Kayıtlı API anahtarı var mı?
func has_api_key() -> bool:
	return _key_store.has_key(PROVIDER)


## Kayıtlı API anahtarını siler ve canlı modu kapatır.
## Dönen: silinecek anahtar var mıydı.
func clear_api_key() -> bool:
	var existed: bool = _key_store.delete_key(PROVIDER)
	settings.set_live_mode(false)
	return existed


## Çözülmüş API anahtarını döndürür (router'a vermek için).
## Dönen: {ok, key, reason}
func resolve_api_key() -> Dictionary:
	var r: Dictionary = _key_store.retrieve_key(PROVIDER)
	return {
		"ok": bool(r["ok"]),
		"key": str(r.get("key", "")),
		"reason": str(r.get("reason", "")),
	}


## Canlı modu elle ayarlar (iç kullanım/test). Normalde anahtarla
## otomatik yönetilir — kullanıcıya ayrı anahtar gösterilmez.
func set_live_mode(value: bool) -> void:
	settings.set_live_mode(value)


## Yapay zeka modelini ayarlar. İzinli liste dışı → reddedilir (false).
func set_model(model_id: String) -> bool:
	if not ALLOWED_MODELS.has(model_id):
		push_warning("MainPanelController: geçersiz model %s" % model_id)
		return false
	_model = model_id
	return true


## Seçili model adı.
func model_name() -> String:
	return _model


# ============================================================
# KONUŞMA LOG'U — sohbet ekranı (#2 izlenebilirlik)
# ============================================================

## Sohbete bir mesaj ekler. role: "user" | "assistant" | "system".
func add_message(role: String, text: String) -> void:
	var sev: int = AIFeedEvent.Severity.INFO
	_feed.emit_event("CHAT", text, role, sev)


## Sohbet mesajları — UI çizer. [{role, text}] (en eski → en yeni).
func messages() -> Array:
	var out: Array = []
	for e in _feed_model.visible_events():
		var ev: AIFeedEvent = e
		out.append({"role": ev.owner_role, "text": ev.message})
	return out


## Sohbet olay yayıncısı — workspace Canlı Akış sekmesi buna bağlanır.
func feed() -> AIFeedEmitter:
	return _feed


# ============================================================
# SİSTEM SIFIRLAMA — Ayarlar (working + kuyruk temizlenir)
# ============================================================

## Çalışma belleğini ve senkron kuyruğunu sıfırlar. Episodic /
## procedural KORUNUR (Aşama 4b hata↔bellek köprüsü onlara dayanır).
## Dönen: {ok, working_cleared, queue_cleared, message}
func reset_memory_and_queue() -> Dictionary:
	memory_manager.working.clear()
	sync_queue.clear()
	_status = "✓ Hafıza (çalışma) ve kuyruk sıfırlandı"
	return {
		"ok": true,
		"working_cleared": memory_manager.working.count() == 0,
		"queue_cleared": sync_queue.size() == 0,
		"message": _status,
	}


# ============================================================
# GÖREV ÖN KOŞULLARI — mock policy
# ============================================================

# ============================================================
# NİYET AYRIMI — sohbet mi, kod üretimi mi
# ============================================================

## Kullanıcı niyeti: düz sohbet mi yoksa kod/dosya üretimi mi.
enum Intent { CHAT, BUILD }

## Kod/üretim sinyali veren kökler (nesne/güçlü fiil). Sade "yap"
## bilerek YOK — "ne yapabilirsin" sohbettir.
const BUILD_HINTS: Array = [
	"üret", "uret", "oluştur", "olustur", "script", "skript",
	"kod yaz", "kodla", "node", "sahne", "scene", "shader",
	"fonksiyon", "function", "sınıf", " class ", ".gd", ".tscn",
	"generate", "create ", "implement", "refactor", "build a",
	"make a", "make me", "write a", "yaz:", "düzelt", "duzelt",
	"ekle ", "oyun", "game",
]

## Açıkça sohbet olan selam/küçük konuşma.
const CHAT_HINTS: Array = [
	"merhaba", "selam", "selamün", "hey", "hello", "hi ", "hi.",
	"günaydın", "gunaydin", "nasılsın", "nasilsin", "naber",
	"teşekkür", "tesekkur", "sağ ol", "sag ol", "kimsin",
	"ne yapabilirsin", "yardım", "yardim",
]


## Mesajın niyetini sezgisel sınıflar. Çevrimdışı, deterministik.
## Selam/soru → CHAT; üretim sinyali → BUILD.
func classify_intent(text: String) -> int:
	var t: String = text.strip_edges().to_lower()
	if t.is_empty():
		return Intent.CHAT
	for g in CHAT_HINTS:
		if t == str(g).strip_edges() or t.begins_with(str(g)):
			return Intent.CHAT
	# Soru ya da çok kısa → sohbet (BUILD kökü olsa bile soru güvenli)
	if t.ends_with("?") or t.split(" ", false).size() <= 2:
		return Intent.CHAT
	for b in BUILD_HINTS:
		if t.contains(str(b)):
			return Intent.BUILD
	return Intent.CHAT


## Bir görev çalıştırılabilir mi? Boş görev / anahtarsız → açık ret
## (sahte başlatma YOK). Anahtar varsa zaten canlı çalışılır — ayrı
## "canlı mod" engeli kullanıcıya gösterilmez.
## Dönen: {ok, reason}
func can_run_task(task_text: String) -> Dictionary:
	if task_text.strip_edges().is_empty():
		return {"ok": false, "reason": "Görev tanımı boş"}
	if not has_api_key():
		return {
			"ok": false,
			"reason": "API anahtarı yok — Ayarlar'dan girin",
		}
	return {"ok": true, "reason": ""}


## Görev için varsayılan hedef dosya yolu üretir.
func default_target_path(task_text: String) -> String:
	var slug: String = ""
	for c in task_text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif c == " " and slug.length() > 0 and not slug.ends_with("_"):
			slug += "_"
		if slug.length() >= 24:
			break
	if slug.is_empty():
		slug = "uretim"
	return "user://ai_assistant/uretilen/%s.gd" % slug


# ============================================================
# SEKME DURUMU (#4) + DURUM METNİ (#2)
# ============================================================

## 9 sekme adı listesi.
func tab_names() -> Array:
	var names: Array = []
	for t in state.all_tabs():
		names.append(t["name"])
	return names


## Sekme değiştir (0..8).
func switch_tab(tab: int) -> bool:
	return state.switch_tab(tab)


## Aktif sekme adı.
func active_tab_name() -> String:
	return state.active_tab_name()


## Durum metnini ayarlar (panel üst bilgisi — #2 izlenebilirlik).
func set_status(text: String) -> void:
	_status = text


## Güncel durum metni.
func status_text() -> String:
	return _status


## Pipeline sonucunu kaydeder ve durum metnine yansıtır.
func record_result(result: Dictionary) -> void:
	_last_result = result
	var ok: bool = bool(result.get("ok", false))
	var stage: String = str(result.get("stage", "?"))
	if ok:
		_status = "✓ Tamamlandı (%s): %s" % [
			stage, str(result.get("message", ""))
		]
	else:
		_status = "✗ Durdu (%s): %s" % [
			stage, str(result.get("message", ""))
		]


## Son pipeline sonucu (boş = henüz yok).
func last_result() -> Dictionary:
	return _last_result


## Panel özet durumu — UI başlığı için.
func summary() -> Dictionary:
	return {
		"status": _status,
		"live_mode": settings.live_mode,
		"has_key": has_api_key(),
		"active_tab": active_tab_name(),
		"automation": settings.automation_name(),
		"model": _model,
	}
