@tool
class_name AIOfflineCompletionTest
extends RefCounted

## Madde 07 — Offline Tamamlama Self-Test
##
## Sıkı testler: cache kalan (rag_result_cache, asset_metadata_cache,
## validation_cache), bandwidth (data_meter, bandwidth_tracker,
## bandwidth_governor), queue (priority_resolver, sync_queue,
## queue_processor).


static func run_all() -> Array:
	var results: Array = []

	# Cache kalan
	results.append(_b("OfflineExt: Cache", _test_rag_cache()))
	results.append(_b("OfflineExt: Cache", _test_rag_invalidate()))
	results.append(_b("OfflineExt: Cache", _test_asset_cache()))
	results.append(_b("OfflineExt: Cache", _test_asset_folder()))
	results.append(_b("OfflineExt: Cache", _test_validation_cache()))

	# Bandwidth
	results.append(_b("OfflineExt: Bandwidth", _test_data_meter()))
	results.append(_b("OfflineExt: Bandwidth", _test_bw_tracker()))
	results.append(_b("OfflineExt: Bandwidth", _test_bw_slow()))
	results.append(_b("OfflineExt: Bandwidth", _test_governor_cap()))
	results.append(_b("OfflineExt: Bandwidth", _test_governor_wifi()))
	results.append(_b("OfflineExt: Bandwidth", _test_governor_critical()))

	# Queue
	results.append(_b("OfflineExt: Queue", _test_priority_compute()))
	results.append(_b("OfflineExt: Queue", _test_priority_sort()))
	results.append(_b("OfflineExt: Queue", _test_sync_queue()))
	results.append(_b("OfflineExt: Queue", _test_queue_full()))
	results.append(_b("OfflineExt: Queue", _test_processor_success()))
	results.append(_b("OfflineExt: Queue", _test_processor_abandon()))
	results.append(_b("OfflineExt: Queue", _test_processor_offline()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# CACHE
# ============================================================

static func _test_rag_cache() -> Dictionary:
	var name := "RAGResultCache sakla/al"
	var cache := AIOfflineRAGResultCache.new()
	var ids := PackedStringArray(["doc1", "doc2", "doc3"])
	var scores := PackedFloat32Array([0.9, 0.8, 0.7])
	cache.store("nasıl zıplarım", 3, "docs", ids, scores)
	# Aynı sorgu — isabet
	var result: Dictionary = cache.fetch("nasıl zıplarım", 3, "docs")
	if not bool(result["hit"]):
		return _fail(name, "saklanan RAG sonucu alınabilmeli")
	var fetched_ids: PackedStringArray = result["result_ids"]
	if fetched_ids.size() != 3:
		return _fail(name, "sonuç kimlikleri korunmalı")
	return _ok(name)


static func _test_rag_invalidate() -> Dictionary:
	var name := "RAGResultCache koleksiyon invalidate"
	var cache := AIOfflineRAGResultCache.new()
	cache.store("soru1", 5, "kitaplar",
		PackedStringArray(["a"]), PackedFloat32Array([1.0]))
	cache.store("soru2", 5, "kitaplar",
		PackedStringArray(["b"]), PackedFloat32Array([1.0]))
	# Koleksiyon geçersizleştir
	var invalidated: int = cache.invalidate_collection("kitaplar")
	if invalidated != 2:
		return _fail(name, "koleksiyondaki tüm sonuçlar geçersizleşmeli")
	if cache.has("soru1", 5, "kitaplar"):
		return _fail(name, "invalidate sonrası sonuç kalmamalı")
	return _ok(name)


static func _test_asset_cache() -> Dictionary:
	var name := "AssetMetadataCache sakla/al"
	var cache := AIOfflineAssetMetadataCache.new()
	cache.store("res://player.tscn", {"size": 2048, "deps": []})
	var result: Dictionary = cache.fetch("res://player.tscn")
	if not bool(result["hit"]):
		return _fail(name, "varlık metadata'sı alınabilmeli")
	# Invalidate
	if not cache.invalidate("res://player.tscn"):
		return _fail(name, "varlık invalidate edilebilmeli")
	if cache.has("res://player.tscn"):
		return _fail(name, "invalidate sonrası varlık kalmamalı")
	return _ok(name)


static func _test_asset_folder() -> Dictionary:
	var name := "AssetMetadataCache klasör invalidate"
	var cache := AIOfflineAssetMetadataCache.new()
	cache.store("res://ui/menu.tscn", {"size": 100})
	cache.store("res://ui/hud.tscn", {"size": 200})
	cache.store("res://player.tscn", {"size": 300})
	# Klasör geçersizleştir
	var invalidated: int = cache.invalidate_folder("res://ui")
	if invalidated != 2:
		return _fail(name, "klasördeki varlıklar geçersizleşmeli")
	# Klasör dışı korunmalı
	if not cache.has("res://player.tscn"):
		return _fail(name, "klasör dışı varlık korunmalı")
	return _ok(name)


static func _test_validation_cache() -> Dictionary:
	var name := "ValidationCache içerik anahtarı"
	var cache := AIOfflineValidationCache.new()
	var code := "func test() -> void: pass"
	cache.store(code, "gdlint", true, PackedStringArray())
	# Aynı kod — isabet
	if not cache.has(code, "gdlint"):
		return _fail(name, "saklanan doğrulama alınabilmeli")
	# Farklı kod — ıska (içerik anahtarı değişir)
	if cache.has("func farkli() -> void: pass", "gdlint"):
		return _fail(name, "farklı kod farklı anahtar olmalı")
	return _ok(name)


# ============================================================
# BANDWIDTH
# ============================================================

static func _test_data_meter() -> Dictionary:
	var name := "DataMeter kategori sayımı"
	var meter := AIOfflineDataMeter.new()
	meter.record(AIOfflineDataMeter.CATEGORY_LLM, 1000, 5000)
	meter.record(AIOfflineDataMeter.CATEGORY_LLM, 500, 2000)
	# LLM toplamı = 1000+5000+500+2000
	if meter.category_total(AIOfflineDataMeter.CATEGORY_LLM) != 8500:
		return _fail(name, "kategori toplamı doğru olmalı")
	if meter.category_count(AIOfflineDataMeter.CATEGORY_LLM) != 2:
		return _fail(name, "işlem sayısı doğru olmalı")
	return _ok(name)


static func _test_bw_tracker() -> Dictionary:
	var name := "BandwidthTracker hız hesabı"
	var tracker := AIOfflineBandwidthTracker.new()
	tracker.record_transfer(100000, 1.0)  # 100 KB/s
	tracker.record_transfer(120000, 1.0)  # 120 KB/s
	# Ortalama ~110 KB/s
	var avg: float = tracker.average_speed()
	if avg < 100000.0 or avg > 120000.0:
		return _fail(name, "ortalama hız makul aralıkta olmalı")
	return _ok(name)


static func _test_bw_slow() -> Dictionary:
	var name := "BandwidthTracker yavaş tespiti"
	var tracker := AIOfflineBandwidthTracker.new()
	# Çok yavaş transfer — 10 KB/s
	tracker.record_transfer(10000, 1.0)
	tracker.record_transfer(8000, 1.0)
	if not tracker.is_slow():
		return _fail(name, "yavaş bağlantı tespit edilmeli")
	return _ok(name)


static func _test_governor_cap() -> Dictionary:
	var name := "BandwidthGovernor sınır denetimi"
	var governor := AIOfflineBandwidthGovernor.new()
	governor.set_mobile_cap(100 * 1024 * 1024)
	governor.set_connection(false)  # mobil
	# Sınır içinde — izin
	var ok_result: Dictionary = governor.authorize(1024 * 1024)
	if not bool(ok_result["allowed"]):
		return _fail(name, "sınır içi işlem izinli olmalı")
	# Sınırı aşacak işlem — reddet
	governor.mobile_used_bytes = 99 * 1024 * 1024
	var deny: Dictionary = governor.authorize(5 * 1024 * 1024)
	if bool(deny["allowed"]):
		return _fail(name, "sınır aşımı reddedilmeli")
	return _ok(name)


static func _test_governor_wifi() -> Dictionary:
	var name := "BandwidthGovernor Wi-Fi muafiyeti"
	var governor := AIOfflineBandwidthGovernor.new()
	governor.set_mobile_cap(10 * 1024 * 1024)
	governor.set_connection(true)  # Wi-Fi
	governor.mobile_used_bytes = 50 * 1024 * 1024  # sınır çok aşılmış
	# Wi-Fi'de mobil sınır uygulanmaz
	var result: Dictionary = governor.authorize(20 * 1024 * 1024)
	if not bool(result["allowed"]):
		return _fail(name, "Wi-Fi'de mobil sınır uygulanmamalı")
	return _ok(name)


static func _test_governor_critical() -> Dictionary:
	var name := "BandwidthGovernor kritik işlem"
	var governor := AIOfflineBandwidthGovernor.new()
	governor.set_mobile_cap(100 * 1024 * 1024)
	governor.set_connection(false)
	governor.mobile_used_bytes = 100 * 1024 * 1024  # sınır dolu
	# Kritik işlem — sınır dolu olsa da geçmeli
	var result: Dictionary = governor.authorize(1024 * 1024, true)
	if not bool(result["allowed"]):
		return _fail(name, "kritik işlem sınır dolsa da geçmeli")
	return _ok(name)


# ============================================================
# QUEUE
# ============================================================

static func _test_priority_compute() -> Dictionary:
	var name := "PriorityResolver öncelik hesabı"
	var resolver := AIOfflinePriorityResolver.new()
	# Kritik tür düşük türden öncelikli
	var critical: float = resolver.compute_priority("save_sync", 0.0, 0)
	var low: float = resolver.compute_priority("analytics", 0.0, 0)
	if critical <= low:
		return _fail(name, "kritik tür yüksek öncelikli olmalı")
	# Bekleme önceliği artırır
	var waited: float = resolver.compute_priority("analytics", 600.0, 0)
	if waited <= low:
		return _fail(name, "uzun bekleme önceliği artırmalı")
	return _ok(name)


static func _test_priority_sort() -> Dictionary:
	var name := "PriorityResolver sıralama"
	var resolver := AIOfflinePriorityResolver.new()
	var ops: Array = [
		{"type": "analytics", "wait_seconds": 0.0,
			"retry_count": 0, "id": "low"},
		{"type": "save_sync", "wait_seconds": 0.0,
			"retry_count": 0, "id": "high"},
	]
	var sorted_ops: Array = resolver.sort_by_priority(ops)
	# save_sync önce gelmeli
	if str((sorted_ops[0] as Dictionary)["id"]) != "high":
		return _fail(name, "yüksek öncelik öne sıralanmalı")
	return _ok(name)


static func _test_sync_queue() -> Dictionary:
	var name := "SyncQueue ekle/çıkar"
	var queue := AIOfflineSyncQueue.new()
	var result: Dictionary = queue.enqueue(
		"op1", "save_sync", {"data": "x"}, 1000
	)
	if not bool(result["enqueued"]):
		return _fail(name, "geçerli işlem eklenebilmeli")
	# Aynı id — çift eklenmez
	queue.enqueue("op1", "save_sync", {"data": "y"}, 1000)
	if queue.size() != 1:
		return _fail(name, "aynı id çift eklenmemeli")
	# Dequeue
	if not queue.dequeue("op1"):
		return _fail(name, "işlem kuyruktan çıkarılabilmeli")
	if not queue.is_empty():
		return _fail(name, "dequeue sonrası kuyruk boş olmalı")
	return _ok(name)


static func _test_queue_full() -> Dictionary:
	var name := "SyncQueue dolu kuyruk"
	var queue := AIOfflineSyncQueue.new(2)
	queue.enqueue("a", "save_sync", {}, 1)
	queue.enqueue("b", "save_sync", {}, 1)
	# Üçüncü — dolu kuyruk reddetmeli
	var result: Dictionary = queue.enqueue("c", "save_sync", {}, 1)
	if bool(result["enqueued"]):
		return _fail(name, "dolu kuyruk yeni işlem reddetmeli")
	return _ok(name)


static func _test_processor_success() -> Dictionary:
	var name := "QueueProcessor başarılı işlem"
	var queue := AIOfflineSyncQueue.new()
	queue.enqueue("s1", "save_sync", {}, 1000)
	var processor := AIOfflineQueueProcessor.new(queue)
	# Başarılı sonuç — kuyruktan çıkmalı
	var result: Dictionary = processor.report_result("s1", true)
	if str(result["action"]) != "removed":
		return _fail(name, "başarılı işlem kuyruktan çıkmalı")
	if processor.has_pending():
		return _fail(name, "başarılı işlem sonrası kuyruk boş olmalı")
	return _ok(name)


static func _test_processor_abandon() -> Dictionary:
	var name := "QueueProcessor vazgeçme"
	var queue := AIOfflineSyncQueue.new()
	queue.enqueue("s2", "save_sync", {}, 1000)
	var processor := AIOfflineQueueProcessor.new(queue)
	# Çok kez başarısız — sonunda vazgeçilmeli.
	# abandon anında döngü durur (sonrası işlem kuyrukta yok).
	var last_action: String = ""
	for i in range(AIOfflineQueueProcessor.MAX_RETRIES + 2):
		if not queue.has_operation("s2"):
			break
		var result: Dictionary = processor.report_result("s2", false)
		last_action = str(result["action"])
	if last_action != "abandoned":
		return _fail(name, "çok denenmiş işlem vazgeçilmeli")
	if queue.has_operation("s2"):
		return _fail(name, "vazgeçilen işlem kuyruktan silinmeli")
	return _ok(name)


static func _test_processor_offline() -> Dictionary:
	var name := "QueueProcessor çevrimdışı"
	var queue := AIOfflineSyncQueue.new()
	queue.enqueue("s3", "save_sync", {}, 1000)
	var processor := AIOfflineQueueProcessor.new(queue)
	# Çevrimdışı — işleme yapılamaz
	var plan: Dictionary = processor.plan_batch(false, 2000)
	if bool(plan["can_process"]):
		return _fail(name, "çevrimdışıyken işleme yapılamamalı")
	# Çevrimiçi + dolu kuyruk — işlenebilir
	var online_plan: Dictionary = processor.plan_batch(true, 2000)
	if not bool(online_plan["can_process"]):
		return _fail(name, "çevrimiçi + dolu kuyruk işlenebilmeli")
	return _ok(name)
