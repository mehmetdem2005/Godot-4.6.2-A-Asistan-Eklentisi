@tool
class_name AISaveSlotCard
extends RefCounted

## SlotCard — kayıt slotu kartı (Madde 09 / save_load / ui).
##
## Bir kayıt slotunun görsel kartı: thumbnail, oyun adı/türü, oynama
## süresi, son kayıt tarihi, sil düğmesi. Slot picker bu kartlardan
## bir liste gösterir.
##
## Bu view-model tek bir slotun kart verisini hazırlar — slot dolu mu
## boş mu, hangi metadata gösterilecek, kart hangi durumda (normal/
## bozuk/yükleniyor).
##
## save_manager + slot metadata (mantık katmanı) ile beslenir.
##
## Mock policy: kart gerçek slot metadata'sından.

## Kart görsel durumu.
enum CardState { EMPTY, FILLED, CORRUPTED, LOADING }

const STATE_NAMES: Dictionary = {
	CardState.EMPTY: "empty",
	CardState.FILLED: "filled",
	CardState.CORRUPTED: "corrupted",
	CardState.LOADING: "loading",
}


## Slot kimliği (örn. "slot_1", "autosave", "quicksave").
var slot_id: String = ""

## Kart durumu.
var state: int = CardState.EMPTY

## Slot metadata'sı (dolu slotta).
var _metadata: Dictionary = {}


func _init(p_slot_id: String = "") -> void:
	slot_id = p_slot_id


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Kartı dolu bir slot için ayarlar.
## metadata: {genre, character_name, playtime, saved_at, has_thumbnail}
func set_filled(metadata: Dictionary) -> void:
	_metadata = metadata.duplicate(true)
	state = CardState.FILLED


## Kartı boş slot olarak ayarlar.
func set_empty() -> void:
	_metadata.clear()
	state = CardState.EMPTY


## Kartı bozuk slot olarak ayarlar.
func set_corrupted() -> void:
	state = CardState.CORRUPTED


## Kartı yükleniyor durumuna alır.
func set_loading() -> void:
	state = CardState.LOADING


# ============================================================
# SUNUM
# ============================================================

## Kartın görsel verisini üretir — UI kart düğümü bunu çizer.
## Dönen: {slot_id, state, title, subtitle, playtime_text,
##         has_thumbnail, can_delete, can_load}
func build_card() -> Dictionary:
	var card: Dictionary = {
		"slot_id": slot_id,
		"state": state,
		"state_name": STATE_NAMES.get(state, "?"),
	}

	match state:
		CardState.EMPTY:
			card["title"] = "Boş Slot"
			card["subtitle"] = "Yeni oyun başlat"
			card["playtime_text"] = ""
			card["has_thumbnail"] = false
			card["can_delete"] = false
			card["can_load"] = false
		CardState.CORRUPTED:
			card["title"] = "Bozuk Kayıt"
			card["subtitle"] = "Bu kayıt okunamıyor"
			card["playtime_text"] = ""
			card["has_thumbnail"] = false
			card["can_delete"] = true
			card["can_load"] = false
		CardState.LOADING:
			card["title"] = "Yükleniyor..."
			card["subtitle"] = ""
			card["playtime_text"] = ""
			card["has_thumbnail"] = false
			card["can_delete"] = false
			card["can_load"] = false
		_:  # FILLED
			card["title"] = str(_metadata.get(
				"character_name", "Kayıt"
			))
			card["subtitle"] = _genre_label()
			card["playtime_text"] = _format_playtime()
			card["has_thumbnail"] = bool(
				_metadata.get("has_thumbnail", false)
			)
			card["can_delete"] = true
			card["can_load"] = true

	return card


## Oyna süresini insan-okunur metne çevirir.
func _format_playtime() -> String:
	var seconds: float = float(_metadata.get("playtime", 0.0))
	var hours: int = int(seconds / 3600.0)
	var minutes: int = int(seconds / 60.0) % 60
	if hours > 0:
		return "%d sa %d dk" % [hours, minutes]
	return "%d dk" % minutes


## Tür etiketini döndürür.
func _genre_label() -> String:
	var genre: String = str(_metadata.get("genre", ""))
	return genre if not genre.is_empty() else "Bilinmeyen tür"


# ============================================================
# SORGULAMA
# ============================================================

## Slot dolu mu?
func is_filled() -> bool:
	return state == CardState.FILLED


## Slot bu karttan yüklenebilir mi?
func is_loadable() -> bool:
	return state == CardState.FILLED


## Bu slot silinebilir mi?
func is_deletable() -> bool:
	return state == CardState.FILLED or state == CardState.CORRUPTED
