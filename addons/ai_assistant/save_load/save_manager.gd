@tool
class_name AISaveManager
extends RefCounted

## SaveManager — kayıt yöneticisi (Madde 09 / Save-Load ana API).
##
## Save/Load sisteminin tek giriş noktası. Alt parçaları birleştirir:
##   serializer   — oyun durumu -> JSON
##   deserializer — JSON -> oyun durumu (savunmacı)
##   atomic_writer — yarım-yazma imkansız
##   slot_manager — slot kataloğu
##   integrity    — HMAC imza + doğrulama
##
## Tek bir save() / load() API'si — oyun kodu sadece bunu çağırır.
##
## Akış (save):
##   1. Oyun durumu serileştirilir (kendini-tanımlayan zarf)
##   2. Zarf HMAC ile imzalanır
##   3. İmzalı içerik atomik yazılır (tmp -> rename)
##   4. Slot dolu işaretlenir
##
## Akış (load):
##   1. Dosya okunur
##   2. İmza doğrulanır (kurcalanmış mı)
##   3. JSON çözümlenir (bozuk mu)
##   4. Oyun durumu döndürülür
##
## Save/Load'ın 5 invariant'ı bu akışta korunur: atomik yazma,
## şema versiyonu, bütünlük, savunmacı okuma, slot izolasyonu.
##
## Mock policy: her aşama gerçekten yapılır; başarı gerçek
## sonuçtan raporlanır — sahte "kaydedildi" yok.

## Bir save işleminin sonucu.
class SaveResult extends RefCounted:
	var ok: bool = false
	var slot_id: String = ""
	var bytes_written: int = 0
	var error: String = ""

	func to_dict() -> Dictionary:
		return {"ok": ok, "slot_id": slot_id,
			"bytes_written": bytes_written, "error": error}


## Bir load işleminin sonucu.
class LoadResult extends RefCounted:
	var ok: bool = false
	var slot_id: String = ""
	var game_data: Dictionary = {}
	var schema_version: int = -1
	var error: String = ""

	func to_dict() -> Dictionary:
		return {"ok": ok, "slot_id": slot_id,
			"schema_version": schema_version, "error": error}


## Alt bileşenler.
var _serializer: AISaveSerializer
var _deserializer: AISaveDeserializer
var _writer: AISaveAtomicWriter
var _slots: AISaveSlotManager
var _integrity: AISaveIntegrityVerifier


func _init(integrity_key: String = "") -> void:
	_serializer = AISaveSerializer.new()
	_deserializer = AISaveDeserializer.new()
	_writer = AISaveAtomicWriter.new()
	_slots = AISaveSlotManager.new()
	var signer := AISaveHMACSigner.new(integrity_key)
	_integrity = AISaveIntegrityVerifier.new(signer)


## Slot yöneticisine erişim — UI için.
func slots() -> AISaveSlotManager:
	return _slots


# ============================================================
# KAYDETME
# ============================================================

## Oyun durumunu bir slota kaydeder.
## slot_id: hedef slot. game_state: kaydedilecek oyun verisi.
## schema_version: oyunun şema sürümü.
## Dönen: SaveResult.
func save(
	slot_id: String, game_state: Dictionary, schema_version: int
) -> SaveResult:
	var result := SaveResult.new()
	result.slot_id = slot_id

	# --- Slot geçerli mi ---
	var slot: AISaveSlotManager.SlotInfo = _slots.get_slot(slot_id)
	if slot == null:
		result.error = "Geçersiz slot: " + slot_id
		return result

	# --- Adım 1: serileştir ---
	var ser: AISaveSerializer.SerializeResult = _serializer.serialize(
		game_state, schema_version, slot_id
	)
	if not ser.ok:
		result.error = "Serileştirme başarısız: " + ser.error
		return result

	# --- Adım 2: imzala (bütünlük zarfı) ---
	var signed: Dictionary = _integrity.create_signed_envelope(ser.json_text)
	var signed_json: String = _serializer.serialize_raw(signed)
	if signed_json.is_empty():
		result.error = "İmzalı zarf serileştirilemedi"
		return result

	# --- Adım 3: atomik yaz ---
	var write: AISaveAtomicWriter.WriteResult = _writer.write(
		slot.file_path, signed_json
	)
	if not write.ok:
		result.error = "Atomik yazma başarısız: " + write.error
		return result

	# --- Adım 4: slotu dolu işaretle ---
	_slots.mark_occupied(slot_id, int(Time.get_unix_time_from_system()))

	result.bytes_written = write.bytes_written
	result.ok = true
	return result


# ============================================================
# YÜKLEME
# ============================================================

## Bir slottan oyun durumunu yükler.
## slot_id: kaynak slot.
## Dönen: LoadResult — bozuk/kurcalanmış kayıtta ok=false + açık hata.
func load_slot(slot_id: String) -> LoadResult:
	var result := LoadResult.new()
	result.slot_id = slot_id

	var slot: AISaveSlotManager.SlotInfo = _slots.get_slot(slot_id)
	if slot == null:
		result.error = "Geçersiz slot: " + slot_id
		return result

	# --- Adım 1: dosyayı oku ---
	if not FileAccess.file_exists(slot.file_path):
		result.error = "Slotta kayıt yok: " + slot_id
		return result
	var file := FileAccess.open(slot.file_path, FileAccess.READ)
	if file == null:
		result.error = "Kayıt dosyası açılamadı"
		return result
	var raw: String = file.get_as_text()
	file.close()

	# --- Adım 2: imzalı zarfı çöz ---
	var outer := JSON.new()
	if outer.parse(raw) != OK:
		result.error = "Kayıt dosyası bozuk (dış JSON)"
		return result
	var outer_data: Variant = outer.data
	if typeof(outer_data) != TYPE_DICTIONARY:
		result.error = "Kayıt zarfı geçersiz"
		return result

	# --- Adım 3: bütünlük doğrula (HMAC) ---
	var integrity: AISaveIntegrityVerifier.IntegrityReport = _integrity.verify(
		outer_data
	)
	if not integrity.trusted:
		result.error = "Bütünlük hatası: " + integrity.detail
		return result

	# --- Adım 4: iç içeriği çözümle (savunmacı) ---
	var inner_content: String = str((outer_data as Dictionary)["content"])
	var deser: AISaveDeserializer.DeserializeResult = _deserializer.deserialize(
		inner_content
	)
	if not deser.ok:
		result.error = "Kayıt çözümlenemedi: " + deser.error
		return result

	result.game_data = deser.data
	result.schema_version = deser.schema_version
	result.ok = true
	return result


# ============================================================
# SİLME
# ============================================================

## Bir slottaki kaydı siler.
## Dönen: {ok: bool, error: String}
func delete_slot(slot_id: String) -> Dictionary:
	var slot: AISaveSlotManager.SlotInfo = _slots.get_slot(slot_id)
	if slot == null:
		return {"ok": false, "error": "Geçersiz slot"}
	if not FileAccess.file_exists(slot.file_path):
		return {"ok": false, "error": "Slot zaten boş"}
	var dir := DirAccess.open(slot.file_path.get_base_dir())
	if dir == null:
		return {"ok": false, "error": "Dizin açılamadı"}
	if dir.remove(slot.file_path) != OK:
		return {"ok": false, "error": "Silme başarısız"}
	_slots.mark_empty(slot_id)
	return {"ok": true, "error": ""}


# ============================================================
# BAŞLANGIÇ KURTARMA
# ============================================================

## Sistem başlangıcında yarım-yazma kalıntılarını temizler.
## Dönen: temizlenen .tmp dosya sayısı.
func recover_on_startup() -> int:
	return _writer.recover_orphan_temps(AISaveSlotManager.SAVE_DIR)


## Durum özeti.
func summary() -> Dictionary:
	return {
		"slots": _slots.summary(),
	}
