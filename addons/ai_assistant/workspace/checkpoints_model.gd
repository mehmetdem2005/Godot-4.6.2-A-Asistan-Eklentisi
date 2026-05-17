@tool
class_name AICheckpointsModel
extends RefCounted

## CheckpointsModel — Kontrol Noktaları sekmesi modeli (Layer 11).
##
## Sistem ilerlerken kontrol noktaları (checkpoint) oluşturur — geri
## dönülebilir kayıt noktaları. Layer 4 (journal/undo) ve Layer 8
## (HITL gate) bunları üretir.
##
## Bu sekme kullanıcıya der: "şu ana kadar şu noktalar oluştu, istersen
## buraya geri dönebilirsin". Bir checkpoint seçilip geri yüklenebilir.
##
## Mock policy: checkpoint kayıtları gerçek sistemden eklenir;
## model kayıt uydurmaz. Geri yükleme niyeti işaretlenir — gerçek
## geri yükleme Layer 4'ün işidir.

## Bir kontrol noktasının kaynağı.
enum CheckpointKind { AUTO, MANUAL, GATE_APPROVAL, ITERATION_END }

const KIND_NAMES: Dictionary = {
	CheckpointKind.AUTO: "Otomatik",
	CheckpointKind.MANUAL: "Manuel",
	CheckpointKind.GATE_APPROVAL: "Onay Kapısı",
	CheckpointKind.ITERATION_END: "Iterasyon Sonu",
}


## Tek bir kontrol noktası.
class Checkpoint extends RefCounted:
	var id: String = ""
	var label: String = ""
	var kind: int = AICheckpointsModel.CheckpointKind.AUTO
	var sequence: int = 0              ## Sıra numarası (oluşma sırası)
	var restorable: bool = true        ## Geri yüklenebilir mi

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"label": label,
			"kind": AICheckpointsModel.KIND_NAMES.get(kind, "?"),
			"sequence": sequence,
			"restorable": restorable,
		}


## Kontrol noktaları — oluşma sırasıyla.
var _checkpoints: Array = []

## Bir sonraki sıra numarası.
var _next_sequence: int = 1

## Seçili checkpoint id'si (geri yükleme için).
var selected_id: String = ""


# ============================================================
# KAYIT
# ============================================================

## Bir kontrol noktası ekler.
## id: benzersiz kimlik. label: açıklama. kind: kaynak tipi.
## Dönen: eklenen Checkpoint (veya null — geçersiz id).
func add_checkpoint(id: String, label: String, kind: int) -> Checkpoint:
	if id.is_empty():
		push_warning("CheckpointsModel: boş checkpoint id")
		return null
	# Aynı id varsa ekleme
	for cp in _checkpoints:
		if (cp as Checkpoint).id == id:
			push_warning("CheckpointsModel: id zaten var: " + id)
			return null

	var checkpoint := Checkpoint.new()
	checkpoint.id = id
	checkpoint.label = label
	if KIND_NAMES.has(kind):
		checkpoint.kind = kind
	checkpoint.sequence = _next_sequence
	_next_sequence += 1
	_checkpoints.append(checkpoint)
	return checkpoint


## Bir checkpoint'i id ile döndürür. Yoksa null.
func get_checkpoint(id: String) -> Checkpoint:
	for cp in _checkpoints:
		if (cp as Checkpoint).id == id:
			return cp
	return null


# ============================================================
# SEÇİM + GERİ YÜKLEME
# ============================================================

## Bir checkpoint'i seçer (geri yükleme adayı).
func select(id: String) -> bool:
	if get_checkpoint(id) == null:
		return false
	selected_id = id
	return true


## Seçili checkpoint için geri yükleme niyetini hazırlar.
## Gerçek geri yükleme Layer 4'ün işi — bu sadece niyeti döndürür.
## Dönen: {ok: bool, checkpoint_id: String, reason: String}
func request_restore() -> Dictionary:
	if selected_id.is_empty():
		return {
			"ok": false,
			"checkpoint_id": "",
			"reason": "Seçili kontrol noktası yok",
		}
	var cp: Checkpoint = get_checkpoint(selected_id)
	if cp == null:
		return {
			"ok": false,
			"checkpoint_id": selected_id,
			"reason": "Kontrol noktası bulunamadı",
		}
	if not cp.restorable:
		return {
			"ok": false,
			"checkpoint_id": selected_id,
			"reason": "Bu kontrol noktası geri yüklenemez",
		}
	return {
		"ok": true,
		"checkpoint_id": selected_id,
		"reason": "Geri yükleme hazır",
	}


# ============================================================
# SORGULAMA
# ============================================================

## Toplam kontrol noktası sayısı.
func count() -> int:
	return _checkpoints.size()


## En son (en yüksek sıralı) kontrol noktası. Yoksa null.
func latest() -> Checkpoint:
	if _checkpoints.is_empty():
		return null
	return _checkpoints[_checkpoints.size() - 1]


## Geri yüklenebilir kontrol noktaları.
func restorable_checkpoints() -> Array:
	var result: Array = []
	for cp in _checkpoints:
		if (cp as Checkpoint).restorable:
			result.append(cp)
	return result


## UI'da gösterilecek liste — en yeni önce.
func display_list() -> Array:
	var list: Array = []
	for i in range(_checkpoints.size() - 1, -1, -1):
		list.append((_checkpoints[i] as Checkpoint).to_dict())
	return list


## Durum özeti.
func summary() -> Dictionary:
	return {
		"count": count(),
		"restorable": restorable_checkpoints().size(),
		"selected": selected_id,
	}


## Tüm kontrol noktalarını temizler.
func clear() -> void:
	_checkpoints.clear()
	_next_sequence = 1
	selected_id = ""
