@tool
class_name AISaveRacing3DSchema
extends AISaveGenreSchemaBase

## Racing3DSchema — yarış oyun kayıt şeması (Madde 09 / genre_schemas).
##
## Yarış oyunu kaydeder: açılan araçlar/pistler, en iyi tur süreleri,
## kazanılan para, şampiyona ilerlemesi, araç ayarları.


func _init() -> void:
	genre_name = "racing_3d"
	# Araçlar ve pistler
	define_field("unlocked_cars", FieldType.ARRAY, ["baslangic_araci"])
	define_field("unlocked_tracks", FieldType.ARRAY, ["pist_1"])
	define_field("selected_car", FieldType.STRING, "baslangic_araci")
	# Ekonomi ve ilerleme
	define_field("credits", FieldType.INT, 0)
	define_field("championship_progress", FieldType.INT, 0)
	define_field("completed_races", FieldType.ARRAY, [])
	# Performans kayıtları
	define_field("best_lap_times", FieldType.DICT, {})
	define_field("car_upgrades", FieldType.DICT, {}, false)
	define_field("total_races", FieldType.INT, 0, false)
