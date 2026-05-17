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
## Görsel Control (main_dock.gd) ince bir kabuktur, mantık burada —
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

var settings: AISettingsModel = null
var state: AIWorkspaceState = null
var _key_store: AIAPIKeyStore = null
var _status: String = "Hazır"
var _last_result: Dictionary = {}


func _init() -> void:
	settings = AISettingsModel.new()
	state = AIWorkspaceState.new()
	_key_store = AIAPIKeyStore.new()
	_key_store.load_from_disk()


# ============================================================
# AYARLAR — gerçek etki (#5)
# ============================================================

## API anahtarını şifreli olarak kaydeder. Boş anahtar reddedilir.
## Dönen: {ok, reason}
func save_api_key(plaintext: String) -> Dictionary:
	if plaintext.strip_edges().is_empty():
		return {"ok": false, "reason": "API anahtarı boş olamaz"}
	var res: Dictionary = _key_store.store_key(PROVIDER, plaintext)
	return {"ok": bool(res["saved"]), "reason": str(res["reason"])}


## Kayıtlı API anahtarı var mı?
func has_api_key() -> bool:
	return _key_store.has_key(PROVIDER)


## Çözülmüş API anahtarını döndürür (router'a vermek için).
## Dönen: {ok, key, reason}
func resolve_api_key() -> Dictionary:
	var r: Dictionary = _key_store.retrieve_key(PROVIDER)
	return {
		"ok": bool(r["ok"]),
		"key": str(r.get("key", "")),
		"reason": str(r.get("reason", "")),
	}


## Canlı modu ayarlar (Ayarlar sekmesi anahtarı).
func set_live_mode(value: bool) -> void:
	settings.set_live_mode(value)


# ============================================================
# GÖREV ÖN KOŞULLARI — mock policy
# ============================================================

## Bir görev çalıştırılabilir mi? Boş görev / anahtarsız / canlı
## kapalı → açık ret (sahte başlatma YOK).
## Dönen: {ok, reason}
func can_run_task(task_text: String) -> Dictionary:
	if task_text.strip_edges().is_empty():
		return {"ok": false, "reason": "Görev tanımı boş"}
	if not settings.live_mode:
		return {
			"ok": false,
			"reason": "Canlı mod kapalı — Ayarlar'dan açın",
		}
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
	}
