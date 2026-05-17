@tool
class_name AILifecycleVibration
extends RefCounted

## VibrationHelper — titreşim yardımcısı (Madde 10 / device_control).
##
## Dokunsal geri bildirim (haptic) oyunu zenginleştirir: vuruş alınca
## kısa titreşim, patlama olunca güçlü titreşim. Ama abartılırsa
## rahatsız eder ve pil tüketir.
##
## Bu sınıf titreşim taleplerini yönetir:
##   - hazır titreşim DESENLERİ (kısa/orta/uzun/darbe)
##   - kullanıcı ayarı (titreşim kapalıysa hiç titremesin)
##   - debounce (üst üste çok titreşim tek titreşime düşer)
##
## Gerçek titreşim Input.vibrate_handheld'in işi; bu sınıf KARARI
## ve deseni üretir — test edilebilir.
##
## Mock policy: titreşim kararı gerçek ayar + desen tanımından.

## Hazır titreşim desenleri — id -> süre (ms).
const PATTERNS: Dictionary = {
	"tick": 10,           # çok hafif — UI dokunuşu
	"light": 30,          # hafif — eşya toplama
	"medium": 80,         # orta — vuruş
	"heavy": 200,         # güçlü — patlama, ölüm
	"pulse": 50,          # darbe — uyarı
}

## Üst üste titreşimler arası minimum süre (ms) — debounce.
const DEBOUNCE_MS: int = 50


## Kullanıcı ayarı — titreşim açık mı.
var vibration_enabled: bool = true

## Son titreşim zamanı (ms) — debounce için.
var _last_vibration_tick: int = -1000

## Toplam titreşim sayısı.
var _vibration_count: int = 0


# ============================================================
# AYAR
# ============================================================

## Titreşimi kullanıcı ayarına göre açar/kapatır.
func set_enabled(enabled: bool) -> void:
	vibration_enabled = enabled


# ============================================================
# TİTREŞİM TALEBİ
# ============================================================

## Bir titreşim deseni talep eder.
## pattern_id: desen kimliği (PATTERNS'ten). current_tick: şu anki
## zaman (ms) — debounce için.
## Dönen: {vibrate: bool, duration_ms: int, reason: String}
func request(pattern_id: String, current_tick: int) -> Dictionary:
	# Kullanıcı titreşimi kapatmışsa — hiç titreme
	if not vibration_enabled:
		return {
			"vibrate": false, "duration_ms": 0,
			"reason": "Titreşim kullanıcı ayarında kapalı",
		}

	# Bilinmeyen desen
	if not PATTERNS.has(pattern_id):
		return {
			"vibrate": false, "duration_ms": 0,
			"reason": "Bilinmeyen titreşim deseni: " + pattern_id,
		}

	# Debounce — son titreşimden çok az süre geçtiyse atla
	if current_tick - _last_vibration_tick < DEBOUNCE_MS:
		return {
			"vibrate": false, "duration_ms": 0,
			"reason": "Debounce — önceki titreşime çok yakın",
		}

	_last_vibration_tick = current_tick
	_vibration_count += 1
	var duration: int = int(PATTERNS[pattern_id])
	return {
		"vibrate": true,
		"duration_ms": duration,
		"reason": "Titreşim: %s (%d ms)" % [pattern_id, duration],
	}


## Doğrudan bir süre titreşimi talep eder (desen yerine).
## duration_ms: titreşim süresi. current_tick: şu anki zaman.
func request_custom(duration_ms: int, current_tick: int) -> Dictionary:
	if not vibration_enabled:
		return {"vibrate": false, "duration_ms": 0,
			"reason": "Titreşim kapalı"}
	if duration_ms <= 0:
		return {"vibrate": false, "duration_ms": 0,
			"reason": "Geçersiz süre"}
	if current_tick - _last_vibration_tick < DEBOUNCE_MS:
		return {"vibrate": false, "duration_ms": 0,
			"reason": "Debounce"}
	_last_vibration_tick = current_tick
	_vibration_count += 1
	return {
		"vibrate": true, "duration_ms": duration_ms,
		"reason": "Özel titreşim: %d ms" % duration_ms,
	}


# ============================================================
# SORGULAMA
# ============================================================

## Bir desen tanımlı mı?
func has_pattern(pattern_id: String) -> bool:
	return PATTERNS.has(pattern_id)


## Bir desenin süresini döndürür (ms). Yoksa 0.
func pattern_duration(pattern_id: String) -> int:
	return int(PATTERNS.get(pattern_id, 0))


## Toplam titreşim sayısı.
func vibration_count() -> int:
	return _vibration_count
