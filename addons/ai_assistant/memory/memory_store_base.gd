@tool
class_name AIMemoryStoreBase
extends RefCounted

## Bellek deposu temel sınıfı (Layer 1).
##
## Dört bellek katmanının (working/episodic/semantic/procedural) ortak davranışı:
## ekleme, sorgulama, silme, disk kalıcılığı, decay uygulama.
##
## Her depo AIMemoryRecord contract'larını saklar. Disk yazımı ATOMİK'tir
## (önce .tmp dosyaya yaz, sonra rename) — yarım dosya riski yok.
##
## Alt sınıflar: WorkingMemory, EpisodicMemory, SemanticMemory, ProceduralMemory.

## Bu deponun hangi bellek katmanı olduğu (alt sınıf belirler).
var _layer: int = AIMemoryRecord.Layer.WORKING

## Bellek kayıtları — id -> AIMemoryRecord
var _records: Dictionary = {}

## Bu depo diske yazılır mı? (working memory yazılmaz, kısa ömürlü)
var _persistent: bool = true

## Disk dosya yolu (persistent depolar için)
var _storage_path: String = ""

## Bu depoda izin verilen maksimum kayıt sayısı (0 = sınırsız)
var _capacity: int = 0


## Alt sınıf tarafından çağrılır — depoyu kurar.
func _setup(p_layer: int, p_storage_path: String, p_persistent: bool, p_capacity: int) -> void:
	_layer = p_layer
	_storage_path = p_storage_path
	_persistent = p_persistent
	_capacity = p_capacity


## Bu deponun katman adı.
func layer_name() -> String:
	return AIMemoryRecord.LAYER_NAMES.get(_layer, "working")


# ============================================================
# EKLEME
# ============================================================

## Bir bellek kaydı ekler. Kayıt geçersizse eklenmez ve false döner.
## Kapasite doluysa en düşük önemli kayıt çıkarılır (eviction).
func add(record: AIMemoryRecord) -> bool:
	if record == null:
		push_warning("MemoryStore.add: null kayıt")
		return false

	var validation: AIValidationResult = record.validate()
	if not validation.ok:
		push_warning("MemoryStore.add: geçersiz kayıt — %s" % validation.summary())
		return false

	# Kayıt bu deponun katmanına ait mi
	if record.layer != _layer:
		push_warning(
			"MemoryStore.add: katman uyuşmazlığı — kayıt '%s', depo '%s'"
			% [record.layer_name(), layer_name()]
		)
		return false

	# Kapasite kontrolü — doluysa eviction
	if _capacity > 0 and _records.size() >= _capacity and not _records.has(record.id):
		_evict_lowest_salience()

	_records[record.id] = record
	return true


## Metin içerikten hızlı kayıt ekler (kolaylık metodu).
func add_content(content: String, tags: PackedStringArray = PackedStringArray()) -> AIMemoryRecord:
	var record := AIMemoryRecord.create(_layer, content)
	record.tags = tags
	if add(record):
		return record
	return null


# ============================================================
# SORGULAMA
# ============================================================

## ID ile kayıt getirir. Yoksa null döner. Erişim sayacını artırır.
func get_by_id(id: String) -> AIMemoryRecord:
	if not _records.has(id):
		return null
	var record: AIMemoryRecord = _records[id]
	record.mark_accessed()
	return record


## Belirli bir etikete sahip tüm kayıtları döndürür.
func find_by_tag(tag: String) -> Array:
	var matches: Array = []
	for id in _records:
		var record: AIMemoryRecord = _records[id]
		if record.tags.has(tag):
			matches.append(record)
	return matches


## İçeriğinde verilen metni geçen kayıtları döndürür (basit metin araması).
func search_content(query: String) -> Array:
	var matches: Array = []
	var lower_query: String = query.to_lower()
	for id in _records:
		var record: AIMemoryRecord = _records[id]
		if record.content.to_lower().contains(lower_query):
			matches.append(record)
	return matches


## En önemli N kaydı döndürür (salience'a göre sıralı).
func top_by_salience(n: int) -> Array:
	var all: Array = _records.values()
	all.sort_custom(func(a, b): return a.salience > b.salience)
	if n <= 0 or n >= all.size():
		return all
	return all.slice(0, n)


## Tüm kayıtları döndürür.
func all() -> Array:
	return _records.values()


## Depodaki kayıt sayısı.
func count() -> int:
	return _records.size()


## Depo boş mu?
func is_empty() -> bool:
	return _records.is_empty()


# ============================================================
# SİLME
# ============================================================

## ID ile kayıt siler. Yoksa false döner.
func remove(id: String) -> bool:
	if not _records.has(id):
		return false
	_records.erase(id)
	return true


## Tüm kayıtları siler.
func clear() -> void:
	_records.clear()


## En düşük önemli kaydı çıkarır (kapasite eviction).
func _evict_lowest_salience() -> void:
	if _records.is_empty():
		return
	var lowest_id: String = ""
	var lowest_salience: float = 2.0  # 1.0'dan büyük başlangıç
	for id in _records:
		var record: AIMemoryRecord = _records[id]
		if record.salience < lowest_salience:
			lowest_salience = record.salience
			lowest_id = id
	if not lowest_id.is_empty():
		_records.erase(lowest_id)


# ============================================================
# DECAY (zaman içinde zayıflama)
# ============================================================

## Tüm kayıtlara decay uygular. effective_salience eşiğin altına düşen
## kayıtlar silinir. Dönen değer: silinen kayıt sayısı.
## elapsed_days: son decay'den bu yana geçen gün.
## threshold: bu önemin altındaki kayıtlar unutulur.
func apply_decay(elapsed_days: float, threshold: float = 0.05) -> int:
	var to_remove: PackedStringArray = PackedStringArray()
	for id in _records:
		var record: AIMemoryRecord = _records[id]
		var eff: float = record.effective_salience(elapsed_days)
		if eff < threshold:
			to_remove.append(id)
		else:
			# Decay'i kalıcı yap — salience güncellenir
			record.salience = eff
	for id in to_remove:
		_records.erase(id)
	return to_remove.size()


# ============================================================
# DİSK KALICILIĞI (atomic write)
# ============================================================

## Depoyu diske yazar (persistent değilse hiçbir şey yapmaz).
## Atomik: önce .tmp dosyaya yaz, sonra rename — yarım dosya riski yok.
func save_to_disk() -> bool:
	if not _persistent:
		return true  # Working memory diske yazılmaz, bu normal
	if _storage_path.is_empty():
		push_warning("MemoryStore.save: storage_path boş")
		return false

	# Tüm kayıtları serialize et
	var data: Dictionary = {
		"layer": layer_name(),
		"saved_at": AIContractBase.now_iso(),
		"records": [],
	}
	for id in _records:
		var record: AIMemoryRecord = _records[id]
		(data["records"] as Array).append(record.to_dict())

	var json_text: String = JSON.stringify(data, "  ")

	# Klasör mevcut değilse oluştur
	var dir_path: String = _storage_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# ATOMİK YAZIM: önce .tmp'e yaz
	var tmp_path: String = _storage_path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("MemoryStore.save: dosya açılamadı — %s" % tmp_path)
		return false
	f.store_string(json_text)
	f.close()

	# Yazım başarılıysa rename ile asıl dosyaya geç (atomik)
	var rename_err: int = DirAccess.rename_absolute(tmp_path, _storage_path)
	if rename_err != OK:
		push_error("MemoryStore.save: rename başarısız (kod %d)" % rename_err)
		return false
	return true


## Depoyu diskten yükler (persistent değilse hiçbir şey yapmaz).
## Dosya yoksa boş depo ile başlar — hata değil.
func load_from_disk() -> bool:
	if not _persistent:
		return true
	if _storage_path.is_empty():
		return false
	if not FileAccess.file_exists(_storage_path):
		return true  # İlk çalıştırma — dosya henüz yok, normal

	var f: FileAccess = FileAccess.open(_storage_path, FileAccess.READ)
	if f == null:
		push_error("MemoryStore.load: dosya açılamadı — %s" % _storage_path)
		return false
	var json_text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_error("MemoryStore.load: bozuk JSON — %s" % _storage_path)
		return false

	var data: Dictionary = parsed as Dictionary
	_records.clear()
	for record_dict in data.get("records", []):
		var record := AIMemoryRecord.new()
		record.from_dict(record_dict)
		# Yüklenen kayıt doğrulanır — bozuk kayıt atlanır (mock policy)
		if record.is_valid():
			_records[record.id] = record
		else:
			push_warning("MemoryStore.load: bozuk kayıt atlandı")
	return true
