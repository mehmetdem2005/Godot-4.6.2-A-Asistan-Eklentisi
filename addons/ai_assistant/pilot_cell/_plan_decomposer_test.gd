@tool
class_name AIPlanDecomposerTest
extends RefCounted

## PlanDecomposer Self-Test (Plan C).
##
## SAF ayrıştırma + güvenlik yüzeyini ağsız doğrular: JSON çıkarma,
## prose içinden dizi yakalama, bozuk/boş → tek görev fallback (sahte
## plan yok), model-üretimi yolun user:// önekine zorlanması (path
## traversal / res:// imkânsız). Köprüsüz dürüst fallback.
##
## Gerçek LLM bölme ASENKRON — tools/build_plan_runner.gd'de
## gerçek anahtarla kanıtlanır.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Decompose: Parse", _test_parse_valid()))
	results.append(_b("Decompose: Parse", _test_parse_prose_wrapped()))
	results.append(_b("Decompose: Parse", _test_parse_string_items()))
	results.append(_b("Decompose: Parse", _test_parse_max_cap()))
	results.append(_b("Decompose: Fallback", _test_parse_garbage()))
	results.append(_b("Decompose: Fallback", _test_parse_empty_array()))
	results.append(_b("Decompose: Güvenlik", _test_sanitize_traversal()))
	results.append(_b("Decompose: Güvenlik", _test_sanitize_resource()))
	results.append(_b("Decompose: Güvenlik", _test_sanitize_default()))
	results.append(_b("Decompose: Köprü", _test_no_bridge_fallback()))
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _new() -> AIPlanDecomposer:
	return AIPlanDecomposer.new()


static func _test_parse_valid() -> Dictionary:
	var name := "Geçerli JSON dizi alt görevlere ayrışır"
	var d := _new()
	var raw := (
		"[{\"title\":\"Oyuncu\",\"target_file\":\"player.gd\"},"
		+ "{\"title\":\"Düşman\",\"target_file\":\"enemy.gd\"}]"
	)
	var tasks: Array = d.parse_plan(raw, "oyun yap")
	d.free()
	if tasks.size() != 2:
		return _fail(name, "2 görev beklendi: %d" % tasks.size())
	if str(tasks[0]["title"]) != "Oyuncu":
		return _fail(name, "başlık kayboldu")
	if str(tasks[0]["target_file"]) != "user://ai_assistant/uretilen/player.gd":
		return _fail(name, "yol: " + str(tasks[0]["target_file"]))
	return _ok(name)


static func _test_parse_prose_wrapped() -> Dictionary:
	var name := "Açıklama metni içinden JSON dizi yakalanır"
	var d := _new()
	var raw := (
		"İşte plan:\n[{\"title\":\"A\",\"target_file\":\"a.gd\"}]\n"
		+ "umarım yardımcı olur."
	)
	var tasks: Array = d.parse_plan(raw, "x")
	d.free()
	if tasks.size() != 1 or str(tasks[0]["title"]) != "A":
		return _fail(name, "prose içinden ayrışmadı")
	return _ok(name)


static func _test_parse_string_items() -> Dictionary:
	var name := "Düz string öğeler başlık olarak kabul edilir"
	var d := _new()
	var tasks: Array = d.parse_plan("[\"Envanter\",\"UI\"]", "x")
	d.free()
	if tasks.size() != 2 or str(tasks[1]["title"]) != "UI":
		return _fail(name, "string öğeler ayrışmadı")
	if not str(tasks[0]["target_file"]).begins_with(
		"user://ai_assistant/uretilen/"
	):
		return _fail(name, "string öğeye güvenli yol verilmedi")
	return _ok(name)


static func _test_parse_max_cap() -> Dictionary:
	var name := "Alt görev sayısı MAX_TASKS ile sınırlanır"
	var d := _new()
	var parts: PackedStringArray = PackedStringArray()
	for i in 20:
		parts.append("{\"title\":\"T%d\",\"target_file\":\"t%d.gd\"}" % [i, i])
	var raw := "[" + ",".join(parts) + "]"
	var tasks: Array = d.parse_plan(raw, "x")
	d.free()
	if tasks.size() != AIPlanDecomposer.MAX_TASKS:
		return _fail(name, "sınır uygulanmadı: %d" % tasks.size())
	return _ok(name)


static func _test_parse_garbage() -> Dictionary:
	var name := "Bozuk içerik → tek görev fallback (sahte plan yok)"
	var d := _new()
	var tasks: Array = d.parse_plan("özür dilerim, JSON yok", "envanter yap")
	d.free()
	if tasks.size() != 1:
		return _fail(name, "fallback tek görev olmalı")
	if str(tasks[0]["title"]) != "envanter yap":
		return _fail(name, "fallback orijinal isteği korumalı")
	return _ok(name)


static func _test_parse_empty_array() -> Dictionary:
	var name := "Boş dizi → tek görev fallback"
	var d := _new()
	var tasks: Array = d.parse_plan("[]", "bir şey yap")
	d.free()
	if tasks.size() != 1 or str(tasks[0]["title"]) != "bir şey yap":
		return _fail(name, "boş dizi fallback'e düşmeli")
	return _ok(name)


static func _test_sanitize_traversal() -> Dictionary:
	var name := "Path traversal nötrlenir (basename + user://)"
	var d := _new()
	var p: String = d.sanitize_target("../../etc/passwd", "x")
	d.free()
	if not p.begins_with("user://ai_assistant/uretilen/"):
		return _fail(name, "güvenli öneke zorlanmadı: " + p)
	if p.contains("..") or p.contains("etc"):
		return _fail(name, "traversal sızdı: " + p)
	return _ok(name)


static func _test_sanitize_resource() -> Dictionary:
	var name := "res:// denemesi user://'ye indirgenir"
	var d := _new()
	var p: String = d.sanitize_target("res://core/engine.gd", "yedek")
	d.free()
	if not p.begins_with("user://ai_assistant/uretilen/"):
		return _fail(name, "res:// engellenmedi: " + p)
	if not p.ends_with(".gd"):
		return _fail(name, ".gd uzantısı zorlanmadı")
	return _ok(name)


static func _test_sanitize_default() -> Dictionary:
	var name := "Boş ad → başlıktan slug, o da boşsa 'uretim'"
	var d := _new()
	var p1: String = d.sanitize_target("", "Oyuncu Hareketi")
	var p2: String = d.sanitize_target("", "!!!")
	d.free()
	if p1 != "user://ai_assistant/uretilen/oyuncu_hareketi.gd":
		return _fail(name, "başlık slug yanlış: " + p1)
	if p2 != "user://ai_assistant/uretilen/uretim.gd":
		return _fail(name, "varsayılan yanlış: " + p2)
	return _ok(name)


static func _test_no_bridge_fallback() -> Dictionary:
	var name := "Köprüsüz decompose → dürüst tek görev fallback"
	var d := _new()
	var captured: Array = []
	d.decomposed.connect(func(tasks: Array) -> void:
		captured.append(tasks)
	)
	var started: bool = d.decompose("envanter sistemli oyun")
	d.free()
	if started:
		return _fail(name, "köprüsüz başlamamalı")
	if captured.is_empty() or captured[0].size() != 1:
		return _fail(name, "tek görev fallback yayılmalı")
	if str(captured[0][0]["title"]) != "envanter sistemli oyun":
		return _fail(name, "fallback isteği korumalı")
	return _ok(name)
