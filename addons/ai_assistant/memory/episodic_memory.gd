@tool
class_name AIEpisodicMemory
extends AIMemoryStoreBase

## Episodic Memory — olay/deneyim belleği (Layer 1).
##
## "Ne yaptık, ne oldu" belleği. Her iteration sonunda, her debug oturumunda,
## her önemli olayda buraya kayıt düşer. İnsan zihnindeki "anı" gibi.
##
## Karakter:
##   - Kalıcı (diske yazılır — uygulama kapansa da kalır)
##   - Sınırsız kapasite (ama çok eski + önemsiz olanlar decay ile silinir)
##   - Yavaş decay — aylarca hatırlanır

## Episodic memory disk yolu.
const STORAGE_PATH: String = "user://ai_assistant/memory/episodic.json"


func _init() -> void:
	_setup(
		AIMemoryRecord.Layer.EPISODIC,
		STORAGE_PATH,
		true,   # persistent = true
		0       # kapasite sınırsız
	)


## Episodic kayıtlar yavaş zayıflar — uzun süre hatırlanır.
func add(record: AIMemoryRecord) -> bool:
	if record != null and record.layer == AIMemoryRecord.Layer.EPISODIC:
		# Yavaş decay — varsayılanın yarısı
		record.decay_rate = 0.005
	return super.add(record)


## Bir iteration'ın sonucunu kaydeder (retrospektif).
## outcome: "success" | "partial" | "failed"
func record_iteration_outcome(
	iteration_id: String, outcome: String, summary: String
) -> AIMemoryRecord:
	var record := AIMemoryRecord.create(
		AIMemoryRecord.Layer.EPISODIC,
		"Iteration %s — %s: %s" % [iteration_id, outcome, summary]
	)
	record.source_ref = iteration_id
	record.tags = PackedStringArray(["iteration", outcome])
	# Başarısız iteration'lar daha önemli — onlardan öğreniriz
	record.salience = 0.8 if outcome == "failed" else 0.6
	add(record)
	return record


## Bir debug oturumunun sonucunu kaydeder.
func record_debug_outcome(
	error_summary: String, was_resolved: bool, fix_summary: String
) -> AIMemoryRecord:
	var status: String = "çözüldü" if was_resolved else "çözülemedi"
	var record := AIMemoryRecord.create(
		AIMemoryRecord.Layer.EPISODIC,
		"Hata (%s): %s — Düzeltme: %s" % [status, error_summary, fix_summary]
	)
	record.tags = PackedStringArray(["debug", "resolved" if was_resolved else "unresolved"])
	record.salience = 0.7
	add(record)
	return record


## Belirli bir iteration'a ait tüm anıları döndürür.
func recall_iteration(iteration_id: String) -> Array:
	var matches: Array = []
	for record in all():
		if record.source_ref == iteration_id:
			matches.append(record)
	return matches


## Geçmiş başarısızlıkları döndürür — yeni planlamada "bunu tekrar yapma" için.
func recall_failures() -> Array:
	return find_by_tag("failed") + find_by_tag("unresolved")
