@tool
class_name AIProceduralMemory
extends AIMemoryStoreBase

## Procedural Memory — nasıl-yapılır belleği (Layer 1).
##
## Öğrenilmiş prosedürler: "şu işi şöyle yaparsan çalışır" bilgisi. İnsan
## zihnindeki "kas hafızası" gibi — adım adım, tekrarlanabilir reçeteler.
##
## Karakter:
##   - Kalıcı (diske yazılır)
##   - Neredeyse hiç decay yok — bir kez öğrenilen prosedür kalıcıdır
##   - Başarı oranı takip edilir — sık başarılı prosedür önem kazanır

## Procedural memory disk yolu.
const STORAGE_PATH: String = "user://ai_assistant/memory/procedural.json"


func _init() -> void:
	_setup(
		AIMemoryRecord.Layer.PROCEDURAL,
		STORAGE_PATH,
		true,   # persistent
		0       # sınırsız
	)


## Prosedürel bellek pratikte hiç zayıflamaz.
func add(record: AIMemoryRecord) -> bool:
	if record != null and record.layer == AIMemoryRecord.Layer.PROCEDURAL:
		record.decay_rate = 0.0  # decay yok
	return super.add(record)


## Yeni bir prosedür kaydeder.
## steps: adım adım yapılacaklar listesi.
func record_procedure(
	procedure_name: String, steps: PackedStringArray, context: String = ""
) -> AIMemoryRecord:
	var content: String = "Prosedür: %s\n" % procedure_name
	for i in range(steps.size()):
		content += "%d. %s\n" % [i + 1, steps[i]]
	if not context.is_empty():
		content += "Bağlam: %s" % context

	var record := AIMemoryRecord.create(AIMemoryRecord.Layer.PROCEDURAL, content)
	record.tags = PackedStringArray(["procedure"])
	record.structured_data["procedure_name"] = procedure_name
	record.structured_data["steps"] = steps
	record.structured_data["success_count"] = 0
	record.structured_data["failure_count"] = 0
	record.salience = 0.5
	add(record)
	return record


## Bir prosedürün kullanım sonucunu kaydeder.
## Başarılıysa önem artar, başarısızsa düşer.
func record_outcome(procedure_id: String, succeeded: bool) -> bool:
	var record: AIMemoryRecord = get_by_id(procedure_id)
	if record == null:
		return false

	if succeeded:
		var sc: int = int(record.structured_data.get("success_count", 0))
		record.structured_data["success_count"] = sc + 1
		record.salience = minf(1.0, record.salience + 0.05)
	else:
		var fc: int = int(record.structured_data.get("failure_count", 0))
		record.structured_data["failure_count"] = fc + 1
		record.salience = maxf(0.0, record.salience - 0.1)
	return true


## Bir prosedürün başarı oranını döndürür (0.0-1.0). Hiç kullanılmadıysa -1.
func success_rate(procedure_id: String) -> float:
	var record: AIMemoryRecord = get_by_id(procedure_id)
	if record == null:
		return -1.0
	var sc: int = int(record.structured_data.get("success_count", 0))
	var fc: int = int(record.structured_data.get("failure_count", 0))
	var total: int = sc + fc
	if total == 0:
		return -1.0  # hiç kullanılmadı
	return float(sc) / float(total)


## Bir prosedürün adımlarını döndürür.
func get_steps(procedure_id: String) -> PackedStringArray:
	var record: AIMemoryRecord = get_by_id(procedure_id)
	if record == null:
		return PackedStringArray()
	return PackedStringArray(record.structured_data.get("steps", []))


## İsme göre prosedür bulur. Yoksa null.
func find_procedure(procedure_name: String) -> AIMemoryRecord:
	for record in find_by_tag("procedure"):
		if record.structured_data.get("procedure_name", "") == procedure_name:
			return record
	return null


## En güvenilir prosedürleri döndürür (yüksek başarı oranlı).
func most_reliable(n: int = 5) -> Array:
	var procedures: Array = find_by_tag("procedure")
	procedures.sort_custom(func(a, b):
		return a.salience > b.salience
	)
	if n <= 0 or n >= procedures.size():
		return procedures
	return procedures.slice(0, n)
