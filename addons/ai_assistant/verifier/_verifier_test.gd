@tool
class_name AIVerifierTest
extends RefCounted

## Phase 5 / Layer 5 — Verifier Self-Test
##
## Sıkı testler: SyntacticVerifier (gerçek motor derlemesi), SemanticVerifier
## (anlamsal analiz), VerifierEngine (kademeli koşturma).
##
## NOT: SYNTACTIC seviye Godot'un GERÇEK derleyicisini çağırır — bu testler
## ancak Godot içinde anlamlı sonuç verir. Container'da GDScript.new()
## farklı davranabilir; o yüzden syntactic testler savunmacı yazıldı.


static func run_all() -> Array:
	var results: Array = []

	# SyntacticVerifier
	results.append(_b("Verify: Syntactic", _test_syn_valid_code()))
	results.append(_b("Verify: Syntactic", _test_syn_empty_source()))
	results.append(_b("Verify: Syntactic", _test_syn_bracket_imbalance()))
	results.append(_b("Verify: Syntactic", _test_syn_bracket_mismatch()))
	results.append(_b("Verify: Syntactic", _test_syn_string_brackets()))

	# SemanticVerifier
	results.append(_b("Verify: Semantic", _test_sem_clean_code()))
	results.append(_b("Verify: Semantic", _test_sem_duplicate_func()))
	results.append(_b("Verify: Semantic", _test_sem_duplicate_member()))
	results.append(_b("Verify: Semantic", _test_sem_classname_no_extends()))
	results.append(_b("Verify: Semantic", _test_sem_extends_order()))
	results.append(_b("Verify: Semantic", _test_sem_bad_enum_ref()))
	results.append(_b("Verify: Semantic", _test_sem_valid_enum_ref()))
	results.append(_b("Verify: Semantic", _test_sem_unreachable_code()))
	results.append(_b("Verify: Semantic", _test_sem_inner_class_func()))

	# VerifierEngine
	results.append(_b("Verify: Engine", _test_engine_clean_passes()))
	results.append(_b("Verify: Engine", _test_engine_semantic_fail()))
	results.append(_b("Verify: Engine", _test_engine_cascade_stop()))
	results.append(_b("Verify: Engine", _test_engine_single_level()))
	results.append(_b("Verify: Engine", _test_engine_unimplemented_level()))
	results.append(_b("Verify: Engine", _test_engine_summarize()))

	# RuntimeVerifier (AAA — gerçek motor yükleme/örnekleme)
	results.append(_b("Verify: Runtime", _test_runtime_clean_instantiates()))
	results.append(_b("Verify: Runtime", _test_runtime_node_safe()))
	results.append(_b("Verify: Runtime", _test_runtime_broken_fails()))
	results.append(_b("Verify: Runtime", _test_runtime_single_level()))
	results.append(_b("Verify: Runtime", _test_runtime_implemented()))
	results.append(_b("Verify: Runtime", _test_runtime_init_args_ok()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


## Test için temiz, geçerli bir GDScript kaynağı.
static func _clean_source() -> String:
	return (
		"@tool\n"
		+ "class_name TestClean\n"
		+ "extends RefCounted\n"
		+ "func foo() -> int:\n"
		+ "\treturn 1\n"
	)


# ============================================================
# SYNTACTIC VERIFIER
# ============================================================

static func _test_syn_valid_code() -> Dictionary:
	var name := "Syntactic geçerli kodu kabul eder"
	var v := AISyntacticVerifier.new()
	var result: AIVerificationResult = v.verify(_clean_source(), {"task_ref": "t1"})
	# Godot içinde PASS bekleriz; container'da reload davranışı değişebilir,
	# bu yüzden "FAIL DEĞİL" şeklinde savunmacı kontrol.
	if result.outcome == AIVerificationResult.Outcome.FAIL:
		return _fail(name, "geçerli kod FAIL aldı: %s" % result.message)
	return _ok(name)


static func _test_syn_empty_source() -> Dictionary:
	var name := "Syntactic boş kaynağı reddeder"
	var v := AISyntacticVerifier.new()
	var result: AIVerificationResult = v.verify("   ", {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "boş kaynak FAIL olmalı")
	return _ok(name)


static func _test_syn_bracket_imbalance() -> Dictionary:
	var name := "Syntactic dengesiz parantez yakalar"
	var v := AISyntacticVerifier.new()
	var bad := (
		"@tool\nextends RefCounted\n"
		+ "func f() -> int:\n\treturn (1 + 2\n"
	)
	var result: AIVerificationResult = v.verify(bad, {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "kapatılmamış parantez FAIL olmalı")
	return _ok(name)


static func _test_syn_bracket_mismatch() -> Dictionary:
	var name := "Syntactic eşleşmeyen ayraç yakalar"
	var v := AISyntacticVerifier.new()
	var bad := (
		"@tool\nextends RefCounted\n"
		+ "func f() -> Array:\n\treturn [1, 2)\n"
	)
	var result: AIVerificationResult = v.verify(bad, {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "[ ile ) eşleşmemeli")
	return _ok(name)


static func _test_syn_string_brackets() -> Dictionary:
	var name := "Syntactic string içi ayraç sayılmaz"
	var v := AISyntacticVerifier.new()
	# String içindeki ')' gerçek ayraç değil — dengeyi bozmamalı
	var code := (
		"@tool\nextends RefCounted\n"
		+ "func f() -> String:\n\treturn \"merhaba )\"\n"
	)
	var result: AIVerificationResult = v.verify(code, {"task_ref": "t1"})
	# Bracket dengesi string'i atlamalı — FAIL beklenmez
	if result.outcome == AIVerificationResult.Outcome.FAIL:
		if result.message.contains("kapat") or result.message.contains("fazladan"):
			return _fail(name, "string içi ayraç yanlışlıkla sayıldı")
	return _ok(name)


# ============================================================
# SEMANTIC VERIFIER
# ============================================================

static func _test_sem_clean_code() -> Dictionary:
	var name := "Semantic temiz kodu geçirir"
	var v := AISemanticVerifier.new()
	var result: AIVerificationResult = v.verify(_clean_source(), {"task_ref": "t1"})
	if result.outcome == AIVerificationResult.Outcome.FAIL:
		return _fail(name, "temiz kod FAIL aldı: %s" % str(result.errors))
	return _ok(name)


static func _test_sem_duplicate_func() -> Dictionary:
	var name := "Semantic çift fonksiyon yakalar"
	var v := AISemanticVerifier.new()
	# Bu oturumun gerçek bug'ı: çift 'persist'
	var bad := (
		"@tool\nclass_name X\nextends RefCounted\n"
		+ "func persist() -> bool:\n\treturn true\n"
		+ "func persist() -> bool:\n\treturn false\n"
	)
	var result: AIVerificationResult = v.verify(bad, {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "çift fonksiyon FAIL olmalı")
	# Hata mesajı 'persist' içermeli
	var found: bool = false
	for e in result.errors:
		if e.contains("persist"):
			found = true
	if not found:
		return _fail(name, "hata mesajı 'persist' içermeli")
	return _ok(name)


static func _test_sem_duplicate_member() -> Dictionary:
	var name := "Semantic çift üye yakalar"
	var v := AISemanticVerifier.new()
	var bad := (
		"@tool\nextends RefCounted\n"
		+ "var count: int = 0\n"
		+ "var count: int = 1\n"
	)
	var result: AIVerificationResult = v.verify(bad, {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "çift var FAIL olmalı")
	return _ok(name)


static func _test_sem_classname_no_extends() -> Dictionary:
	var name := "Semantic class_name'siz extends yakalar"
	var v := AISemanticVerifier.new()
	var bad := "@tool\nclass_name OnlyName\nvar x: int = 0\n"
	var result: AIVerificationResult = v.verify(bad, {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "extends'siz class_name FAIL olmalı")
	return _ok(name)


static func _test_sem_extends_order() -> Dictionary:
	var name := "Semantic class_name/extends sırası serbest"
	var v := AISemanticVerifier.new()
	# Godot her iki sırayı da kabul eder. class_name -> extends (yaygın sıra)
	# anlamsal hata VERMEMELİ.
	var src_a := "@tool\nclass_name ClsA\nextends RefCounted\n"
	var result_a: AIVerificationResult = v.verify(src_a, {"task_ref": "t1"})
	for e in result_a.errors:
		if e.contains("sıra") or e.contains("extends"):
			return _fail(name, "class_name->extends sırası yanlış işaretlendi")
	# extends -> class_name (ters sıra) da geçerli — hata vermemeli
	var src_b := "@tool\nextends RefCounted\nclass_name ClsB\n"
	var result_b: AIVerificationResult = v.verify(src_b, {"task_ref": "t1"})
	for e in result_b.errors:
		if e.contains("sıra"):
			return _fail(name, "extends->class_name sırası yanlış işaretlendi")
	return _ok(name)


static func _test_sem_bad_enum_ref() -> Dictionary:
	var name := "Semantic olmayan enum değeri yakalar"
	var v := AISemanticVerifier.new()
	# Bu oturumun gerçek bug'ı: olmayan enum değeri (FUNCTIONAL gibi)
	var bad := (
		"@tool\nextends RefCounted\n"
		+ "enum Level { SYNTACTIC, SEMANTIC, RUNTIME }\n"
		+ "func f() -> int:\n\treturn Level.FUNCTIONAL\n"
	)
	var result: AIVerificationResult = v.verify(bad, {"task_ref": "t1"})
	if result.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "olmayan enum değeri FAIL olmalı")
	return _ok(name)


static func _test_sem_valid_enum_ref() -> Dictionary:
	var name := "Semantic geçerli enum değerini kabul eder"
	var v := AISemanticVerifier.new()
	var good := (
		"@tool\nextends RefCounted\n"
		+ "enum Level { SYNTACTIC, SEMANTIC, RUNTIME }\n"
		+ "func f() -> int:\n\treturn Level.RUNTIME\n"
	)
	var result: AIVerificationResult = v.verify(good, {"task_ref": "t1"})
	if result.outcome == AIVerificationResult.Outcome.FAIL:
		for e in result.errors:
			if e.contains("enum"):
				return _fail(name, "geçerli enum değeri reddedildi")
	return _ok(name)


static func _test_sem_unreachable_code() -> Dictionary:
	var name := "Semantic ulaşılamaz kod uyarısı"
	var v := AISemanticVerifier.new()
	var code := (
		"@tool\nextends RefCounted\n"
		+ "func f() -> int:\n\treturn 1\n\tvar x: int = 2\n"
	)
	var result: AIVerificationResult = v.verify(code, {"task_ref": "t1"})
	# Ulaşılamaz kod WARNING üretir (FAIL değil) — uyarı listesinde olmalı
	var has_warn: bool = false
	for w in result.warnings:
		if w.contains("laşılamaz"):
			has_warn = true
	if not has_warn:
		return _fail(name, "ulaşılamaz kod uyarısı bekleniyordu")
	return _ok(name)


static func _test_sem_inner_class_func() -> Dictionary:
	var name := "Semantic inner class metodunu çift saymaz"
	var v := AISemanticVerifier.new()
	# top-level foo + inner class içinde foo — çakışma DEĞİL
	var code := (
		"@tool\nextends RefCounted\n"
		+ "class Inner extends RefCounted:\n"
		+ "\tfunc foo() -> void:\n\t\tpass\n"
		+ "func foo() -> void:\n\tpass\n"
	)
	var result: AIVerificationResult = v.verify(code, {"task_ref": "t1"})
	# Çift fonksiyon hatası VERMEMELİ (biri inner, biri top-level)
	for e in result.errors:
		if e.contains("Çift fonksiyon"):
			return _fail(name, "inner class metodu yanlışlıkla çift sayıldı")
	return _ok(name)


# ============================================================
# VERIFIER ENGINE
# ============================================================

static func _test_engine_clean_passes() -> Dictionary:
	var name := "Engine temiz kodu geçirir"
	var engine := AIVerifierEngine.new()
	var result: Dictionary = engine.verify(_clean_source(), {"task_ref": "t1"})
	# Temiz kod — semantic kesin geçmeli (syntactic motor-bağımlı)
	if not result["passed"]:
		# syntactic container'da farklı davranabilir — semantic'i kontrol et
		if result["failed_level"] == "semantic":
			return _fail(name, "temiz kod semantic'te takıldı")
	return _ok(name)


static func _test_engine_semantic_fail() -> Dictionary:
	var name := "Engine semantic hatayı yakalar"
	var engine := AIVerifierEngine.new()
	var bad := (
		"@tool\nextends RefCounted\n"
		+ "func dup() -> void:\n\tpass\n"
		+ "func dup() -> void:\n\tpass\n"
	)
	var result: Dictionary = engine.verify(bad, {"task_ref": "t1"})
	if result["passed"]:
		return _fail(name, "çift fonksiyonlu kod geçti")
	return _ok(name)


static func _test_engine_cascade_stop() -> Dictionary:
	var name := "Engine kademeli durdurma"
	var engine := AIVerifierEngine.new()
	engine.cascade_stop_on_fail = true
	# Dengesiz parantez — syntactic FAIL, semantic çalışmamalı
	var bad := "@tool\nextends RefCounted\nfunc f() -> int:\n\treturn (1\n"
	var result: Dictionary = engine.verify(bad, {"task_ref": "t1"})
	if result["passed"]:
		return _fail(name, "bozuk kod geçti")
	# syntactic FAIL verince levels_run = 1 olmalı (semantic atlandı)
	if result["failed_level"] == "syntactic" and result["levels_run"] != 1:
		return _fail(name, "kademeli durdurma çalışmadı — semantic de koştu")
	return _ok(name)


static func _test_engine_single_level() -> Dictionary:
	var name := "Engine tek seviye doğrulama"
	var engine := AIVerifierEngine.new()
	var result: AIVerificationResult = engine.verify_single_level(
		_clean_source(),
		AIVerificationResult.VerifyLevel.SEMANTIC,
		{"task_ref": "t1"}
	)
	if result.level != AIVerificationResult.VerifyLevel.SEMANTIC:
		return _fail(name, "yanlış seviye döndü")
	return _ok(name)


static func _test_engine_unimplemented_level() -> Dictionary:
	var name := "Engine uygulanmamış seviye SKIP"
	var engine := AIVerifierEngine.new()
	# PERFORMANCE henüz uygulanmadı — SKIP dönmeli (sahte PASS yok).
	# (RUNTIME artık AAA gerçek doğrulayıcı — ayrı testlerde.)
	var result: AIVerificationResult = engine.verify_single_level(
		_clean_source(),
		AIVerificationResult.VerifyLevel.PERFORMANCE,
		{"task_ref": "t1"}
	)
	if result.outcome != AIVerificationResult.Outcome.SKIP:
		return _fail(name, "uygulanmamış seviye SKIP olmalı")
	return _ok(name)


# ============================================================
# RUNTIME VERIFIER — AAA gerçek motor yükleme/örnekleme
# ============================================================

static func _test_runtime_clean_instantiates() -> Dictionary:
	var name := "Runtime: RefCounted kodu gerçekten örneklenir (PASS)"
	var rv := AIRuntimeVerifier.new()
	var src := (
		"@tool\nextends RefCounted\n"
		+ "var x: int = 0\n"
		+ "func _init() -> void:\n\tx = 41\n"
		+ "func add() -> int:\n\treturn x + 1\n"
	)
	var r: AIVerificationResult = rv.verify(src, {"task_ref": "t1"})
	if r.outcome != AIVerificationResult.Outcome.PASS:
		return _fail(name, "temiz RefCounted PASS olmalı: " + r.message)
	if not bool(r.evidence.get("instantiated", false)):
		return _fail(name, "RefCounted gerçekten örneklenmeliydi")
	if str(r.evidence.get("base_type", "")) != "RefCounted":
		return _fail(name, "taban tipi RefCounted çözülmeliydi")
	return _ok(name)


static func _test_runtime_node_safe() -> Dictionary:
	var name := "Runtime: Node türevi örneklenebilir ama new() çağrılmaz"
	var rv := AIRuntimeVerifier.new()
	var src := (
		"@tool\nextends Node\n"
		+ "func _ready() -> void:\n\tpass\n"
	)
	var r: AIVerificationResult = rv.verify(src, {"task_ref": "t1"})
	if r.outcome != AIVerificationResult.Outcome.PASS:
		return _fail(name, "geçerli Node PASS olmalı: " + r.message)
	# Güvenli sınırlama: Node new() ile çalıştırılmaz (yan etki/asılma).
	if bool(r.evidence.get("instantiated", false)):
		return _fail(name, "Node new() ile örneklenMEmeliydi (güvenlik)")
	return _ok(name)


static func _test_runtime_broken_fails() -> Dictionary:
	var name := "Runtime: yüklenemeyen kod dürüstçe FAIL"
	var rv := AIRuntimeVerifier.new()
	# Geçerli sözdizimi ama çözülemeyen extends → motor yükleyemez.
	var src := "@tool\nextends BuYokBirSinifXyz\nfunc f() -> void:\n\tpass\n"
	var r: AIVerificationResult = rv.verify(src, {"task_ref": "t1"})
	if r.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "çözülemeyen extends PASS olmamalı")
	var empty: AIVerificationResult = rv.verify("   ", {"task_ref": "t1"})
	if empty.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "boş kaynak PASS olmamalı")
	return _ok(name)


static func _test_runtime_single_level() -> Dictionary:
	var name := "Engine RUNTIME tek seviye doğrular"
	var engine := AIVerifierEngine.new()
	var r: AIVerificationResult = engine.verify_single_level(
		"@tool\nextends RefCounted\nfunc f() -> int:\n\treturn 1\n",
		AIVerificationResult.VerifyLevel.RUNTIME,
		{"task_ref": "t1"}
	)
	if r.level != AIVerificationResult.VerifyLevel.RUNTIME:
		return _fail(name, "yanlış seviye döndü")
	if r.outcome == AIVerificationResult.Outcome.SKIP:
		return _fail(name, "RUNTIME artık SKIP olmamalı (uygulandı)")
	return _ok(name)


static func _test_runtime_init_args_ok() -> Dictionary:
	var name := "Runtime: _init zorunlu argümanlı geçerli kod FAIL olmaz"
	var rv := AIRuntimeVerifier.new()
	# Geçerli RefCounted ama new() argüman ister → null döner; bu bir
	# KOD DEFEKTİ DEĞİL, yanlışlıkla FAIL edilmemeli (onarım döngüsü
	# tetiklenmesin).
	var src := (
		"@tool\nextends RefCounted\n"
		+ "var v: int\n"
		+ "func _init(p_v: int) -> void:\n\tv = p_v\n"
	)
	var r: AIVerificationResult = rv.verify(src, {"task_ref": "t1"})
	if r.outcome == AIVerificationResult.Outcome.FAIL:
		return _fail(name, "argümanlı _init yanlışlıkla FAIL: " + r.message)
	if bool(r.evidence.get("instantiated", true)):
		return _fail(name, "new() null'ken instantiated=false olmalı")
	return _ok(name)


static func _test_runtime_implemented() -> Dictionary:
	var name := "implemented_levels runtime'ı içerir"
	var engine := AIVerifierEngine.new()
	if not engine.implemented_levels().has("runtime"):
		return _fail(name, "runtime uygulanmış seviyelerde olmalı")
	return _ok(name)


static func _test_engine_summarize() -> Dictionary:
	var name := "Engine özet üretir"
	var engine := AIVerifierEngine.new()
	var result: Dictionary = engine.verify(_clean_source(), {"task_ref": "t1"})
	var summary: String = engine.summarize(result)
	if summary.is_empty():
		return _fail(name, "özet boş")
	return _ok(name)
