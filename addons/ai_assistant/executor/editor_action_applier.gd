@tool
class_name AIEditorActionApplier
extends RefCounted

## Canlı Godot editörü mutasyon köprüsü.
##
## Bütün sahne değişiklikleri Godot'un EditorUndoRedoManager geçmişine
## kaydedilir. Model doğrudan sahne metni yazmaz. İstenen sahne ile
## editörde açık sahne eşleşmiyorsa işlem açık biçimde reddedilir.


func _result(
	ok: bool,
	available: bool,
	reason: String,
	undoable: bool = false,
	scene_path: String = ""
) -> Dictionary:
	return {
		"ok": ok,
		"available": available,
		"reason": reason,
		"undoable": undoable,
		"scene_path": scene_path,
	}


func _editor_available() -> bool:
	# EditorInterface, Godot 4.6'da Engine singleton listesinde aranan
	# bir extension singleton değildir; doğrudan global editör API'sidir.
	return Engine.is_editor_hint()


func _scene_context(plan: Dictionary) -> Dictionary:
	if not _editor_available():
		return {
			"ok": false,
			"available": false,
			"reason": "Godot editör bağlamı yok",
		}

	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {
			"ok": false,
			"available": true,
			"reason": "Düzenlenen açık sahne yok",
		}

	var expected: String = str(plan.get("scene_path", "")).strip_edges()
	var actual: String = root.scene_file_path.strip_edges()
	if expected == AISceneActionPlanner.ACTIVE_EDITED_SCENE_TARGET:
		# '@edited_scene' serbest hedef değildir. Kullanıcının editörde
		# açık tuttuğu sahnenin gerçek ve kayıtlı yolu burada bağlanır;
		# kaydedilmemiş sahnede mutasyon yapılmaz.
		if actual.is_empty():
			return {
				"ok": false,
				"available": true,
				"reason": "Aktif sahne henüz kaydedilmemiş; önce .tscn olarak kaydet",
			}
		expected = actual
	elif expected.is_empty():
		return {
			"ok": false,
			"available": true,
			"reason": "Editör mutasyonu için hedef sahne belirtilmedi",
		}

	if actual.is_empty():
		return {
			"ok": false,
			"available": true,
			"reason": "Açık sahne henüz kaydedilmemiş; hedef: %s" % expected,
		}
	if actual.simplify_path() != expected.simplify_path():
		return {
			"ok": false,
			"available": true,
			"reason": "Yanlış sahne açık. Beklenen: %s, açık: %s" % [
				expected, actual,
			],
		}

	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	if undo_redo == null:
		return {
			"ok": false,
			"available": true,
			"reason": "EditorUndoRedoManager alınamadı",
		}

	return {
		"ok": true,
		"available": true,
		"reason": "",
		"root": root,
		"undo_redo": undo_redo,
		"scene_path": actual,
	}


func _resolve(root: Node, node_path: String) -> Node:
	if node_path == ".":
		return root
	return root.get_node_or_null(NodePath(node_path))


func _save_active_scene() -> Dictionary:
	var error: int = EditorInterface.save_scene()
	if error != OK:
		return {
			"ok": false,
			"reason": "Değişiklik uygulandı ancak sahne kaydedilemedi: %d" % error,
		}
	return {"ok": true, "reason": ""}


func apply_node_add(plan: Dictionary) -> Dictionary:
	var context: Dictionary = _scene_context(plan)
	if not bool(context["ok"]):
		return _result(
			false,
			bool(context["available"]),
			str(context["reason"])
		)

	var root: Node = context["root"]
	var parent: Node = _resolve(root, str(plan["parent"]))
	if parent == null:
		return _result(false, true, "Ebeveyn bulunamadı: %s" % plan["parent"])

	var node_name: String = str(plan["node_name"])
	if parent.get_node_or_null(NodePath(node_name)) != null:
		return _result(false, true, "Aynı adlı child zaten var: %s" % node_name)

	var node_type: String = str(plan["node_type"])
	if not ClassDB.can_instantiate(node_type):
		return _result(false, true, "'%s' örneklenemez" % node_type)
	var instance: Object = ClassDB.instantiate(node_type)
	if not (instance is Node):
		return _result(false, true, "'%s' Node üretmedi" % node_type)

	var node: Node = instance
	node.name = node_name
	var undo_redo: EditorUndoRedoManager = context["undo_redo"]
	undo_redo.create_action(
		"AI: Node ekle — %s" % node_name,
		UndoRedo.MERGE_DISABLE,
		root
	)
	undo_redo.add_do_method(parent, &"add_child", node)
	undo_redo.add_do_property(node, &"owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_property(node, &"owner", null)
	undo_redo.add_undo_method(parent, &"remove_child", node)
	undo_redo.commit_action()

	var saved: Dictionary = _save_active_scene()
	if not bool(saved["ok"]):
		return _result(
			false, true, str(saved["reason"]), true, str(context["scene_path"])
		)
	return _result(
		true,
		true,
		"Node eklendi: %s (%s)" % [node_name, node_type],
		true,
		str(context["scene_path"])
	)


func apply_node_remove(plan: Dictionary) -> Dictionary:
	var context: Dictionary = _scene_context(plan)
	if not bool(context["ok"]):
		return _result(
			false,
			bool(context["available"]),
			str(context["reason"])
		)

	var root: Node = context["root"]
	var node: Node = _resolve(root, str(plan["node_path"]))
	if node == null:
		return _result(false, true, "Node bulunamadı: %s" % plan["node_path"])
	if node == root:
		return _result(false, true, "Sahne kökü silinemez")
	var parent: Node = node.get_parent()
	if parent == null:
		return _result(false, true, "Node ebeveyni bulunamadı")

	var old_index: int = node.get_index()
	var old_owner: Node = node.owner
	var undo_redo: EditorUndoRedoManager = context["undo_redo"]
	undo_redo.create_action(
		"AI: Node sil — %s" % node.name,
		UndoRedo.MERGE_DISABLE,
		root
	)
	undo_redo.add_do_property(node, &"owner", null)
	undo_redo.add_do_method(parent, &"remove_child", node)
	undo_redo.add_undo_method(parent, &"add_child", node)
	undo_redo.add_undo_method(parent, &"move_child", node, old_index)
	undo_redo.add_undo_property(node, &"owner", old_owner)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()

	var saved: Dictionary = _save_active_scene()
	if not bool(saved["ok"]):
		return _result(
			false, true, str(saved["reason"]), true, str(context["scene_path"])
		)
	return _result(
		true,
		true,
		"Node silindi: %s" % str(plan["node_path"]),
		true,
		str(context["scene_path"])
	)


func apply_property_set(plan: Dictionary) -> Dictionary:
	var context: Dictionary = _scene_context(plan)
	if not bool(context["ok"]):
		return _result(
			false,
			bool(context["available"]),
			str(context["reason"])
		)

	var root: Node = context["root"]
	var node: Node = _resolve(root, str(plan["node_path"]))
	if node == null:
		return _result(false, true, "Node bulunamadı: %s" % plan["node_path"])

	var property_name: String = str(plan["property"])
	var info: Dictionary = _property_info(node, property_name)
	if info.is_empty():
		return _result(false, true, "Property bulunamadı: %s" % property_name)
	if (int(info.get("usage", 0)) & PROPERTY_USAGE_READ_ONLY) != 0:
		return _result(false, true, "Property salt-okunur: %s" % property_name)

	var converted: Dictionary = _coerce_property_value(info, plan["value"])
	if not bool(converted["ok"]):
		return _result(false, true, str(converted["reason"]))
	var previous: Variant = node.get(property_name)
	var next_value: Variant = converted["value"]

	var undo_redo: EditorUndoRedoManager = context["undo_redo"]
	undo_redo.create_action(
		"AI: Property değiştir — %s.%s" % [node.name, property_name],
		UndoRedo.MERGE_DISABLE,
		root
	)
	undo_redo.add_do_property(node, StringName(property_name), next_value)
	undo_redo.add_undo_property(node, StringName(property_name), previous)
	undo_redo.commit_action()

	var saved: Dictionary = _save_active_scene()
	if not bool(saved["ok"]):
		return _result(
			false, true, str(saved["reason"]), true, str(context["scene_path"])
		)
	return _result(
		true,
		true,
		"Property atandı: %s.%s" % [str(plan["node_path"]), property_name],
		true,
		str(context["scene_path"])
	)


func apply_script_attach(plan: Dictionary) -> Dictionary:
	var context: Dictionary = _scene_context(plan)
	if not bool(context["ok"]):
		return _result(
			false,
			bool(context["available"]),
			str(context["reason"])
		)

	var root: Node = context["root"]
	var node: Node = _resolve(root, str(plan["node_path"]))
	if node == null:
		return _result(false, true, "Node bulunamadı: %s" % plan["node_path"])

	var script_path: String = str(plan["script_path"])
	if not ResourceLoader.exists(script_path, "Script"):
		return _result(false, true, "Script yok: %s" % script_path)
	var resource: Resource = ResourceLoader.load(script_path, "Script")
	if not (resource is Script):
		return _result(false, true, "Geçerli Script değil: %s" % script_path)
	var script: Script = resource
	if not script.can_instantiate():
		return _result(false, true, "Script derlenemiyor: %s" % script_path)

	var previous: Variant = node.get_script()
	var undo_redo: EditorUndoRedoManager = context["undo_redo"]
	undo_redo.create_action(
		"AI: Script bağla — %s" % node.name,
		UndoRedo.MERGE_DISABLE,
		root
	)
	undo_redo.add_do_method(node, &"set_script", script)
	undo_redo.add_undo_method(node, &"set_script", previous)
	undo_redo.commit_action()

	var saved: Dictionary = _save_active_scene()
	if not bool(saved["ok"]):
		return _result(
			false, true, str(saved["reason"]), true, str(context["scene_path"])
		)
	return _result(
		true,
		true,
		"Script bağlandı: %s → %s" % [str(plan["node_path"]), script_path],
		true,
		str(context["scene_path"])
	)


func apply_project_setting(plan: Dictionary) -> Dictionary:
	if not _editor_available():
		return _result(false, false, "Godot editör bağlamı yok")
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	if undo_redo == null:
		return _result(false, true, "EditorUndoRedoManager alınamadı")

	var key: String = str(plan["key"])
	var existed: bool = ProjectSettings.has_setting(key)
	var previous: Variant = ProjectSettings.get_setting(key) if existed else null
	undo_redo.create_action(
		"AI: Proje ayarı — %s" % key,
		UndoRedo.MERGE_DISABLE,
		ProjectSettings
	)
	undo_redo.add_do_method(ProjectSettings, &"set_setting", key, plan["value"])
	undo_redo.add_do_method(ProjectSettings, &"save")
	undo_redo.add_undo_method(ProjectSettings, &"set_setting", key, previous)
	undo_redo.add_undo_method(ProjectSettings, &"save")
	undo_redo.commit_action()

	var error: int = ProjectSettings.save()
	if error != OK:
		return _result(
			false,
			true,
			"Ayar uygulandı fakat project.godot kaydedilemedi: %d" % error,
			true
		)
	return _result(true, true, "Proje ayarı yazıldı: %s" % key, true)


func _property_info(node: Node, property_name: String) -> Dictionary:
	for entry in node.get_property_list():
		if str(entry.get("name", "")) == property_name:
			return entry
	return {}


func _coerce_property_value(info: Dictionary, value: Variant) -> Dictionary:
	var expected_type: int = int(info.get("type", TYPE_NIL))
	var actual_type: int = typeof(value)
	if expected_type == TYPE_NIL or expected_type == actual_type:
		return {"ok": true, "reason": "", "value": value}
	if value == null and expected_type == TYPE_OBJECT:
		return {"ok": true, "reason": "", "value": null}
	if expected_type == TYPE_FLOAT and actual_type == TYPE_INT:
		return {"ok": true, "reason": "", "value": float(value)}
	if expected_type == TYPE_INT and actual_type == TYPE_FLOAT:
		var number: float = float(value)
		if is_equal_approx(number, round(number)):
			return {"ok": true, "reason": "", "value": int(number)}
	if expected_type == TYPE_STRING_NAME and actual_type == TYPE_STRING:
		return {"ok": true, "reason": "", "value": StringName(value)}
	if expected_type == TYPE_NODE_PATH and actual_type == TYPE_STRING:
		return {"ok": true, "reason": "", "value": NodePath(value)}
	return {
		"ok": false,
		"reason": "Property tip uyuşmazlığı. Beklenen=%d, gelen=%d" % [
			expected_type, actual_type,
		],
		"value": null,
	}
