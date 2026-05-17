@tool
class_name AISaveRPGTopdownSchema
extends AISaveGenreSchemaBase

## RPGTopdownSchema — RPG oyun kayıt şeması (Madde 09 / genre_schemas).
##
## Tepeden-bakış RPG en zengin kayıt yapısına sahiptir: karakter
## seviyesi/deneyimi, envanter, görevler, harita keşfi, NPC ilişkileri,
## altın, beceri ağacı.


func _init() -> void:
	genre_name = "rpg_topdown"
	# Karakter
	define_field("character_name", FieldType.STRING, "Kahraman")
	define_field("level", FieldType.INT, 1)
	define_field("experience", FieldType.INT, 0)
	define_field("health", FieldType.FLOAT, 100.0)
	define_field("mana", FieldType.FLOAT, 50.0)
	define_field("position", FieldType.DICT, {"x": 0.0, "y": 0.0})
	define_field("current_map", FieldType.STRING, "baslangic_koyu")
	# Envanter ve ekonomi
	define_field("gold", FieldType.INT, 0)
	define_field("inventory", FieldType.ARRAY, [])
	define_field("equipped_items", FieldType.DICT, {})
	# Görevler ve dünya
	define_field("active_quests", FieldType.ARRAY, [])
	define_field("completed_quests", FieldType.ARRAY, [])
	define_field("discovered_maps", FieldType.ARRAY, [])
	define_field("npc_relations", FieldType.DICT, {}, false)
	# Beceriler
	define_field("skill_tree", FieldType.DICT, {}, false)
	define_field("playtime_seconds", FieldType.FLOAT, 0.0, false)
