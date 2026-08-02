@tool
class_name AIMobileLayoutPolicy
extends RefCounted

## Android/dar ekran responsive düzen politikası.
##
## Control katmanları ekran ölçüsünü bu saf sınıfa verir; sınıf hiçbir
## node'a dokunmadan uygulanabilir bir profil döndürür. Böylece 360 px
## portre dahil kritik cihaz sınıfları headless contract testlerinde
## doğrulanabilir.

enum WidthClass {
	VERY_COMPACT,
	COMPACT,
	MEDIUM,
	WIDE,
}

const VERY_COMPACT_MAX: int = 420
const COMPACT_MAX: int = 720
const MEDIUM_MAX: int = 1024
const MIN_TOUCH_TARGET: int = 48
const REFERENCE_DPI: float = 160.0


static func width_class(width: int) -> int:
	if width <= VERY_COMPACT_MAX:
		return WidthClass.VERY_COMPACT
	if width <= COMPACT_MAX:
		return WidthClass.COMPACT
	if width <= MEDIUM_MAX:
		return WidthClass.MEDIUM
	return WidthClass.WIDE


static func profile(viewport_size: Vector2i, dpi: int = 160) -> Dictionary:
	var safe_width: int = maxi(viewport_size.x, 1)
	var safe_height: int = maxi(viewport_size.y, 1)
	var cls: int = width_class(safe_width)
	var landscape: bool = safe_width > safe_height
	var very_compact: bool = cls == WidthClass.VERY_COMPACT
	var compact: bool = cls <= WidthClass.COMPACT

	var margin: int = 10
	var separation: int = 8
	var header_font: int = 18
	var body_font: int = 13
	var input_height: int = 110
	var chat_height: int = clampi(int(float(safe_height) * 0.34), 180, 320)
	var title_mode: String = "full"

	if cls == WidthClass.VERY_COMPACT:
		margin = 6
		separation = 6
		header_font = 15
		body_font = 12
		input_height = 92 if not landscape else 72
		chat_height = clampi(int(float(safe_height) * 0.27), 120, 220)
		title_mode = "hidden" if safe_width < 380 else "short"
	elif cls == WidthClass.COMPACT:
		margin = 8
		separation = 7
		header_font = 16
		input_height = 100 if not landscape else 76
		chat_height = clampi(int(float(safe_height) * 0.30), 140, 250)
		title_mode = "short"
	elif cls == WidthClass.MEDIUM:
		chat_height = clampi(int(float(safe_height) * 0.32), 180, 280)

	var dpi_scale: float = clampf(float(maxi(dpi, 96)) / REFERENCE_DPI, 0.75, 3.0)
	# Viewport ölçüleri Godot Control için mantıksal pikseldir. Dokunmatik
	# hedefi DPI ile büyütüp dar ekranda taşırmak yerine 48 mantıksal px
	# tabanını koruruz; sadece yazı ölçeği sınırlı biçimde etkilenir.
	var font_scale: float = clampf(dpi_scale, 0.9, 1.35)

	return {
		"width_class": cls,
		"very_compact": very_compact,
		"compact": compact,
		"landscape": landscape,
		"margin": margin,
		"separation": separation,
		"touch_target": MIN_TOUCH_TARGET,
		"header_font": maxi(14, int(round(float(header_font) * font_scale))),
		"body_font": maxi(12, int(round(float(body_font) * font_scale))),
		"chat_min_height": chat_height,
		"input_min_height": maxi(MIN_TOUCH_TARGET, input_height),
		"settings_columns": 1 if compact else 2,
		"settings_vertical": compact,
		"title_mode": title_mode,
		"workspace_scroll": safe_width <= COMPACT_MAX,
		"workspace_tab_height": MIN_TOUCH_TARGET,
		"ui_scale": dpi_scale,
	}


static func title_for(view_title: String, title_mode: String) -> String:
	match title_mode:
		"hidden":
			return ""
		"short":
			return view_title
		_:
			return "AI Asistan — " + view_title


static func is_touch_safe(profile_data: Dictionary) -> bool:
	return (
		int(profile_data.get("touch_target", 0)) >= MIN_TOUCH_TARGET
		and int(profile_data.get("input_min_height", 0)) >= MIN_TOUCH_TARGET
		and int(profile_data.get("workspace_tab_height", 0)) >= MIN_TOUCH_TARGET
	)
