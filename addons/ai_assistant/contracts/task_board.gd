@tool
class_name AITaskBoard
extends AIContractBase

## TaskBoard — Kanban tahtası yapısı.
##
## Task'lar bir board üzerinde kolonlarda görüntülenir. Her board birden çok
## kolon içerir (Backlog / Ready / Active / Blocked / Review / Done).
## Task Workspace'in "📋 Görevler" sekmesi board'ları render eder.

## Varsayılan Kanban kolonları (TaskLifecycle durumlarıyla eşleşir).
const DEFAULT_COLUMNS: Array = [
	"backlog", "ready", "active", "blocked", "review", "done"
]

## Kolon -> Türkçe başlık.
const COLUMN_DISPLAY_TR: Dictionary = {
	"backlog": "Backlog",
	"ready": "Hazır",
	"active": "Aktif",
	"blocked": "Engelli",
	"review": "İnceleme",
	"done": "Bitti",
}

## Kolon -> hangi TaskLifecycle durumlarını içerir.
const COLUMN_STATUS_MAP: Dictionary = {
	"backlog": [AITaskLifecycle.Status.QUEUED],
	"ready": [AITaskLifecycle.Status.READY],
	"active": [AITaskLifecycle.Status.IN_PROGRESS],
	"blocked": [AITaskLifecycle.Status.BLOCKED],
	"review": [AITaskLifecycle.Status.IN_REVIEW],
	"done": [AITaskLifecycle.Status.DONE, AITaskLifecycle.Status.ARCHIVED],
}

# --- Kimlik ---
var id: String = ""
var name: String = ""                ## Board adı (örn: "Iteration 3 Board")
var board_type: String = "iteration" ## iteration | backlog | archive

# --- İçerik ---
var columns: PackedStringArray = PackedStringArray()  ## Kolon kimlikleri
var task_ids: PackedStringArray = PackedStringArray()  ## Bu board'daki task'lar

# --- Bağlam ---
var iteration_id: String = ""        ## Hangi iteration'a ait (varsa)

# --- Zaman ---
var created_at: String = ""


func contract_type() -> String:
	return "TaskBoard"


## Varsayılan kolonlarla yeni board oluşturur (factory).
static func create(p_name: String, p_type: String = "iteration") -> AITaskBoard:
	var b := AITaskBoard.new()
	b.id = AIContractBase.generate_id("board")
	b.name = p_name
	b.board_type = p_type
	b.columns = PackedStringArray(DEFAULT_COLUMNS)
	b.created_at = AIContractBase.now_iso()
	return b


## Bir task'ı board'a ekler (zaten varsa eklenmez).
func add_task(task_id: String) -> void:
	if not task_ids.has(task_id):
		task_ids.append(task_id)


## Bir task'ı board'dan çıkarır.
func remove_task(task_id: String) -> void:
	var idx: int = task_ids.find(task_id)
	if idx >= 0:
		task_ids.remove_at(idx)


## Verilen TaskLifecycle durumunun hangi kolona düştüğünü döndürür.
## Eşleşme yoksa boş string döner.
static func column_for_status(status: int) -> String:
	for col in COLUMN_STATUS_MAP:
		if (COLUMN_STATUS_MAP[col] as Array).has(status):
			return col
	return ""


## Kolonun Türkçe görünen adı.
static func column_display_tr(column_id: String) -> String:
	return COLUMN_DISPLAY_TR.get(column_id, column_id)


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"board_type": board_type,
		"columns": columns,
		"task_ids": task_ids,
		"iteration_id": iteration_id,
		"created_at": created_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	name = data.get("name", "")
	board_type = data.get("board_type", "iteration")
	columns = PackedStringArray(data.get("columns", DEFAULT_COLUMNS))
	task_ids = PackedStringArray(data.get("task_ids", []))
	iteration_id = data.get("iteration_id", "")
	created_at = data.get("created_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, name, "name")
	require_in_set(
		result, board_type, ["iteration", "backlog", "archive"], "board_type"
	)
	if columns.is_empty():
		result.add_error("Board en az bir kolon içermeli")
