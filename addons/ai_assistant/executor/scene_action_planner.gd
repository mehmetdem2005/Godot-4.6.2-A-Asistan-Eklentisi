@tool
class_name AISceneActionPlanner
extends RefCounted

## SceneActionPlanner — editör mutasyon işlemlerinin saf doğrulayıcısı.
##
## Bu sınıf editöre dokunmaz. Modelden gelen serbest veriyi, canlı
## editör köprüsünün güvenle uygulayabileceği dar ve doğrulanmış bir
## plana çevirir. Geçersiz girişlerde işlem yapılmaz; açık hata döner.

const BAD_NAME_CHARS: Array[String] = ["/", ":", "@", "\"", "%"]
const FORBIDDEN_PROJECT_SETTINGS: Array[String] = [
	"editor_plugins/enabled",
	"application/config/project_settings_override",
	"application/run/disable_stdout",
	"application/run/disable_stderr",
]


## NODE_ADD planı: yeni node tipi, ad, ebeveyn ve isteğe bağlı hedef
## sahne yolunu doğrular.
func plan_node_add(params: Dictionary) -> Dictionary:
	var node_type: String = str(params.get("node_type", "")).strip_edges()
	var node_name: String = str(params.get("node_name", "")).strip_edges()
	var parent: String = str(params.get("parent", ".")).strip_edges()
	if parent.is_empty():
		parent = "."

	var scene: Dictionary = _validate_scene_path(params)
	if not bool(scene["ok"]):
		return scene
	if node_type.is_empty():
		return _no("NODE_ADD: 'node_type' boş")
	if not ClassDB.class_exists(node_type):
		return _no("NODE_ADD: '%s' geçerli bir Godot sınıfı değil" % node_type)
	if not ClassDB.is_parent_class(node_type, "Node"):
		return _no("NODE_ADD: '%s' bir Node türevi değil" % node_type)
	if not ClassDB.can_instantiate(node_type):
		return _no("NODE_ADD: '%s' örneklenemez" % node_type)

	var name_error: String = _name_error(node_name)
	if not name_error.is_empty():
		return _no("NODE_ADD: " + name_error)
	var path_error: String = _node_path_error(parent, true)
	if not path_error.is_empty():
		return _no("NODE_ADD parent: " + path_error)

	return {
		"ok": true,
		"reason": "",
		"scene_path": str(scene["scene_path"]),
		"node_type": node_type,
		"node_name": node_name,
		"parent": parent,
	}


func plan_node_remove(params: Dictionary) -> Dictionary:
	var scene: Dictionary = _validate_scene_path(params)
	if not bool(scene["ok"]):
		return scene
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	var path_error: String = _node_path_error(node_path, false)
	if not path_error.is_empty():
		return _no("NODE_REMOVE: " + path_error)
	return {
		"ok": true,
		"reason": "",
		"scene_path": str(scene["scene_path"]),
		"node_path": node_path,
	}


func plan_property_set(params: Dictionary) -> Dictionary:
	var scene: Dictionary = _validate_scene_path(params)
	if not bool(scene["ok"]):
		return scene
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	var property_name: String = str(params.get("property", "")).strip_edges()
	var path_error: String = _node_path_error(node_path, true)
	if not path_error.is_empty():
		return _no("PROPERTY_SET: " + path_error)
	if property_name.is_empty():
		return _no("PROPERTY_SET: 'property' boş")
	if property_name.contains("/") or property_name.contains(":"):
		return _no("PROPERTY_SET: alt-yol veya subname property kabul edilmez")
	if not params.has("value"):
		return _no("PROPERTY_SET: 'value' anahtarı yok")
	return {
		"ok": true,
		"reason": "",
		"scene_path": str(scene["scene_path"]),
		"node_path": node_path,
		"property": property_name,
		"value": params["value"],
	}


func plan_script_attach(params: Dictionary) -> Dictionary:
	var scene: Dictionary = _validate_scene_path(params)
	if not bool(scene["ok"]):
		return scene
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	var script_path: String = str(params.get("script_path", "")).strip_edges()
	var path_error: String = _node_path_error(node_path, true)
	if not path_error.is_empty():
		return _no("SCRIPT_ATTACH: " + path_error)
	if script_path.is_empty():
		return _no("SCRIPT_ATTACH: 'script_path' boş")
	if not script_path.ends_with(".gd"):
		return _no("SCRIPT_ATTACH: yalnız .gd script bağlanır")
	if not AIPathGuard.can_read(script_path):
		return _no("SCRIPT_ATTACH: '%s' güvenli/erişilebilir değil" % script_path)
	return {
		"ok": true,
		"reason": "",
		"scene_path": str(scene["scene_path"]),
		"node_path": node_path,
		"script_path": script_path,
	}


func plan_project_setting(params: Dictionary) -> Dictionary:
	var key: String = str(params.get("key", "")).strip_edges()
	if key.is_empty():
		return _no("PROJECT_SETTING: 'key' boş")
	if not params.has("value"):
		return _no("PROJECT_SETTING: 'value' anahtarı yok")
	if key.begins_with("/") or key.ends_with("/"):
		return _no("PROJECT_SETTING: geçersiz ayar yolu")
	if key.contains("\\") or key.contains("..") or not key.contains("/"):
		return _no("PROJECT_SETTING: ayar anahtarı tam kategori yolu olmalı")
	if FORBIDDEN_PROJECT_SETTINGS.has(key):
		return _no("PROJECT_SETTING: güvenlik-kritik ayar değiştirilemez: %s" % key)
	return {
		"ok": true,
		"reason": "",
		"key": key,
		"value": params["value"],
	}


func plan_for(action_type: int, params: Dictionary) -> Dictionary:
	match action_type:
		AIActionSpec.ActionType.NODE_ADD:
			return plan_node_add(params)
		AIActionSpec.ActionType.NODE_REMOVE:
			return plan_node_remove(params)
		AIActionSpec.ActionType.PROPERTY_SET:
			return plan_property_set(params)
		AIActionSpec.ActionType.SCRIPT_ATTACH:
			return plan_script_attach(params)
		AIActionSpec.ActionType.PROJECT_SETTING:
			return plan_project_setting(params)
		_:
			return _no("Bu planlayıcı bu action tipini bilmiyor")


func _validate_scene_path(params: Dictionary) -> Dictionary:
	var scene_path: String = str(params.get("scene_path", "")).strip_edges()
	# Doğrudan planner birim testleri ve eski kayıtların okunması için boş
	# değer kabul edilir. Executor canlı işlemde ActionSpec.target_path'i
	# zorunlu olarak buraya enjekte eder.
	if scene_path.is_empty():
		return {"ok": true, "reason": "", "scene_path": ""}
	if not scene_path.begins_with("res://"):
		return _no("SCENE: hedef yalnız res:// altında olabilir")
	if not scene_path.ends_with(".tscn") and not scene_path.ends_with(".scn"):
		return _no("SCENE: hedef .tscn veya .scn olmalı")
	if not AIPathGuard.can_read(scene_path):
		return _no("SCENE: hedef yol güvenli/erişilebilir değil")
	return {
		"ok": true,
		"reason": "",
		"scene_path": scene_path.simplify_path(),
	}


func _node_path_error(node_path: String, allow_root: bool) -> String:
	if node_path.is_empty():
		return "'node_path' boş"
	if node_path == ".":
		return "" if allow_root else "sahne kökü hedeflenemez"
	if node_path == "/root" or node_path.begins_with("/"):
		return "mutlak node yolu kabul edilmez"
	if node_path.contains("\\") or node_path.contains(":"):
		return "geçersiz node yolu"
	var segments: PackedStringArray = node_path.split("/", false)
	if segments.is_empty():
		return "geçersiz node yolu"
	for segment in segments:
		if segment.is_empty() or segment == "." or segment == "..":
			return "node yolu traversal içeriyor"
	return ""


func _name_error(node_name: String) -> String:
	if node_name.is_empty():
		return "'node_name' boş"
	if node_name == "." or node_name == "..":
		return "özel yol adı node adı olamaz"
	for character in BAD_NAME_CHARS:
		if node_name.contains(character):
			return "'node_name' yasak karakter içeriyor: '%s'" % character
	return ""


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
