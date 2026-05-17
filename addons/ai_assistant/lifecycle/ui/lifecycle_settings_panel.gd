@tool
class_name AILifecycleSettingsPanel
extends RefCounted

## LifecycleSettingsPanel — yaşam döngüsü ayarları (Madde 10 / ui).
##
## Cihaz/yaşam döngüsü ayarlarının kullanıcı paneli: titreşim aç/kapat,
## ekran uyanık tutma tercihi, pil tasarrufu modu, geri tuşu davranışı.
##
## Bu view-model ayar durumlarını tutar ve doğrular — her ayar geçerli
## değerde mi, değişiklik var mı. Görsel panel anahtarları/kaydırıcıları
## bu duruma bağlar.
##
## device_control modülleri (mantık katmanı) ile beslenir.
##
## Mock policy: ayarlar gerçek kullanıcı tercihlerinden.

## Ayar tanımları — anahtar -> {type, default, label}.
## type: "bool" | "enum"
const SETTINGS: Dictionary = {
	"vibration_enabled": {
		"type": "bool", "default": true, "label": "Titreşim",
	},
	"keep_screen_awake": {
		"type": "bool", "default": false,
		"label": "Ekranı Açık Tut (Cutscene)",
	},
	"power_save_mode": {
		"type": "bool", "default": false, "label": "Güç Tasarrufu",
	},
	"confirm_on_exit": {
		"type": "bool", "default": true, "label": "Çıkışta Onay Sor",
	},
}


## Mevcut ayar değerleri.
var _values: Dictionary = {}

## Varsayılandan değişen ayarlar — "değiştirildi" rozeti için.
var _changed: Dictionary = {}


func _init() -> void:
	_load_defaults()


## Tüm ayarları varsayılan değerlerine yükler.
func _load_defaults() -> void:
	for key in SETTINGS:
		_values[key] = SETTINGS[key]["default"]
	_changed.clear()


# ============================================================
# AYAR DEĞİŞTİRME
# ============================================================

## Bir ayar değerini günceller.
## key: ayar anahtarı. value: yeni değer.
## Dönen: {applied: bool, reason: String}
func set_value(key: String, value: Variant) -> Dictionary:
	if not SETTINGS.has(key):
		return {"applied": false, "reason": "Bilinmeyen ayar: " + key}

	# Tip kontrolü — bool ayarlar bool değer almalı
	var setting_type: String = str(SETTINGS[key]["type"])
	if setting_type == "bool" and typeof(value) != TYPE_BOOL:
		return {"applied": false, "reason": "Bu ayar bool değer bekler"}

	_values[key] = value
	# Varsayılandan farklıysa "değiştirildi" işaretle
	_changed[key] = (value != SETTINGS[key]["default"])
	return {"applied": true, "reason": "Ayar güncellendi"}


## Bir ayarın mevcut değerini döndürür.
func get_value(key: String) -> Variant:
	return _values.get(key, null)


## Tüm ayarları varsayılana sıfırlar.
func reset_to_defaults() -> void:
	_load_defaults()


# ============================================================
# SUNUM
# ============================================================

## Tüm ayarların görsel listesini üretir.
## Dönen: her biri {key, label, type, value, changed} dizi.
func build_settings_list() -> Array:
	var list: Array = []
	for key in SETTINGS:
		list.append({
			"key": key,
			"label": str(SETTINGS[key]["label"]),
			"type": str(SETTINGS[key]["type"]),
			"value": _values.get(key, SETTINGS[key]["default"]),
			"changed": bool(_changed.get(key, false)),
		})
	return list


# ============================================================
# KALICILIK
# ============================================================

## Ayarları kaydetmek için sözlüğe çevirir.
func to_dict() -> Dictionary:
	return _values.duplicate(true)


## Kaydedilmiş ayarları yükler.
## data: ayar sözlüğü.
func from_dict(data: Dictionary) -> void:
	_load_defaults()
	for key in SETTINGS:
		if data.has(key):
			set_value(key, data[key])


# ============================================================
# SORGULAMA
# ============================================================

## Herhangi bir ayar varsayılandan değiştirildi mi?
func has_changes() -> bool:
	for key in _changed:
		if bool(_changed[key]):
			return true
	return false


## Toplam ayar sayısı.
func setting_count() -> int:
	return SETTINGS.size()
