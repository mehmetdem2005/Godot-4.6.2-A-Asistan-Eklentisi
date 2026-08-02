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

## Kullanıcıya gösterilen üretim profilleri. Legacy model kimlikleri yalnız
## eski kayıtları okumak için kabul edilir; arayüzde gösterilmez.
const MODEL_PRO_MAX_LABEL: String = "DeepSeek V4 Pro — MAX"
const MODEL_OPTIONS: Array = [
	{
		"id": AIDeepSeekModelPolicy.MODEL_PRO,
		"label": MODEL_PRO_MAX_LABEL,
		"profile": "max",
		"thinking": "maximum",
	},
]
const ALLOWED_MODELS: Array = [AIDeepSeekModelPolicy.MODEL_PRO]

var settings: AISettingsModel = null
var state: AIWorkspaceState = null
var memory_manager: AIMemoryManager = null
var sync_queue: AIOfflineSyncQueue = null
var _key_store: AIAPIKeyStore = null
var _status: String = "Hazır"
var _last_result: Dictionary = {}
var _model: String = AIDeepSeekModelPolicy.MODEL_PRO
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


## Arayüzde gösterilecek kanonik model seçenekleri.
func model_options() -> Array:
	return MODEL_OPTIONS.duplicate(true)


## Yapay zeka modelini ayarlar. Legacy DeepSeek kimlikleri eski kayıtlar
## için V4 Pro'ya normalize edilir; bilinmeyen sağlayıcı/model reddedilir.
func set_model(model_id: String) -> bool:
	var requested: String = model_id.strip_edges()
	if AIDeepSeekModelPolicy.LEGACY_MODELS.has(requested):
		requested = AIDeepSeekModelPolicy.canonical_model(requested)
	if not ALLOWED_MODELS.has(requested):
		push_warning("MainPanelController: geçersiz model %s" % model_id)
		return false
	_model = requested
	return true


## Seçili kanonik model kimliği.
func model_name() -> String:
	return _model


## Seçili modelin kullanıcıya gösterilecek adı.
func model_display_name() -> String:
	for option in MODEL_OPTIONS:
		if str(option.get("id", "")) == _model:
			return str(option.get("label", _model))
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


## Çok-turlu hafıza: LLM'e beslenecek gerçek konuşma geçmişi.
## messages() kaynaktır ama sistem/iz satırları (… ✓ ⚠ ✗) AYIKLANIR —
## yalnız gerçek user/assistant turları. En son user turu DROP edilir
## (think_chat güncel mesajı kendi ekler — _on_send sırası gereği).
## Kayan pencere: en yeni max_turns tur, toplam char_budget altına
## kırpılır (en eski taşan baştan atılır). Dönen: [{role, content}]
## eski→yeni. Kırpma burada (controller) — köprü saf/test edilebilir.
func conversation_history(
	max_turns: int = 12, char_budget: int = 6000
) -> Array:
	var clean: Array = []
	for m in messages():
		var role: String = str(m.get("role", ""))
		var text: String = str(m.get("text", "")).strip_edges()
		if role != "user" and role != "assistant":
			continue
		if text.is_empty():
			continue
		# İz/durum satırları (record_result / _on_progress) gerçek
		# konuşma değil — bağlama girmemeli.
		var head: String = text.substr(0, 1)
		if head == "…" or head == "✓" or head == "⚠" or head == "✗":
			continue
		clean.append({"role": role, "content": text})
	# Güncel kullanıcı mesajı (son user turu) think_chat tarafından
	# ayrıca eklenir — geçmişte tekrarlanmasın.
	if not clean.is_empty() and str(clean[-1]["role"]) == "user":
		clean.remove_at(clean.size() - 1)
	# Kayan pencere: tur sayısı.
	if clean.size() > max_turns:
		clean = clean.slice(clean.size() - max_turns)
	# Kayan pencere: karakter bütçesi (en eskiyi baştan at).
	var total: int = 0
	for t in clean:
		total += str(t["content"]).length()
	while clean.size() > 1 and total > char_budget:
		total -= str(clean[0]["content"]).length()
		clean.remove_at(0)
	return clean


## Asistanın GERÇEK proje görünümü (salt-okunur). Sohbet/üretim
## bağlamına gömülür — "erişimim yok" sorunu giderilir.
func project_context() -> String:
	return AIProjectScanner.new().project_summary()


## İnteraktif dosya okuma niyeti: "X.gd oku/aç/göster" gibi mesajlarda
## istenen dosyanın GERÇEK içeriğini (salt-okunur, path_guard korumalı)
## sohbet/üretim bağlamına gömülecek metin olarak döndürür. İstek
## yoksa / dosya güvensizse boş string (dürüst — uydurma yok).
## Saf: yalnız diskten okur, ağ yok — test edilebilir.
const READ_VERBS: Array = [
	"oku", "aç", "ac", "göster", "goster", "read", "open", "show",
	"incele", "bak",
]


func requested_file_context(text: String) -> String:
	var low: String = text.to_lower()
	var has_verb: bool = false
	for v in READ_VERBS:
		if low.contains(str(v)):
			has_verb = true
			break
	if not has_verb:
		return ""
	var path: String = _extract_path(text)
	if path.is_empty():
		return ""
	var r: Dictionary = AIProjectScanner.new().read_file(path)
	if not bool(r.get("ok", false)):
		return ""
	return (
		"\n\nİSTENEN DOSYA (%s, salt-okunur gerçek içerik):\n%s"
		% [path, str(r["content"])]
	)


## Mesajdan res:// / user:// ile başlayan ilk yol belirtecini çıkarır
## (sondaki noktalama temizlenir). Yoksa boş.
func _extract_path(text: String) -> String:
	for raw in text.split(" ", false):
		var tok: String = str(raw).strip_edges()
		if tok.begins_with("res://") or tok.begins_with("user://"):
			while tok.length() > 0 and tok.right(1) in [
				".", ",", "?", "!", ")", "(", "'", "\"", ":", ";"
			]:
				tok = tok.left(tok.length() - 1)
			return tok
	return ""


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

## GÜÇLÜ üretim komutu — TAM sözcük (emir kipi). Bunlar kısa/2-kelimelik
## olsa da BUILD'dir ("sen oluştur", "oyun yap", "node ekle"). Telefon
## testi: kısa emirler yanlışlıkla CHAT'e düşüp asistan "yazma yetkim
## yok" diyordu — bu liste o kör noktayı kapatır.
const STRONG_BUILD_TOKENS: Array = [
	"oluştur", "olustur", "üret", "uret", "yap", "yarat", "yaz",
	"kodla", "inşa", "insa", "ekle", "düzelt", "duzelt", "generate",
	"implement", "build", "create", "refactor", "make", "write",
]

## GÜÇLÜ üretim kalıbı — çok sözcüklü (alt-dize eşleşmesi).
const STRONG_BUILD_PHRASES: Array = [
	"görev zincir", "gorev zincir", "make me", "make a", "build a",
	"write a",
]


## Bir metni sözcüklere böler, çevresel noktalamayı temizler.
func _tokens(t: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw in t.replace("\n", " ").replace("\t", " ").split(" ", false):
		var w: String = str(raw)
		while w.length() > 0 and w.substr(0, 1) in [
			"(", "\"", "'", "*", "-", "`",
		]:
			w = w.substr(1)
		while w.length() > 0 and w.right(1) in [
			".", ",", "?", "!", ")", "(", "'", "\"", ":", ";", "*", "`",
		]:
			w = w.left(w.length() - 1)
		if not w.is_empty():
			out.append(w)
	return out


## Mesajın niyetini sezgisel sınıflar. Çevrimdışı, deterministik.
## Sıra: selam → açık soru(?) → GÜÇLÜ emir (kısa olsa da BUILD) →
## zayıf BUILD ipucu → CHAT. Böylece "sen oluştur"/"oyun yap" gibi
## kısa üretim komutları artık doğru biçimde BUILD'e gider.
func classify_intent(text: String) -> int:
	var t: String = text.strip_edges().to_lower()
	if t.is_empty():
		return Intent.CHAT
	for g in CHAT_HINTS:
		if t == str(g).strip_edges() or t.begins_with(str(g)):
			return Intent.CHAT
	# Soru → açıklama beklenir, sohbet (kullanıcı '?'yi atınca üretir).
	if t.ends_with("?"):
		return Intent.CHAT
	# GÜÇLÜ emir: kısa/2-kelime olsa bile üretim (kör nokta düzeltmesi).
	var toks: PackedStringArray = _tokens(t)
	for tok in toks:
		if STRONG_BUILD_TOKENS.has(tok):
			return Intent.BUILD
	for ph in STRONG_BUILD_PHRASES:
		if t.contains(str(ph)):
			return Intent.BUILD
	# Zayıf ipucu (nesne adı vb.) — kısa-soru güvenliği artık gerekmiyor.
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
	# AAA yerleşim: üretilen scriptler res://game/scripts/ altında
	# (proje İÇİNDE — Godot class_name kaydeder; path_guard sıkıştırır).
	return "res://game/scripts/%s.gd" % slug


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
		"model_label": model_display_name(),
	}
