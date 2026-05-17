@tool
class_name AIDAGResolver
extends RefCounted

## DAG Resolver — bağımlılık grafı çözücü (Layer 3).
##
## Plan düğümleri (AIPlanNode) birbirine bağımlıdır: "mesh oluştur" task'ı
## "sahne kur" task'ından sonra gelmeli. Bu bağımlılıklar bir DAG (Directed
## Acyclic Graph — yönlü çevrimsiz graf) oluşturur.
##
## Bu sınıfın üç görevi:
##   1. Döngü tespiti — A->B->C->A gibi imkansız bağımlılıkları yakala
##   2. Topolojik sıralama — düğümleri "önce yapılacaklar" sırasına diz
##   3. Hazır düğüm tespiti — bağımlılıkları tamamlanmış, başlanabilir düğümler
##
## Mock policy: döngü varsa sahte sıra üretmez — açıkça hata raporlar.


## Düğüm kümesi içinde döngü olup olmadığını tespit eder.
## nodes: id -> AIPlanNode  (her düğümün depends_on listesi vardır)
## Dönen: {has_cycle: bool, cycle_path: PackedStringArray}
## cycle_path döngüyü oluşturan düğüm id'lerini sırayla içerir.
static func detect_cycle(nodes: Dictionary) -> Dictionary:
	# DFS tabanlı döngü tespiti — üç renk: beyaz(0)=ziyaret edilmedi,
	# gri(1)=işleniyor, siyah(2)=tamamlandı. Gri düğüme tekrar gelmek = döngü.
	var color: Dictionary = {}
	for id in nodes:
		color[id] = 0

	var cycle_path: PackedStringArray = PackedStringArray()

	for start_id in nodes:
		if color[start_id] == 0:
			var path: PackedStringArray = PackedStringArray()
			if _dfs_cycle(start_id, nodes, color, path, cycle_path):
				return {"has_cycle": true, "cycle_path": cycle_path}

	return {"has_cycle": false, "cycle_path": PackedStringArray()}


## DFS yardımcısı — döngü bulursa true döner, cycle_path'i doldurur.
static func _dfs_cycle(
	node_id: String,
	nodes: Dictionary,
	color: Dictionary,
	path: PackedStringArray,
	out_cycle: PackedStringArray
) -> bool:
	color[node_id] = 1  # gri — işleniyor
	path.append(node_id)

	var node: AIPlanNode = nodes[node_id]
	for dep_id in node.depends_on:
		# Bağımlılık grafta yoksa atla (eksik referans — ayrı kontrol)
		if not nodes.has(dep_id):
			continue
		if color[dep_id] == 1:
			# Gri düğüme geri geldik — DÖNGÜ
			out_cycle.clear()
			var cycle_start: int = path.find(dep_id)
			if cycle_start >= 0:
				for i in range(cycle_start, path.size()):
					out_cycle.append(path[i])
				out_cycle.append(dep_id)  # döngüyü kapat
			return true
		if color[dep_id] == 0:
			if _dfs_cycle(dep_id, nodes, color, path, out_cycle):
				return true

	color[node_id] = 2  # siyah — tamamlandı
	path.remove_at(path.size() - 1)
	return false


## Düğümleri topolojik sıraya dizer — bağımlılığı olmayanlar önce.
## Dönen: {ok: bool, order: PackedStringArray, error: String}
## Döngü varsa ok=false, sıra üretilmez (mock policy: sahte sıra yok).
static func topological_sort(nodes: Dictionary) -> Dictionary:
	# Önce döngü kontrolü — döngü varsa sıralama anlamsız
	var cycle_check: Dictionary = detect_cycle(nodes)
	if cycle_check["has_cycle"]:
		var path: PackedStringArray = cycle_check["cycle_path"]
		return {
			"ok": false,
			"order": PackedStringArray(),
			"error": "Döngüsel bağımlılık: %s" % " -> ".join(path),
		}

	# Kahn algoritması — in-degree (gelen bağımlılık sayısı) tabanlı
	var in_degree: Dictionary = {}
	for id in nodes:
		in_degree[id] = 0
	# Her düğümün depends_on'u, o düğüme gelen kenar sayısını artırır
	for id in nodes:
		var node: AIPlanNode = nodes[id]
		for dep_id in node.depends_on:
			if nodes.has(dep_id):
				in_degree[id] = int(in_degree[id]) + 1

	# in-degree 0 olanlar (bağımlılığı tamamlanmış) kuyruğa
	var queue: Array = []
	for id in nodes:
		if in_degree[id] == 0:
			queue.append(id)
	# Deterministik sıra için kuyruğu sırala
	queue.sort()

	var order: PackedStringArray = PackedStringArray()
	while not queue.is_empty():
		var current: String = queue.pop_front()
		order.append(current)
		# current'a bağımlı olan düğümlerin in-degree'sini azalt
		var newly_ready: Array = []
		for id in nodes:
			var node: AIPlanNode = nodes[id]
			if node.depends_on.has(current):
				in_degree[id] = int(in_degree[id]) - 1
				if in_degree[id] == 0:
					newly_ready.append(id)
		newly_ready.sort()
		for id in newly_ready:
			queue.append(id)

	# Tüm düğümler sıraya girdiyse başarılı
	if order.size() != nodes.size():
		return {
			"ok": false,
			"order": PackedStringArray(),
			"error": "Topolojik sıralama eksik — gizli döngü olabilir",
		}

	return {"ok": true, "order": order, "error": ""}


## Şu an başlanabilir (hazır) düğümleri döndürür.
## Bir düğüm hazırdır: tamamlanmamış VE tüm bağımlılıkları tamamlanmış.
## completed_ids: tamamlanmış düğüm id'leri kümesi.
static func ready_nodes(nodes: Dictionary, completed_ids: PackedStringArray) -> PackedStringArray:
	var completed_set: Dictionary = {}
	for cid in completed_ids:
		completed_set[cid] = true

	var ready: PackedStringArray = PackedStringArray()
	for id in nodes:
		var node: AIPlanNode = nodes[id]
		# Zaten tamamlanmış veya işaretli — hazır değil
		if completed_set.has(id) or node.is_completed:
			continue
		# Tüm bağımlılıkları tamamlanmış mı
		var all_deps_done: bool = true
		for dep_id in node.depends_on:
			if not completed_set.has(dep_id):
				all_deps_done = false
				break
		if all_deps_done:
			ready.append(id)

	ready.sort()  # deterministik
	return ready


## Bağımlılık referanslarının geçerliliğini kontrol eder.
## Bir düğüm var olmayan bir düğüme bağımlıysa, bu eksik referanstır.
## Dönen: eksik referansların listesi [{node, missing_dep}]
static func find_missing_dependencies(nodes: Dictionary) -> Array:
	var missing: Array = []
	for id in nodes:
		var node: AIPlanNode = nodes[id]
		for dep_id in node.depends_on:
			if not nodes.has(dep_id):
				missing.append({"node": id, "missing_dep": dep_id})
	return missing


## Bir düğümün (geçişli) tüm bağımlılıklarını döndürür.
## Yani A->B->C ise A'nın tüm bağımlılıkları [B, C].
static func all_dependencies(node_id: String, nodes: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var visited: Dictionary = {}
	_collect_deps(node_id, nodes, visited, result)
	return result


static func _collect_deps(
	node_id: String, nodes: Dictionary, visited: Dictionary, out: PackedStringArray
) -> void:
	if visited.has(node_id) or not nodes.has(node_id):
		return
	visited[node_id] = true
	var node: AIPlanNode = nodes[node_id]
	for dep_id in node.depends_on:
		if not out.has(dep_id):
			out.append(dep_id)
		_collect_deps(dep_id, nodes, visited, out)
