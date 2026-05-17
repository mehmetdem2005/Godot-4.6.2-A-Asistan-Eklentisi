@tool
class_name AIPromptCache
extends RefCounted

## PromptCache — istem önbelleği (Layer 7).
##
## Aynı istek (aynı model + aynı mesajlar + aynı parametreler) iki kez
## gelirse, ikincisinde API'ye GİTMEYE GEREK YOK — ilk yanıtı sakla,
## tekrarında onu dön. Her cache hit = kazanılmış para.
##
## Bütçe-sınırlı bir proje için bu kritik bir tasarruf mekanizması.
##
## Cache anahtarı AIProviderRequest.compute_cache_key() ile deterministik
## üretilir — aynı içerik her zaman aynı anahtarı verir.
##
## Mock policy: cache sadece GERÇEK alınmış yanıtları saklar.

## Bellekte tutulan maksimum cache girdisi (LRU — en az kullanılan atılır).
const MAX_ENTRIES: int = 500

## Disk yolu — cache kalıcı (oturumlar arası tasarruf).
const CACHE_PATH: String = "user://ai_assistant/router/prompt_cache.json"


## Tek bir cache girdisi.
class CacheEntry extends RefCounted:
	var key: String = ""
	var content: String = ""
	var provider: int = 0
	var model: String = ""
	var input_tokens: int = 0
	var output_tokens: int = 0
	var created_at: String = ""
	var last_used_at: String = ""
	var hit_count: int = 0

	func to_dict() -> Dictionary:
		return {
			"key": key, "content": content, "provider": provider,
			"model": model, "input_tokens": input_tokens,
			"output_tokens": output_tokens, "created_at": created_at,
			"last_used_at": last_used_at, "hit_count": hit_count,
		}

	func from_dict(d: Dictionary) -> void:
		key = d.get("key", "")
		content = d.get("content", "")
		provider = int(d.get("provider", 0))
		model = d.get("model", "")
		input_tokens = int(d.get("input_tokens", 0))
		output_tokens = int(d.get("output_tokens", 0))
		created_at = d.get("created_at", "")
		last_used_at = d.get("last_used_at", "")
		hit_count = int(d.get("hit_count", 0))


## Cache girdileri — key -> CacheEntry
var _entries: Dictionary = {}

## LRU sırası — en eski kullanılan başta, en yeni sonda (key listesi).
var _lru_order: Array = []

## İstatistik sayaçları.
var _hit_count: int = 0
var _miss_count: int = 0


## Cache'teki girdi sayısı.
func count() -> int:
	return _entries.size()


# ============================================================
# OKUMA / YAZMA
# ============================================================

## Bir istek için cache'te yanıt var mı kontrol eder.
## request: AIProviderRequest.
## Dönen: AIProviderResponse (from_cache=true) veya null (cache miss).
func lookup(request: AIProviderRequest) -> AIProviderResponse:
	var key: String = request.compute_cache_key()
	if not _entries.has(key):
		_miss_count += 1
		return null

	# Cache hit — LRU'da en sona taşı (en yeni kullanılan)
	_hit_count += 1
	var entry: CacheEntry = _entries[key]
	entry.hit_count += 1
	entry.last_used_at = AIContractBase.now_iso()
	_touch_lru(key)

	var response := AIProviderResponse.create_from_cache(
		entry.content, entry.provider, entry.model
	)
	response.input_tokens = entry.input_tokens
	response.output_tokens = entry.output_tokens
	response.request_ref = request.id
	return response


## Bir yanıtı cache'e yazar.
## request: hangi istekti. response: alınan başarılı yanıt.
## Sadece başarılı, içerik dolu yanıtlar cache'lenir.
func store(request: AIProviderRequest, response: AIProviderResponse) -> bool:
	if response == null or not response.is_usable():
		return false  # başarısız/boş yanıt cache'lenmez
	# Zaten cache'ten gelen bir yanıtı tekrar yazma
	if response.from_cache:
		return false

	var key: String = request.compute_cache_key()
	var entry := CacheEntry.new()
	entry.key = key
	entry.content = response.content
	entry.provider = response.provider
	entry.model = response.model
	entry.input_tokens = response.input_tokens
	entry.output_tokens = response.output_tokens
	entry.created_at = AIContractBase.now_iso()
	entry.last_used_at = entry.created_at

	_entries[key] = entry
	_touch_lru(key)

	# Kapasite aşıldıysa en az kullanılanı (LRU başı) at
	while _entries.size() > MAX_ENTRIES and not _lru_order.is_empty():
		var evict_key: String = _lru_order.pop_front()
		_entries.erase(evict_key)
	return true


## Bir anahtarı LRU sırasında en sona (en yeni) taşır.
func _touch_lru(key: String) -> void:
	var idx: int = _lru_order.find(key)
	if idx >= 0:
		_lru_order.remove_at(idx)
	_lru_order.append(key)


## Bir istek için cache'te girdi var mı (bool — yanıt üretmeden).
func has(request: AIProviderRequest) -> bool:
	return _entries.has(request.compute_cache_key())


# ============================================================
# İSTATİSTİK
# ============================================================

## Cache hit oranı (0.0 - 1.0). Yüksek = iyi (para tasarrufu).
func hit_rate() -> float:
	var total: int = _hit_count + _miss_count
	if total == 0:
		return 0.0
	return float(_hit_count) / float(total)


## Cache istatistiği.
func stats() -> Dictionary:
	return {
		"entries": _entries.size(),
		"hits": _hit_count,
		"misses": _miss_count,
		"hit_rate": hit_rate(),
		"capacity": MAX_ENTRIES,
	}


# ============================================================
# DİSK KALICILIĞI
# ============================================================

## Cache'i diske yazar — atomik. Oturumlar arası tasarruf.
func save_to_disk() -> bool:
	var data: Dictionary = {
		"saved_at": AIContractBase.now_iso(),
		"entries": [],
		"lru_order": _lru_order,
	}
	for key in _entries:
		(data["entries"] as Array).append((_entries[key] as CacheEntry).to_dict())

	var dir_path: String = CACHE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp: String = CACHE_PATH + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("PromptCache.save: dosya açılamadı")
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, CACHE_PATH) == OK


## Cache'i diskten yükler.
func load_from_disk() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return true
	var f: FileAccess = FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("PromptCache.load: bozuk JSON")
		return false

	_entries.clear()
	for ed in (parsed as Dictionary).get("entries", []):
		var entry := CacheEntry.new()
		entry.from_dict(ed)
		if not entry.key.is_empty():
			_entries[entry.key] = entry
	_lru_order = (parsed as Dictionary).get("lru_order", [])
	return true


## Cache'i tamamen temizler — istatistikler de sıfırlanır.
func clear() -> void:
	_entries.clear()
	_lru_order.clear()
	_hit_count = 0
	_miss_count = 0
