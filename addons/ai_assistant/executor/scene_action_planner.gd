@tool
class_name AISceneActionPlanner
extends RefCounted

## SceneActionPlanner — editör mutasyon işlemlerinin SAF doğrulayıcısı.
##
## SORUN: NODE_ADD / NODE_REMOVE / PROPERTY_SET / SCRIPT_ATTACH /
## PROJECT_SETTING action'ları executor_engine.gd'de SKIP ediliyordu —
## "sahne node kur / property değiştir / script bağla / sil / proje
## ayarı" hiç çalışmıyordu (kullanıcının açık isteği).
##
## ÇÖZÜM: Karar mantığı (geçerli mi? hangi tip? hangi yol?) buraya;
## editöre DOKUNAN ince kısım editor_action_applier.gd'ye ayrılır.
## Bu sınıf RefCounted + saf → headless TAM test edilebilir
## (ClassDB headless'ta da çalışır; gerçek node tipi doğrulanır).
##
## Mock policy: geçersiz node tipi / boş ad / güvensiz yol → SAHTE
## başarı YOK; {ok:false, reason:...} ile dürüst RET. Editör uygulama
## bu plana güvenir; plan geçmezse editör hiç çağrılmaz.

## Sahne içi yol ayıracı (Godot NodePath) ve yasak ad karakterleri.
const PATH_SEP: String = "/"
const BAD_NAME_CHARS: Array = ["/", ":", "@", "."]


## NODE_ADD planı: yeni node tipi + ad + ebeveyn yolu doğrular.
## params: {node_type, node_name, parent}. parent boşsa "." (sahne kökü).
## Dönen: {ok, reason, node_type, node_name, parent}
func plan_node_add(params: Dictionary) -> Dictionary:
	var node_type: String = str(params.get("node_type", "")).strip_edges()
	var node_name: String = str(params.get("node_name", "")).strip_edges()
	var parent: String = str(params.get("parent", ".")).strip_edges()
	if parent.is_empty():
		parent = "."
	if node_type.is_empty():
		return _no("NODE_ADD: 'node_type' boş")
	if not ClassDB.class_exists(node_type):
		return _no(
			"NODE_ADD: '%s' geçerli bir Godot sınıfı değil" % node_type
		)
	if not ClassDB.is_parent_class(node_type, "Node"):
		return _no("NODE_ADD: '%s' bir Node türevi değil" % node_type)
	if not ClassDB.can_instantiate(node_type):
		return _no(
			"NODE_ADD: '%s' örneklenemez (soyut sınıf)" % node_type
		)
	var name_err: String = _name_error(node_name)
	if not name_err.is_empty():
		return _no("NODE_ADD: " + name_err)
	return {
		"ok": true,
		"reason": "",
		"node_type": node_type,
		"node_name": node_name,
		"parent": parent,
	}


## NODE_REMOVE planı: silinecek node yolu doğrular (yıkıcı — HITL'de
## ayrıca onaylanır).
func plan_node_remove(params: Dictionary) -> Dictionary:
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return _no("NODE_REMOVE: 'node_path' boş")
	if node_path == "." or node_path == "/root":
		return _no("NODE_REMOVE: sahne kökü silinemez")
	return {"ok": true, "reason": "", "node_path": node_path}


## PROPERTY_SET planı: hedef node + property adı + değer doğrular.
## value anahtarı params'ta BULUNMALI (null geçerli bir değer olabilir
## ama anahtar yoksa "ne atanacak" belirsizdir → RET).
func plan_property_set(params: Dictionary) -> Dictionary:
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	var prop: String = str(params.get("property", "")).strip_edges()
	if node_path.is_empty():
		return _no("PROPERTY_SET: 'node_path' boş")
	if prop.is_empty():
		return _no("PROPERTY_SET: 'property' boş")
	if not params.has("value"):
		return _no("PROPERTY_SET: 'value' anahtarı yok (ne atanacak?)")
	return {
		"ok": true,
		"reason": "",
		"node_path": node_path,
		"property": prop,
		"value": params["value"],
	}


## SCRIPT_ATTACH planı: hedef node + .gd script yolu doğrular.
func plan_script_attach(params: Dictionary) -> Dictionary:
	var node_path: String = str(params.get("node_path", "")).strip_edges()
	var script_path: String = str(
		params.get("script_path", "")
	).strip_edges()
	if node_path.is_empty():
		return _no("SCRIPT_ATTACH: 'node_path' boş")
	if script_path.is_empty():
		return _no("SCRIPT_ATTACH: 'script_path' boş")
	if not script_path.ends_with(".gd"):
		return _no("SCRIPT_ATTACH: yalnız .gd script bağlanır")
	if not AIPathGuard.can_read(script_path):
		return _no(
			"SCRIPT_ATTACH: '%s' güvenli/erişilebilir değil" % script_path
		)
	return {
		"ok": true,
		"reason": "",
		"node_path": node_path,
		"script_path": script_path,
	}


## PROJECT_SETTING planı: ayar anahtarı + değer doğrular (yıkıcı —
## HITL'de ayrıca onaylanır).
func plan_project_setting(params: Dictionary) -> Dictionary:
	var key: String = str(params.get("key", "")).strip_edges()
	if key.is_empty():
		return _no("PROJECT_SETTING: 'key' boş")
	if not params.has("value"):
		return _no("PROJECT_SETTING: 'value' anahtarı yok")
	return {
		"ok": true,
		"reason": "",
		"key": key,
		"value": params["value"],
	}


## Bir ActionSpec tipine göre uygun plan fonksiyonunu seçer.
## Dönen: {ok, reason, ...} (tip desteklenmiyorsa ok:false).
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


# ============================================================
# DAHİLİ
# ============================================================

## Node adı doğrulama — boş veya yasak karakter içeren ad RET.
## Dönen: hata mesajı (boş = geçerli).
func _name_error(node_name: String) -> String:
	if node_name.is_empty():
		return "'node_name' boş"
	for ch in BAD_NAME_CHARS:
		if node_name.contains(ch):
			return "'node_name' yasak karakter içeriyor: '%s'" % ch
	return ""


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
