@tool
class_name AIAudioVolumeManager
extends RefCounted

## VolumeManager — ses ayarı yöneticisi (Madde 08 / Audio System).
##
## Oyuncu ayarlar menüsünden ses seviyelerini değiştirir: müzik %70,
## efektler %100, vb. Bu sınıf o ayarları YÖNETİR ve KALICI yapar
## (sözlük olarak — Save/Load ile diske yazılabilir).
##
## Ses, kullanıcıya YÜZDE (0-100) olarak gösterilir ama motor DESİBEL
## kullanır. Bu sınıf ikisi arasında çevirir — doğru logaritmik eğri
## ile (insan kulağı sesi logaritmik algılar; lineer yüzde yanlış
## hissettirir).
##
## Mock policy: ayarlar gerçek kullanıcı girdisinden; çevrim gerçek
## logaritmik formülden.

## Yüzde sınırları.
const MIN_PERCENT: float = 0.0
const MAX_PERCENT: float = 100.0

## Sessizlik eşiği — bu yüzdenin altı tam sessiz sayılır.
const SILENCE_PERCENT: float = 0.5


## Bus ses ayarları — bus_name -> yüzde (0-100).
var _volumes: Dictionary = {}


func _init() -> void:
	_set_defaults()


## Varsayılan ses seviyeleri — makul oyun varsayılanları.
func _set_defaults() -> void:
	_volumes = {
		"Master": 100.0,
		"Music": 70.0,
		"SFX": 100.0,
		"UI": 80.0,
		"Ambient": 60.0,
		"Voice": 100.0,
	}


# ============================================================
# SES AYARLAMA
# ============================================================

## Bir bus'ın sesini yüzde olarak ayarlar.
## percent: 0-100. Sınır dışı değer kırpılır.
func set_volume_percent(bus_name: String, percent: float) -> void:
	if bus_name.is_empty():
		return
	_volumes[bus_name] = clampf(percent, MIN_PERCENT, MAX_PERCENT)


## Bir bus'ın yüzde sesini döndürür. Tanımsızsa 100.
func get_volume_percent(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 100.0))


## Bir bus tam sessiz mi (yüzde sessizlik eşiğinin altında)?
func is_silent(bus_name: String) -> bool:
	return get_volume_percent(bus_name) < SILENCE_PERCENT


# ============================================================
# YÜZDE <-> DESİBEL ÇEVRİMİ
# ============================================================

## Yüzdeyi (0-100) desibele çevirir — logaritmik eğri.
## %100 -> 0 dB, %0 -> -80 dB (sessiz). İnsan kulağına doğru his.
func percent_to_db(percent: float) -> float:
	var clamped: float = clampf(percent, MIN_PERCENT, MAX_PERCENT)
	if clamped < SILENCE_PERCENT:
		return -80.0  # tam sessiz
	# linear_to_db: 0.0-1.0 lineer ses -> dB
	return linear_to_db(clamped / 100.0)


## Desibeli yüzdeye çevirir — percent_to_db'nin tersi.
func db_to_percent(db: float) -> float:
	if db <= -80.0:
		return 0.0
	# db_to_linear: dB -> 0.0-1.0 lineer
	var linear: float = db_to_linear(db)
	return clampf(linear * 100.0, MIN_PERCENT, MAX_PERCENT)


## Bir bus'ın sesini doğrudan dB olarak döndürür — motora vermek için.
func get_volume_db(bus_name: String) -> float:
	return percent_to_db(get_volume_percent(bus_name))


# ============================================================
# KALICILIK
# ============================================================

## Ayarları sözlük olarak — Save/Load ile diske yazılır.
func to_dict() -> Dictionary:
	return _volumes.duplicate()


## Bir sözlükten ayarları yükler — geçersiz değerler kırpılır.
func from_dict(data: Dictionary) -> void:
	for bus_name in data:
		var value: Variant = data[bus_name]
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			set_volume_percent(str(bus_name), float(value))


## Ayarları varsayılana sıfırlar.
func reset() -> void:
	_set_defaults()


## Ayar özeti.
func summary() -> Dictionary:
	return {
		"bus_count": _volumes.size(),
		"master_percent": get_volume_percent("Master"),
	}
