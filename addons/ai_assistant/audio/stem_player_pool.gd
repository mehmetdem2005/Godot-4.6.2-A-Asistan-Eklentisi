@tool
class_name AIAudioStemPlayerPool
extends RefCounted

## StemPlayerPool — katman çalar havuzu (Madde 08 / music_layering).
##
## Katmanlı müzik aynı anda birden fazla ses parçası (stem) çalar:
## ritim, melodi, davul, gerilim — hepsi SENKRON. Bu sınıf o
## katmanları yönetir: hangisi aktif, hangisinin sesi ne, hepsi
## aynı pozisyonda mı.
##
## Senkron kritik: katmanlar birbirinden kayarsa müzik dağılır.
## Tüm katmanlar aynı playback pozisyonunu paylaşır.
##
## Gerçek ses çalma Godot AudioStreamPlayer'ın işidir — bu sınıf
## havuzun MANTIK durumunu tutar: katman tanımları, aktiflik,
## ses seviyeleri, ortak pozisyon. Test edilebilir.
##
## Mock policy: katman durumu gerçek tanımlardan.

## Bir müzik katmanı.
class Stem extends RefCounted:
	var stem_name: String = ""
	var layer_index: int = 0          ## 0 = temel katman
	var target_volume: float = 1.0    ## Hedef ses (intensity'ye göre)
	var current_volume: float = 0.0   ## Anlık ses (geçiş sırasında)
	var is_active: bool = false

	func _init(p_name: String, p_index: int) -> void:
		stem_name = p_name
		layer_index = p_index


## Katmanlar — layer_index sırasıyla.
var _stems: Array = []

## Tüm katmanların paylaştığı çalma pozisyonu (saniye).
var playback_position: float = 0.0

## Ses geçiş hızı (saniyede ses birimi) — katman ekle/çıkar yumuşaklığı.
var volume_fade_rate: float = 2.0


# ============================================================
# KATMAN TANIMLAMA
# ============================================================

## Havuza bir katman ekler.
## stem_name: katman adı. layer_index: katman sırası (0 = temel).
func add_stem(stem_name: String, layer_index: int) -> void:
	if stem_name.is_empty():
		return
	_stems.append(Stem.new(stem_name, layer_index))
	# Katman sırasına göre sırala
	_stems.sort_custom(func(a: Stem, b: Stem) -> bool:
		return a.layer_index < b.layer_index)


## Tanımlı katman sayısı.
func stem_count() -> int:
	return _stems.size()


## Belirli sıradaki katmanı döndürür. Yoksa null.
func get_stem(layer_index: int) -> Stem:
	for stem_obj in _stems:
		var stem: Stem = stem_obj
		if stem.layer_index == layer_index:
			return stem
	return null


# ============================================================
# AKTİFLİK — intensity_manager ile entegrasyon
# ============================================================

## Aktif olması gereken katman sayısını uygular.
## active_count: IntensityManager'dan gelen aktif katman sayısı.
## Aktif katmanların hedef sesi 1'e, pasiflerin 0'a ayarlanır.
func set_active_layers(active_count: int) -> void:
	for stem_obj in _stems:
		var stem: Stem = stem_obj
		if stem.layer_index < active_count:
			stem.is_active = true
			stem.target_volume = 1.0
		else:
			# Pasif katman — sesi 0'a çekilir ama hemen susmaz
			stem.target_volume = 0.0


## Zamanı ilerletir — sesler hedefe doğru yumuşakça kayar.
## delta_seconds: geçen süre.
func tick(delta_seconds: float) -> void:
	if delta_seconds < 0.0:
		return
	playback_position += delta_seconds
	var max_change: float = volume_fade_rate * delta_seconds
	for stem_obj in _stems:
		var stem: Stem = stem_obj
		stem.current_volume = move_toward(
			stem.current_volume, stem.target_volume, max_change
		)
		# Ses tamamen 0 olunca katman gerçekten pasif
		if is_zero_approx(stem.current_volume) \
				and is_zero_approx(stem.target_volume):
			stem.is_active = false


# ============================================================
# SENKRON
# ============================================================

## Tüm katmanları belirli bir pozisyona senkronlar.
## Yeni katman eklenince mevcut pozisyondan başlamalı — kaymamalı.
func sync_to_position(position: float) -> void:
	playback_position = maxf(position, 0.0)


## Şu an duyulabilir (sesi 0'dan büyük) katman sayısı.
func audible_stem_count() -> int:
	var count: int = 0
	for stem_obj in _stems:
		if not is_zero_approx((stem_obj as Stem).current_volume):
			count += 1
	return count


# ============================================================
# DURUM
# ============================================================

## Havuz durum özeti.
func summary() -> Dictionary:
	return {
		"stem_count": _stems.size(),
		"audible_stems": audible_stem_count(),
		"playback_position": playback_position,
	}
