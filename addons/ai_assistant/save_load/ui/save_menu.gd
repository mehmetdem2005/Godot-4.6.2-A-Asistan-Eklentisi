@tool
class_name AISaveMenu
extends RefCounted

## SaveMenu — kayıt/yükleme menüsü (Madde 09 / save_load / ui).
##
## Ana kayıt/yükleme ekranı. SlotPicker'ı barındırır, kaydet/yükle
## modları arasında geçiş yapar, onay diyaloglarını yönetir (üzerine
## yazma onayı, silme onayı).
##
## Bu view-model menü akışının durumunu tutar: hangi ekranda (slot
## listesi / onay diyaloğu), bekleyen eylem ne.
##
## slot_picker + save_manager (mantık katmanı) ile beslenir.
##
## Mock policy: menü durumu gerçek slot + kullanıcı akışından.

## Menü ekranı.
enum MenuScreen { SLOT_LIST, CONFIRM_OVERWRITE, CONFIRM_DELETE, BUSY }

const SCREEN_NAMES: Dictionary = {
	MenuScreen.SLOT_LIST: "slot_list",
	MenuScreen.CONFIRM_OVERWRITE: "confirm_overwrite",
	MenuScreen.CONFIRM_DELETE: "confirm_delete",
	MenuScreen.BUSY: "busy",
}


## Mevcut menü ekranı.
var screen: int = MenuScreen.SLOT_LIST

## Bekleyen eylemin hedef slotu (onay diyaloglarında).
var pending_slot: String = ""

## Slot seçici.
var _picker: AISaveSlotPicker


func _init() -> void:
	_picker = AISaveSlotPicker.new()


## Slot seçiciye erişim.
func picker() -> AISaveSlotPicker:
	return _picker


# ============================================================
# MENÜ AKIŞI
# ============================================================

## Menüyü kaydetme veya yükleme modunda açar.
## save_mode: true = kaydet, false = yükle.
func open(save_mode: bool) -> void:
	_picker.set_mode(
		AISaveSlotPicker.PickerMode.SAVE if save_mode \
		else AISaveSlotPicker.PickerMode.LOAD
	)
	screen = MenuScreen.SLOT_LIST
	pending_slot = ""


## Bir slota kaydetme isteği — dolu slotsa onay ister.
## slot_id: hedef slot.
## Dönen: {action: String, reason: String}
##   action: "save_now" | "need_confirm" | "rejected"
func request_save(slot_id: String) -> Dictionary:
	var card: AISaveSlotCard = _picker.get_card(slot_id)
	if card == null:
		return {"action": "rejected", "reason": "Bilinmeyen slot"}

	# Dolu slot — üzerine yazma onayı gerekir
	if card.is_filled():
		pending_slot = slot_id
		screen = MenuScreen.CONFIRM_OVERWRITE
		return {
			"action": "need_confirm",
			"reason": "Bu slot dolu — üzerine yazma onayı gerekli",
		}

	# Boş slot — doğrudan kaydet
	pending_slot = slot_id
	return {"action": "save_now", "reason": "Boş slota kaydedilecek"}


## Bir slotu silme isteği — her zaman onay ister.
## slot_id: hedef slot.
## Dönen: {action: String, reason: String}
func request_delete(slot_id: String) -> Dictionary:
	var card: AISaveSlotCard = _picker.get_card(slot_id)
	if card == null or not card.is_deletable():
		return {
			"action": "rejected",
			"reason": "Bu slot silinemez (boş veya geçersiz)",
		}
	pending_slot = slot_id
	screen = MenuScreen.CONFIRM_DELETE
	return {
		"action": "need_confirm",
		"reason": "Silme onayı gerekli",
	}


## Bekleyen onayı onaylar.
## Dönen: {confirmed_action: String, slot: String}
##   confirmed_action: "save" | "delete" | "none"
func confirm() -> Dictionary:
	var result: Dictionary = {"confirmed_action": "none", "slot": ""}
	match screen:
		MenuScreen.CONFIRM_OVERWRITE:
			result = {"confirmed_action": "save", "slot": pending_slot}
		MenuScreen.CONFIRM_DELETE:
			result = {"confirmed_action": "delete", "slot": pending_slot}
	screen = MenuScreen.SLOT_LIST
	return result


## Bekleyen onayı iptal eder — slot listesine döner.
func cancel() -> void:
	pending_slot = ""
	screen = MenuScreen.SLOT_LIST


## Menüyü meşgul (işlem sürüyor) durumuna alır.
func set_busy() -> void:
	screen = MenuScreen.BUSY


## Meşgul durumdan slot listesine döner.
func finish_busy() -> void:
	screen = MenuScreen.SLOT_LIST


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut ekranın adı.
func screen_name() -> String:
	return SCREEN_NAMES.get(screen, "?")


## Şu an bir onay bekleniyor mu?
func awaiting_confirmation() -> bool:
	return screen == MenuScreen.CONFIRM_OVERWRITE \
		or screen == MenuScreen.CONFIRM_DELETE


## Menü meşgul mu?
func is_busy() -> bool:
	return screen == MenuScreen.BUSY
