@tool
class_name AISaveAutosaveScheduler
extends RefCounted

## AutosaveScheduler — otomatik kayıt zamanlayıcı (Madde 09 / autosave).
##
## Oyuncu kaydetmeyi unutur — sonra ilerlemesini kaybeder. Otomatik
## kayıt bunu çözer: belirli aralıklarla sessizce kaydet.
##
## Ama akıllı olmalı: çok sık kayıt = performans + disk yıpranması;
## çok seyrek = kayıp risk. Ayrıca KÖTÜ ANDA kaydetmemeli (yükleme
## ekranı, sahne geçişi sırasında).
##
## Bu sınıf zamanı kendi tutmaz — kendisine "şu kadar saniye geçti"
## bildirilir, "şimdi kaydetme zamanı mı" cevabını verir. Saf,
## test edilebilir mantık.
##
## Mock policy: karar gerçek geçen süre + gerçek durumdan.

## Varsayılan otomatik kayıt aralığı (saniye).
const DEFAULT_INTERVAL: float = 300.0  # 5 dakika

## Minimum aralık — bundan sık kayıt engellenir.
const MIN_INTERVAL: float = 30.0


## Otomatik kayıt aralığı (saniye).
var interval: float = DEFAULT_INTERVAL

## Son kayıttan bu yana geçen süre.
var elapsed: float = 0.0

## Otomatik kayıt etkin mi.
var enabled: bool = true

## Kayıt şu an güvenli mi (yükleme/geçiş sırasında false).
var _save_safe: bool = true

## Toplam tetiklenen otomatik kayıt sayısı.
var _trigger_count: int = 0


# ============================================================
# AYAR
# ============================================================

## Otomatik kayıt aralığını ayarlar (minimum sınırla).
func set_interval(seconds: float) -> void:
	interval = maxf(seconds, MIN_INTERVAL)


## Otomatik kaydı açar/kapatır.
func set_enabled(value: bool) -> void:
	enabled = value


## Kayıt güvenli bölgesini işaretler.
## Yükleme/sahne geçişi başında false, bitince true yapılmalı.
func set_save_safe(safe: bool) -> void:
	_save_safe = safe


# ============================================================
# ZAMANLAMA
# ============================================================

## Geçen süreyi ekler ve kayıt zamanı gelip gelmediğini söyler.
## delta_seconds: son çağrıdan bu yana geçen süre.
## Dönen: {should_save: bool, reason: String}
func tick(delta_seconds: float) -> Dictionary:
	if delta_seconds < 0.0:
		return {"should_save": false, "reason": "Geçersiz süre"}

	# Devre dışıysa sayaç da işlemez
	if not enabled:
		return {"should_save": false, "reason": "Otomatik kayıt kapalı"}

	elapsed += delta_seconds

	# Aralık dolmadı
	if elapsed < interval:
		return {"should_save": false, "reason": "Henüz zaman gelmedi"}

	# Aralık doldu ama kayıt güvenli değil — beklet
	if not _save_safe:
		return {
			"should_save": false,
			"reason": "Kayıt zamanı geldi ama şu an güvenli değil",
		}

	# Kayıt zamanı — sayacı sıfırla
	elapsed = 0.0
	_trigger_count += 1
	return {
		"should_save": true,
		"reason": "Otomatik kayıt zamanı",
	}


## Bir manuel kayıt yapıldığında sayacı sıfırlar.
## (Manuel kayıt sonrası otomatik kayıt aralığı yeniden başlar.)
func notify_manual_save() -> void:
	elapsed = 0.0


# ============================================================
# SORGULAMA
# ============================================================

## Bir sonraki otomatik kayda kalan süre (saniye).
func seconds_until_next() -> float:
	if not enabled:
		return -1.0
	return maxf(interval - elapsed, 0.0)


## Toplam kaç otomatik kayıt tetiklendi?
func trigger_count() -> int:
	return _trigger_count


## Durum özeti.
func summary() -> Dictionary:
	return {
		"enabled": enabled,
		"interval": interval,
		"elapsed": elapsed,
		"save_safe": _save_safe,
		"triggers": _trigger_count,
	}
