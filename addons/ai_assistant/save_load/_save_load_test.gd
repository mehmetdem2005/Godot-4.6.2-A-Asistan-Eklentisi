@tool
class_name AISaveLoadTest
extends RefCounted

## Madde 09 — Save/Load Çekirdek Self-Test
##
## Sıkı testler: core (serializer, deserializer, atomic_writer,
## slot_manager, save_manager) + integrity (hmac_signer,
## integrity_verifier, anomaly_detector).
##
## Save/Load'ın 5 invariant'ı test edilir: atomik yazma, şema
## versiyonu, bütünlük imzası, savunmacı okuma, slot izolasyonu.
##
## NOT: Dosya G/Ç testleri user:// altında gerçek dosya kullanır;
## her test kendi geçici dosyasını temizler.


static func run_all() -> Array:
	var results: Array = []

	# Serializer
	results.append(_b("Save: Serializer", _test_serialize_envelope()))
	results.append(_b("Save: Serializer", _test_serialize_json_unsafe()))

	# Deserializer
	results.append(_b("Save: Deserializer", _test_deserialize_valid()))
	results.append(_b("Save: Deserializer", _test_deserialize_corrupt()))
	results.append(_b("Save: Deserializer", _test_deserialize_missing_meta()))
	results.append(_b("Save: Deserializer", _test_deserialize_peek_version()))

	# AtomicWriter
	results.append(_b("Save: Atomic", _test_atomic_write_read()))
	results.append(_b("Save: Atomic", _test_atomic_empty_path()))
	results.append(_b("Save: Atomic", _test_atomic_no_orphan()))

	# SlotManager
	results.append(_b("Save: Slots", _test_slot_catalog()))
	results.append(_b("Save: Slots", _test_slot_occupancy()))
	results.append(_b("Save: Slots", _test_slot_invalid()))

	# HMACSigner
	results.append(_b("Save: HMAC", _test_hmac_sign_verify()))
	results.append(_b("Save: HMAC", _test_hmac_tamper_caught()))
	results.append(_b("Save: HMAC", _test_hmac_empty()))

	# IntegrityVerifier
	results.append(_b("Save: Integrity", _test_integrity_trusted()))
	results.append(_b("Save: Integrity", _test_integrity_no_signature()))
	results.append(_b("Save: Integrity", _test_integrity_tampered()))

	# AnomalyDetector
	results.append(_b("Save: Anomaly", _test_anomaly_clean()))
	results.append(_b("Save: Anomaly", _test_anomaly_flagged()))
	results.append(_b("Save: Anomaly", _test_anomaly_progress()))

	# SaveManager — uçtan uca
	results.append(_b("Save: Manager", _test_manager_roundtrip()))
	results.append(_b("Save: Manager", _test_manager_tamper_rejected()))
	results.append(_b("Save: Manager", _test_manager_invalid_slot()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# SERIALIZER
# ============================================================

static func _test_serialize_envelope() -> Dictionary:
	var name := "Serializer kendini-tanımlayan zarf"
	var s := AISaveSerializer.new()
	var result: AISaveSerializer.SerializeResult = s.serialize(
		{"level": 5, "hp": 100}, 2, "oyun1"
	)
	if not result.ok:
		return _fail(name, "serileştirme başarısız: " + result.error)
	# Zarf _meta ve data içermeli
	if not result.json_text.contains("_meta"):
		return _fail(name, "zarf _meta içermeli")
	if not result.json_text.contains("schema_version"):
		return _fail(name, "zarf şema sürümü içermeli")
	return _ok(name)


static func _test_serialize_json_unsafe() -> Dictionary:
	var name := "Serializer JSON-uyumsuz tip reddi"
	var s := AISaveSerializer.new()
	# Vector2 JSON'a çevrilemez
	var result: AISaveSerializer.SerializeResult = s.serialize(
		{"pos": Vector2(1, 2)}, 1
	)
	if result.ok:
		return _fail(name, "JSON-uyumsuz tip reddedilmeli")
	return _ok(name)


# ============================================================
# DESERIALIZER
# ============================================================

static func _test_deserialize_valid() -> Dictionary:
	var name := "Deserializer geçerli kayıt"
	var s := AISaveSerializer.new()
	var d := AISaveDeserializer.new()
	var serialized: AISaveSerializer.SerializeResult = s.serialize(
		{"score": 999}, 3
	)
	var result: AISaveDeserializer.DeserializeResult = d.deserialize(
		serialized.json_text
	)
	if not result.ok:
		return _fail(name, "geçerli kayıt çözülmeli")
	if result.schema_version != 3:
		return _fail(name, "şema sürümü 3 okunmalı")
	if int(result.data.get("score", 0)) != 999:
		return _fail(name, "veri korunmalı")
	return _ok(name)


static func _test_deserialize_corrupt() -> Dictionary:
	var name := "Deserializer bozuk JSON — çökmez"
	var d := AISaveDeserializer.new()
	# Bozuk JSON — çökmeden hata dönmeli
	var result: AISaveDeserializer.DeserializeResult = d.deserialize(
		"{bu bozuk json"
	)
	if result.ok:
		return _fail(name, "bozuk JSON kabul edilmemeli")
	if result.error.is_empty():
		return _fail(name, "açık hata mesajı olmalı")
	return _ok(name)


static func _test_deserialize_missing_meta() -> Dictionary:
	var name := "Deserializer eksik _meta"
	var d := AISaveDeserializer.new()
	# _meta'sız geçerli JSON
	var result: AISaveDeserializer.DeserializeResult = d.deserialize(
		'{"data": {"x": 1}}'
	)
	if result.ok:
		return _fail(name, "_meta'sız kayıt reddedilmeli")
	return _ok(name)


static func _test_deserialize_peek_version() -> Dictionary:
	var name := "Deserializer şema sürümü peek"
	var s := AISaveSerializer.new()
	var d := AISaveDeserializer.new()
	var serialized: AISaveSerializer.SerializeResult = s.serialize({"a": 1}, 7)
	# peek — tam çözümleme yapmadan sürüm okur
	if d.peek_schema_version(serialized.json_text) != 7:
		return _fail(name, "peek şema sürümü 7 dönmeli")
	# Bozuk metinde -1
	if d.peek_schema_version("bozuk") != -1:
		return _fail(name, "bozuk metinde peek -1 dönmeli")
	return _ok(name)


# ============================================================
# ATOMIC WRITER
# ============================================================

static func _test_atomic_write_read() -> Dictionary:
	var name := "Atomic yaz ve oku"
	var w := AISaveAtomicWriter.new()
	var test_path := "user://_test_atomic.tmp_save"
	var content := "test içeriği 123"
	var result: AISaveAtomicWriter.WriteResult = w.write(test_path, content)
	if not result.ok:
		return _fail(name, "atomik yazma başarısız: " + result.error)
	# Geri oku — içerik eşleşmeli
	var file := FileAccess.open(test_path, FileAccess.READ)
	if file == null:
		return _fail(name, "yazılan dosya okunamadı")
	var read_back: String = file.get_as_text()
	file.close()
	# Temizle
	DirAccess.open("user://").remove(test_path)
	if read_back != content:
		return _fail(name, "okunan içerik yazılanla eşleşmeli")
	return _ok(name)


static func _test_atomic_empty_path() -> Dictionary:
	var name := "Atomic boş yol reddi"
	var w := AISaveAtomicWriter.new()
	var result: AISaveAtomicWriter.WriteResult = w.write("", "içerik")
	if result.ok:
		return _fail(name, "boş yol reddedilmeli")
	return _ok(name)


static func _test_atomic_no_orphan() -> Dictionary:
	var name := "Atomic başarılı yazma .tmp bırakmaz"
	var w := AISaveAtomicWriter.new()
	var test_path := "user://_test_orphan.tmp_save"
	w.write(test_path, "veri")
	# Başarılı yazma sonrası .tmp kalmamalı
	var has_orphan: bool = w.has_orphan_temp(test_path)
	# Temizle
	DirAccess.open("user://").remove(test_path)
	if has_orphan:
		return _fail(name, "başarılı yazma .tmp bırakmamalı")
	return _ok(name)


# ============================================================
# SLOT MANAGER
# ============================================================

static func _test_slot_catalog() -> Dictionary:
	var name := "Slot kataloğu — 3 manuel + auto + quick"
	var m := AISaveSlotManager.new(3)
	# 3 manuel + 1 autosave + 1 quicksave = 5
	if m.all_slots().size() != 5:
		return _fail(name, "5 slot bekleniyordu, %d" % m.all_slots().size())
	if not m.has_slot("autosave"):
		return _fail(name, "autosave slotu olmalı")
	if not m.has_slot("quicksave"):
		return _fail(name, "quicksave slotu olmalı")
	return _ok(name)


static func _test_slot_occupancy() -> Dictionary:
	var name := "Slot doluluk yönetimi"
	var m := AISaveSlotManager.new(3)
	# Başlangıçta boş slot var
	if not m.has_empty_slot():
		return _fail(name, "başlangıçta boş slot olmalı")
	# Bir slotu dolu işaretle
	if not m.mark_occupied("manual_1", 12345):
		return _fail(name, "slot dolu işaretlenemedi")
	var slot: AISaveSlotManager.SlotInfo = m.get_slot("manual_1")
	if not slot.occupied:
		return _fail(name, "slot dolu olmalı")
	return _ok(name)


static func _test_slot_invalid() -> Dictionary:
	var name := "Slot geçersiz id reddi"
	var m := AISaveSlotManager.new(3)
	if m.get_slot("var_olmayan_slot") != null:
		return _fail(name, "geçersiz slot null dönmeli")
	if m.mark_occupied("yok", 1):
		return _fail(name, "geçersiz slot işaretlenememeli")
	return _ok(name)


# ============================================================
# HMAC SIGNER
# ============================================================

static func _test_hmac_sign_verify() -> Dictionary:
	var name := "HMAC imzala ve doğrula"
	var signer := AISaveHMACSigner.new("test_anahtari")
	var content := '{"oyun":"verisi"}'
	var signature: String = signer.sign_content(content)
	if signature.is_empty():
		return _fail(name, "imza üretilmeli")
	if not signer.verify(content, signature):
		return _fail(name, "doğru imza doğrulanmalı")
	return _ok(name)


static func _test_hmac_tamper_caught() -> Dictionary:
	var name := "HMAC kurcalama yakalanır"
	var signer := AISaveHMACSigner.new("anahtar")
	var content := "orijinal içerik"
	var signature: String = signer.sign_content(content)
	# İçerik değişti — imza tutmamalı
	if signer.verify("değiştirilmiş içerik", signature):
		return _fail(name, "kurcalanmış içerik yakalanmalı")
	return _ok(name)


static func _test_hmac_empty() -> Dictionary:
	var name := "HMAC boş girdi güvenliği"
	var signer := AISaveHMACSigner.new()
	# Boş içerik — boş imza
	if not signer.sign_content("").is_empty():
		return _fail(name, "boş içerik boş imza vermeli")
	# Boş imza doğrulama — false
	if signer.verify("içerik", ""):
		return _fail(name, "boş imza doğrulanmamalı")
	return _ok(name)


# ============================================================
# INTEGRITY VERIFIER
# ============================================================

static func _test_integrity_trusted() -> Dictionary:
	var name := "Integrity sağlam zarf güvenilir"
	var verifier := AISaveIntegrityVerifier.new()
	var envelope: Dictionary = verifier.create_signed_envelope(
		'{"içerik": "test"}'
	)
	var report: AISaveIntegrityVerifier.IntegrityReport = verifier.verify(
		envelope
	)
	if not report.trusted:
		return _fail(name, "doğru imzalı zarf güvenilir olmalı")
	return _ok(name)


static func _test_integrity_no_signature() -> Dictionary:
	var name := "Integrity imzasız zarf reddi"
	var verifier := AISaveIntegrityVerifier.new()
	var report: AISaveIntegrityVerifier.IntegrityReport = verifier.verify(
		{"content": "imzasız içerik"}
	)
	if report.trusted:
		return _fail(name, "imzasız zarf güvenilmemeli")
	if report.issue != AISaveIntegrityVerifier.IntegrityIssue.MISSING_SIGNATURE:
		return _fail(name, "sorun MISSING_SIGNATURE olmalı")
	return _ok(name)


static func _test_integrity_tampered() -> Dictionary:
	var name := "Integrity kurcalanmış zarf reddi"
	var verifier := AISaveIntegrityVerifier.new()
	var envelope: Dictionary = verifier.create_signed_envelope("orijinal")
	# İçeriği değiştir, imzayı bırak
	envelope["content"] = "kurcalanmış"
	var report: AISaveIntegrityVerifier.IntegrityReport = verifier.verify(
		envelope
	)
	if report.trusted:
		return _fail(name, "kurcalanmış zarf güvenilmemeli")
	return _ok(name)


# ============================================================
# ANOMALY DETECTOR
# ============================================================

static func _test_anomaly_clean() -> Dictionary:
	var name := "Anomaly normal değer temiz"
	var d := AISaveAnomalyDetector.new()
	d.add_rule("gold", 0.0, 100000.0)
	d.add_rule("level", 1.0, 100.0)
	var report: AISaveAnomalyDetector.AnomalyReport = d.detect(
		{"gold": 500, "level": 12}
	)
	if report.is_suspicious():
		return _fail(name, "normal değerler temiz olmalı")
	return _ok(name)


static func _test_anomaly_flagged() -> Dictionary:
	var name := "Anomaly aşırı değer işaretlenir"
	var d := AISaveAnomalyDetector.new()
	d.add_rule("gold", 0.0, 100000.0)
	# 9 milyon altın — sınır aşımı
	var report: AISaveAnomalyDetector.AnomalyReport = d.detect(
		{"gold": 9000000}
	)
	if not report.is_suspicious():
		return _fail(name, "aşırı değer şüpheli işaretlenmeli")
	return _ok(name)


static func _test_anomaly_progress() -> Dictionary:
	var name := "Anomaly ilerleme hızı"
	var d := AISaveAnomalyDetector.new()
	# Makul ilerleme — şüpheli değil
	if d.is_progress_anomalous(0.0, 100.0, 60.0, 10.0):
		return _fail(name, "makul ilerleme şüpheli olmamalı")
	# 1 saniyede 100000 — aşırı hızlı
	if not d.is_progress_anomalous(0.0, 100000.0, 1.0, 10.0):
		return _fail(name, "aşırı hızlı ilerleme şüpheli olmalı")
	return _ok(name)


# ============================================================
# SAVE MANAGER — uçtan uca
# ============================================================

static func _test_manager_roundtrip() -> Dictionary:
	var name := "Manager kaydet-yükle round-trip"
	# user://saves dizini gerekiyor
	if not DirAccess.dir_exists_absolute(AISaveSlotManager.SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(AISaveSlotManager.SAVE_DIR)
	var manager := AISaveManager.new("test_key")
	var game_state: Dictionary = {"level": 8, "score": 4200}
	# Kaydet
	var save: AISaveManager.SaveResult = manager.save(
		"manual_1", game_state, 5
	)
	if not save.ok:
		return _fail(name, "kaydetme başarısız: " + save.error)
	# Yükle
	var load: AISaveManager.LoadResult = manager.load_slot("manual_1")
	# Temizle
	manager.delete_slot("manual_1")
	if not load.ok:
		return _fail(name, "yükleme başarısız: " + load.error)
	if int(load.game_data.get("score", 0)) != 4200:
		return _fail(name, "round-trip'te veri korunmalı")
	if load.schema_version != 5:
		return _fail(name, "round-trip'te şema sürümü korunmalı")
	return _ok(name)


static func _test_manager_tamper_rejected() -> Dictionary:
	var name := "Manager kurcalanmış kayıt reddi"
	if not DirAccess.dir_exists_absolute(AISaveSlotManager.SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(AISaveSlotManager.SAVE_DIR)
	var manager := AISaveManager.new("test_key")
	manager.save("manual_2", {"gold": 100}, 1)
	# Dosyayı kurcala
	var slot: AISaveSlotManager.SlotInfo = manager.slots().get_slot("manual_2")
	var file := FileAccess.open(slot.file_path, FileAccess.READ)
	var raw: String = file.get_as_text()
	file.close()
	var tampered: String = raw.replace("100", "999999")
	var wf := FileAccess.open(slot.file_path, FileAccess.WRITE)
	wf.store_string(tampered)
	wf.close()
	# Yüklemeye çalış — reddedilmeli
	var load: AISaveManager.LoadResult = manager.load_slot("manual_2")
	manager.delete_slot("manual_2")
	if load.ok:
		return _fail(name, "kurcalanmış kayıt yüklenmemeli")
	return _ok(name)


static func _test_manager_invalid_slot() -> Dictionary:
	var name := "Manager geçersiz slot reddi"
	var manager := AISaveManager.new()
	var save: AISaveManager.SaveResult = manager.save(
		"olmayan_slot", {"x": 1}, 1
	)
	if save.ok:
		return _fail(name, "geçersiz slota kaydetme reddedilmeli")
	var load: AISaveManager.LoadResult = manager.load_slot("olmayan_slot")
	if load.ok:
		return _fail(name, "geçersiz slottan yükleme reddedilmeli")
	return _ok(name)
