@tool
class_name AISaveFPS3DSchema
extends AISaveGenreSchemaBase

## FPS3DSchema — FPS oyun kayıt şeması (Madde 09 / genre_schemas).
##
## Birinci-şahıs nişancı oyunu neyi kaydeder: oyuncu canı/zırhı,
## cephane, mevcut silah, tamamlanan bölüm, kontrol noktası konumu.


func _init() -> void:
	genre_name = "fps_3d"
	# Oyuncu durumu
	define_field("health", FieldType.FLOAT, 100.0)
	define_field("armor", FieldType.FLOAT, 0.0)
	define_field("position", FieldType.DICT, {"x": 0.0, "y": 0.0, "z": 0.0})
	# Silah ve cephane
	define_field("current_weapon", FieldType.STRING, "pistol")
	define_field("ammo_reserves", FieldType.DICT, {})
	define_field("unlocked_weapons", FieldType.ARRAY, [])
	# İlerleme
	define_field("current_level", FieldType.INT, 1)
	define_field("completed_levels", FieldType.ARRAY, [])
	define_field("checkpoint_id", FieldType.STRING, "", false)
	# İstatistik
	define_field("total_kills", FieldType.INT, 0, false)
	define_field("playtime_seconds", FieldType.FLOAT, 0.0, false)
