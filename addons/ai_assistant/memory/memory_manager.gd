@tool
class_name AIMemoryManager
extends RefCounted

## Memory Manager — 4 bellek deposunu yöneten ana sınıf (Layer 1).
##
## Sistemin geri kalanı belleğe DOĞRUDAN değil, bu yönetici üzerinden erişir.
## Tek sorumluluk noktası: kaydet, hatırla, diske yaz, diskten yükle, decay uygula.
##
## 4 depo:
##   working    — anlık (diske yazılmaz)
##   episodic   — olaylar (kalıcı)
##   semantic   — bilgi (kalıcı)
##   procedural — prosedürler (kalıcı)

var working: AIWorkingMemory
var episodic: AIEpisodicMemory
var semantic: AISemanticMemory
var procedural: AIProceduralMemory

## Son decay uygulamasının zamanı (ISO 8601).
var _last_decay_at: String = ""


func _init() -> void:
	working = AIWorkingMemory.new()
	episodic = AIEpisodicMemory.new()
	semantic = AISemanticMemory.new()
	procedural = AIProceduralMemory.new()
	_last_decay_at = AIContractBase.now_iso()


## Sistem başlangıcında çağrılır — kalıcı depoları diskten yükler.
## Working memory yüklenmez (kısa ömürlü, her oturum sıfırdan).
func initialize() -> bool:
	var ok: bool = true
	ok = episodic.load_from_disk() and ok
	ok = semantic.load_from_disk() and ok
	ok = procedural.load_from_disk() and ok
	return ok


## Tüm kalıcı depoları diske yazar. Düzenli aralıklarla + kapanışta çağrılır.
func persist() -> bool:
	var ok: bool = true
	ok = episodic.save_to_disk() and ok
	ok = semantic.save_to_disk() and ok
	ok = procedural.save_to_disk() and ok
	return ok


## Verilen katmanın deposunu döndürür.
func store_for_layer(layer: int) -> AIMemoryStoreBase:
	match layer:
		AIMemoryRecord.Layer.WORKING:
			return working
		AIMemoryRecord.Layer.EPISODIC:
			return episodic
		AIMemoryRecord.Layer.SEMANTIC:
			return semantic
		AIMemoryRecord.Layer.PROCEDURAL:
			return procedural
		_:
			return null


## Bir kaydı doğru depoya ekler (kaydın layer alanına göre).
func remember(record: AIMemoryRecord) -> bool:
	if record == null:
		return false
	var store: AIMemoryStoreBase = store_for_layer(record.layer)
	if store == null:
		push_warning("MemoryManager.remember: bilinmeyen katman")
		return false
	return store.add(record)


## Tüm depolarda metin araması yapar — ilgili tüm anıları döndürür.
## Bu, bir cell role'e "bu konuda ne biliyoruz" bilgisini verir.
func recall(query: String) -> Dictionary:
	return {
		"working": working.search_content(query),
		"episodic": episodic.search_content(query),
		"semantic": semantic.search_content(query),
		"procedural": procedural.search_content(query),
	}


## Tüm depolardaki toplam kayıt sayısı.
func total_records() -> int:
	return (
		working.count()
		+ episodic.count()
		+ semantic.count()
		+ procedural.count()
	)


## Her depoya decay uygular. Dönen değer: silinen toplam kayıt sayısı.
## Decay, son uygulamadan bu yana geçen süreye göre hesaplanır.
func run_decay_cycle() -> int:
	var now_unix: int = AIContractBase.iso_to_unix(AIContractBase.now_iso())
	var last_unix: int = AIContractBase.iso_to_unix(_last_decay_at)
	var elapsed_seconds: int = maxi(0, now_unix - last_unix)
	var elapsed_days: float = float(elapsed_seconds) / 86400.0

	var removed: int = 0
	removed += working.apply_decay(elapsed_days)
	removed += episodic.apply_decay(elapsed_days)
	removed += semantic.apply_decay(elapsed_days)
	removed += procedural.apply_decay(elapsed_days)

	_last_decay_at = AIContractBase.now_iso()
	return removed


## Bellek sistemi özeti — UI ve debug için.
func stats() -> Dictionary:
	return {
		"working": working.count(),
		"episodic": episodic.count(),
		"semantic": semantic.count(),
		"procedural": procedural.count(),
		"total": total_records(),
		"last_decay_at": _last_decay_at,
	}


## Yeni göreve geçişte çağrılır — working memory temizlenir, diğerleri korunur.
func new_task_boundary() -> void:
	working.reset_for_new_task()
