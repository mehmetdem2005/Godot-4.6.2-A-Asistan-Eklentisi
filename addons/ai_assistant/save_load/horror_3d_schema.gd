@tool
class_name AISaveHorror3DSchema
extends AISaveGenreSchemaBase

## Horror3DSchema — korku oyun kayıt şeması (Madde 09 / genre_schemas).
##
## Korku oyunu gerilim-odaklı kaydeder: oyuncu konumu, sağlık/akıl
## sağlığı, envanter (anahtar/eşya), çözülen bulmacalar, tetiklenen
## olaylar, keşfedilen alanlar, pil/fener durumu.


func _init() -> void:
	genre_name = "horror_3d"
	# Oyuncu durumu
	define_field("health", FieldType.FLOAT, 100.0)
	define_field("sanity", FieldType.FLOAT, 100.0)
	define_field("position", FieldType.DICT, {"x": 0.0, "y": 0.0, "z": 0.0})
	# Envanter
	define_field("inventory", FieldType.ARRAY, [])
	define_field("key_items", FieldType.ARRAY, [])
	define_field("flashlight_battery", FieldType.FLOAT, 100.0)
	# İlerleme
	define_field("solved_puzzles", FieldType.ARRAY, [])
	define_field("triggered_events", FieldType.ARRAY, [])
	define_field("explored_areas", FieldType.ARRAY, [])
	define_field("current_chapter", FieldType.INT, 1)
	# İstatistik
	define_field("times_died", FieldType.INT, 0, false)
