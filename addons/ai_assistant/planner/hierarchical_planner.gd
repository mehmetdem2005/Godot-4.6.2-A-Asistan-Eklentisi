@tool
class_name AIHierarchicalPlanner
extends RefCounted

## HierarchicalPlanner — hiyerarşik planlama motoru (Layer 3).
##
## Sistemin "beyni": bir kullanıcı isteğini çalıştırılabilir plana çevirir.
##   Girdi:  "FPS oyunu yap" (serbest metin hedef)
##   Çıktı:  PlanTree (Goal -> Milestone -> Task -> Action hiyerarşisi)
##
## DAGResolver (bağımlılık) + PlanTree (hiyerarşi) bu sınıfta birleşir.
##
## NOT: Bu sınıf plan YAPISINI yönetir. LLM ile gerçek plan ÜRETİMİ
## (hedefi adımlara bölme) Layer 7 entegrasyonunda eklenecek. Şu an
## planı programatik kurma + doğrulama + sıralama API'si sağlar.

## Yönetilen plan ağacı.
var tree: AIPlanTree

## Tamamlanmış düğüm id'leri — ilerleme takibi.
var _completed: PackedStringArray = PackedStringArray()


func _init() -> void:
	tree = AIPlanTree.new()


# ============================================================
# PLAN KURMA
# ============================================================

## Yeni bir plan başlatır — kök GOAL düğümü oluşturur.
## Önceki plan varsa temizlenir.
## Dönen: oluşturulan kök düğüm, veya başarısızsa null.
func start_plan(goal_title: String) -> AIPlanNode:
	tree = AIPlanTree.new()
	_completed = PackedStringArray()

	var root := AIPlanNode.create(AIPlanNode.Level.GOAL, goal_title)
	if tree.add_node(root):
		return root
	return null


## Bir milestone ekler (GOAL'un altına).
func add_milestone(title: String, parent_goal_id: String) -> AIPlanNode:
	return _add_child(AIPlanNode.Level.MILESTONE, title, parent_goal_id)


## Bir task ekler (MILESTONE'un altına).
func add_task(title: String, parent_milestone_id: String, assigned_role: String = "") -> AIPlanNode:
	var node: AIPlanNode = _add_child(AIPlanNode.Level.TASK, title, parent_milestone_id)
	if node != null and not assigned_role.is_empty():
		node.assigned_role = assigned_role
	return node


## Bir action ekler (TASK'ın altına).
func add_action(title: String, parent_task_id: String) -> AIPlanNode:
	return _add_child(AIPlanNode.Level.ACTION, title, parent_task_id)


## Ortak alt-düğüm ekleme yardımcısı.
func _add_child(level: int, title: String, parent_id: String) -> AIPlanNode:
	var parent: AIPlanNode = tree.get_node(parent_id)
	if parent == null:
		push_warning("Planner: parent bulunamadı — %s" % parent_id)
		return null

	var node := AIPlanNode.create(level, title)
	node.parent_id = parent_id
	# Kardeşler arası sıra — parent'ın mevcut child sayısı
	node.order = parent.children_ids.size()

	if tree.add_node(node):
		return node
	return null


## İki düğüm arasında bağımlılık kurar — dependent, dependency'den SONRA gelir.
## Döngü oluşturacak bağımlılık reddedilir (DAG bütünlüğü korunur).
func add_dependency(dependent_id: String, dependency_id: String) -> bool:
	var dependent: AIPlanNode = tree.get_node(dependent_id)
	var dependency: AIPlanNode = tree.get_node(dependency_id)
	if dependent == null or dependency == null:
		push_warning("Planner.add_dependency: düğüm(ler) bulunamadı")
		return false
	if dependent_id == dependency_id:
		push_warning("Planner.add_dependency: düğüm kendine bağımlı olamaz")
		return false
	if dependent.depends_on.has(dependency_id):
		return true  # zaten var

	# Geçici ekle, döngü kontrolü yap, döngü varsa geri al
	dependent.depends_on.append(dependency_id)
	var cycle_check: Dictionary = AIDAGResolver.detect_cycle(tree.all_nodes())
	if cycle_check["has_cycle"]:
		# Geri al — bu bağımlılık döngü yaratıyor
		var idx: int = dependent.depends_on.find(dependency_id)
		if idx >= 0:
			dependent.depends_on.remove_at(idx)
		push_warning(
			"Planner: bağımlılık reddedildi (döngü): %s"
			% " -> ".join(cycle_check["cycle_path"])
		)
		return false
	return true


# ============================================================
# PLAN ÇÖZÜMLEME
# ============================================================

## Planın çalıştırma sırasını döndürür (topolojik sıra).
## Dönen: {ok, order: PackedStringArray, error}
func execution_order() -> Dictionary:
	return AIDAGResolver.topological_sort(tree.all_nodes())


## Şu an başlanabilir düğümleri döndürür (bağımlılıkları tamamlanmış).
func ready_nodes() -> PackedStringArray:
	return AIDAGResolver.ready_nodes(tree.all_nodes(), _completed)


## Sıradaki çalıştırılabilir task'ları döndürür — hazır VE TASK seviyesi.
## Cell pipeline bir sonraki işi buradan alır.
func next_tasks() -> Array:
	var ready: PackedStringArray = ready_nodes()
	var tasks: Array = []
	for id in ready:
		var node: AIPlanNode = tree.get_node(id)
		if node != null and node.level == AIPlanNode.Level.TASK:
			tasks.append(node)
	return tasks


# ============================================================
# İLERLEME
# ============================================================

## Bir düğümü tamamlanmış olarak işaretler.
func mark_completed(node_id: String) -> bool:
	var node: AIPlanNode = tree.get_node(node_id)
	if node == null:
		return false
	node.is_completed = true
	if not _completed.has(node_id):
		_completed.append(node_id)
	return true


## Planın tamamlanma yüzdesi (0.0 - 1.0).
func progress() -> float:
	return tree.progress()


## Plan tamamen bitti mi?
func is_complete() -> bool:
	return tree.is_complete()


# ============================================================
# DOĞRULAMA
# ============================================================

## Planın bütünlüğünü tam olarak doğrular.
## Hem ağaç bütünlüğü (PlanTree) hem bağımlılık bütünlüğü (DAG) kontrol edilir.
## Dönen: AIValidationResult.
func validate_plan() -> AIValidationResult:
	var result := AIValidationResult.new()

	# 1. Ağaç bütünlüğü
	var tree_result: AIValidationResult = tree.validate_tree()
	result.merge(tree_result)

	# 2. Eksik bağımlılık referansları
	var missing: Array = AIDAGResolver.find_missing_dependencies(tree.all_nodes())
	for m in missing:
		result.add_error(
			"Düğüm '%s' var olmayan bağımlılığa işaret ediyor: %s"
			% [m["node"], m["missing_dep"]]
		)

	# 3. Döngü kontrolü
	var cycle_check: Dictionary = AIDAGResolver.detect_cycle(tree.all_nodes())
	if cycle_check["has_cycle"]:
		result.add_error(
			"Planda döngüsel bağımlılık: %s"
			% " -> ".join(cycle_check["cycle_path"])
		)

	return result


## Plan özeti — UI ve debug için.
func summary() -> Dictionary:
	return {
		"total_nodes": tree.node_count(),
		"goals": tree.nodes_at_level(AIPlanNode.Level.GOAL).size(),
		"milestones": tree.nodes_at_level(AIPlanNode.Level.MILESTONE).size(),
		"tasks": tree.nodes_at_level(AIPlanNode.Level.TASK).size(),
		"actions": tree.nodes_at_level(AIPlanNode.Level.ACTION).size(),
		"completed": tree.completed_count(),
		"progress": progress(),
	}
