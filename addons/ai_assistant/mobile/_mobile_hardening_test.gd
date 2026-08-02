@tool
class_name AIMobileHardeningTest
extends RefCounted

## Faz 7 — Android ve dar ekran sözleşme testleri.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("Mobile: 360", _test_360_portrait()))
	results.append(_b("Mobile: 480", _test_480_portrait()))
	results.append(_b("Mobile: 720", _test_720_boundary()))
	results.append(_b("Mobile: 1080", _test_1080_wide()))
	results.append(_b("Mobile: Yön", _test_landscape_compaction()))
	results.append(_b("Mobile: DPI", _test_dpi_bounds()))
	results.append(_b("Mobile: Başlık", _test_title_modes()))
	results.append(_b("Android: Audit", _test_safe_project()))
	results.append(_b("Android: Audit", _test_plaintext_endpoint_rejected()))
	results.append(_b("Android: Audit", _test_embedded_secret_rejected()))
	results.append(_b("Android: Audit", _test_missing_export_is_warning()))
	results.append(_b("Android: Audit", _test_internet_permission_required()))
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray()
	lines.append("=== Mobile Hardening Test Sonuçları ===")
	var current_batch: String = ""
	for result in results:
		if str(result["batch"]) != current_batch:
			current_batch = str(result["batch"])
			lines.append("--- %s ---" % current_batch)
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append(
		"--- %d geçti, %d başarısız (toplam %d) ---" % [
			passed, failed, results.size()
		]
	)
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _test_360_portrait() -> Dictionary:
	var name := "360 px portre tek kolon ve dokunmatik güvenli"
	var p: Dictionary = AIMobileLayoutPolicy.profile(Vector2i(360, 800), 440)
	if int(p["width_class"]) != AIMobileLayoutPolicy.WidthClass.VERY_COMPACT:
		return _fail(name, "VERY_COMPACT beklenir")
	if int(p["settings_columns"]) != 1 or not bool(p["settings_vertical"]):
		return _fail(name, "ayarlar tek kolona düşmeli")
	if not AIMobileLayoutPolicy.is_touch_safe(p):
		return _fail(name, "48 px dokunmatik tabanı korunmadı")
	if int(p["margin"]) > 6:
		return _fail(name, "360 px için margin fazla")
	if int(p["input_min_height"]) > 96:
		return _fail(name, "giriş alanı klavye açıkken fazla yüksek")
	return _ok(name)


static func _test_480_portrait() -> Dictionary:
	var name := "480 px portre compact tek kolon"
	var p: Dictionary = AIMobileLayoutPolicy.profile(Vector2i(480, 900), 320)
	if int(p["width_class"]) != AIMobileLayoutPolicy.WidthClass.COMPACT:
		return _fail(name, "COMPACT beklenir")
	if int(p["settings_columns"]) != 1:
		return _fail(name, "480 px ayarlar tek kolon olmalı")
	if str(p["title_mode"]) != "short":
		return _fail(name, "başlık kısa moda geçmeli")
	return _ok(name)


static func _test_720_boundary() -> Dictionary:
	var name := "720 px sınırında sekmeler kayar ve ayarlar taşmaz"
	var p: Dictionary = AIMobileLayoutPolicy.profile(Vector2i(720, 1280), 240)
	if not bool(p["compact"]):
		return _fail(name, "720 compact sınırına dahil olmalı")
	if not bool(p["workspace_scroll"]):
		return _fail(name, "workspace sekmeleri kaydırılmalı")
	if int(p["settings_columns"]) != 1:
		return _fail(name, "720 px'te ayarlar tek kolon olmalı")
	return _ok(name)


static func _test_1080_wide() -> Dictionary:
	var name := "1080 px geniş görünüm iki kolon ve tam başlık"
	var p: Dictionary = AIMobileLayoutPolicy.profile(Vector2i(1080, 1920), 420)
	if int(p["width_class"]) != AIMobileLayoutPolicy.WidthClass.WIDE:
		return _fail(name, "WIDE beklenir")
	if int(p["settings_columns"]) != 2:
		return _fail(name, "geniş ekranda ayarlar iki kolon olmalı")
	if str(p["title_mode"]) != "full":
		return _fail(name, "tam başlık beklenir")
	if bool(p["workspace_scroll"]):
		return _fail(name, "1080 px'te zorunlu sekme kaydırması olmamalı")
	return _ok(name)


static func _test_landscape_compaction() -> Dictionary:
	var name := "Landscape görünüm giriş yüksekliğini sıkıştırır"
	var portrait: Dictionary = AIMobileLayoutPolicy.profile(
		Vector2i(480, 900), 320
	)
	var landscape: Dictionary = AIMobileLayoutPolicy.profile(
		Vector2i(480, 320), 320
	)
	if not bool(landscape["landscape"]):
		return _fail(name, "landscape algılanmadı")
	if int(landscape["input_min_height"]) >= int(portrait["input_min_height"]):
		return _fail(name, "landscape giriş alanı daha kısa olmalı")
	if not AIMobileLayoutPolicy.is_touch_safe(landscape):
		return _fail(name, "sıkıştırma dokunmatik tabanı bozmamalı")
	return _ok(name)


static func _test_dpi_bounds() -> Dictionary:
	var name := "DPI ölçeği 0.75-3.0 ve yazı boyutu güvenli"
	var low: Dictionary = AIMobileLayoutPolicy.profile(Vector2i(360, 800), 72)
	var high: Dictionary = AIMobileLayoutPolicy.profile(Vector2i(360, 800), 960)
	if float(low["ui_scale"]) < 0.75:
		return _fail(name, "alt DPI sınırı aşıldı")
	if float(high["ui_scale"]) > 3.0:
		return _fail(name, "üst DPI sınırı aşıldı")
	if int(low["body_font"]) < 12:
		return _fail(name, "gövde yazısı okunamaz küçüklüğe inmemeli")
	return _ok(name)


static func _test_title_modes() -> Dictionary:
	var name := "Başlık hidden/short/full profillerini uygular"
	if AIMobileLayoutPolicy.title_for("Sohbet", "hidden") != "":
		return _fail(name, "hidden başlık boş olmalı")
	if AIMobileLayoutPolicy.title_for("Sohbet", "short") != "Sohbet":
		return _fail(name, "short yalnız görünüm adını taşımalı")
	if AIMobileLayoutPolicy.title_for("Sohbet", "full") != "AI Asistan — Sohbet":
		return _fail(name, "full başlık yanlış")
	return _ok(name)


static func _safe_project_text() -> String:
	return (
		"config_version=5\n"
		+ "config/features=PackedStringArray(\"4.6\", \"Mobile\")\n"
		+ "renderer/rendering_method=\"mobile\"\n"
		+ "renderer/rendering_method.mobile=\"mobile\"\n"
	)


static func _endpoints() -> Array:
	return [
		"https://api.deepseek.com/chat/completions",
		"https://api.openai.com/v1/chat/completions",
		"https://api.anthropic.com/v1/messages",
	]


static func _test_safe_project() -> Dictionary:
	var name := "Mobile renderer + HTTPS + internet izni geçer"
	var result: Dictionary = AIAndroidReadinessAudit.audit(
		_safe_project_text(),
		_endpoints(),
		"permissions/internet=true\n"
	)
	if not bool(result["ok"]):
		return _fail(name, "güvenli proje reddedildi: " + str(result["errors"]))
	var checks: Dictionary = result["checks"]
	if not bool(checks["mobile_renderer"]) or not bool(checks["https_endpoints"]):
		return _fail(name, "temel readiness kontrolleri geçmedi")
	return _ok(name)


static func _test_plaintext_endpoint_rejected() -> Dictionary:
	var name := "HTTP sağlayıcı endpointi reddedilir"
	var result: Dictionary = AIAndroidReadinessAudit.audit(
		_safe_project_text(),
		["http://api.example.test/chat"],
		"permissions/internet=true\n"
	)
	if bool(result["ok"]):
		return _fail(name, "plaintext HTTP kabul edilmemeli")
	if bool(result["checks"]["https_endpoints"]):
		return _fail(name, "https_endpoints false olmalı")
	return _ok(name)


static func _test_embedded_secret_rejected() -> Dictionary:
	var name := "project.godot içindeki gömülü sk anahtarı reddedilir"
	var unsafe: String = _safe_project_text() + "\napi_key=\"sk-1234567890ABCDEFGHIJ\"\n"
	var result: Dictionary = AIAndroidReadinessAudit.audit(
		unsafe, _endpoints(), "permissions/internet=true\n"
	)
	if bool(result["ok"]):
		return _fail(name, "gömülü anahtar kabul edilmemeli")
	if bool(result["checks"]["no_embedded_secret"]):
		return _fail(name, "secret kontrolü false olmalı")
	return _ok(name)


static func _test_missing_export_is_warning() -> Dictionary:
	var name := "Export preset yokluğu uyarı, otomatik sahte hata değil"
	var result: Dictionary = AIAndroidReadinessAudit.audit(
		_safe_project_text(), _endpoints()
	)
	if not bool(result["ok"]):
		return _fail(name, "preset yokluğu tek başına hard fail olmamalı")
	if (result["warnings"] as Array).is_empty():
		return _fail(name, "manuel INTERNET kontrolü uyarısı beklenir")
	return _ok(name)


static func _test_internet_permission_required() -> Dictionary:
	var name := "Preset verilmişse INTERNET izni zorunludur"
	var result: Dictionary = AIAndroidReadinessAudit.audit(
		_safe_project_text(), _endpoints(), "permissions/camera=false\n"
	)
	if bool(result["ok"]):
		return _fail(name, "INTERNET izinsiz preset kabul edilmemeli")
	if bool(result["checks"]["internet_permission"]):
		return _fail(name, "internet_permission false olmalı")
	return _ok(name)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(name: String) -> Dictionary:
	return {"ok": true, "name": name, "reason": ""}


static func _fail(name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": name, "reason": reason}
