@tool
class_name AIProjectScannerTest
extends RefCounted

## ProjectScanner Self-Test (proje görünürlüğü).
##
## SALT-OKUNUR tarama gerçek diskten doğrulanır (sahte ağaç yok):
## bilinen proje dosyaları listelenir, yol güvenliği (traversal /
## dış erişim reddedilir), anahtar dosya okunur, özet biçimi.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Scanner: Ağaç", _test_scan_lists_known()))
	results.append(_b("Scanner: Ağaç", _test_scan_skips_hidden()))
	results.append(_b("Scanner: Ağaç", _test_scan_cap()))
	results.append(_b("Scanner: Güvenlik", _test_unsafe_root_empty()))
	results.append(_b("Scanner: Güvenlik", _test_read_traversal()))
	results.append(_b("Scanner: Güvenlik", _test_read_outside()))
	results.append(_b("Scanner: Oku", _test_read_known()))
	results.append(_b("Scanner: Oku", _test_read_missing()))
	results.append(_b("Scanner: Özet", _test_summary_format()))
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _new() -> AIProjectScanner:
	return AIProjectScanner.new()


static func _test_scan_lists_known() -> Dictionary:
	var name := "Ağaç gerçek proje dosyalarını listeler"
	var s := _new()
	var tree: Array = s.scan_tree("res://", 300)
	if tree.is_empty():
		return _fail(name, "res:// boş dönmemeli")
	var has_project := false
	var has_addons_dir := false
	for e in tree:
		if str(e) == "res://project.godot":
			has_project = true
		if str(e) == "res://addons/":
			has_addons_dir = true
	if not has_project:
		return _fail(name, "project.godot listelenmeli")
	if not has_addons_dir:
		return _fail(name, "addons/ dizini '/' ile listelenmeli")
	return _ok(name)


static func _test_scan_skips_hidden() -> Dictionary:
	var name := "Gizli/çöp dizinler (.godot/.git) atlanır"
	var s := _new()
	var tree: Array = s.scan_tree("res://", 300)
	for e in tree:
		var p: String = str(e)
		if p.contains("/.godot/") or p.begins_with("res://.godot"):
			return _fail(name, ".godot sızdı: " + p)
		if p.contains("/.git/") or p.begins_with("res://.git"):
			return _fail(name, ".git sızdı: " + p)
	return _ok(name)


static func _test_scan_cap() -> Dictionary:
	var name := "Giriş sayısı üst sınırı uygulanır"
	var s := _new()
	var tree: Array = s.scan_tree("res://", 5)
	if tree.size() > 5:
		return _fail(name, "sınır aşıldı: %d" % tree.size())
	return _ok(name)


static func _test_unsafe_root_empty() -> Dictionary:
	var name := "Güvensiz kök → boş ağaç (dürüst)"
	var s := _new()
	if not s.scan_tree("/etc", 50).is_empty():
		return _fail(name, "/etc boş dönmeli")
	if not s.scan_tree("res://../..", 50).is_empty():
		return _fail(name, "traversal kök boş dönmeli")
	return _ok(name)


static func _test_read_traversal() -> Dictionary:
	var name := "read_file '..' reddeder"
	var s := _new()
	var r: Dictionary = s.read_file("res://../../etc/passwd")
	if bool(r["ok"]):
		return _fail(name, "traversal okunmamalı")
	return _ok(name)


static func _test_read_outside() -> Dictionary:
	var name := "read_file res:// / user:// dışını reddeder"
	var s := _new()
	var r: Dictionary = s.read_file("/etc/hostname")
	if bool(r["ok"]):
		return _fail(name, "dış yol okunmamalı")
	return _ok(name)


static func _test_read_known() -> Dictionary:
	var name := "read_file project.godot içeriğini döndürür"
	var s := _new()
	var r: Dictionary = s.read_file("res://project.godot")
	if not bool(r["ok"]):
		return _fail(name, "project.godot okunmalı: " + str(r["reason"]))
	if str(r["content"]).strip_edges().is_empty():
		return _fail(name, "içerik boş olmamalı")
	return _ok(name)


static func _test_read_missing() -> Dictionary:
	var name := "Olmayan dosya dürüst hata"
	var s := _new()
	var r: Dictionary = s.read_file("res://yok_boyle_bir_dosya_12345.gd")
	if bool(r["ok"]):
		return _fail(name, "olmayan dosya ok olmamalı")
	return _ok(name)


static func _test_summary_format() -> Dictionary:
	var name := "Özet başlık + project.godot içeriği içerir"
	var s := _new()
	var sum: String = s.project_summary(300)
	if not sum.contains("PROJE DOSYALARI"):
		return _fail(name, "başlık yok")
	if not sum.contains("res://project.godot"):
		return _fail(name, "anahtar dosya bölümü yok")
	return _ok(name)
