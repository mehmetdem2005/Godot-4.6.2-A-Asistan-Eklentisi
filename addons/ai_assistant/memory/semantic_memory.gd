@tool
class_name AISemanticMemory
extends AIMemoryStoreBase

## Semantic Memory — kavram/bilgi belleği (Layer 1).
##
## "Nasıl çalışır" bilgisi: Godot API gerçekleri, node pattern'leri, genre
## bilgisi. İnsan zihnindeki "kavramsal bilgi" gibi — olaya değil bilgiye dayalı.
##
## Karakter:
##   - Kalıcı (diske yazılır)
##   - Çok yavaş decay — bilgi kolay unutulmaz
##   - Doğrulanmış bilgi (verified) daha yüksek önem taşır

## Semantic memory disk yolu.
const STORAGE_PATH: String = "user://ai_assistant/memory/semantic.json"


func _init() -> void:
	_setup(
		AIMemoryRecord.Layer.SEMANTIC,
		STORAGE_PATH,
		true,   # persistent
		0       # sınırsız
	)


## Semantic bilgi neredeyse hiç zayıflamaz.
func add(record: AIMemoryRecord) -> bool:
	if record != null and record.layer == AIMemoryRecord.Layer.SEMANTIC:
		record.decay_rate = 0.001  # çok yavaş
	return super.add(record)


## Bir Godot API gerçeğini kaydeder.
## Örn: "AudioStreamPlayer3D inverse attenuation kullanır"
func record_api_fact(fact: String, godot_class: String = "") -> AIMemoryRecord:
	var record := AIMemoryRecord.create(AIMemoryRecord.Layer.SEMANTIC, fact)
	record.tags = PackedStringArray(["api_fact"])
	if not godot_class.is_empty():
		record.tags.append(godot_class)
		record.structured_data["godot_class"] = godot_class
	record.salience = 0.7
	add(record)
	return record


## Bir node pattern'i kaydeder.
## Örn: "FPS kamerası: Camera3D + SpringArm3D + raycast"
func record_pattern(pattern_name: String, description: String, genre_id: String = "") -> AIMemoryRecord:
	var record := AIMemoryRecord.create(
		AIMemoryRecord.Layer.SEMANTIC,
		"%s: %s" % [pattern_name, description]
	)
	record.tags = PackedStringArray(["pattern"])
	record.structured_data["pattern_name"] = pattern_name
	if not genre_id.is_empty():
		record.genre_id = genre_id
		record.tags.append(genre_id)
	record.salience = 0.65
	add(record)
	return record


## Bir bilgiyi "doğrulandı" olarak işaretler — önemi artar.
## Doğrulanmış bilgi (test edilmiş, çalıştığı görülmüş) daha güvenilir.
func mark_verified(record_id: String) -> bool:
	var record: AIMemoryRecord = get_by_id(record_id)
	if record == null:
		return false
	record.structured_data["verified"] = true
	record.salience = minf(1.0, record.salience + 0.2)
	return true


## Tüm API gerçeklerini döndürür.
func all_api_facts() -> Array:
	return find_by_tag("api_fact")


## Belirli bir genre için kayıtlı pattern'leri döndürür.
func patterns_for_genre(genre_id: String) -> Array:
	var matches: Array = []
	for record in find_by_tag("pattern"):
		if record.genre_id == genre_id:
			matches.append(record)
	return matches
