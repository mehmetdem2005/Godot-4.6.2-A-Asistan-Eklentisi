@tool
class_name AIMemoryTest
extends RefCounted

## Phase 1 / Layer 1 — Memory System Self-Test
##
## Sıkı testler: round-trip, decay davranışı, kapasite eviction, disk
## persistence, ve edge case'ler (boş depo, null kayıt, katman uyuşmazlığı).
##
## Mock policy: testler GERÇEK doğrulama yapar.
## Disk testleri user://ai_assistant/memory/test/ altında geçici dosya kullanır.

const TEST_DIR: String = "user://ai_assistant/memory/test"


## Tüm memory testlerini çalıştırır.
static func run_all() -> Array:
	var results: Array = []

	# Working Memory
	results.append(_b("Memory: Working", _test_working_not_persistent()))
	results.append(_b("Memory: Working", _test_working_capacity_eviction()))
	results.append(_b("Memory: Working", _test_working_fast_decay()))
	results.append(_b("Memory: Working", _test_working_reset()))

	# Episodic Memory
	results.append(_b("Memory: Episodic", _test_episodic_iteration_outcome()))
	results.append(_b("Memory: Episodic", _test_episodic_recall_failures()))
	results.append(_b("Memory: Episodic", _test_episodic_slow_decay()))

	# Semantic Memory
	results.append(_b("Memory: Semantic", _test_semantic_api_fact()))
	results.append(_b("Memory: Semantic", _test_semantic_verified_boost()))
	results.append(_b("Memory: Semantic", _test_semantic_genre_patterns()))

	# Procedural Memory
	results.append(_b("Memory: Procedural", _test_procedural_record()))
	results.append(_b("Memory: Procedural", _test_procedural_success_rate()))
	results.append(_b("Memory: Procedural", _test_procedural_no_decay()))

	# Store base — ortak davranış + edge case
	results.append(_b("Memory: Base", _test_base_null_record()))
	results.append(_b("Memory: Base", _test_base_layer_mismatch()))
	results.append(_b("Memory: Base", _test_base_search_and_tag()))
	results.append(_b("Memory: Base", _test_base_empty_store()))

	# Disk persistence
	results.append(_b("Memory: Disk", _test_disk_save_load_roundtrip()))
	results.append(_b("Memory: Disk", _test_disk_missing_file()))

	# Manager
	results.append(_b("Memory: Manager", _test_manager_routing()))
	results.append(_b("Memory: Manager", _test_manager_recall()))
	results.append(_b("Memory: Manager", _test_manager_stats()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(test_name: String) -> Dictionary:
	return {"ok": true, "name": test_name, "reason": ""}


static func _fail(test_name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": test_name, "reason": reason}


# ============================================================
# WORKING MEMORY
# ============================================================

static func _test_working_not_persistent() -> Dictionary:
	var name := "Working memory diske yazılmaz"
	var wm := AIWorkingMemory.new()
	# save_to_disk persistent=false olduğu için true döner ama dosya yazmaz
	if not wm.save_to_disk():
		return _fail(name, "non-persistent save true dönmeli")
	return _ok(name)


static func _test_working_capacity_eviction() -> Dictionary:
	var name := "Working memory kapasite eviction"
	var wm := AIWorkingMemory.new()
	# Kapasite 20 — 25 kayıt ekle, 20'de kalmalı
	for i in range(25):
		var r := AIMemoryRecord.create(AIMemoryRecord.Layer.WORKING, "kayit %d" % i)
		r.salience = 0.1 + (i * 0.03)  # artan önem
		wm.add(r)
	if wm.count() > AIWorkingMemory.DEFAULT_CAPACITY:
		return _fail(name, "kapasite aşıldı: %d" % wm.count())
	return _ok(name)


static func _test_working_fast_decay() -> Dictionary:
	var name := "Working memory hızlı decay"
	var wm := AIWorkingMemory.new()
	var r: AIMemoryRecord = wm.add_content("geçici bilgi")
	if r == null:
		return _fail(name, "add_content null döndü")
	# Working decay_rate 0.1 olmalı
	if abs(r.decay_rate - 0.1) > 0.0001:
		return _fail(name, "working decay_rate 0.1 olmalı: %s" % str(r.decay_rate))
	return _ok(name)


static func _test_working_reset() -> Dictionary:
	var name := "Working memory görev sınırında temizlenir"
	var wm := AIWorkingMemory.new()
	wm.add_content("a")
	wm.add_content("b")
	if wm.count() != 2:
		return _fail(name, "2 kayıt eklenmeli")
	wm.reset_for_new_task()
	if not wm.is_empty():
		return _fail(name, "reset sonrası boş olmalı")
	return _ok(name)


# ============================================================
# EPISODIC MEMORY
# ============================================================

static func _test_episodic_iteration_outcome() -> Dictionary:
	var name := "Episodic iteration sonucu kaydı"
	var em := AIEpisodicMemory.new()
	var r: AIMemoryRecord = em.record_iteration_outcome(
		"iter_5", "failed", "mesh oluşmadı"
	)
	if r == null:
		return _fail(name, "kayıt null döndü")
	if r.source_ref != "iter_5":
		return _fail(name, "source_ref yanlış")
	# Başarısız iteration daha yüksek önem (0.8)
	if abs(r.salience - 0.8) > 0.0001:
		return _fail(name, "başarısız iteration salience 0.8 olmalı")
	var recalled: Array = em.recall_iteration("iter_5")
	if recalled.size() != 1:
		return _fail(name, "recall_iteration yanlış")
	return _ok(name)


static func _test_episodic_recall_failures() -> Dictionary:
	var name := "Episodic başarısızlıkları hatırlama"
	var em := AIEpisodicMemory.new()
	em.record_iteration_outcome("i1", "success", "tamam")
	em.record_iteration_outcome("i2", "failed", "hata")
	em.record_debug_outcome("crash", false, "çözülemedi")
	var failures: Array = em.recall_failures()
	# i2 (failed) + debug (unresolved) = 2
	if failures.size() != 2:
		return _fail(name, "2 başarısızlık beklenir, %d bulundu" % failures.size())
	return _ok(name)


static func _test_episodic_slow_decay() -> Dictionary:
	var name := "Episodic yavaş decay"
	var em := AIEpisodicMemory.new()
	var r: AIMemoryRecord = em.add_content("önemli olay")
	if abs(r.decay_rate - 0.005) > 0.0001:
		return _fail(name, "episodic decay_rate 0.005 olmalı")
	return _ok(name)


# ============================================================
# SEMANTIC MEMORY
# ============================================================

static func _test_semantic_api_fact() -> Dictionary:
	var name := "Semantic API gerçeği kaydı"
	var sm := AISemanticMemory.new()
	var r: AIMemoryRecord = sm.record_api_fact(
		"AudioStreamPlayer3D inverse attenuation kullanır", "AudioStreamPlayer3D"
	)
	if r == null:
		return _fail(name, "kayıt null")
	if not r.tags.has("api_fact"):
		return _fail(name, "api_fact etiketi yok")
	if not r.tags.has("AudioStreamPlayer3D"):
		return _fail(name, "godot_class etiketi yok")
	if sm.all_api_facts().size() != 1:
		return _fail(name, "all_api_facts yanlış")
	return _ok(name)


static func _test_semantic_verified_boost() -> Dictionary:
	var name := "Semantic doğrulanmış bilgi önem kazanır"
	var sm := AISemanticMemory.new()
	var r: AIMemoryRecord = sm.record_api_fact("test gerçeği")
	var before: float = r.salience
	if not sm.mark_verified(r.id):
		return _fail(name, "mark_verified başarısız")
	if r.salience <= before:
		return _fail(name, "doğrulama önemi artırmalı")
	if r.structured_data.get("verified") != true:
		return _fail(name, "verified bayrağı set edilmeli")
	return _ok(name)


static func _test_semantic_genre_patterns() -> Dictionary:
	var name := "Semantic genre pattern filtreleme"
	var sm := AISemanticMemory.new()
	sm.record_pattern("FPS kamera", "Camera3D + raycast", "fps_3d")
	sm.record_pattern("Platform zıplama", "CharacterBody2D", "platformer_2d")
	var fps_patterns: Array = sm.patterns_for_genre("fps_3d")
	if fps_patterns.size() != 1:
		return _fail(name, "fps_3d için 1 pattern beklenir")
	return _ok(name)


# ============================================================
# PROCEDURAL MEMORY
# ============================================================

static func _test_procedural_record() -> Dictionary:
	var name := "Procedural prosedür kaydı"
	var pm := AIProceduralMemory.new()
	var steps := PackedStringArray(["Adım 1", "Adım 2", "Adım 3"])
	var r: AIMemoryRecord = pm.record_procedure("mesh ekleme", steps, "3d sahne")
	if r == null:
		return _fail(name, "kayıt null")
	var retrieved: PackedStringArray = pm.get_steps(r.id)
	if retrieved.size() != 3:
		return _fail(name, "3 adım beklenir, %d bulundu" % retrieved.size())
	var found: AIMemoryRecord = pm.find_procedure("mesh ekleme")
	if found == null:
		return _fail(name, "find_procedure bulamadı")
	return _ok(name)


static func _test_procedural_success_rate() -> Dictionary:
	var name := "Procedural başarı oranı takibi"
	var pm := AIProceduralMemory.new()
	var r: AIMemoryRecord = pm.record_procedure("test", PackedStringArray(["x"]))
	# Hiç kullanılmadı -> -1
	if pm.success_rate(r.id) != -1.0:
		return _fail(name, "kullanılmamış prosedür -1 dönmeli")
	# 3 başarı, 1 başarısızlık -> 0.75
	pm.record_outcome(r.id, true)
	pm.record_outcome(r.id, true)
	pm.record_outcome(r.id, true)
	pm.record_outcome(r.id, false)
	var rate: float = pm.success_rate(r.id)
	if abs(rate - 0.75) > 0.0001:
		return _fail(name, "başarı oranı 0.75 olmalı: %s" % str(rate))
	return _ok(name)


static func _test_procedural_no_decay() -> Dictionary:
	var name := "Procedural decay yok"
	var pm := AIProceduralMemory.new()
	var r: AIMemoryRecord = pm.record_procedure("kalıcı", PackedStringArray(["a"]))
	if r.decay_rate != 0.0:
		return _fail(name, "procedural decay_rate 0 olmalı")
	# 1000 gün geçse bile silinmemeli
	var removed: int = pm.apply_decay(1000.0)
	if removed != 0:
		return _fail(name, "procedural decay ile silinmemeli")
	return _ok(name)


# ============================================================
# STORE BASE — ortak davranış + edge case
# ============================================================

static func _test_base_null_record() -> Dictionary:
	var name := "Base null kayıt reddi"
	var wm := AIWorkingMemory.new()
	if wm.add(null):
		return _fail(name, "null kayıt eklenmemeli")
	return _ok(name)


static func _test_base_layer_mismatch() -> Dictionary:
	var name := "Base katman uyuşmazlığı reddi"
	var wm := AIWorkingMemory.new()
	# Episodic kayıt working depoya eklenememeli
	var wrong := AIMemoryRecord.create(AIMemoryRecord.Layer.EPISODIC, "yanlış katman")
	if wm.add(wrong):
		return _fail(name, "yanlış katman kaydı eklenmemeli")
	return _ok(name)


static func _test_base_search_and_tag() -> Dictionary:
	var name := "Base içerik arama ve etiket"
	var sm := AISemanticMemory.new()
	sm.add_content("Godot shader bilgisi", PackedStringArray(["shader"]))
	sm.add_content("Godot fizik bilgisi", PackedStringArray(["physics"]))
	var search: Array = sm.search_content("shader")
	if search.size() != 1:
		return _fail(name, "içerik araması 1 sonuç vermeli")
	var by_tag: Array = sm.find_by_tag("physics")
	if by_tag.size() != 1:
		return _fail(name, "etiket araması 1 sonuç vermeli")
	# Olmayan arama boş dönmeli
	if sm.search_content("yokböyle").size() != 0:
		return _fail(name, "olmayan içerik boş dönmeli")
	return _ok(name)


static func _test_base_empty_store() -> Dictionary:
	var name := "Base boş depo davranışı"
	var wm := AIWorkingMemory.new()
	if not wm.is_empty():
		return _fail(name, "yeni depo boş olmalı")
	if wm.count() != 0:
		return _fail(name, "boş depo count 0 olmalı")
	if wm.get_by_id("yok") != null:
		return _fail(name, "olmayan id null dönmeli")
	if wm.top_by_salience(5).size() != 0:
		return _fail(name, "boş depo top_by_salience boş dönmeli")
	return _ok(name)


# ============================================================
# DİSK PERSISTENCE
# ============================================================

static func _test_disk_save_load_roundtrip() -> Dictionary:
	var name := "Disk save/load round-trip"
	# Geçici test deposu — episodic mantığı ama test yolu
	var em := AIEpisodicMemory.new()
	em._storage_path = TEST_DIR + "/episodic_test.json"
	em.record_iteration_outcome("test_iter", "success", "test özeti")
	em.add_content("ikinci kayıt")
	var count_before: int = em.count()
	if not em.save_to_disk():
		return _fail(name, "save_to_disk başarısız")

	# Yeni depo — diskten yükle
	var em2 := AIEpisodicMemory.new()
	em2._storage_path = TEST_DIR + "/episodic_test.json"
	if not em2.load_from_disk():
		return _fail(name, "load_from_disk başarısız")
	if em2.count() != count_before:
		return _fail(name, "yüklenen kayıt sayısı uyuşmuyor: %d != %d" % [
			em2.count(), count_before
		])

	# Temizlik
	DirAccess.remove_absolute(TEST_DIR + "/episodic_test.json")
	return _ok(name)


static func _test_disk_missing_file() -> Dictionary:
	var name := "Disk eksik dosya zarif başlangıç"
	var em := AIEpisodicMemory.new()
	em._storage_path = TEST_DIR + "/yok_boyle_dosya.json"
	# Dosya yok — load_from_disk true dönmeli (ilk çalıştırma normal)
	if not em.load_from_disk():
		return _fail(name, "eksik dosya load true dönmeli (ilk çalıştırma)")
	if not em.is_empty():
		return _fail(name, "eksik dosyadan yükleme boş depo vermeli")
	return _ok(name)


# ============================================================
# MEMORY MANAGER
# ============================================================

static func _test_manager_routing() -> Dictionary:
	var name := "Manager kaydı doğru depoya yönlendirir"
	var mgr := AIMemoryManager.new()
	var episodic_rec := AIMemoryRecord.create(
		AIMemoryRecord.Layer.EPISODIC, "olay"
	)
	if not mgr.remember(episodic_rec):
		return _fail(name, "episodic kayıt eklenemedi")
	if mgr.episodic.count() != 1:
		return _fail(name, "kayıt episodic depoya gitmedi")
	if mgr.working.count() != 0:
		return _fail(name, "kayıt yanlış depoya gitti")
	return _ok(name)


static func _test_manager_recall() -> Dictionary:
	var name := "Manager tüm depolarda arama"
	var mgr := AIMemoryManager.new()
	mgr.working.add_content("Godot sahne")
	mgr.semantic.add_content("Godot API")
	var results: Dictionary = mgr.recall("Godot")
	var total: int = (
		(results["working"] as Array).size()
		+ (results["semantic"] as Array).size()
	)
	if total != 2:
		return _fail(name, "recall 2 sonuç vermeli, %d buldu" % total)
	return _ok(name)


static func _test_manager_stats() -> Dictionary:
	var name := "Manager istatistik doğruluğu"
	var mgr := AIMemoryManager.new()
	mgr.working.add_content("a")
	mgr.episodic.add_content("b")
	mgr.semantic.add_content("c")
	var stats: Dictionary = mgr.stats()
	if stats["total"] != 3:
		return _fail(name, "total 3 olmalı: %d" % stats["total"])
	if stats["working"] != 1 or stats["episodic"] != 1 or stats["semantic"] != 1:
		return _fail(name, "per-depo sayı yanlış")
	return _ok(name)
