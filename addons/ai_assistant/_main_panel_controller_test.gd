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
	results.append(_b("Panel: Görev", _test_run_ready()))
	results.append(_b("Panel: Görev", _test_target_path()))
	results.append(_b("Panel: Sekme", _test_nine_tabs()))
	results.append(_b("Panel: Durum", _test_status_and_result()))
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
	var name := "Canlı mod kapalı → reddedilir"
	var c := _c()
	# live_mode varsayılan kapalı
	var g: Dictionary = c.can_run_task("bir oyun yap")
	if bool(g["ok"]):
		return _fail(name, "canlı kapalıyken çalışmamalı")
	if not str(g["reason"]).contains("Canlı"):
		return _fail(name, "sebep canlı modu belirtmeli")
	return _ok(name)


static func _test_run_ready() -> Dictionary:
	var name := "Canlı + anahtar + görev → hazır"
	var c := _c()
	c.set_live_mode(true)
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
