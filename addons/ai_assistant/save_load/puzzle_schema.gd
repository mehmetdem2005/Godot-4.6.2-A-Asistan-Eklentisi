@tool
class_name AISavePuzzleSchema
extends AISaveGenreSchemaBase

## PuzzleSchema — bulmaca oyun kayıt şeması (Madde 09 / genre_schemas).
##
## Bulmaca oyunu sade kaydeder: çözülen bulmacalar, mevcut bulmaca,
## yıldız/puan, ipucu sayacı, açılan bölüm paketleri.


func _init() -> void:
	genre_name = "puzzle"
	# İlerleme
	define_field("current_puzzle", FieldType.INT, 1)
	define_field("solved_puzzles", FieldType.ARRAY, [])
	define_field("unlocked_packs", FieldType.ARRAY, [])
	# Puanlama
	define_field("total_stars", FieldType.INT, 0)
	define_field("puzzle_scores", FieldType.DICT, {})
	define_field("hints_remaining", FieldType.INT, 5)
	# İstatistik
	define_field("best_solve_times", FieldType.DICT, {}, false)
	define_field("total_moves", FieldType.INT, 0, false)
