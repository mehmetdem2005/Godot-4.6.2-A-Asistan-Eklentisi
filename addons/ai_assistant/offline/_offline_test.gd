@tool
class_name AIOfflineTest
extends RefCounted

## Madde 07 — Offline / Graceful Degradation Çekirdek Self-Test
##
## Sıkı testler: connection (ConnectionMonitor, LatencyTracker),
## cache (CacheBase, LLMResponseCache, EmbeddingCache), fallback
## (CapabilityMapper, TemplateLibrary, ProceduralFallbackRouter).


static func run_all() -> Array:
	var results: Array = []

	# ConnectionMonitor
	results.append(_b("Offline: Conn", _test_conn_states()))
	results.append(_b("Offline: Conn", _test_conn_failure_threshold()))
	results.append(_b("Offline: Conn", _test_conn_recovery()))
	results.append(_b("Offline: Conn", _test_conn_metered()))

	# LatencyTracker
	results.append(_b("Offline: Latency", _test_latency_average()))
	results.append(_b("Offline: Latency", _test_latency_window()))
	results.append(_b("Offline: Latency", _test_latency_slow()))

	# CacheBase
	results.append(_b("Offline: Cache", _test_cache_put_get()))
	results.append(_b("Offline: Cache", _test_cache_miss()))
	results.append(_b("Offline: Cache", _test_cache_lru()))
	results.append(_b("Offline: Cache", _test_cache_invalidate()))
	results.append(_b("Offline: Cache", _test_cache_hit_ratio()))

	# LLMResponseCache
	results.append(_b("Offline: LLMCache", _test_llm_key_stable()))
	results.append(_b("Offline: LLMCache", _test_llm_store_lookup()))

	# EmbeddingCache
	results.append(_b("Offline: EmbCache", _test_emb_store_lookup()))

	# CapabilityMapper
	results.append(_b("Offline: Capability", _test_cap_always()))
	results.append(_b("Offline: Capability", _test_cap_online_only()))
	results.append(_b("Offline: Capability", _test_cap_cache_backed()))

	# TemplateLibrary
	results.append(_b("Offline: Template", _test_template_generate()))
	results.append(_b("Offline: Template", _test_template_unknown()))

	# ProceduralFallbackRouter
	results.append(_b("Offline: Router", _test_router_online()))
	results.append(_b("Offline: Router", _test_router_cache()))
	results.append(_b("Offline: Router", _test_router_template()))
	results.append(_b("Offline: Router", _test_router_reject()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# CONNECTION MONITOR
# ============================================================

static func _test_conn_states() -> Dictionary:
	var name := "Conn durum geçişleri"
	var m := AIOfflineConnectionMonitor.new()
	# Hızlı başarı — online
	if m.report_success(500.0) != AIOfflineConnectionMonitor \
			.ConnState.ONLINE:
		return _fail(name, "hızlı başarı ONLINE olmalı")
	# Yavaş başarı — degraded
	if m.report_success(3000.0) != AIOfflineConnectionMonitor \
			.ConnState.DEGRADED:
		return _fail(name, "yavaş başarı DEGRADED olmalı")
	return _ok(name)


static func _test_conn_failure_threshold() -> Dictionary:
	var name := "Conn başarısızlık eşiği"
	var m := AIOfflineConnectionMonitor.new()
	# Tek hata — henüz offline değil
	m.report_failure()
	if m.is_offline():
		return _fail(name, "tek hata offline yapmamalı")
	# Eşiğe kadar hata — offline
	m.report_failure()
	m.report_failure()
	if not m.is_offline():
		return _fail(name, "3 hata sonrası offline olmalı")
	return _ok(name)


static func _test_conn_recovery() -> Dictionary:
	var name := "Conn başarı sonrası toparlanma"
	var m := AIOfflineConnectionMonitor.new()
	# Offline'a düş
	m.report_failure()
	m.report_failure()
	m.report_failure()
	# Başarı — toparlanmalı, fail sayacı sıfırlanmalı
	m.report_success(300.0)
	if m.is_offline():
		return _fail(name, "başarı sonrası offline olmamalı")
	if m.failure_count() != 0:
		return _fail(name, "başarı fail sayacını sıfırlamalı")
	return _ok(name)


static func _test_conn_metered() -> Dictionary:
	var name := "Conn ölçülü bağlantı"
	var m := AIOfflineConnectionMonitor.new()
	m.report_success(300.0)
	m.set_metered(false)
	if not m.is_safe_for_large_transfer():
		return _fail(name, "online + ölçülü değil — büyük transfer güvenli")
	m.set_metered(true)
	if m.is_safe_for_large_transfer():
		return _fail(name, "ölçülü bağlantıda büyük transfer güvensiz")
	return _ok(name)


# ============================================================
# LATENCY TRACKER
# ============================================================

static func _test_latency_average() -> Dictionary:
	var name := "Latency hareketli ortalama"
	var t := AIOfflineLatencyTracker.new()
	t.record(100.0)
	t.record(200.0)
	t.record(150.0)
	if absf(t.average() - 150.0) > 0.1:
		return _fail(name, "ortalama 150 olmalı")
	# Negatif yok sayılmalı
	t.record(-50.0)
	if t.sample_count() != 3:
		return _fail(name, "negatif ölçüm yok sayılmalı")
	return _ok(name)


static func _test_latency_window() -> Dictionary:
	var name := "Latency pencere sınırı"
	var t := AIOfflineLatencyTracker.new()
	# Pencere boyutundan fazla ekle
	for i in range(20):
		t.record(100.0)
	if t.sample_count() > AIOfflineLatencyTracker.WINDOW_SIZE:
		return _fail(name, "ölçüm sayısı pencereyi aşmamalı")
	return _ok(name)


static func _test_latency_slow() -> Dictionary:
	var name := "Latency yavaşlık tespiti"
	var t := AIOfflineLatencyTracker.new()
	# Hızlı — yavaş değil
	t.record(200.0)
	if t.is_slow():
		return _fail(name, "hızlı bağlantı yavaş sayılmamalı")
	# Yavaş ölçümler
	var slow := AIOfflineLatencyTracker.new()
	slow.record(3000.0)
	slow.record(3500.0)
	if not slow.is_slow():
		return _fail(name, "yüksek gecikme yavaş sayılmalı")
	return _ok(name)


# ============================================================
# CACHE BASE
# ============================================================

static func _test_cache_put_get() -> Dictionary:
	var name := "Cache yaz ve oku"
	var c := AIOfflineCacheBase.new(10, 3600)
	c.put("anahtar", "değer")
	var result: Dictionary = c.get_value("anahtar")
	if not result["hit"]:
		return _fail(name, "yazılan değer okunabilmeli")
	if str(result["value"]) != "değer":
		return _fail(name, "okunan değer yazılanla eşleşmeli")
	return _ok(name)


static func _test_cache_miss() -> Dictionary:
	var name := "Cache ıska"
	var c := AIOfflineCacheBase.new(10, 3600)
	var result: Dictionary = c.get_value("olmayan")
	if result["hit"]:
		return _fail(name, "olmayan anahtar ıska olmalı")
	# Boş anahtar reddi
	c.put("", "değer")
	if c.size() != 0:
		return _fail(name, "boş anahtar reddedilmeli")
	return _ok(name)


static func _test_cache_lru() -> Dictionary:
	var name := "Cache LRU eviction"
	var c := AIOfflineCacheBase.new(2, 0)  # max 2 girdi
	c.put("k1", "v1")
	c.put("k2", "v2")
	# k1'e eriş — k2 daha az kullanılan olur
	c.get_value("k1")
	# Üçüncü girdi — k2 atılmalı (LRU)
	c.put("k3", "v3")
	if c.has_valid("k2"):
		return _fail(name, "en az kullanılan k2 atılmalıydı")
	if not c.has_valid("k1"):
		return _fail(name, "yakında kullanılan k1 kalmalı")
	return _ok(name)


static func _test_cache_invalidate() -> Dictionary:
	var name := "Cache geçersiz kılma"
	var c := AIOfflineCacheBase.new(10, 3600)
	c.put("x", "1")
	if not c.invalidate("x"):
		return _fail(name, "var olan anahtar geçersiz kılınabilmeli")
	if c.has_valid("x"):
		return _fail(name, "geçersiz kılınan anahtar bulunmamalı")
	# Olmayan anahtar
	if c.invalidate("yok"):
		return _fail(name, "olmayan anahtar geçersiz kılınamaz")
	return _ok(name)


static func _test_cache_hit_ratio() -> Dictionary:
	var name := "Cache isabet oranı"
	var c := AIOfflineCacheBase.new(10, 3600)
	c.put("x", "1")
	c.get_value("x")       # hit
	c.get_value("x")       # hit
	c.get_value("yok")     # miss
	# 2 hit / 3 toplam
	if absf(c.hit_ratio() - (2.0 / 3.0)) > 0.01:
		return _fail(name, "isabet oranı 2/3 olmalı")
	return _ok(name)


# ============================================================
# LLM RESPONSE CACHE
# ============================================================

static func _test_llm_key_stable() -> Dictionary:
	var name := "LLMCache anahtar kararlılığı"
	var cache := AIOfflineLLMCache.new()
	var k1: String = cache.make_key("merhaba", "deepseek", 0.7)
	var k2: String = cache.make_key("merhaba", "deepseek", 0.7)
	# Aynı istek — aynı anahtar
	if k1 != k2:
		return _fail(name, "aynı istek aynı anahtar vermeli")
	# Farklı sıcaklık — farklı anahtar
	var k3: String = cache.make_key("merhaba", "deepseek", 0.9)
	if k1 == k3:
		return _fail(name, "farklı sıcaklık farklı anahtar vermeli")
	return _ok(name)


static func _test_llm_store_lookup() -> Dictionary:
	var name := "LLMCache sakla ve ara"
	var cache := AIOfflineLLMCache.new()
	cache.store("soru", "model_x", 0.5, "cevap metni")
	var result: Dictionary = cache.lookup("soru", "model_x", 0.5)
	if not result["hit"]:
		return _fail(name, "saklanan cevap bulunmalı")
	if str(result["response"]) != "cevap metni":
		return _fail(name, "bulunan cevap saklanan ile eşleşmeli")
	# Farklı istek — ıska
	var miss: Dictionary = cache.lookup("başka soru", "model_x", 0.5)
	if miss["hit"]:
		return _fail(name, "saklanmamış istek ıska olmalı")
	return _ok(name)


# ============================================================
# EMBEDDING CACHE
# ============================================================

static func _test_emb_store_lookup() -> Dictionary:
	var name := "EmbCache sakla ve ara"
	var cache := AIOfflineEmbeddingCache.new()
	var vector := PackedFloat32Array([0.1, 0.2, 0.3])
	cache.store("metin", "emb_model", vector)
	var result: Dictionary = cache.lookup("metin", "emb_model")
	if not result["hit"]:
		return _fail(name, "saklanan embedding bulunmalı")
	var found: PackedFloat32Array = result["embedding"]
	if found.size() != 3:
		return _fail(name, "embedding boyutu korunmalı")
	return _ok(name)


# ============================================================
# CAPABILITY MAPPER
# ============================================================

static func _test_cap_always() -> Dictionary:
	var name := "Capability ALWAYS yetenek"
	var m := AIOfflineCapabilityMapper.new()
	# template_codegen ALWAYS — offline bile available
	var offline: int = m.evaluate("template_codegen", false, false)
	if offline != AIOfflineCapabilityMapper.Availability.AVAILABLE:
		return _fail(name, "ALWAYS yetenek offline'da bile kullanılabilir")
	return _ok(name)


static func _test_cap_online_only() -> Dictionary:
	var name := "Capability ONLINE_ONLY yetenek"
	var m := AIOfflineCapabilityMapper.new()
	# new_llm_response ONLINE_ONLY
	if m.evaluate("new_llm_response", true, false) != \
			AIOfflineCapabilityMapper.Availability.AVAILABLE:
		return _fail(name, "ONLINE_ONLY online'da available olmalı")
	if m.evaluate("new_llm_response", false, true) != \
			AIOfflineCapabilityMapper.Availability.UNAVAILABLE:
		return _fail(name, "ONLINE_ONLY offline'da unavailable olmalı")
	return _ok(name)


static func _test_cap_cache_backed() -> Dictionary:
	var name := "Capability CACHE_BACKED yetenek"
	var m := AIOfflineCapabilityMapper.new()
	# rag_search CACHE_BACKED — offline + cache = degraded
	var degraded: int = m.evaluate("rag_search", false, true)
	if degraded != AIOfflineCapabilityMapper.Availability.DEGRADED:
		return _fail(name, "offline + cache DEGRADED olmalı")
	# offline + cache yok = unavailable
	var unavailable: int = m.evaluate("rag_search", false, false)
	if unavailable != AIOfflineCapabilityMapper.Availability.UNAVAILABLE:
		return _fail(name, "offline + cache yok UNAVAILABLE olmalı")
	return _ok(name)


# ============================================================
# TEMPLATE LIBRARY
# ============================================================

static func _test_template_generate() -> Dictionary:
	var name := "Template kod üretimi"
	var lib := AIOfflineTemplateLibrary.new()
	var result: Dictionary = lib.generate("empty_node", {
		"class_name": "Player", "base": "CharacterBody2D"
	})
	if not result["ok"]:
		return _fail(name, "geçerli şablon üretilmeli")
	var code: String = result["code"]
	# Yer tutucular doldurulmuş olmalı
	if not code.contains("Player"):
		return _fail(name, "class_name doldurulmalı")
	if code.contains("{class_name}"):
		return _fail(name, "yer tutucu kalmamalı")
	return _ok(name)


static func _test_template_unknown() -> Dictionary:
	var name := "Template bilinmeyen şablon"
	var lib := AIOfflineTemplateLibrary.new()
	var result: Dictionary = lib.generate("olmayan_sablon", {})
	if result["ok"]:
		return _fail(name, "bilinmeyen şablon reddedilmeli")
	return _ok(name)


# ============================================================
# FALLBACK ROUTER
# ============================================================

static func _test_router_online() -> Dictionary:
	var name := "Router online -> ağ"
	var conn := AIOfflineConnectionMonitor.new()
	conn.report_success(300.0)  # online
	var router := AIOfflineFallbackRouter.new(conn)
	var decision: AIOfflineFallbackRouter.RouteDecision = router.route(
		"new_llm_response"
	)
	if decision.route != AIOfflineFallbackRouter.Route.USE_NETWORK:
		return _fail(name, "online'da ağ kullanılmalı")
	return _ok(name)


static func _test_router_cache() -> Dictionary:
	var name := "Router offline + cache -> önbellek"
	var conn := AIOfflineConnectionMonitor.new()
	# Offline'a düşür
	conn.report_failure()
	conn.report_failure()
	conn.report_failure()
	var router := AIOfflineFallbackRouter.new(conn)
	var decision: AIOfflineFallbackRouter.RouteDecision = router.route(
		"new_llm_response", true, false, false
	)
	if decision.route != AIOfflineFallbackRouter.Route.USE_CACHE:
		return _fail(name, "offline + cache önbellek kullanmalı")
	return _ok(name)


static func _test_router_template() -> Dictionary:
	var name := "Router offline + şablon -> template"
	var conn := AIOfflineConnectionMonitor.new()
	conn.report_failure()
	conn.report_failure()
	conn.report_failure()
	var router := AIOfflineFallbackRouter.new(conn)
	# cache yok, template var
	var decision: AIOfflineFallbackRouter.RouteDecision = router.route(
		"new_llm_response", false, true, false
	)
	if decision.route != AIOfflineFallbackRouter.Route.USE_TEMPLATE:
		return _fail(name, "offline + şablon template kullanmalı")
	return _ok(name)


static func _test_router_reject() -> Dictionary:
	var name := "Router hiçbir yol yok -> REJECT"
	var conn := AIOfflineConnectionMonitor.new()
	conn.report_failure()
	conn.report_failure()
	conn.report_failure()
	var router := AIOfflineFallbackRouter.new(conn)
	# offline, cache yok, template yok, queueable değil
	var decision: AIOfflineFallbackRouter.RouteDecision = router.route(
		"new_llm_response", false, false, false
	)
	if decision.route != AIOfflineFallbackRouter.Route.REJECT:
		return _fail(name, "hiçbir yol yokken REJECT olmalı (sahte başarı yok)")
	return _ok(name)
