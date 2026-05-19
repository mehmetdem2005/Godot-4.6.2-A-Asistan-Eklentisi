@tool
class_name AIAutonomousErrorLoopTest
extends RefCounted

## Otonom hata düzeltme döngüsü self-test (Parça 4).
##
## Doğrular: log izleyici gerçek hata satırlarını tanır, cursor artımlı
## ilerler, dosya rotasyonu sıfırlar; yönlendirici güvensiz yolu
## reddeder, devre kesici aynı hatada açılır; thin Node köprüsü
## başlatılır/durdurulur, pipeline yokken sessiz uyur (sahte iş yok).
##
## Gerçek editör koşusu (Output paneli + LLM onarımı) live verify —
## burada DEĞİL (devir §5.4). Burası saf kerneller + glue sağlığı.

const TMP_LOG: String = "user://__autonomous_error_loop_test__.log"


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Otonom: Log", _test_watcher_empty()))
	results.append(_b("Otonom: Log", _test_watcher_detects_script_error()))
	results.append(_b("Otonom: Log", _test_watcher_cursor_advances()))
	results.append(_b("Otonom: Log", _test_watcher_rotation_resets()))
	results.append(_b("Otonom: Yön", _test_router_unsafe_path_rejected()))
	results.append(_b("Otonom: Yön", _test_router_empty_sig_rejected()))
	results.append(_b("Otonom: Yön", _test_router_first_attempt_ok()))
	results.append(_b("Otonom: Yön", _test_router_same_sig_breaker()))
	results.append(_b("Otonom: Yön", _test_router_instruction_complete()))
	results.append(_b("Otonom: Glue", _test_autofix_idle_without_pipeline()))
	results.append(_b("Otonom: Glue", _test_autofix_start_stop()))
	return results


# ============================================================
# WATCHER
# ============================================================

static func _test_watcher_empty() -> Dictionary:
	var name := "Watcher: dosya yoksa boş (sahte hata yok)"
	var w := AIErrorLogWatcher.new("user://__yok__.log")
	var ev: Array = w.poll()
	if not ev.is_empty():
		return _fail(name, "yok dosyada olay üretildi")
	return _ok(name)


static func _test_watcher_detects_script_error() -> Dictionary:
	var name := "Watcher: SCRIPT ERROR satırını yakalar + dosya yolunu çıkarır"
	_write_log(
		"INFO bir şey\n"
		+ "SCRIPT ERROR: Parse Error: Identifier 'Foo' not declared\n"
		+ "   at: (res://game/scripts/player.gd:12)\n"
	)
	var w := AIErrorLogWatcher.new(TMP_LOG)
	var ev: Array = w.poll()
	_clear_log()
	if ev.size() != 1:
		return _fail(name, "1 hata olayı beklendi: %d" % ev.size())
	var e: Dictionary = ev[0]
	if str(e["category"]) != "parse_error":
		return _fail(name, "parse_error kategorisi: " + str(e["category"]))
	if str(e["file_path"]) != "res://game/scripts/player.gd":
		return _fail(name, "dosya yolu çıkmadı: " + str(e["file_path"]))
	if int(e["line_no"]) != 12:
		return _fail(name, "satır no: %d" % int(e["line_no"]))
	if str(e["signature"]).is_empty():
		return _fail(name, "imza boş — circuit breaker beslenemez")
	return _ok(name)


static func _test_watcher_cursor_advances() -> Dictionary:
	var name := "Watcher: cursor artımlı — ikinci poll yalnız YENİ satırlar"
	_write_log("SCRIPT ERROR: Parse Error: foo\n")
	var w := AIErrorLogWatcher.new(TMP_LOG)
	var first: Array = w.poll()
	_append_log("SCRIPT ERROR: Invalid call. Nonexistent function 'bar'\n")
	var second: Array = w.poll()
	_clear_log()
	if first.size() != 1 or second.size() != 1:
		return _fail(name, "her poll 1 olay (cursor ilerlemeli): %d/%d" % [
			first.size(), second.size()])
	if str(second[0]["category"]) != "api_error":
		return _fail(name, "ikinci hata api_error olmalı")
	return _ok(name)


static func _test_watcher_rotation_resets() -> Dictionary:
	var name := "Watcher: dosya küçülürse (rotasyon) cursor sıfırlanır"
	_write_log("SCRIPT ERROR: Parse Error: aaa\nSCRIPT ERROR: Parse Error: bbb\n")
	var w := AIErrorLogWatcher.new(TMP_LOG)
	w.poll()
	_write_log("SCRIPT ERROR: Parse Error: ccc\n")  # küçük yeni içerik
	var ev: Array = w.poll()
	_clear_log()
	if ev.size() != 1:
		return _fail(name, "rotasyon sonrası 1 olay beklendi: %d" % ev.size())
	return _ok(name)


# ============================================================
# ROUTER
# ============================================================

static func _test_router_unsafe_path_rejected() -> Dictionary:
	var name := "Router: sandbox dışı yol reddedilir (yalnız res://game/)"
	var r := AIAutonomousRepairRouter.new()
	var d: Dictionary = r.should_repair("user://x.gd", "sig1")
	if bool(d["ok"]):
		return _fail(name, "user:// yolu kabul edildi")
	return _ok(name)


static func _test_router_empty_sig_rejected() -> Dictionary:
	var name := "Router: boş imza reddedilir (sınıflandırılamaz)"
	var r := AIAutonomousRepairRouter.new()
	var d: Dictionary = r.should_repair("res://game/scripts/a.gd", "")
	if bool(d["ok"]):
		return _fail(name, "boş imza kabul edildi")
	return _ok(name)


static func _test_router_first_attempt_ok() -> Dictionary:
	var name := "Router: ilk deneme — onar; attempt=1"
	var r := AIAutonomousRepairRouter.new()
	var d: Dictionary = r.should_repair("res://game/scripts/a.gd", "parse|Foo|res://game/a.gd")
	if not bool(d["ok"]):
		return _fail(name, "ilk deneme reddedildi: " + str(d["reason"]))
	if int(d["attempt"]) != 1:
		return _fail(name, "attempt 1 olmalı: %d" % int(d["attempt"]))
	return _ok(name)


static func _test_router_same_sig_breaker() -> Dictionary:
	var name := "Router: aynı imza tekrar — devre kesici durdurur"
	var r := AIAutonomousRepairRouter.new()
	r.should_repair("res://game/scripts/a.gd", "parse|X|res://game/a.gd")
	var d2: Dictionary = r.should_repair(
		"res://game/scripts/a.gd", "parse|X|res://game/a.gd"
	)
	if bool(d2["ok"]):
		return _fail(name, "aynı imza ikinci kez kabul — döngü riski")
	if not str(d2["reason"]).to_lower().contains("devre"):
		return _fail(name, "devre kesici sebebi raporlanmalı")
	return _ok(name)


static func _test_router_instruction_complete() -> Dictionary:
	var name := "Router: onarım talimatı dosya+hata+kod içerir"
	var r := AIAutonomousRepairRouter.new()
	var inst: String = r.build_instruction(
		"res://game/scripts/a.gd", "extends Node\n",
		"SCRIPT ERROR: Parse Error"
	)
	for token in [
		"res://game/scripts/a.gd",
		"extends Node",
		"Parse Error",
		"Godot 4.6",
	]:
		if not inst.contains(token):
			return _fail(name, "talimatta eksik: " + token)
	return _ok(name)


# ============================================================
# GLUE NODE
# ============================================================

static func _test_autofix_idle_without_pipeline() -> Dictionary:
	var name := "AutoFix: pipeline yokken start false, tick boş (sahte iş yok)"
	var n := AIEditorLogAutoFix.new()
	var started: bool = n.start(null)
	var t: Array = n.tick()
	var active: bool = n.is_active()
	n.free()
	if started or active or not t.is_empty():
		return _fail(name, "pipeline'sız çalışmamalı")
	return _ok(name)


static func _test_autofix_start_stop() -> Dictionary:
	var name := "AutoFix: pipeline verilince start/stop güvenli"
	var pipe := AIPipelineOrchestrator.new()
	var n := AIEditorLogAutoFix.new()
	# Node Timer kullandığı için sahneye eklenmeli.
	var root := Node.new()
	root.add_child(n)
	var started: bool = n.start(pipe, "user://__nope__.log")
	var active1: bool = n.is_active()
	n.stop()
	var active2: bool = n.is_active()
	root.free()
	pipe.free()
	if not started or not active1 or active2:
		return _fail(name, "start/stop yaşam döngüsü hatalı")
	return _ok(name)


# ============================================================
# YARDIMCILAR
# ============================================================

static func _write_log(content: String) -> void:
	var f: FileAccess = FileAccess.open(TMP_LOG, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()


static func _append_log(content: String) -> void:
	var f: FileAccess = FileAccess.open(TMP_LOG, FileAccess.READ_WRITE)
	if f == null:
		_write_log(content)
		return
	f.seek_end()
	f.store_string(content)
	f.close()


static func _clear_log() -> void:
	if FileAccess.file_exists(TMP_LOG):
		DirAccess.remove_absolute(TMP_LOG)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}
