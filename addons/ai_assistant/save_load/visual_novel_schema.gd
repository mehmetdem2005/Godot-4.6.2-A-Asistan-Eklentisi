@tool
class_name AISaveVisualNovelSchema
extends AISaveGenreSchemaBase

## VisualNovelSchema — görsel roman kayıt şeması (Madde 09).
##
## Görsel roman hikaye-odaklı kaydeder: mevcut sahne/diyalog,
## yapılan seçimler, görülen rotalar, karakter ilişki puanları,
## açılan sonlar, okunan CG galerisi.


func _init() -> void:
	genre_name = "visual_novel"
	# Hikaye konumu
	define_field("current_scene", FieldType.STRING, "prolog")
	define_field("dialogue_index", FieldType.INT, 0)
	define_field("current_route", FieldType.STRING, "ortak", false)
	# Seçimler ve ilerleme
	define_field("choices_made", FieldType.DICT, {})
	define_field("flags", FieldType.DICT, {})
	define_field("affection_points", FieldType.DICT, {})
	# Açılanlar
	define_field("unlocked_endings", FieldType.ARRAY, [])
	define_field("seen_cg", FieldType.ARRAY, [], false)
	define_field("read_scenes", FieldType.ARRAY, [], false)
	# Ayar
	define_field("text_speed", FieldType.FLOAT, 1.0, false)
