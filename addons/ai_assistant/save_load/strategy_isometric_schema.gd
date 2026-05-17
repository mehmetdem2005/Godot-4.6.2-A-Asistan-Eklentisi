@tool
class_name AISaveStrategyIsometricSchema
extends AISaveGenreSchemaBase

## StrategyIsometricSchema — strateji oyun şeması (Madde 09).
##
## İzometrik strateji oyunu kaydeder: kaynaklar, kurulan binalar,
## birimler, araştırma ilerlemesi, harita durumu, oyun turu.


func _init() -> void:
	genre_name = "strategy_isometric"
	# Tur ve harita
	define_field("turn_number", FieldType.INT, 1)
	define_field("map_id", FieldType.STRING, "harita_1")
	# Kaynaklar
	define_field("resources", FieldType.DICT, {
		"gold": 100, "wood": 50, "stone": 50
	})
	# Varlıklar
	define_field("buildings", FieldType.ARRAY, [])
	define_field("units", FieldType.ARRAY, [])
	# Araştırma
	define_field("completed_research", FieldType.ARRAY, [])
	define_field("active_research", FieldType.STRING, "", false)
	# Diplomasi ve istatistik
	define_field("faction_relations", FieldType.DICT, {}, false)
	define_field("total_turns_played", FieldType.INT, 0, false)
