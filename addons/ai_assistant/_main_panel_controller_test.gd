@tool
class_name AIMainPanelControllerTest
extends RefCounted

## Ana Panel Kontrolcü Self-Test (Aşama 5).
##
## Panelin BEYNİNİ sahnesiz doğrular: API anahtarı gerçek kaydı
## (Ayarlar çalışır #5), görev ön koşulları (mock policy — boş /
## anahtarsız / canlı kapalı reddedilir), 9 sekme erişimi (#4),
## durum metni (#2). Görsel kabuk kullanıcı tarafından doğrulanır.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Panel: Anahtar", _test_empty_key_rejected()))
	results.append(_b("Panel: Anahtar", _test_key_roundtrip()))
	results.append(_b("Panel: Görev", _test_empty_task_blocked()))
	results.append(_b("Panel: Görev", _test_live_off_blocked()))
	results.append(_b("Panel: Görev", _test_key_autoenables_live()))
	results.append(_b("Panel: Görev", _test_run_ready()))
	results.append(_b("Panel: Görev", _test_target_path()))
	results.append(_b("Panel: Sekme", _test_nine_tabs()))
	results.append(_b("Panel: Durum", _test_status_and_result()))
	results.append(_b("Panel: Model", _test_model_default()))
	results.append(_b("Panel: Model", _test_model_valid_set()))
	results.append(_b("Panel: Model", _test_model_invalid_rejected()))
	results.append(_b("Panel: Sohbet", _test_chat_log()))
	results.append(_b("Panel: Sıfırla", _test_reset_clears_working_queue()))
	results.append(_b("Panel: Sıfırla", _test_reset_preserves_episodic()))
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _c() -> AIMainPanelController:
	return AIMainPanelController.new()


# ============================================================
# AYARLAR — gerçek anahtar etkisi (#5)
# ============================================================

static func _test_empty_key_rejected() -> Dictionary:
	var name := "Boş API anahtarı reddedilir"
	var c := _c()
	var r: Dictionary = c.save_api_key("   ")
	if bool(r["ok"]):
		return _fail(name, "boş anahtar kabul edilmemeli")
	return _ok(name)


static func _test_key_roundtrip() -> Dictionary:
	var name := "Anahtar kaydedilir ve çözülür (gerçek etki)"
	var c := _c()
	var saved: Dictionary = c.save_api_key("sk-test-panel-0001")
	if not bool(saved["ok"]):
		return _fail(name, "geçerli anahtar kaydedilmeli: " +
			str(saved["reason"]))
	if not c.has_api_key():
		return _fail(name, "kayıttan sonra anahtar var olmalı")
	var resolved: Dictionary = c.resolve_api_key()
	if not bool(resolved["ok"]):
		return _fail(name, "anahtar çözülememeli değil")
	if str(resolved["key"]) != "sk-test-panel-0001":
		return _fail(name, "çözülen anahtar yanlış")
	return _ok(name)


# ============================================================
# GÖREV ÖN KOŞULLARI — mock policy
# ============================================================

static func _test_empty_task_blocked() -> Dictionary:
	var name := "Boş görev reddedilir (sahte başlatma yok)"
	var c := _c()
	var g: Dictionary = c.can_run_task("   ")
	if bool(g["ok"]):
		return _fail(name, "boş görev çalıştırılmamalı")
	if not str(g["reason"]).contains("boş"):
		return _fail(name, "sebep boş görevi belirtmeli")
	return _ok(name)


static func _test_live_off_blocked() -> Dictionary:
	var name := "Anahtarsız görev reddedilir (sahte başlatma yok)"
	var c := _c()
	c.clear_api_key()  # diskte kalıcı anahtar olabilir — ön koşulu netle
	var g: Dictionary = c.can_run_task("bir oyun yap")
	if bool(g["ok"]):
		return _fail(name, "anahtarsız çalışmamalı")
	if not str(g["reason"]).contains("anahtar"):
		return _fail(name, "sebep API anahtarını belirtmeli")
	return _ok(name)


static func _test_key_autoenables_live() -> Dictionary:
	var name := "Anahtar kaydı canlı modu otomatik açar"
	var c := _c()
	c.clear_api_key()  # diskte kalıcı anahtar olabilir — ön koşulu netle
	if bool(c.summary()["live_mode"]):
		return _fail(name, "anahtar yokken canlı kapalı olmalı")
	c.save_api_key("sk-test-autolive")
	if not bool(c.summary()["live_mode"]):
		return _fail(name, "anahtar kaydı canlı modu açmalı")
	return _ok(name)


static func _test_run_ready() -> Dictionary:
	var name := "Anahtar + görev → hazır (canlı otomatik)"
	var c := _c()
	c.save_api_key("sk-test-panel-ready")
	var g: Dictionary = c.can_run_task("platform oyunu yap")
	if not bool(g["ok"]):
		return _fail(name, "tüm koşullar sağlanınca hazır olmalı: " +
			str(g["reason"]))
	return _ok(name)


static func _test_target_path() -> Dictionary:
	var name := "Hedef yol görevden türetilir"
	var c := _c()
	var p: String = c.default_target_path("Merhaba Dunya")
	if not p.begins_with("user://ai_assistant/uretilen/"):
		return _fail(name, "yol izinli user:// kökünde olmalı")
	if not p.ends_with(".gd"):
		return _fail(name, "yol .gd ile bitmeli")
	return _ok(name)


# ============================================================
# SEKME (#4) + DURUM (#2)
# ============================================================

static func _test_nine_tabs() -> Dictionary:
	var name := "9 sekme erişilebilir"
	var c := _c()
	var tabs: Array = c.tab_names()
	if tabs.size() != 9:
		return _fail(name, "9 sekme bekleniyor, %d" % tabs.size())
	if not c.switch_tab(8):
		return _fail(name, "son sekmeye geçilebilmeli")
	if c.active_tab_name().is_empty():
		return _fail(name, "aktif sekme adı boş olmamalı")
	return _ok(name)


static func _test_status_and_result() -> Dictionary:
	var name := "Durum metni ve sonuç yansıması"
	var c := _c()
	c.set_status("test durumu")
	if c.status_text() != "test durumu":
		return _fail(name, "durum metni korunmalı")
	c.record_result({"ok": true, "stage": "executed", "message": "yazıldı"})
	if not c.status_text().contains("✓"):
		return _fail(name, "başarı ✓ yansımalı")
	c.record_result({"ok": false, "stage": "verify", "message": "hata"})
	if not c.status_text().contains("✗"):
		return _fail(name, "başarısızlık ✗ yansımalı")
	return _ok(name)


# ============================================================
# MODEL SEÇİMİ (Plan B — Ayarlar)
# ============================================================

static func _test_model_default() -> Dictionary:
	var name := "Varsayılan model deepseek-chat"
	var c := _c()
	if c.model_name() != "deepseek-chat":
		return _fail(name, "varsayılan deepseek-chat olmalı: " +
			c.model_name())
	return _ok(name)


static func _test_model_valid_set() -> Dictionary:
	var name := "Geçerli model ayarlanır"
	var c := _c()
	if not c.set_model("deepseek-reasoner"):
		return _fail(name, "izinli model kabul edilmeli")
	if c.model_name() != "deepseek-reasoner":
		return _fail(name, "model güncellenmedi")
	return _ok(name)


static func _test_model_invalid_rejected() -> Dictionary:
	var name := "Geçersiz model reddedilir"
	var c := _c()
	if c.set_model("gpt-4"):
		return _fail(name, "izinsiz model kabul edilmemeli")
	if c.model_name() != "deepseek-chat":
		return _fail(name, "ret sonrası model değişmemeli")
	return _ok(name)


# ============================================================
# SOHBET LOG'U (Plan B — Sohbet ekranı)
# ============================================================

static func _test_chat_log() -> Dictionary:
	var name := "Sohbet mesajları eklenir ve sıralı listelenir"
	var c := _c()
	c.add_message("user", "merhaba")
	c.add_message("assistant", "selam")
	var msgs: Array = c.messages()
	if msgs.size() != 2:
		return _fail(name, "2 mesaj bekleniyor, %d" % msgs.size())
	if str(msgs[0]["role"]) != "user" or str(msgs[0]["text"]) != "merhaba":
		return _fail(name, "ilk mesaj kullanıcı/merhaba olmalı")
	if str(msgs[1]["role"]) != "assistant":
		return _fail(name, "ikinci mesaj asistan olmalı")
	return _ok(name)


# ============================================================
# SİSTEM SIFIRLAMA (Plan B — working+kuyruk temizlenir,
# episodic/procedural korunur — Aşama 4b köprüsü)
# ============================================================

static func _test_reset_clears_working_queue() -> Dictionary:
	var name := "Sıfırla working belleği ve kuyruğu temizler"
	var c := _c()
	c.memory_manager.working.add_content("geçici düşünce")
	c.sync_queue.enqueue("op1", "SYNC", {"x": 1}, 1000)
	if c.memory_manager.working.count() == 0:
		return _fail(name, "ön koşul: working dolu olmalı")
	if c.sync_queue.size() == 0:
		return _fail(name, "ön koşul: kuyruk dolu olmalı")
	var r: Dictionary = c.reset_memory_and_queue()
	if not bool(r["ok"]):
		return _fail(name, "sıfırlama ok dönmeli")
	if c.memory_manager.working.count() != 0:
		return _fail(name, "working temizlenmeli")
	if c.sync_queue.size() != 0:
		return _fail(name, "kuyruk temizlenmeli")
	return _ok(name)


static func _test_reset_preserves_episodic() -> Dictionary:
	var name := "Sıfırla episodic/procedural'ı KORUR (4b köprüsü)"
	var c := _c()
	c.memory_manager.episodic.add_content("çözülmüş hata kaydı")
	c.memory_manager.procedural.add_content("öğrenilmiş prosedür")
	c.memory_manager.working.add_content("geçici")
	c.reset_memory_and_queue()
	if c.memory_manager.episodic.count() != 1:
		return _fail(name, "episodic korunmalı")
	if c.memory_manager.procedural.count() != 1:
		return _fail(name, "procedural korunmalı")
	if c.memory_manager.working.count() != 0:
		return _fail(name, "working yine de temizlenmeli")
	return _ok(name)
