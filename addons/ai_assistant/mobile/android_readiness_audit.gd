@tool
class_name AIAndroidReadinessAudit
extends RefCounted

## Android üretim hazırlığı denetimi.
##
## Proje ayarlarını, sağlayıcı endpointlerini ve varsa Android export
## preset metnini saf olarak inceler. Dosyaya yazmaz; API anahtarını
## çözmez veya loglamaz.


static func audit(
	project_text: String,
	endpoints: Array,
	export_preset_text: String = ""
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var checks: Dictionary = {}

	checks["mobile_feature"] = (
		project_text.contains("config/features=")
		and project_text.contains("\"Mobile\"")
	)
	if not bool(checks["mobile_feature"]):
		errors.append("project.godot Mobile feature içermiyor")

	checks["mobile_renderer"] = (
		project_text.contains("renderer/rendering_method=\"mobile\"")
		and project_text.contains("renderer/rendering_method.mobile=\"mobile\"")
	)
	if not bool(checks["mobile_renderer"]):
		errors.append("Forward Mobile renderer tam yapılandırılmamış")

	checks["https_endpoints"] = true
	if endpoints.is_empty():
		warnings.append("Sağlayıcı endpoint listesi boş; HTTPS denetimi yapılmadı")
	for endpoint_value in endpoints:
		var endpoint: String = str(endpoint_value).strip_edges()
		if endpoint.is_empty() or not endpoint.begins_with("https://"):
			checks["https_endpoints"] = false
			errors.append("HTTPS olmayan veya boş sağlayıcı endpointi: " + endpoint)

	checks["no_embedded_secret"] = not _contains_secret(project_text)
	if not bool(checks["no_embedded_secret"]):
		errors.append("project.godot içinde gömülü API anahtarı kalıbı bulundu")

	checks["internet_permission"] = false
	if export_preset_text.strip_edges().is_empty():
		warnings.append(
			"Android export preset verilmedi; INTERNET izni cihaz smoke öncesi "
			+ "manuel doğrulanmalı"
		)
	else:
		checks["internet_permission"] = (
			export_preset_text.contains("permissions/internet=true")
			or export_preset_text.contains("permissions/internet=1")
		)
		if not bool(checks["internet_permission"]):
			errors.append("Android export preset INTERNET iznini etkinleştirmiyor")
		if _contains_secret(export_preset_text):
			errors.append("Android export preset içinde gömülü API anahtarı bulundu")

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"checks": checks,
	}


static func _contains_secret(text: String) -> bool:
	# DeepSeek/OpenAI benzeri uzun sk- veya sk_ anahtar kalıpları.
	var regex := RegEx.new()
	var compile_error: int = regex.compile("(?i)sk[-_][a-z0-9]{16,}")
	if compile_error != OK:
		# Denetim regex'i derlenemezse güvenli tarafta başarısız kabul et.
		return true
	return regex.search(text) != null
