@tool
class_name AIEditorActionApplier
extends RefCounted

## EditorActionApplier — editör mutasyon planlarını GERÇEKTEN uygular.
##
## SceneActionPlanner planı doğrular (saf, test edilebilir). Bu sınıf
## o doğrulanmış planı canlı Godot editörüne uygular: sahneye node
## ekler/siler, property atar, script bağlar, proje ayarı yazar.
##
## DİSİPLİN: EditorInterface yalnız canlı editörde vardır → bu kısım
## headless birim-test edilemez (devir §5.4: "asenkron/editör işi
## senkron test panistine girmez"). Saf karar mantığı planner'da test
## edilir; burası INCE bir köprüdür, kullanıcı Godot'ta göz ile
## doğrular.
##
## Mock policy: editör/sahne yoksa SAHTE başarı YOK — {available:false}
## ile dürüst döner; çağıran (executor) bunu SKIP'e çevirir, "yapıldı"
## demez.

## Bir uygulama sonucu sözleşmesi.
## available=false → editör bağlamı yok (headless/sahne kapalı).
func _r(ok: bool, available: bool, reason: String) -> Dictionary:
	return {"ok": ok, "available": available, "reason": reason}


## Canlı editör arayüzünü güvenli çözer (headless'ta null).
func _editor() -> Object:
	if not Engine.is_editor_hint():
		return null
	if not Engine.has_singleton("EditorInterface"):
		return null
	return Engine.get_singleton("EditorInterface")


## Açık (düzenlenen) sahnenin kökünü verir; yoksa null.
func _scene_root() -> Node:
	var ed: Object = _editor()
	if ed == null:
		return null
	return ed.get_edited_scene_root()


## Sahne içi bir node'u yola göre çözer ("." = kök).
func _resolve(root: Node, node_path: String) -> Node:
	if node_path == "." or node_path.is_empty():
		return root
	return root.get_node_or_null(NodePath(node_path))


## Mutasyon sonrası açık sahneyi diske yazar (kalıcılık).
func _persist(ed: Object) -> void:
	if ed != null and ed.has_method("save_scene"):
		ed.save_scene()


## NODE_ADD: doğrulanmış plana göre sahneye yeni node ekler.
## plan: {node_type, node_name, parent}
func apply_node_add(plan: Dictionary) -> Dictionary:
	var root: Node = _scene_root()
	if root == null:
		return _r(false, false, "Editör/sahne yok — Godot'ta sahne aç")
	var parent: Node = _resolve(root, str(plan["parent"]))
	if parent == null:
		return _r(false, true, "Ebeveyn bulunamadı: %s" % str(plan["parent"]))
	var node_type: String = str(plan["node_type"])
	if not ClassDB.can_instantiate(node_type):
		return _r(false, true, "'%s' örneklenemez" % node_type)
	var inst: Object = ClassDB.instantiate(node_type)
	if not (inst is Node):
		return _r(false, true, "'%s' Node üretmedi" % node_type)
	var node: Node = inst
	node.name = str(plan["node_name"])
	parent.add_child(node)
	node.owner = root
	_persist(_editor())
	return _r(true, true, "Node eklendi: %s (%s)" % [node.name, node_type])


## NODE_REMOVE: sahneden bir node'u siler.
func apply_node_remove(plan: Dictionary) -> Dictionary:
	var root: Node = _scene_root()
	if root == null:
		return _r(false, false, "Editör/sahne yok — Godot'ta sahne aç")
	var node: Node = _resolve(root, str(plan["node_path"]))
	if node == null:
		return _r(false, true, "Node bulunamadı: %s" % str(plan["node_path"]))
	if node == root:
		return _r(false, true, "Sahne kökü silinemez")
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()
	_persist(_editor())
	return _r(true, true, "Node silindi: %s" % str(plan["node_path"]))


## PROPERTY_SET: bir node'un property'sini değiştirir (Inspector).
func apply_property_set(plan: Dictionary) -> Dictionary:
	var root: Node = _scene_root()
	if root == null:
		return _r(false, false, "Editör/sahne yok — Godot'ta sahne aç")
	var node: Node = _resolve(root, str(plan["node_path"]))
	if node == null:
		return _r(false, true, "Node bulunamadı: %s" % str(plan["node_path"]))
	var prop: String = str(plan["property"])
	if not _has_property(node, prop):
		return _r(false, true, "'%s' bu node'da property değil" % prop)
	node.set(prop, plan["value"])
	_persist(_editor())
	return _r(true, true, "Property atandı: %s.%s" % [
		str(plan["node_path"]), prop
	])


## SCRIPT_ATTACH: bir node'a .gd script bağlar.
func apply_script_attach(plan: Dictionary) -> Dictionary:
	var root: Node = _scene_root()
	if root == null:
		return _r(false, false, "Editör/sahne yok — Godot'ta sahne aç")
	var node: Node = _resolve(root, str(plan["node_path"]))
	if node == null:
		return _r(false, true, "Node bulunamadı: %s" % str(plan["node_path"]))
	var script_path: String = str(plan["script_path"])
	if not ResourceLoader.exists(script_path):
		return _r(false, true, "Script yok: %s" % script_path)
	var res: Resource = load(script_path)
	if not (res is Script):
		return _r(false, true, "Geçerli bir Script değil: %s" % script_path)
	node.set_script(res)
	_persist(_editor())
	return _r(true, true, "Script bağlandı: %s → %s" % [
		str(plan["node_path"]), script_path
	])


## PROJECT_SETTING: proje ayarını yazar ve kaydeder (project.godot).
func apply_project_setting(plan: Dictionary) -> Dictionary:
	# ProjectSettings headless'ta da vardır; ama yıkıcı → executor
	# bunu yalnız HITL onayından sonra çağırır.
	var key: String = str(plan["key"])
	ProjectSettings.set_setting(key, plan["value"])
	var err: int = ProjectSettings.save()
	if err != OK:
		return _r(false, true, "ProjectSettings.save hatası: %d" % err)
	return _r(true, true, "Proje ayarı yazıldı: %s" % key)


# ============================================================
# DAHİLİ
# ============================================================

## Node'da gerçek bir property var mı (uydurma ada atama yapma).
func _has_property(node: Node, prop: String) -> bool:
	for entry in node.get_property_list():
		if str(entry.get("name", "")) == prop:
			return true
	return false
