@tool
class_name AISavePlatformer2DSchema
extends AISaveGenreSchemaBase

## Platformer2DSchema — 2D platform oyun şeması (Madde 09).
##
## 2D platform oyunu neyi kaydeder: oyuncu canı, toplanan paralar/
## yıldızlar, açılan bölümler, mevcut dünya, güçlendirmeler.


func _init() -> void:
	genre_name = "platformer_2d"
	# Oyuncu durumu
	define_field("lives", FieldType.INT, 3)
	define_field("position", FieldType.DICT, {"x": 0.0, "y": 0.0})
	# Toplananlar
	define_field("coins", FieldType.INT, 0)
	define_field("stars_collected", FieldType.ARRAY, [])
	define_field("powerups", FieldType.ARRAY, [])
	# İlerleme
	define_field("current_world", FieldType.INT, 1)
	define_field("current_level", FieldType.INT, 1)
	define_field("unlocked_levels", FieldType.ARRAY, [])
	# İstatistik
	define_field("best_times", FieldType.DICT, {}, false)
	define_field("total_deaths", FieldType.INT, 0, false)
