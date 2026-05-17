@tool
class_name AIAudioSfxDesigner
extends RefCounted

## ProceduralSfxDesigner — ses efekti tasarımcısı (Madde 08 / audio / ui).
##
## Prosedürel ses tasarım paneli: kullanıcı bir sfxr önayarı seçer
## (jump, explosion...), kaydırıcılarla parametreleri ayarlar
## (frekans, zarf...), önizler ve kaydeder.
##
## Bu view-model tasarımcının durumunu tutar: seçili önayar, ayarlanan
## parametreler, hangi parametreler değiştirildi. Görsel panel
## kaydırıcıları bu duruma bağlar.
##
## sfxr_presets + synth_engine (mantık katmanı) ile beslenir; bu
## sınıf düzenleme oturumunun durumunu yönetir.
##
## Mock policy: durum gerçek önayar + kullanıcı düzenlemelerinden.

## Ayarlanabilir parametreler ve görsel sınırları.
## param -> {min, max, label}
const PARAM_RANGES: Dictionary = {
	"frequency": {"min": 20.0, "max": 2000.0, "label": "Frekans"},
	"attack": {"min": 0.0, "max": 1.0, "label": "Atak"},
	"decay": {"min": 0.0, "max": 1.0, "label": "Düşüş"},
	"sustain": {"min": 0.0, "max": 1.0, "label": "Tutuş"},
	"release": {"min": 0.0, "max": 2.0, "label": "Bırakış"},
	"freq_slide": {"min": -1000.0, "max": 1000.0, "label": "Frekans Kayması"},
}


## Seçili önayar kimliği (yoksa boş).
var selected_preset: String = ""

## Mevcut parametre değerleri (önayardan + kullanıcı düzenlemeleri).
var _params: Dictionary = {}

## Kullanıcının değiştirdiği parametreler — "değiştirildi" rozeti için.
var _modified: Dictionary = {}


# ============================================================
# ÖNAYAR SEÇİMİ
# ============================================================

## Bir önayarı yükler — parametreleri önayardan alır.
## preset_id: önayar kimliği. preset_params: önayar parametreleri.
func load_preset(preset_id: String, preset_params: Dictionary) -> void:
	selected_preset = preset_id
	_params = preset_params.duplicate(true)
	_modified.clear()


# ============================================================
# PARAMETRE DÜZENLEME
# ============================================================

## Bir parametreyi ayarlar — kaydırıcı hareketinde çağrılır.
## param: parametre adı. value: yeni değer (sınıra çekilir).
## Dönen: {applied: float, clamped: bool}
func set_param(param: String, value: float) -> Dictionary:
	if not PARAM_RANGES.has(param):
		return {"applied": value, "clamped": false}
	var range_info: Dictionary = PARAM_RANGES[param]
	var clamped_value: float = clampf(
		value, float(range_info["min"]), float(range_info["max"])
	)
	_params[param] = clamped_value
	_modified[param] = true
	return {
		"applied": clamped_value,
		"clamped": not is_equal_approx(value, clamped_value),
	}


## Bir parametrenin mevcut değerini döndürür.
func get_param(param: String) -> float:
	return float(_params.get(param, 0.0))


## Bir parametre kullanıcı tarafından değiştirildi mi?
func is_modified(param: String) -> bool:
	return _modified.get(param, false)


## Tüm düzenlemeleri geri alır — önayarın orijinaline döner.
## original_params: orijinal önayar parametreleri.
func revert(original_params: Dictionary) -> void:
	_params = original_params.duplicate(true)
	_modified.clear()


# ============================================================
# SUNUM
# ============================================================

## Tüm parametre kaydırıcılarının görsel listesini üretir.
## Dönen: her biri {param, label, value, min, max, modified} dizi.
func build_sliders() -> Array:
	var sliders: Array = []
	for param in PARAM_RANGES:
		var range_info: Dictionary = PARAM_RANGES[param]
		sliders.append({
			"param": param,
			"label": str(range_info["label"]),
			"value": get_param(param),
			"min": float(range_info["min"]),
			"max": float(range_info["max"]),
			"modified": is_modified(param),
		})
	return sliders


## Mevcut parametreleri synth_engine'e verilecek sözlük olarak döndürür.
func current_params() -> Dictionary:
	return _params.duplicate(true)


# ============================================================
# SORGULAMA
# ============================================================

## Bir önayar yüklü mü?
func has_preset() -> bool:
	return not selected_preset.is_empty()


## Herhangi bir parametre değiştirildi mi?
func has_modifications() -> bool:
	for param in _modified:
		if bool(_modified[param]):
			return true
	return false


## Değiştirilen parametre sayısı.
func modified_count() -> int:
	var count: int = 0
	for param in _modified:
		if bool(_modified[param]):
			count += 1
	return count
