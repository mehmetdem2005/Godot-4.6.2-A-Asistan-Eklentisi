@tool
class_name AIPlanTreeModel
extends RefCounted

## PlanTreeModel — Plan Ağacı sekmesi modeli (Layer 11 / Workspace).
##
## Layer 3 Planner bir hiyerarşik plan kurar (GOAL -> EPIC -> TASK).
## Bu model o ağacı UI'da gösterilebilir, KATLANABILIR düğümler
## listesine çevirir.
##
## Model salt-veridir: düğümleri tutar, hangileri açık/kapalı bilir,
## görünür düğüm listesi üretir. Gerçek plan verisi Planner'dan gelir.
##
## Mock policy: düğümler dışarıdan eklenir; model veri uydurmaz.

## Düğüm seviyesi — plan hiyerarşisi.
enum NodeLevel { GOAL, EPIC, TASK, SUBTASK }

const LEVEL_NAMES: Dictionary = {
	NodeLevel.GOAL: "Hedef",
	NodeLevel.EPIC: "Epik",
	NodeLevel.TASK: "Görev",
	NodeLevel.SUBTASK: "Alt Görev",
}


## Ağaçtaki bir düğüm.
class TreeNode extends RefCounted:
	var id: String = ""
	var parent_id: String = ""
	var label: String = ""
	var level: int = AIPlanTreeModel.NodeLevel.TASK
	var status: String = "pending"     ## pending | active | done | failed
	var expanded: bool = true          ## UI'da açık mı
	var depth: int = 0                 ## Ağaçtaki derinlik

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"label": label,
			"level": AIPlanTreeModel.LEVEL_NAMES.get(level, "?"),
			"status": status,
			"expanded": expanded,
			"depth": depth,
		}


## Düğümler — id -> TreeNode.
var _nodes: Dictionary = {}

## Kök düğümün id'si.
var _root_id: String = ""


# ============================================================
# DÜĞÜM YÖNETİMİ
# ============================================================

## Bir düğüm ekler.
## id: benzersiz kimlik. parent_id: üst düğüm (kök için boş).
## Dönen: eklenen TreeNode (veya null — geçersiz).
func add_node(
	id: String, parent_id: String, label: String, level: int
) -> TreeNode:
	if id.is_empty():
		push_warning("PlanTreeModel: boş düğüm id")
		return null
	if _nodes.has(id):
		push_warning("PlanTreeModel: düğüm zaten var: " + id)
		return null
	# Kök değilse parent var olmalı
	if not parent_id.is_empty() and not _nodes.has(parent_id):
		push_warning("PlanTreeModel: parent yok: " + parent_id)
		return null

	var node := TreeNode.new()
	node.id = id
	node.parent_id = parent_id
	node.label = label
	node.level = level

	if parent_id.is_empty():
		# Kök düğüm
		if _root_id.is_empty():
			_root_id = id
			node.depth = 0
		else:
			push_warning("PlanTreeModel: ikinci kök reddedildi")
			return null
	else:
		var parent: TreeNode = _nodes[parent_id]
		node.depth = parent.depth + 1

	_nodes[id] = node
	return node


## Bir düğümü id ile döndürür. Yoksa null.
func get_node(id: String) -> TreeNode:
	return _nodes.get(id, null)


## Bir düğümün durumunu günceller.
func set_node_status(id: String, status: String) -> bool:
	if not _nodes.has(id):
		return false
	(_nodes[id] as TreeNode).status = status
	return true


# ============================================================
# KATLAMA
# ============================================================

## Bir düğümü açar/kapatır.
func toggle_node(id: String) -> bool:
	if not _nodes.has(id):
		return false
	var node: TreeNode = _nodes[id]
	node.expanded = not node.expanded
	return true


## Bir düğümü açar veya kapatır (açık ayar).
func set_expanded(id: String, expanded: bool) -> bool:
	if not _nodes.has(id):
		return false
	(_nodes[id] as TreeNode).expanded = expanded
	return true


# ============================================================
# GÖRÜNÜR DÜĞÜMLER
# ============================================================

## UI'da gösterilecek görünür düğümleri döndürür.
## Kapalı bir düğümün altındakiler görünmez. Sıralama: ağaç önce-derinlik.
func visible_nodes() -> Array:
	if _root_id.is_empty():
		return []
	var visible: Array = []
	_collect_visible(_root_id, visible)
	return visible


## Özyinelemeli — bir düğümü ve görünür alt düğümlerini toplar.
func _collect_visible(node_id: String, output: Array) -> void:
	var node: TreeNode = _nodes.get(node_id, null)
	if node == null:
		return
	output.append(node)
	# Düğüm kapalıysa çocukları gösterme
	if not node.expanded:
		return
	for child_id in _children_of(node_id):
		_collect_visible(child_id, output)


## Bir düğümün doğrudan çocuk id'lerini döndürür.
func _children_of(parent_id: String) -> Array:
	var children: Array = []
	for id in _nodes:
		if (_nodes[id] as TreeNode).parent_id == parent_id:
			children.append(id)
	return children


# ============================================================
# SORGULAMA
# ============================================================

## Toplam düğüm sayısı.
func node_count() -> int:
	return _nodes.size()


## Plan ilerleme oranı — done düğümlerin oranı.
func progress() -> float:
	if _nodes.is_empty():
		return 0.0
	var done: int = 0
	for id in _nodes:
		if (_nodes[id] as TreeNode).status == "done":
			done += 1
	return float(done) / float(_nodes.size())


## Durum özeti.
func summary() -> Dictionary:
	return {
		"node_count": _nodes.size(),
		"visible_count": visible_nodes().size(),
		"progress": progress(),
		"has_root": not _root_id.is_empty(),
	}


## Modeli temizler.
func clear() -> void:
	_nodes.clear()
	_root_id = ""
