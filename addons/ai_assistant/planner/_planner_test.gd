@tool
class_name AIPlannerTest
extends RefCounted

## Phase 3 / Layer 3 — Planner Self-Test
##
## Sıkı testler: DAG döngü tespiti, topolojik sıralama, ağaç bütünlüğü,
## bağımlılık döngü reddi, ilerleme takibi. Edge case'ler dahil.
##
## Mock policy: testler GERÇEK doğrulama yapar.


## Tüm planner testlerini çalıştırır.
static func run_all() -> Array:
	var results: Array = []

	# DAG Resolver
	results.append(_b("Planner: DAG", _test_dag_no_cycle()))
	results.append(_b("Planner: DAG", _test_dag_cycle_detect()))
	results.append(_b("Planner: DAG", _test_dag_self_loop()))
	results.append(_b("Planner: DAG", _test_dag_topo_sort()))
	results.append(_b("Planner: DAG", _test_dag_topo_cycle_fails()))
	results.append(_b("Planner: DAG", _test_dag_ready_nodes()))
	results.append(_b("Planner: DAG", _test_dag_missing_deps()))
	results.append(_b("Planner: DAG", _test_dag_transitive_deps()))
	results.append(_b("Planner: DAG", _test_dag_empty()))

	# Plan Tree
	results.append(_b("Planner: Tree", _test_tree_root()))
	results.append(_b("Planner: Tree", _test_tree_single_root()))
	results.append(_b("Planner: Tree", _test_tree_hierarchy()))
	results.append(_b("Planner: Tree", _test_tree_orphan_parent()))
	results.append(_b("Planner: Tree", _test_tree_leaf_nodes()))
	results.append(_b("Planner: Tree", _test_tree_path_depth()))
	results.append(_b("Planner: Tree", _test_tree_progress()))
	results.append(_b("Planner: Tree", _test_tree_validate()))

	# Hierarchical Planner
	results.append(_b("Planner: Engine", _test_planner_build()))
	results.append(_b("Planner: Engine", _test_planner_dependency()))
	results.append(_b("Planner: Engine", _test_planner_cycle_reject()))
	results.append(_b("Planner: Engine", _test_planner_execution_order()))
	results.append(_b("Planner: Engine", _test_planner_next_tasks()))
	results.append(_b("Planner: Engine", _test_planner_progress()))
	results.append(_b("Planner: Engine", _test_planner_validate()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(test_name: String) -> Dictionary:
	return {"ok": true, "name": test_name, "reason": ""}


static func _fail(test_name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": test_name, "reason": reason}


## Test yardımcısı — hızlı plan düğümü oluşturur.
static func _node(id: String, level: int, deps: Array = []) -> AIPlanNode:
	var n := AIPlanNode.create(level, "Test " + id)
	n.id = id
	n.depends_on = PackedStringArray(deps)
	return n


# ============================================================
# DAG RESOLVER
# ============================================================

static func _test_dag_no_cycle() -> Dictionary:
	var name := "DAG döngüsüz graf tespiti"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["B"]),
		"B": _node("B", AIPlanNode.Level.TASK, ["C"]),
		"C": _node("C", AIPlanNode.Level.TASK, []),
	}
	var check: Dictionary = AIDAGResolver.detect_cycle(nodes)
	if check["has_cycle"]:
		return _fail(name, "döngüsüz graf döngülü göründü")
	return _ok(name)


static func _test_dag_cycle_detect() -> Dictionary:
	var name := "DAG döngü tespiti"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["B"]),
		"B": _node("B", AIPlanNode.Level.TASK, ["C"]),
		"C": _node("C", AIPlanNode.Level.TASK, ["A"]),
	}
	var check: Dictionary = AIDAGResolver.detect_cycle(nodes)
	if not check["has_cycle"]:
		return _fail(name, "döngü tespit edilmedi")
	if (check["cycle_path"] as PackedStringArray).is_empty():
		return _fail(name, "döngü yolu boş")
	return _ok(name)


static func _test_dag_self_loop() -> Dictionary:
	var name := "DAG self-loop döngü sayılır"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["A"]),
	}
	var check: Dictionary = AIDAGResolver.detect_cycle(nodes)
	if not check["has_cycle"]:
		return _fail(name, "kendine bağımlılık döngü sayılmalı")
	return _ok(name)


static func _test_dag_topo_sort() -> Dictionary:
	var name := "DAG topolojik sıralama"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["B"]),
		"B": _node("B", AIPlanNode.Level.TASK, ["C"]),
		"C": _node("C", AIPlanNode.Level.TASK, []),
	}
	var result: Dictionary = AIDAGResolver.topological_sort(nodes)
	if not result["ok"]:
		return _fail(name, "sıralama başarısız: %s" % result["error"])
	var order: PackedStringArray = result["order"]
	# C bağımsız — ilk; A en bağımlı — son
	if order[0] != "C":
		return _fail(name, "C ilk gelmeli (bağımsız): %s" % str(order))
	if order[order.size() - 1] != "A":
		return _fail(name, "A son gelmeli (en bağımlı)")
	return _ok(name)


static func _test_dag_topo_cycle_fails() -> Dictionary:
	var name := "DAG döngülü graf sıralanamaz"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["B"]),
		"B": _node("B", AIPlanNode.Level.TASK, ["A"]),
	}
	var result: Dictionary = AIDAGResolver.topological_sort(nodes)
	if result["ok"]:
		return _fail(name, "döngülü graf sıralanmamalı")
	if (result["error"] as String).is_empty():
		return _fail(name, "hata mesajı boş")
	return _ok(name)


static func _test_dag_ready_nodes() -> Dictionary:
	var name := "DAG hazır düğüm tespiti"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["B"]),
		"B": _node("B", AIPlanNode.Level.TASK, []),
	}
	# Hiçbiri tamamlanmamış — sadece B hazır (bağımsız)
	var ready1: PackedStringArray = AIDAGResolver.ready_nodes(nodes, PackedStringArray())
	if not (ready1.has("B") and not ready1.has("A")):
		return _fail(name, "başlangıçta sadece B hazır olmalı")
	# B tamamlanınca A hazır
	var ready2: PackedStringArray = AIDAGResolver.ready_nodes(
		nodes, PackedStringArray(["B"])
	)
	if not ready2.has("A"):
		return _fail(name, "B bitince A hazır olmalı")
	return _ok(name)


static func _test_dag_missing_deps() -> Dictionary:
	var name := "DAG eksik bağımlılık tespiti"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["GHOST"]),
	}
	var missing: Array = AIDAGResolver.find_missing_dependencies(nodes)
	if missing.size() != 1:
		return _fail(name, "1 eksik bağımlılık beklenir")
	if missing[0]["missing_dep"] != "GHOST":
		return _fail(name, "eksik bağımlılık 'GHOST' olmalı")
	return _ok(name)


static func _test_dag_transitive_deps() -> Dictionary:
	var name := "DAG geçişli bağımlılık"
	var nodes: Dictionary = {
		"A": _node("A", AIPlanNode.Level.TASK, ["B"]),
		"B": _node("B", AIPlanNode.Level.TASK, ["C"]),
		"C": _node("C", AIPlanNode.Level.TASK, []),
	}
	var deps: PackedStringArray = AIDAGResolver.all_dependencies("A", nodes)
	if not (deps.has("B") and deps.has("C")):
		return _fail(name, "A'nın geçişli bağımlılıkları B ve C olmalı")
	return _ok(name)


static func _test_dag_empty() -> Dictionary:
	var name := "DAG boş graf"
	var result: Dictionary = AIDAGResolver.topological_sort({})
	if not result["ok"]:
		return _fail(name, "boş graf geçerli olmalı")
	if not (result["order"] as PackedStringArray).is_empty():
		return _fail(name, "boş graf boş sıra vermeli")
	return _ok(name)


# ============================================================
# PLAN TREE
# ============================================================

static func _test_tree_root() -> Dictionary:
	var name := "PlanTree kök ekleme"
	var tree := AIPlanTree.new()
	var root := AIPlanNode.create(AIPlanNode.Level.GOAL, "Oyun yap")
	if not tree.add_node(root):
		return _fail(name, "kök GOAL eklenemedi")
	if tree.root() == null:
		return _fail(name, "root() null döndü")
	if tree.root().id != root.id:
		return _fail(name, "yanlış kök")
	return _ok(name)


static func _test_tree_single_root() -> Dictionary:
	var name := "PlanTree tek kök kuralı"
	var tree := AIPlanTree.new()
	tree.add_node(AIPlanNode.create(AIPlanNode.Level.GOAL, "Birinci"))
	# İkinci GOAL reddedilmeli
	if tree.add_node(AIPlanNode.create(AIPlanNode.Level.GOAL, "İkinci")):
		return _fail(name, "ikinci GOAL kabul edildi — tek kök olmalı")
	return _ok(name)


static func _test_tree_hierarchy() -> Dictionary:
	var name := "PlanTree hiyerarşi kurma"
	var tree := AIPlanTree.new()
	var g := AIPlanNode.create(AIPlanNode.Level.GOAL, "G")
	tree.add_node(g)
	var m := AIPlanNode.create(AIPlanNode.Level.MILESTONE, "M")
	m.parent_id = g.id
	if not tree.add_node(m):
		return _fail(name, "milestone eklenemedi")
	# Parent'ın children listesinde m olmalı
	var children: Array = tree.children_of(g.id)
	if children.size() != 1:
		return _fail(name, "GOAL'un 1 child'ı olmalı")
	# parent_of doğru çalışmalı
	if tree.parent_of(m.id) == null or tree.parent_of(m.id).id != g.id:
		return _fail(name, "parent_of yanlış")
	return _ok(name)


static func _test_tree_orphan_parent() -> Dictionary:
	var name := "PlanTree var olmayan parent reddi"
	var tree := AIPlanTree.new()
	tree.add_node(AIPlanNode.create(AIPlanNode.Level.GOAL, "G"))
	var m := AIPlanNode.create(AIPlanNode.Level.MILESTONE, "M")
	m.parent_id = "VAR_OLMAYAN"
	if tree.add_node(m):
		return _fail(name, "var olmayan parent'lı düğüm kabul edildi")
	return _ok(name)


static func _test_tree_leaf_nodes() -> Dictionary:
	var name := "PlanTree yaprak düğüm tespiti"
	var tree := AIPlanTree.new()
	var g := AIPlanNode.create(AIPlanNode.Level.GOAL, "G")
	tree.add_node(g)
	var m := AIPlanNode.create(AIPlanNode.Level.MILESTONE, "M")
	m.parent_id = g.id
	tree.add_node(m)
	# m yaprak (child'ı yok), g yaprak değil
	var leaves: Array = tree.leaf_nodes()
	var leaf_ids: Array = []
	for l in leaves:
		leaf_ids.append(l.id)
	if not leaf_ids.has(m.id):
		return _fail(name, "M yaprak olmalı")
	if leaf_ids.has(g.id):
		return _fail(name, "G yaprak olmamalı (child'ı var)")
	return _ok(name)


static func _test_tree_path_depth() -> Dictionary:
	var name := "PlanTree yol ve derinlik"
	var tree := AIPlanTree.new()
	var g := AIPlanNode.create(AIPlanNode.Level.GOAL, "G")
	tree.add_node(g)
	var m := AIPlanNode.create(AIPlanNode.Level.MILESTONE, "M")
	m.parent_id = g.id
	tree.add_node(m)
	var t := AIPlanNode.create(AIPlanNode.Level.TASK, "T")
	t.parent_id = m.id
	tree.add_node(t)
	# T'nin derinliği 2 (G=0, M=1, T=2)
	if tree.depth_of(t.id) != 2:
		return _fail(name, "T derinliği 2 olmalı: %d" % tree.depth_of(t.id))
	# Yol G -> M -> T
	var path: Array = tree.path_to(t.id)
	if path.size() != 3:
		return _fail(name, "yol 3 düğüm içermeli")
	if path[0].id != g.id:
		return _fail(name, "yol kökten başlamalı")
	return _ok(name)


static func _test_tree_progress() -> Dictionary:
	var name := "PlanTree ilerleme hesabı"
	var tree := AIPlanTree.new()
	var g := AIPlanNode.create(AIPlanNode.Level.GOAL, "G")
	tree.add_node(g)
	var m := AIPlanNode.create(AIPlanNode.Level.MILESTONE, "M")
	m.parent_id = g.id
	tree.add_node(m)
	# 0/2 tamamlandı
	if tree.progress() != 0.0:
		return _fail(name, "başlangıçta ilerleme 0 olmalı")
	g.is_completed = true
	# 1/2
	if abs(tree.progress() - 0.5) > 0.0001:
		return _fail(name, "1/2 ilerleme 0.5 olmalı")
	m.is_completed = true
	if not tree.is_complete():
		return _fail(name, "hepsi bitince is_complete true olmalı")
	return _ok(name)


static func _test_tree_validate() -> Dictionary:
	var name := "PlanTree bütünlük doğrulama"
	var tree := AIPlanTree.new()
	var g := AIPlanNode.create(AIPlanNode.Level.GOAL, "G")
	tree.add_node(g)
	var m := AIPlanNode.create(AIPlanNode.Level.MILESTONE, "M")
	m.parent_id = g.id
	tree.add_node(m)
	# Geçerli ağaç
	var result: AIValidationResult = tree.validate_tree()
	if not result.ok:
		return _fail(name, "geçerli ağaç invalid çıktı: %s" % result.summary())
	return _ok(name)


# ============================================================
# HIERARCHICAL PLANNER
# ============================================================

static func _test_planner_build() -> Dictionary:
	var name := "Planner plan kurma"
	var planner := AIHierarchicalPlanner.new()
	var goal: AIPlanNode = planner.start_plan("FPS oyunu yap")
	if goal == null:
		return _fail(name, "plan başlatılamadı")
	var ms: AIPlanNode = planner.add_milestone("Karakter sistemi", goal.id)
	if ms == null:
		return _fail(name, "milestone eklenemedi")
	var task: AIPlanNode = planner.add_task("Mesh oluştur", ms.id, "SceneEngineer")
	if task == null:
		return _fail(name, "task eklenemedi")
	if task.assigned_role != "SceneEngineer":
		return _fail(name, "task rolü atanmadı")
	if planner.tree.node_count() != 3:
		return _fail(name, "3 düğüm beklenir")
	return _ok(name)


static func _test_planner_dependency() -> Dictionary:
	var name := "Planner bağımlılık kurma"
	var planner := AIHierarchicalPlanner.new()
	var g: AIPlanNode = planner.start_plan("Test")
	var m: AIPlanNode = planner.add_milestone("M", g.id)
	var t1: AIPlanNode = planner.add_task("T1", m.id)
	var t2: AIPlanNode = planner.add_task("T2", m.id)
	# t2, t1'e bağımlı
	if not planner.add_dependency(t2.id, t1.id):
		return _fail(name, "geçerli bağımlılık kurulamadı")
	if not t2.depends_on.has(t1.id):
		return _fail(name, "bağımlılık kaydedilmedi")
	return _ok(name)


static func _test_planner_cycle_reject() -> Dictionary:
	var name := "Planner döngü yaratan bağımlılık reddi"
	var planner := AIHierarchicalPlanner.new()
	var g: AIPlanNode = planner.start_plan("Test")
	var m: AIPlanNode = planner.add_milestone("M", g.id)
	var t1: AIPlanNode = planner.add_task("T1", m.id)
	var t2: AIPlanNode = planner.add_task("T2", m.id)
	planner.add_dependency(t2.id, t1.id)  # t2 -> t1
	# t1 -> t2 döngü yaratır, reddedilmeli
	if planner.add_dependency(t1.id, t2.id):
		return _fail(name, "döngü yaratan bağımlılık kabul edildi")
	# t1'in depends_on'u temiz kalmalı (geri alındı)
	if t1.depends_on.has(t2.id):
		return _fail(name, "reddedilen bağımlılık geri alınmadı")
	return _ok(name)


static func _test_planner_execution_order() -> Dictionary:
	var name := "Planner çalıştırma sırası"
	var planner := AIHierarchicalPlanner.new()
	var g: AIPlanNode = planner.start_plan("Test")
	var m: AIPlanNode = planner.add_milestone("M", g.id)
	var t1: AIPlanNode = planner.add_task("T1", m.id)
	var t2: AIPlanNode = planner.add_task("T2", m.id)
	planner.add_dependency(t2.id, t1.id)
	var result: Dictionary = planner.execution_order()
	if not result["ok"]:
		return _fail(name, "sıralama başarısız")
	# t1, t2'den önce gelmeli
	var order: PackedStringArray = result["order"]
	var i1: int = order.find(t1.id)
	var i2: int = order.find(t2.id)
	if i1 < 0 or i2 < 0 or i1 > i2:
		return _fail(name, "t1, t2'den önce gelmeli")
	return _ok(name)


static func _test_planner_next_tasks() -> Dictionary:
	var name := "Planner sıradaki task'lar"
	var planner := AIHierarchicalPlanner.new()
	var g: AIPlanNode = planner.start_plan("Test")
	var m: AIPlanNode = planner.add_milestone("M", g.id)
	var t1: AIPlanNode = planner.add_task("T1", m.id)
	var t2: AIPlanNode = planner.add_task("T2", m.id)
	planner.add_dependency(t2.id, t1.id)
	# Başlangıçta sadece t1 hazır task (m,g bağımlılığı yok ama TASK değil)
	var next1: Array = planner.next_tasks()
	var next1_ids: Array = []
	for n in next1:
		next1_ids.append(n.id)
	if not next1_ids.has(t1.id):
		return _fail(name, "t1 sıradaki task olmalı")
	if next1_ids.has(t2.id):
		return _fail(name, "t2 henüz hazır değil (t1 bekliyor)")
	return _ok(name)


static func _test_planner_progress() -> Dictionary:
	var name := "Planner ilerleme takibi"
	var planner := AIHierarchicalPlanner.new()
	var g: AIPlanNode = planner.start_plan("Test")
	var m: AIPlanNode = planner.add_milestone("M", g.id)
	if planner.progress() != 0.0:
		return _fail(name, "başlangıç ilerlemesi 0 olmalı")
	planner.mark_completed(g.id)
	planner.mark_completed(m.id)
	if not planner.is_complete():
		return _fail(name, "hepsi bitince is_complete true olmalı")
	return _ok(name)


static func _test_planner_validate() -> Dictionary:
	var name := "Planner plan doğrulama"
	var planner := AIHierarchicalPlanner.new()
	var g: AIPlanNode = planner.start_plan("Test")
	var m: AIPlanNode = planner.add_milestone("M", g.id)
	planner.add_task("T", m.id)
	# Geçerli plan
	var result: AIValidationResult = planner.validate_plan()
	if not result.ok:
		return _fail(name, "geçerli plan invalid: %s" % result.summary())
	return _ok(name)
