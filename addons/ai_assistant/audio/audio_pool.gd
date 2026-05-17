@tool
class_name AIAudioPool
extends RefCounted

## AudioPool — ses çalar havuzu (Madde 08 / Audio System).
##
## Bir oyunda aynı anda çok ses çalar: ayak sesleri, mermiler,
## patlamalar. Her ses için yeni AudioStreamPlayer yaratmak pahalı
## ve mobilde sınır var (eşzamanlı ses kanalı ~16-32).
##
## Çözüm — havuz (pool): önceden N çalar oluştur, kullanılmayanı
## ödünç ver, ses bitince geri al. Bu sınıf o havuzun TAHSİS
## MANTIĞINI yönetir — hangi çalar boş, hangi meşgul.
##
## Havuz dolu olduğunda: en eski/en az öncelikli sesi kes (voice
## stealing) — mobilde kanal sınırı gerçek.
##
## Gerçek AudioStreamPlayer'lar Node sarmalayıcının; bu model
## tahsis mantığıdır — test edilebilir.
##
## Mock policy: tahsis gerçek havuz durumundan; sahte çalar yok.

## Varsayılan havuz boyutu — mobil için makul.
const DEFAULT_POOL_SIZE: int = 16

## Bir havuz yuvasının durumu.
class PoolSlot extends RefCounted:
	var slot_index: int = 0
	var busy: bool = false
	var priority: int = 0              ## Yüksek = önemli, kesilmesin
	var sound_id: String = ""          ## Çalan sesin kimliği
	var started_tick: int = 0          ## Başlama sırası (voice stealing)

	func to_dict() -> Dictionary:
		return {
			"slot_index": slot_index,
			"busy": busy,
			"priority": priority,
			"sound_id": sound_id,
		}


## Havuz yuvaları.
var _slots: Array = []

## Bir sonraki başlama sıra numarası — voice stealing için.
var _tick: int = 0


func _init(pool_size: int = DEFAULT_POOL_SIZE) -> void:
	var size: int = maxi(pool_size, 1)
	for i in range(size):
		var slot := PoolSlot.new()
		slot.slot_index = i
		_slots.append(slot)


# ============================================================
# TAHSİS
# ============================================================

## Bir ses için havuzdan yuva ödünç alır.
## sound_id: çalınacak sesin kimliği. priority: önem (yüksek=korunur).
## Dönen: {ok: bool, slot_index: int, stole: bool, reason: String}
##   stole=true: havuz doluydu, daha az öncelikli bir ses kesildi.
func acquire(sound_id: String, priority: int = 0) -> Dictionary:
	_tick += 1

	# Boş yuva ara
	var free_slot: PoolSlot = _find_free_slot()
	if free_slot != null:
		_assign(free_slot, sound_id, priority)
		return {
			"ok": true, "slot_index": free_slot.slot_index,
			"stole": false, "reason": "boş yuva",
		}

	# Havuz dolu — voice stealing: en zayıf adayı bul
	var victim: PoolSlot = _find_steal_victim(priority)
	if victim == null:
		# Tüm yuvalar daha öncelikli — bu ses çalınamaz
		return {
			"ok": false, "slot_index": -1, "stole": false,
			"reason": "havuz dolu, tüm sesler daha öncelikli",
		}
	_assign(victim, sound_id, priority)
	return {
		"ok": true, "slot_index": victim.slot_index,
		"stole": true, "reason": "düşük öncelikli ses kesildi",
	}


## Bir yuvayı serbest bırakır — ses bitince.
## Dönen: true = yuva vardı ve bırakıldı.
func release(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot: PoolSlot = _slots[slot_index]
	slot.busy = false
	slot.sound_id = ""
	slot.priority = 0
	return true


## Bir yuvaya ses ata.
func _assign(slot: PoolSlot, sound_id: String, priority: int) -> void:
	slot.busy = true
	slot.sound_id = sound_id
	slot.priority = priority
	slot.started_tick = _tick


# ============================================================
# YUVA ARAMA
# ============================================================

## Boş bir yuva bulur. Yoksa null.
func _find_free_slot() -> PoolSlot:
	for slot in _slots:
		if not (slot as PoolSlot).busy:
			return slot
	return null


## Voice stealing için kurban bulur — yeni sesten daha az öncelikli,
## en eski yuva. Uygun kurban yoksa null.
func _find_steal_victim(new_priority: int) -> PoolSlot:
	var victim: PoolSlot = null
	for slot in _slots:
		var s: PoolSlot = slot
		# Sadece yeni sesten DÜŞÜK öncelikli sesler kesilebilir
		if s.priority >= new_priority:
			continue
		# En eski (en küçük tick) adayı seç
		if victim == null or s.started_tick < victim.started_tick:
			victim = s
	return victim


# ============================================================
# DURUM
# ============================================================

## Havuz boyutu.
func pool_size() -> int:
	return _slots.size()


## Meşgul yuva sayısı.
func busy_count() -> int:
	var n: int = 0
	for slot in _slots:
		if (slot as PoolSlot).busy:
			n += 1
	return n


## Boş yuva sayısı.
func free_count() -> int:
	return _slots.size() - busy_count()


## Havuz dolu mu?
func is_full() -> bool:
	return free_count() == 0


## Tüm yuvaları serbest bırakır — sahne değişiminde.
func release_all() -> void:
	for slot in _slots:
		var s: PoolSlot = slot
		s.busy = false
		s.sound_id = ""
		s.priority = 0


## Havuz durumu özeti.
func summary() -> Dictionary:
	return {
		"pool_size": pool_size(),
		"busy": busy_count(),
		"free": free_count(),
		"is_full": is_full(),
	}
