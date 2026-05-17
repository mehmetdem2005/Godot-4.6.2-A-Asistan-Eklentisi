@tool
class_name AIStateSnapshot
extends AIContractBase

## StateSnapshot — sistem durumunun anlık görüntüsü.
##
## Bir işlem öncesi/sonrası durum kaydedilir. İki snapshot karşılaştırılarak
## ne değiştiği görülür (diff). Transaction rollback, verifier ve VCS bunu kullanır.
##
## Snapshot içeriği: dosya hash'leri, sahne node ağacı özeti, project settings,
## input map, seçili node'lar.

# --- Kimlik ---
var id: String = ""
var label: String = ""               ## İnsan-okunabilir etiket (örn: "mesh ekleme öncesi")
var captured_at: String = ""

# --- Durum içeriği ---
var file_hashes: Dictionary = {}      ## dosya_yolu -> SHA-256 hash
var scene_tree: Dictionary = {}       ## Aktif sahne node ağacı özeti
var project_settings: Dictionary = {} ## İlgili project.godot ayarları
var input_map: Dictionary = {}        ## InputMap action'ları
var selected_nodes: PackedStringArray = PackedStringArray()  ## Editörde seçili node yolları

# --- Bağlam ---
var scene_path: String = ""           ## Hangi sahnenin snapshot'ı
var iteration_ref: String = ""        ## Hangi iteration'da alındı


func contract_type() -> String:
	return "StateSnapshot"


## Yeni bir snapshot oluşturur (factory).
static func create(p_label: String) -> AIStateSnapshot:
	var s := AIStateSnapshot.new()
	s.id = AIContractBase.generate_id("snap")
	s.label = p_label
	s.captured_at = AIContractBase.now_iso()
	return s


## Bu snapshot ile başka bir snapshot arasındaki farkları döndürür.
## Sonuç: {files_added, files_removed, files_changed, scene_changed}
func diff_against(other: AIStateSnapshot) -> Dictionary:
	if other == null:
		return {}

	var files_added: PackedStringArray = PackedStringArray()
	var files_removed: PackedStringArray = PackedStringArray()
	var files_changed: PackedStringArray = PackedStringArray()

	# Bu snapshot'ta olup other'da olmayan -> eklenmiş
	# (other = eski durum, this = yeni durum varsayımı)
	for path in file_hashes:
		if not other.file_hashes.has(path):
			files_added.append(path)
		elif other.file_hashes[path] != file_hashes[path]:
			files_changed.append(path)

	# Other'da olup bu snapshot'ta olmayan -> silinmiş
	for path in other.file_hashes:
		if not file_hashes.has(path):
			files_removed.append(path)

	var scene_changed: bool = scene_tree.hash() != other.scene_tree.hash()

	return {
		"files_added": files_added,
		"files_removed": files_removed,
		"files_changed": files_changed,
		"scene_changed": scene_changed,
	}


## İki snapshot'ın tamamen aynı olup olmadığını kontrol eder.
func equals(other: AIStateSnapshot) -> bool:
	if other == null:
		return false
	var d: Dictionary = diff_against(other)
	return (
		(d.get("files_added", PackedStringArray()) as PackedStringArray).is_empty()
		and (d.get("files_removed", PackedStringArray()) as PackedStringArray).is_empty()
		and (d.get("files_changed", PackedStringArray()) as PackedStringArray).is_empty()
		and not d.get("scene_changed", false)
	)


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"label": label,
		"captured_at": captured_at,
		"file_hashes": file_hashes,
		"scene_tree": scene_tree,
		"project_settings": project_settings,
		"input_map": input_map,
		"selected_nodes": selected_nodes,
		"scene_path": scene_path,
		"iteration_ref": iteration_ref,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	label = data.get("label", "")
	captured_at = data.get("captured_at", "")
	file_hashes = data.get("file_hashes", {})
	scene_tree = data.get("scene_tree", {})
	project_settings = data.get("project_settings", {})
	input_map = data.get("input_map", {})
	selected_nodes = PackedStringArray(data.get("selected_nodes", []))
	scene_path = data.get("scene_path", "")
	iteration_ref = data.get("iteration_ref", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	if captured_at.is_empty():
		result.add_warning("captured_at boş — snapshot zamanı bilinmiyor")
