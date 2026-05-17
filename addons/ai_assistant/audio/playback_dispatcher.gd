@tool
class_name AIAudioPlaybackDispatcher
extends RefCounted

## PlaybackDispatcher — çalma dağıtıcısı (Madde 08 / Audio System).
##
## Oyun kodunun ses çalmak için kullandığı YÜKSEK SEVİYELİ API.
## Oyun "patlama sesi çal" der; dağıtıcı arka planda: havuzdan yuva
## al, doğru bus'a yönlendir, sesi başlat, bittiğinde yuvayı bırak.
##
## Bu sınıf çalma KARARLARINI verir: hangi bus, hangi öncelik, havuz
## doluysa ne yapılır. Gerçek ses çıkışı Node sarmalayıcının; bu model
## dağıtım mantığıdır — test edilebilir.
##
## Ses kategorileri ve varsayılan bus/öncelikleri:
##   SFX     -> SFX bus,     orta öncelik
##   UI      -> UI bus,      yüksek öncelik (her zaman duyulmalı)
##   AMBIENT -> Ambient bus, düşük öncelik
##   VOICE   -> Voice bus,   en yüksek (diyalog kesilmemeli)
##
## Mock policy: çalma kararı gerçek havuz + kategoriden; sahte
## "çalındı" yok — havuz doluysa açıkça raporlanır.

## Ses kategorileri.
enum SoundCategory { SFX, UI, AMBIENT, VOICE }

const CATEGORY_NAMES: Dictionary = {
	SoundCategory.SFX: "sfx",
	SoundCategory.UI: "ui",
	SoundCategory.AMBIENT: "ambient",
	SoundCategory.VOICE: "voice",
}

## Kategori -> hedef bus eşlemesi.
const CATEGORY_BUS: Dictionary = {
	SoundCategory.SFX: "SFX",
	SoundCategory.UI: "UI",
	SoundCategory.AMBIENT: "Ambient",
	SoundCategory.VOICE: "Voice",
}

## Kategori -> varsayılan öncelik (yüksek = korunur).
const CATEGORY_PRIORITY: Dictionary = {
	SoundCategory.SFX: 5,
	SoundCategory.UI: 8,
	SoundCategory.AMBIENT: 2,
	SoundCategory.VOICE: 10,
}


## Bir çalma isteğinin sonucu.
class PlaybackResult extends RefCounted:
	var ok: bool = false
	var sound_id: String = ""
	var bus: String = ""
	var slot_index: int = -1
	var voice_stolen: bool = false     ## Başka ses kesildi mi
	var reason: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok, "sound_id": sound_id, "bus": bus,
			"slot_index": slot_index, "voice_stolen": voice_stolen,
			"reason": reason,
		}


## Ses havuzu.
var _pool: AIAudioPool


func _init(pool: AIAudioPool = null) -> void:
	if pool != null:
		_pool = pool
	else:
		_pool = AIAudioPool.new()


## Bağlı havuza erişim.
func pool() -> AIAudioPool:
	return _pool


# ============================================================
# ÇALMA
# ============================================================

## Bir ses çalar — yüksek seviyeli API.
## sound_id: çalınacak sesin kimliği. category: ses kategorisi.
## priority_override: -1 ise kategori varsayılanı kullanılır.
## Dönen: PlaybackResult.
func play(
	sound_id: String, category: int, priority_override: int = -1
) -> PlaybackResult:
	var result := PlaybackResult.new()
	result.sound_id = sound_id

	if sound_id.strip_edges().is_empty():
		result.reason = "Ses kimliği boş"
		return result
	if not CATEGORY_NAMES.has(category):
		result.reason = "Geçersiz ses kategorisi"
		return result

	# Hedef bus + öncelik belirle
	result.bus = CATEGORY_BUS.get(category, "SFX")
	var priority: int = priority_override
	if priority < 0:
		priority = int(CATEGORY_PRIORITY.get(category, 5))

	# Havuzdan yuva al
	var acquire: Dictionary = _pool.acquire(sound_id, priority)
	if not acquire["ok"]:
		result.reason = "Çalınamadı: " + str(acquire["reason"])
		return result

	result.slot_index = int(acquire["slot_index"])
	result.voice_stolen = bool(acquire["stole"])
	result.ok = true
	result.reason = "Çalınıyor (%s bus)" % result.bus
	return result


## Bir UI sesi çalar — kısayol (UI kategorisi).
func play_ui(sound_id: String) -> PlaybackResult:
	return play(sound_id, SoundCategory.UI)


## Bir SFX çalar — kısayol (SFX kategorisi).
func play_sfx(sound_id: String) -> PlaybackResult:
	return play(sound_id, SoundCategory.SFX)


# ============================================================
# DURDURMA
# ============================================================

## Bir çalan sesi durdurur — yuvasını serbest bırakır.
## slot_index: play()'in döndürdüğü yuva.
## Dönen: true = durduruldu.
func stop(slot_index: int) -> bool:
	return _pool.release(slot_index)


## Tüm sesleri durdurur — sahne değişimi / duraklama.
func stop_all() -> void:
	_pool.release_all()


# ============================================================
# DURUM
# ============================================================

## Şu an kaç ses çalıyor?
func active_count() -> int:
	return _pool.busy_count()


## Dağıtıcı durum özeti.
func summary() -> Dictionary:
	return {
		"active_sounds": active_count(),
		"pool": _pool.summary(),
	}
