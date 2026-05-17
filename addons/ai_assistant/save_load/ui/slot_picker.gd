@tool
class_name AISaveSlotPicker
extends RefCounted

## SlotPicker — slot seçici (Madde 09 / save_load / ui).
##
## Kayıt slotu seçim ekranı: 3 manuel slot + autosave + quicksave.
## SlotCard'lardan bir liste gösterir, kullanıcı bir slot seçer,
## kaydet/yükle/sil eylemini yapar.
##
## Bu view-model seçici durumunu yönetir: slot kartları, hangi slot
## seçili, kaydetme mi yükleme mi modunda.
##
## slot_manager (mantık katmanı) ile beslenir; bu sınıf kart
## listesini ve seçim durumunu yönetir.
##
## Mock policy: seçici gerçek slot durumlarından.

## Seçici çalışma modu.
enum PickerMode { SAVE, LOAD }

const MODE_NAMES: Dictionary = {
	PickerMode.SAVE: "save",
	PickerMode.LOAD: "load",
}

## Standart slot kimlikleri.
const MANUAL_SLOTS: Array = ["slot_1", "slot_2", "slot_3"]
const AUTO_SLOT: String = "autosave"
const QUICK_SLOT: String = "quicksave"


## Çalışma modu.
var mode: int = PickerMode.LOAD

## Slot kartları — slot_id -> AISaveSlotCard.
var _cards: Dictionary = {}

## Seçili slot kimliği (yoksa boş).
var selected_slot: String = ""


func _init() -> void:
	_init_slots()


## Standart slot kartlarını oluşturur.
func _init_slots() -> void:
	for slot_id in MANUAL_SLOTS:
		_cards[slot_id] = AISaveSlotCard.new(slot_id)
	_cards[AUTO_SLOT] = AISaveSlotCard.new(AUTO_SLOT)
	_cards[QUICK_SLOT] = AISaveSlotCard.new(QUICK_SLOT)


# ============================================================
# MOD
# ============================================================

## Seçiciyi kaydetme veya yükleme moduna alır.
func set_mode(p_mode: int) -> void:
	if MODE_NAMES.has(p_mode):
		mode = p_mode
		selected_slot = ""


# ============================================================
# SLOT GÜNCELLEME
# ============================================================

## Bir slotu dolu olarak günceller.
func set_slot_filled(slot_id: String, metadata: Dictionary) -> bool:
	if not _cards.has(slot_id):
		return false
	(_cards[slot_id] as AISaveSlotCard).set_filled(metadata)
	return true


## Bir slotu boş olarak günceller.
func set_slot_empty(slot_id: String) -> bool:
	if not _cards.has(slot_id):
		return false
	(_cards[slot_id] as AISaveSlotCard).set_empty()
	return true


## Bir slotu bozuk olarak işaretler.
func set_slot_corrupted(slot_id: String) -> bool:
	if not _cards.has(slot_id):
		return false
	(_cards[slot_id] as AISaveSlotCard).set_corrupted()
	return true


# ============================================================
# SEÇİM
# ============================================================

## Bir slotu seçer.
## Dönen: {selected: bool, reason: String}
func select_slot(slot_id: String) -> Dictionary:
	if not _cards.has(slot_id):
		return {"selected": false, "reason": "Bilinmeyen slot"}

	var card: AISaveSlotCard = _cards[slot_id]

	# Yükleme modunda — sadece dolu slot seçilebilir
	if mode == PickerMode.LOAD and not card.is_loadable():
		return {
			"selected": false,
			"reason": "Bu slot yüklenemez (boş veya bozuk)",
		}

	selected_slot = slot_id
	return {"selected": true, "reason": "Slot seçildi"}


## Seçimi temizler.
func clear_selection() -> void:
	selected_slot = ""


# ============================================================
# SUNUM
# ============================================================

## Tüm slot kartlarının görsel listesini üretir.
## Dönen: her biri SlotCard.build_card() + {selected} dizi.
func build_slot_list() -> Array:
	var list: Array = []
	# Manuel slotlar önce, sonra auto + quick
	var order: Array = MANUAL_SLOTS.duplicate()
	order.append(AUTO_SLOT)
	order.append(QUICK_SLOT)
	for slot_id in order:
		var card: AISaveSlotCard = _cards[slot_id]
		var card_data: Dictionary = card.build_card()
		card_data["selected"] = (slot_id == selected_slot)
		list.append(card_data)
	return list


# ============================================================
# EYLEM
# ============================================================

## Seçili slotta yapılabilecek eylemi belirler.
## Dönen: {action: String, enabled: bool, reason: String}
##   action: "save" | "load" | "none"
func resolve_action() -> Dictionary:
	if selected_slot.is_empty():
		return {
			"action": "none", "enabled": false,
			"reason": "Önce bir slot seçin",
		}
	var card: AISaveSlotCard = _cards[selected_slot]
	if mode == PickerMode.SAVE:
		return {
			"action": "save", "enabled": true,
			"reason": "Bu slota kaydet",
		}
	# LOAD modu
	if card.is_loadable():
		return {
			"action": "load", "enabled": true,
			"reason": "Bu slotu yükle",
		}
	return {
		"action": "none", "enabled": false,
		"reason": "Slot yüklenemez",
	}


# ============================================================
# SORGULAMA
# ============================================================

## Bir slot seçili mi?
func has_selection() -> bool:
	return not selected_slot.is_empty()


## Toplam slot sayısı.
func slot_count() -> int:
	return _cards.size()


## Bir slot kartını döndürür. Yoksa null.
func get_card(slot_id: String) -> AISaveSlotCard:
	return _cards.get(slot_id, null)
