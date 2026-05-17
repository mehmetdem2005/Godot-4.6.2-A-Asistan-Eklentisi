@tool
class_name AISaveSurvival3DSchema
extends AISaveGenreSchemaBase

## Survival3DSchema — hayatta kalma oyun şeması (Madde 09).
##
## Hayatta kalma oyunu en dinamik kayıt yapısına sahiptir: oyuncu
## hayati değerleri (açlık, susuzluk, sıcaklık), envanter, kurulan
## yapılar, dünya zamanı/günü, üretim ilerlemesi.


func _init() -> void:
	genre_name = "survival_3d"
	# Hayati değerler
	define_field("health", FieldType.FLOAT, 100.0)
	define_field("hunger", FieldType.FLOAT, 100.0)
	define_field("thirst", FieldType.FLOAT, 100.0)
	define_field("temperature", FieldType.FLOAT, 37.0)
	define_field("position", FieldType.DICT, {"x": 0.0, "y": 0.0, "z": 0.0})
	# Envanter ve üretim
	define_field("inventory", FieldType.ARRAY, [])
	define_field("crafted_items", FieldType.ARRAY, [])
	define_field("known_recipes", FieldType.ARRAY, [])
	# Dünya
	define_field("world_day", FieldType.INT, 1)
	define_field("world_time", FieldType.FLOAT, 0.0)
	define_field("placed_structures", FieldType.ARRAY, [])
	define_field("explored_chunks", FieldType.ARRAY, [], false)
	# İstatistik
	define_field("days_survived", FieldType.INT, 0, false)
