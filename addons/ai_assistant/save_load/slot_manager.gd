@tool
class_name AISaveSlotManager
extends RefCounted

## SlotManager — kayıt slotu yöneticisi (Madde 09 / Save-Load).
##
## Oyunlarda kayıt "slot"ları olur: 3 manuel slot + autosave +
## quicksave gibi. Bu sınıf slotların YAŞAM DÖNGÜSÜNÜ yönetir:
## hangi slot dolu, hangi boş, slot dosya yolu ne, üst-verisi ne.
##
## Slot tipleri:
##   - MANUAL: oyuncunun bilinçli kaydettiği (numaralı)
##   - AUTOSAVE: sistem otomatik kaydı
##   - QUICKSAVE: hızlı kaydet/yükle
##
## Bu sınıf dosya YAZMAZ — sadece slot kataloğunu yönetir. Asıl
## yazma SaveManager + AtomicWriter işidir.
##
## Mock policy: slot durumu gerçek dosya varlığından okunur.

## Slot tipleri.
enum SlotKind { MANUAL, AUTOSAVE, QUICKSAVE }

const SLOT_KIND_NAMES: Dictionary = {
	SlotKind.MANUAL: "manual",
	SlotKind.AUTOSAVE: "autosave",
	SlotKind.QUICKSAVE: "quicksave",
}

## Varsayılan manuel slot sayısı.
const DEFAULT_MANUAL_SLOTS: int = 3

## Kayıt dosyalarının kök dizini.
const SAVE_DIR: String = "user://saves"


## Bir slotun durumu.
class SlotInfo extends RefCounted:
	var slot_id: String = ""
	var kind: int = AISaveSlotManager.SlotKind.MANUAL
	var occupied: bool = false         ## Slotta kayıt var mı
	var file_path: String = ""
	var saved_at_unix: int = 0         ## Doluysa kayıt zamanı
	var label: String = ""             ## Kullanıcı görünür ad

	func to_dict() -> Dictionary:
		return {
			"slot_id": slot_id,
			"kind": AISaveSlotManager.SLOT_KIND_NAMES.get(kind, "?"),
			"occupied": occupied,
			"file_path": file_path,
			"saved_at_unix": saved_at_unix,
			"label": label,
		}


## Slot kataloğu — slot_id -> SlotInfo.
var _slots: Dictionary = {}

## Manuel slot sayısı.
var manual_slot_count: int = DEFAULT_MANUAL_SLOTS


func _init(p_manual_slots: int = DEFAULT_MANUAL_SLOTS) -> void:
	manual_slot_count = maxi(p_manual_slots, 1)
	_build_slot_catalog()


# ============================================================
# SLOT KATALOĞU
# ============================================================

## Standart slot setini kurar: N manuel + 1 autosave + 1 quicksave.
func _build_slot_catalog() -> void:
	_slots.clear()
	# Manuel slotlar
	for i in range(manual_slot_count):
		var slot_id: String = "manual_%d" % (i + 1)
		_register_slot(slot_id, SlotKind.MANUAL, "Slot %d" % (i + 1))
	# Autosave
	_register_slot("autosave", SlotKind.AUTOSAVE, "Otomatik Kayıt")
	# Quicksave
	_register_slot("quicksave", SlotKind.QUICKSAVE, "Hızlı Kayıt")


## Bir slot kaydı oluşturur.
func _register_slot(slot_id: String, kind: int, label: String) -> void:
	var info := SlotInfo.new()
	info.slot_id = slot_id
	info.kind = kind
	info.label = label
	info.file_path = SAVE_DIR.path_join(slot_id + ".save.json")
	_slots[slot_id] = info


# ============================================================
# SLOT SORGULAMA
# ============================================================

## Bir slotun bilgisini döndürür. Yoksa null.
func get_slot(slot_id: String) -> SlotInfo:
	return _slots.get(slot_id, null)


## Bir slot var mı?
func has_slot(slot_id: String) -> bool:
	return _slots.has(slot_id)


## Tüm slotların listesi.
func all_slots() -> Array:
	return _slots.values()


## Belirli tipteki slotlar.
func slots_of_kind(kind: int) -> Array:
	var matched: Array = []
	for slot_id in _slots:
		if (_slots[slot_id] as SlotInfo).kind == kind:
			matched.append(_slots[slot_id])
	return matched


## Dolu slotlar.
func occupied_slots() -> Array:
	var occupied: Array = []
	for slot_id in _slots:
		if (_slots[slot_id] as SlotInfo).occupied:
			occupied.append(_slots[slot_id])
	return occupied


## Boş slot var mı?
func has_empty_slot() -> bool:
	for slot_id in _slots:
		if not (_slots[slot_id] as SlotInfo).occupied:
			return true
	return false


# ============================================================
# SLOT DURUM GÜNCELLEME
# ============================================================

## Bir slotu dolu olarak işaretler — kayıt yazıldıktan sonra.
func mark_occupied(slot_id: String, saved_at_unix: int) -> bool:
	if not _slots.has(slot_id):
		return false
	var slot: SlotInfo = _slots[slot_id]
	slot.occupied = true
	slot.saved_at_unix = saved_at_unix
	return true


## Bir slotu boş olarak işaretler — kayıt silindikten sonra.
func mark_empty(slot_id: String) -> bool:
	if not _slots.has(slot_id):
		return false
	var slot: SlotInfo = _slots[slot_id]
	slot.occupied = false
	slot.saved_at_unix = 0
	return true


## Slot durumlarını gerçek dosya sisteminden tazeler.
## Her slot için dosya var mı diye bakar.
func refresh_from_disk() -> void:
	for slot_id in _slots:
		var slot: SlotInfo = _slots[slot_id]
		slot.occupied = FileAccess.file_exists(slot.file_path)


# ============================================================
# DURUM
# ============================================================

## Slot durumu özeti.
func summary() -> Dictionary:
	return {
		"total_slots": _slots.size(),
		"occupied": occupied_slots().size(),
		"has_empty": has_empty_slot(),
		"manual_slots": manual_slot_count,
	}
