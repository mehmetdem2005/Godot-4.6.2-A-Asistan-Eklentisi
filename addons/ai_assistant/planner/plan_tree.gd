@tool
class_name AIPlanTree
extends RefCounted

## PlanTree — hiyerarşik plan ağacı (Layer 3).
##
## Bir planın tüm AIPlanNode düğümlerini tutar ve ağaç yapısını yönetir:
## kök (GOAL) -> milestone'lar -> task'lar -> action'lar.
##
## DAGResolver bağımlılıkları (yatay ilişki) çözer; PlanTree hiyerarşiyi
## (dikey ilişki: parent/child) yönetir. İkisi birlikte tam planı oluşturur.

## Tüm düğümler — id -> AIPlanNode
var _nodes: Dictionary = {}

## Kök düğümün id'si (GOAL seviyesi). Boş = henüz kök yok.
var _root_id: String = ""


## Ağaçtaki düğüm sayısı.
func node_count() -> int:
	return _nodes.size()


## Ağaç boş mu?
func is_empty() -> bool:
	return _nodes.is_empty()


## Kök düğümü döndürür (GOAL). Yoksa null.
func root() -> AIPlanNode:
	if _root_id.is_empty():
		return null
	return _nodes.get(_root_id, null)


# ============================================================
# DÜĞÜM EKLEME
# ============================================================

## Bir düğümü ağaca ekler.
## - Geçersiz düğüm eklenmez.
## - GOAL seviyesi düğüm kök olur (ikinci GOAL reddedilir — tek kök).
## - parent_id belirtilmişse o parent ağaçta olmalı.
func add_node(node: AIPlanNode) -> bool:
	if node == null:
		return false
	if not node.is_valid():
		push_warning("PlanTree.add_node: geçersiz düğüm")
		return false
	if _nodes.has(node.id):
		push_warning("PlanTree.add_node: id zaten mevcut — %s" % node.id)
		return false

	# GOAL seviyesi = kök. Tek kök kuralı.
	if node.level == AIPlanNode.Level.GOAL:
		if not _root_id.is_empty():
			push_warning("PlanTree.add_node: zaten bir kök var, ikinci GOAL reddedildi")
			return false
		_root_id = node.id

	# Parent belirtilmişse ağaçta olmalı
	if not node.parent_id.is_empty():
		if not _nodes.has(node.parent_id):
			push_warning("PlanTree.add_node: parent ağaçta yok — %s" % node.parent_id)
			return false

	_nodes[node.id] = node

	# Parent'ın children listesine ekle
	if not node.parent_id.is_empty():
		var parent: AIPlanNode = _nodes[node.parent_id]
		parent.add_child(node.id)

	return true


## Bir düğümü id ile getirir. Yoksa null.
func get_node(id: String) -> AIPlanNode:
	return _nodes.get(id, null)


## Tüm düğümleri Dictionary olarak döndürür (DAGResolver'a geçmek için).
func all_nodes() -> Dictionary:
	return _nodes


## Tüm düğümleri liste olarak döndürür.
func node_list() -> Array:
	return _nodes.values()


# ============================================================
# HİYERARŞİ GEZİNME
# ============================================================

## Bir düğümün doğrudan alt düğümlerini döndürür.
func children_of(node_id: String) -> Array:
	var node: AIPlanNode = get_node(node_id)
	if node == null:
		return []
	var result: Array = []
	for child_id in node.children_ids:
		var child: AIPlanNode = get_node(child_id)
		if child != null:
			result.append(child)
	return result


## Bir düğümün parent'ını döndürür. Yoksa (kök ise) null.
func parent_of(node_id: String) -> AIPlanNode:
	var node: AIPlanNode = get_node(node_id)
	if node == null or node.parent_id.is_empty():
		return null
	return get_node(node.parent_id)


## Belirli bir seviyedeki tüm düğümleri döndürür.
## level: AIPlanNode.Level.GOAL / MILESTONE / TASK / ACTION
func nodes_at_level(level: int) -> Array:
	var result: Array = []
	for id in _nodes:
		var node: AIPlanNode = _nodes[id]
		if node.level == level:
			result.append(node)
	return result


## Tüm yaprak düğümleri döndürür (alt düğümü olmayanlar).
## Yapraklar genelde ACTION seviyesidir — çalıştırılabilir birimler.
func leaf_nodes() -> Array:
	var result: Array = []
	for id in _nodes:
		var node: AIPlanNode = _nodes[id]
		if node.is_leaf():
			result.append(node)
	return result


## Bir düğümün kökten o düğüme kadar olan yolunu döndürür.
## Örn: [GOAL, MILESTONE_2, TASK_5] — düğümün hiyerarşik konumu.
func path_to(node_id: String) -> Array:
	var path: Array = []
	var current: AIPlanNode = get_node(node_id)
	# Yukarı doğru yürü — kök bulununca dur
	var guard: int = 0
	while current != null and guard < 100:
		path.push_front(current)
		if current.parent_id.is_empty():
			break
		current = get_node(current.parent_id)
		guard += 1
	return path


## Bir düğümün derinliğini döndürür (kök = 0).
func depth_of(node_id: String) -> int:
	return path_to(node_id).size() - 1


# ============================================================
# İLERLEME
# ============================================================

## Tamamlanmış düğüm sayısı.
func completed_count() -> int:
	var count: int = 0
	for id in _nodes:
		if (_nodes[id] as AIPlanNode).is_completed:
			count += 1
	return count


## Planın tamamlanma yüzdesi (0.0 - 1.0).
func progress() -> float:
	if _nodes.is_empty():
		return 0.0
	return float(completed_count()) / float(_nodes.size())


## Plan tamamen bitti mi?
func is_complete() -> bool:
	return not _nodes.is_empty() and completed_count() == _nodes.size()


# ============================================================
# BÜTÜNLÜK DOĞRULAMA
# ============================================================

## Ağaç bütünlüğünü doğrular. Dönen: AIValidationResult.
## Kontroller: kök var mı, hiyerarşi seviyeleri tutarlı mı, yetim düğüm var mı.
func validate_tree() -> AIValidationResult:
	var result := AIValidationResult.new()

	if _nodes.is_empty():
		result.add_warning("Plan ağacı boş")
		return result

	# Kök kontrolü
	if _root_id.is_empty():
		result.add_error("Plan ağacının kökü (GOAL) yok")
	elif not _nodes.has(_root_id):
		result.add_error("Kök id ağaçta bulunamıyor")

	for id in _nodes:
		var node: AIPlanNode = _nodes[id]

		# Yetim düğüm — GOAL dışındaki her düğümün parent'ı olmalı
		if node.level != AIPlanNode.Level.GOAL and node.parent_id.is_empty():
			result.add_error("Yetim düğüm (parent'sız, GOAL değil): %s" % id)

		# Parent ağaçta var mı
		if not node.parent_id.is_empty() and not _nodes.has(node.parent_id):
			result.add_error("Düğüm '%s' var olmayan parent'a bağlı" % id)

		# Hiyerarşi seviye tutarlılığı — child, parent'tan bir alt seviyede olmalı
		if not node.parent_id.is_empty() and _nodes.has(node.parent_id):
			var parent: AIPlanNode = _nodes[node.parent_id]
			var expected: int = parent.expected_child_level()
			if expected >= 0 and node.level != expected:
				result.add_warning(
					"Seviye atlaması: '%s' (%s) parent '%s' (%s) altında"
					% [id, node.level_name(), node.parent_id, parent.level_name()]
				)

		# children_ids tutarlılığı — listelenen her child gerçekten var mı
		for child_id in node.children_ids:
			if not _nodes.has(child_id):
				result.add_error(
					"Düğüm '%s' var olmayan child'a işaret ediyor: %s" % [id, child_id]
				)

	return result
