@tool
class_name AIVCSDiff
extends AIContractBase

## VCSDiff — iki durum arasındaki fark.
##
## İki commit, iki snapshot veya çalışma alanı değişiklikleri karşılaştırıldığında
## ne değiştiğini taşır. Rollback preview, code review ve HITL diff viewer bunu kullanır.
##
## Üç fark tipi: dosya (text), sahne (structural), proje ayarı.

## Bir satır değişikliği tipi.
enum LineOp {
	CONTEXT,  ## Değişmemiş satır (bağlam)
	ADD,      ## Eklenen satır
	DELETE,   ## Silinen satır
}

# --- Kimlik ---
var id: String = ""
var diff_type: String = "file"       ## file | scene | project_settings

# --- Karşılaştırma bağlamı ---
var from_ref: String = ""            ## Eski durum referansı (commit/snapshot id)
var to_ref: String = ""              ## Yeni durum referansı

# --- Dosya farkları ---
var files_added: PackedStringArray = PackedStringArray()
var files_removed: PackedStringArray = PackedStringArray()
var files_changed: PackedStringArray = PackedStringArray()

# --- Detaylı satır farkları (file diff için) ---
## file_path -> [{op: LineOp, line_no: int, content: String}]
var line_diffs: Dictionary = {}

# --- Sahne farkları (scene diff için) ---
var nodes_added: PackedStringArray = PackedStringArray()
var nodes_removed: PackedStringArray = PackedStringArray()
var nodes_modified: PackedStringArray = PackedStringArray()
## node_path -> {property: [old_value, new_value]}
var property_changes: Dictionary = {}

# --- Özet istatistik ---
var lines_added_count: int = 0
var lines_removed_count: int = 0


func contract_type() -> String:
	return "VCSDiff"


## Yeni bir diff oluşturur (factory).
static func create(p_diff_type: String, p_from: String, p_to: String) -> AIVCSDiff:
	var d := AIVCSDiff.new()
	d.id = AIContractBase.generate_id("diff")
	d.diff_type = p_diff_type
	d.from_ref = p_from
	d.to_ref = p_to
	return d


## Bu diff'in herhangi bir değişiklik içerip içermediğini kontrol eder.
func is_empty() -> bool:
	return (
		files_added.is_empty()
		and files_removed.is_empty()
		and files_changed.is_empty()
		and nodes_added.is_empty()
		and nodes_removed.is_empty()
		and nodes_modified.is_empty()
	)


## Toplam etkilenen dosya sayısı.
func total_files_affected() -> int:
	return files_added.size() + files_removed.size() + files_changed.size()


## Toplam etkilenen node sayısı.
func total_nodes_affected() -> int:
	return nodes_added.size() + nodes_removed.size() + nodes_modified.size()


## Diff'in kısa özet metni (UI için).
func summary() -> String:
	if diff_type == "scene":
		return "%d node eklendi, %d silindi, %d değişti" % [
			nodes_added.size(), nodes_removed.size(), nodes_modified.size()
		]
	return "%d dosya, +%d / -%d satır" % [
		total_files_affected(), lines_added_count, lines_removed_count
	]


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"diff_type": diff_type,
		"from_ref": from_ref,
		"to_ref": to_ref,
		"files_added": files_added,
		"files_removed": files_removed,
		"files_changed": files_changed,
		"line_diffs": line_diffs,
		"nodes_added": nodes_added,
		"nodes_removed": nodes_removed,
		"nodes_modified": nodes_modified,
		"property_changes": property_changes,
		"lines_added_count": lines_added_count,
		"lines_removed_count": lines_removed_count,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	diff_type = data.get("diff_type", "file")
	from_ref = data.get("from_ref", "")
	to_ref = data.get("to_ref", "")
	files_added = PackedStringArray(data.get("files_added", []))
	files_removed = PackedStringArray(data.get("files_removed", []))
	files_changed = PackedStringArray(data.get("files_changed", []))
	line_diffs = data.get("line_diffs", {})
	nodes_added = PackedStringArray(data.get("nodes_added", []))
	nodes_removed = PackedStringArray(data.get("nodes_removed", []))
	nodes_modified = PackedStringArray(data.get("nodes_modified", []))
	property_changes = data.get("property_changes", {})
	lines_added_count = int(data.get("lines_added_count", 0))
	lines_removed_count = int(data.get("lines_removed_count", 0))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_in_set(
		result, diff_type, ["file", "scene", "project_settings"], "diff_type"
	)
	if lines_added_count < 0 or lines_removed_count < 0:
		result.add_error("satır sayıları negatif olamaz")
