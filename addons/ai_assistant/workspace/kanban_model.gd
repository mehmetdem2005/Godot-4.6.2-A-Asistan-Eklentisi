@tool
class_name AIKanbanModel
extends RefCounted

## KanbanModel — Kanban panosu veri modeli (Layer 11).
##
## Kanban sekmesinin ALTINDAKI mantık. Görsel sütunlar/kartlar değil —
## "hangi task hangi kolonda, taşıma geçerli mi" durumu. Görsel Control
## node'ları bu modeli okur ve çizer.
##
## Master plan task lifecycle ile uyumlu kolonlar:
##   BACKLOG -> READY -> IN_PROGRESS -> VERIFY -> DONE
##                                  -> BLOCKED (yan durum)
##
## Mock policy: model gerçek task verisinden beslenir.

## Kanban kolonları — task akış sırası.
enum Column { BACKLOG, READY, IN_PROGRESS, VERIFY, DONE, BLOCKED }

const COLUMN_NAMES: Dictionary = {
	Column.BACKLOG: "Backlog",
	Column.READY: "Hazır",
	Column.IN_PROGRESS: "Devam Ediyor",
	Column.VERIFY: "Doğrulama",
	Column.DONE: "Tamamlandı",
	Column.BLOCKED: "Engelli",
}

## Geçerli ileri akış — bir task hangi kolondan hangisine geçebilir.
## BLOCKED her yerden gidilebilir/dönülebilir (yan durum).
const FORWARD_FLOW: Dictionary = {
	Column.BACKLOG: [Column.READY, Column.BLOCKED],
	Column.READY: [Column.IN_PROGRESS, Column.BACKLOG, Column.BLOCKED],
	Column.IN_PROGRESS: [Column.VERIFY, Column.READY, Column.BLOCKED],
	Column.VERIFY: [Column.DONE, Column.IN_PROGRESS, Column.BLOCKED],
	Column.DONE: [Column.IN_PROGRESS],  # yeniden açma
	Column.BLOCKED: [Column.BACKLOG, Column.READY, Column.IN_PROGRESS],
}


## Tek bir Kanban kartı (bir task'ın UI temsili).
class Card extends RefCounted:
	var task_id: String = ""
	var title: String = ""
	var column: int = AIKanbanModel.Column.BACKLOG
	var priority: int = 0          ## Yüksek = önce
	var owner_role: String = ""

	func to_dict() -> Dictionary:
		return {
			"task_id": task_id,
			"title": title,
			"column": column,
			"priority": priority,
			"owner_role": owner_role,
		}


## Tüm kartlar — task_id -> Card
var _cards: Dictionary = {}


## Kart sayısı.
func card_count() -> int:
	return _cards.size()


# ============================================================
# KART YÖNETİMİ
# ============================================================

## Yeni bir kart ekler — varsayılan BACKLOG kolonunda.
func add_card(task_id: String, title: String, owner_role: String = "") -> Card:
	if task_id.is_empty():
		push_warning("KanbanModel.add_card: boş task_id")
		return null
	var card := Card.new()
	card.task_id = task_id
	card.title = title
	card.column = Column.BACKLOG
	card.owner_role = owner_role
	_cards[task_id] = card
	return card


## Bir kartı id ile döndürür. Yoksa null.
func get_card(task_id: String) -> Card:
	return _cards.get(task_id, null)


## Bir kartı kaldırır.
func remove_card(task_id: String) -> bool:
	if not _cards.has(task_id):
		return false
	_cards.erase(task_id)
	return true


# ============================================================
# TAŞIMA — task'ı kolondan kolona
# ============================================================

## Bir kartın hedef kolona taşınabilir olup olmadığını kontrol eder.
## Geçersiz akış (örn. BACKLOG -> DONE doğrudan) reddedilir.
func can_move(task_id: String, target_column: int) -> bool:
	var card: Card = get_card(task_id)
	if card == null:
		return false
	if not COLUMN_NAMES.has(target_column):
		return false
	if card.column == target_column:
		return true  # aynı yer — no-op, geçerli
	var allowed: Array = FORWARD_FLOW.get(card.column, [])
	return allowed.has(target_column)


## Bir kartı hedef kolona taşır.
## Dönen: {ok: bool, reason: String}
func move_card(task_id: String, target_column: int) -> Dictionary:
	var card: Card = get_card(task_id)
	if card == null:
		return {"ok": false, "reason": "Kart bulunamadı"}
	if not COLUMN_NAMES.has(target_column):
		return {"ok": false, "reason": "Geçersiz kolon"}
	if not can_move(task_id, target_column):
		return {
			"ok": false,
			"reason": "Geçersiz akış: %s -> %s" % [
				COLUMN_NAMES.get(card.column, "?"),
				COLUMN_NAMES.get(target_column, "?"),
			],
		}
	card.column = target_column
	return {"ok": true, "reason": ""}


# ============================================================
# SORGULAMA — UI çizimi için
# ============================================================

## Belirli bir kolondaki kartları döndürür — öncelik sırasına göre.
func cards_in_column(column: int) -> Array:
	var result: Array = []
	for task_id in _cards:
		var card: Card = _cards[task_id]
		if card.column == column:
			result.append(card)
	# Öncelik azalan — yüksek öncelik üstte
	result.sort_custom(func(a, b): return a.priority > b.priority)
	return result


## Her kolondaki kart sayısı — {column: count}.
func column_counts() -> Dictionary:
	var counts: Dictionary = {}
	for column in COLUMN_NAMES:
		counts[column] = 0
	for task_id in _cards:
		var col: int = (_cards[task_id] as Card).column
		counts[col] = int(counts.get(col, 0)) + 1
	return counts


## Pano tamamlanma oranı — DONE kartların toplam içindeki payı.
func completion_ratio() -> float:
	if _cards.is_empty():
		return 0.0
	var done: int = cards_in_column(Column.DONE).size()
	return float(done) / float(_cards.size())


## Engelli (BLOCKED) kart var mı — UI uyarısı için.
func has_blocked_cards() -> bool:
	return cards_in_column(Column.BLOCKED).size() > 0


## Pano durum özeti.
func summary() -> Dictionary:
	return {
		"total_cards": _cards.size(),
		"column_counts": column_counts(),
		"completion_ratio": completion_ratio(),
		"has_blocked": has_blocked_cards(),
	}


## Tüm kartları temizler.
func clear() -> void:
	_cards.clear()


## Bir kolonun adı.
static func column_name(column: int) -> String:
	return COLUMN_NAMES.get(column, "?")
