@tool
class_name AIDebugMemoryBridgeTest
extends RefCounted

## Debug ↔ Bellek Köprüsü Self-Test (Aşama 4b).
##
## Doğrular: çözülen hata Episodic'e yazılır; BAŞARILI çözüm
## Procedural reçete olur; aynı hata tekrar gelince bellekten
## önerilir; bilinmeyen hatada dürüstçe found=false (mock policy);
## imza satır no / sayı bağımsız kararlıdır.


static func run_all() -> Array:
	var results: Array = []
	results.append(_b("DbgMem: Yaz", _test_unresolved_not_reusable()))
	results.append(_b("DbgMem: Yaz", _test_resolved_becomes_recipe()))
	results.append(_b("DbgMem: Yaz", _test_empty_fix_not_reusable()))
	results.append(_b("DbgMem: Hatırla", _test_recall_after_store()))
	results.append(_b("DbgMem: Hatırla", _test_recall_unseen_false()))
	results.append(_b("DbgMem: Hatırla", _test_signature_stable()))
	results.append(_b("DbgMem: Durum", _test_stats()))
	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


static func _fresh() -> AIDebugMemoryBridge:
	var ep := AIEpisodicMemory.new()
	var pr := AIProceduralMemory.new()
	ep.clear()
	pr.clear()
	return AIDebugMemoryBridge.new(ep, pr)


# ============================================================
# YAZMA
# ============================================================

static func _test_unresolved_not_reusable() -> Dictionary:
	var name := "Çözülemeyen hata reçete olmaz"
	var b := _fresh()
	var r: Dictionary = b.remember_resolution(
		"Null instance hatası line 10", "", false
	)
	if not bool(r["stored"]):
		return _fail(name, "episodic'e yine de yazılmalı")
	if bool(r["reusable"]):
		return _fail(name, "başarısız çözüm tekrarlanabilir olmamalı")
	return _ok(name)


static func _test_resolved_becomes_recipe() -> Dictionary:
	var name := "Başarılı çözüm Procedural reçete olur"
	var b := _fresh()
	var r: Dictionary = b.remember_resolution(
		"Parse error identifier eksik degisken",
		"degisken tanımı eklendi", true
	)
	if not bool(r["reusable"]):
		return _fail(name, "başarılı çözüm tekrarlanabilir olmalı")
	if str(r["procedure_id"]).is_empty():
		return _fail(name, "prosedür id üretilmeli")
	return _ok(name)


static func _test_empty_fix_not_reusable() -> Dictionary:
	var name := "Boş fix başarı bile olsa reçete olmaz (mock)"
	var b := _fresh()
	var r: Dictionary = b.remember_resolution(
		"Runtime hata bir seyler patladi", "   ", true
	)
	if bool(r["reusable"]):
		return _fail(name, "boş fix tekrarlanabilir olmamalı")
	return _ok(name)


# ============================================================
# HATIRLAMA
# ============================================================

static func _test_recall_after_store() -> Dictionary:
	var name := "Saklanan çözüm tekrar önerilir"
	var b := _fresh()
	b.remember_resolution(
		"Type error cannot convert deger line 42",
		"tür dönüşümü düzeltildi", true
	)
	var rec: Dictionary = b.recall_similar(
		"Type error cannot convert deger line 42"
	)
	if not bool(rec["found"]):
		return _fail(name, "saklanan çözüm bulunmalı")
	if str(rec["source"]) != "procedural":
		return _fail(name, "kanıtlı reçete procedural'dan gelmeli")
	if not str(rec["suggestion"]).contains("tür dönüşümü"):
		return _fail(name, "öneri orijinal fix'i içermeli")
	if float(rec["confidence"]) <= 0.0:
		return _fail(name, "güven skoru pozitif olmalı")
	return _ok(name)


static func _test_recall_unseen_false() -> Dictionary:
	var name := "Bilinmeyen hata: dürüst found=false (mock)"
	var b := _fresh()
	var rec: Dictionary = b.recall_similar(
		"Hic gorulmemis cok farkli bir hata mesaji"
	)
	if bool(rec["found"]):
		return _fail(name, "bilinmeyen hatada uydurma öneri olmamalı")
	if not str(rec["suggestion"]).is_empty():
		return _fail(name, "öneri boş olmalı")
	return _ok(name)


static func _test_signature_stable() -> Dictionary:
	var name := "İmza satır no / sayı bağımsız kararlı"
	var b := _fresh()
	b.remember_resolution(
		"Type error cannot convert deger line 42",
		"tür düzeltildi", true
	)
	# Aynı hata, farklı satır numarası — yine bulunmalı
	var rec: Dictionary = b.recall_similar(
		"Type error cannot convert deger line 9999"
	)
	if not bool(rec["found"]):
		return _fail(name, "satır no değişse de eşleşmeli")
	return _ok(name)


static func _test_stats() -> Dictionary:
	var name := "Köprü istatistikleri"
	var b := _fresh()
	b.remember_resolution("Bir hata oldu burada", "düzeltildi", true)
	var st: Dictionary = b.bridge_stats()
	if int(st["episodic_count"]) < 1:
		return _fail(name, "episodic kayıt sayılmalı")
	if int(st["procedural_count"]) < 1:
		return _fail(name, "procedural reçete sayılmalı")
	return _ok(name)
