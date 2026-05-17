@tool
class_name AIAudioMusicLayeringView
extends RefCounted

## MusicLayeringView — müzik katmanlama görünümü (Madde 08 / audio / ui).
##
## Katmanlı müzik düzenleme paneli: stem'leri (katmanları) listeler,
## her katmanın hangi yoğunluk seviyesinde aktif olduğunu gösterir,
## yoğunluk eşiklerini ayarlatır.
##
## Bu view-model katmanlama düzeninin görsel durumunu tutar: stem
## listesi, eşik ayarları, mevcut yoğunluk önizlemesi.
##
## intensity_manager + stem_player_pool (mantık katmanı) ile
## beslenir; bu sınıf onları görsel düzenleyiciye çevirir.
##
## Mock policy: görünüm gerçek stem + yoğunluk verisinden.

## Bir stem satırının görsel tanımı.
class StemRow extends RefCounted:
	var stem_name: String = ""
	var layer_index: int = 0
	var label: String = ""
	## Bu katmanın aktif olduğu minimum yoğunluk (0-1).
	var activation_threshold: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"name": stem_name, "layer": layer_index,
			"label": label, "threshold": activation_threshold,
		}


## Stem satırları — layer_index sıralı.
var _stems: Array = []

## Önizleme yoğunluğu (0-1) — düzenleyicide test için.
var preview_intensity: float = 0.0


# ============================================================
# STEM TANIMLAMA
# ============================================================

## Bir stem satırı ekler.
## stem_name: katman adı. layer_index: katman sırası.
## label: kullanıcı-dostu etiket. threshold: aktivasyon eşiği.
func add_stem(
	stem_name: String, layer_index: int,
	label: String, threshold: float
) -> void:
	if stem_name.is_empty():
		return
	var row := StemRow.new()
	row.stem_name = stem_name
	row.layer_index = layer_index
	row.label = label
	row.activation_threshold = clampf(threshold, 0.0, 1.0)
	_stems.append(row)
	_stems.sort_custom(func(a: StemRow, b: StemRow) -> bool:
		return a.layer_index < b.layer_index)


## Bir stem'in aktivasyon eşiğini ayarlar.
func set_threshold(layer_index: int, threshold: float) -> bool:
	for stem_obj in _stems:
		var stem: StemRow = stem_obj
		if stem.layer_index == layer_index:
			stem.activation_threshold = clampf(threshold, 0.0, 1.0)
			return true
	return false


# ============================================================
# ÖNİZLEME
# ============================================================

## Önizleme yoğunluğunu ayarlar — düzenleyicide "şu yoğunlukta nasıl"
## test etmek için.
func set_preview_intensity(intensity: float) -> void:
	preview_intensity = clampf(intensity, 0.0, 1.0)


## Bir stem önizleme yoğunluğunda aktif olur mu?
func is_active_at_preview(layer_index: int) -> bool:
	for stem_obj in _stems:
		var stem: StemRow = stem_obj
		if stem.layer_index == layer_index:
			return preview_intensity >= stem.activation_threshold
	return false


# ============================================================
# SUNUM
# ============================================================

## Tüm stem satırlarının görsel listesini üretir.
## Dönen: her biri {name, layer, label, threshold, active_at_preview}
func build_rows() -> Array:
	var rows: Array = []
	for stem_obj in _stems:
		var stem: StemRow = stem_obj
		var row: Dictionary = stem.to_dict()
		row["active_at_preview"] = is_active_at_preview(stem.layer_index)
		rows.append(row)
	return rows


## Önizleme yoğunluğunda kaç katman aktif?
func active_layer_count_at_preview() -> int:
	var count: int = 0
	for stem_obj in _stems:
		if is_active_at_preview((stem_obj as StemRow).layer_index):
			count += 1
	return count


# ============================================================
# SORGULAMA
# ============================================================

## Tanımlı stem sayısı.
func stem_count() -> int:
	return _stems.size()


## Eşikler tutarlı mı (katman sırası arttıkça eşik artmalı)?
## Mantıklı katmanlama: temel katman düşük eşik, üst katmanlar yüksek.
func thresholds_consistent() -> bool:
	for i in range(1, _stems.size()):
		var prev: StemRow = _stems[i - 1]
		var curr: StemRow = _stems[i]
		# Sonraki katmanın eşiği öncekinden küçük olmamalı
		if curr.activation_threshold < prev.activation_threshold:
			return false
	return true
