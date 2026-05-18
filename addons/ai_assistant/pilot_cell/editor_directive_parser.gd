@tool
class_name AIEditorDirectiveParser
extends RefCounted

## EditorDirectiveParser — LLM çıktısını editör mutasyon ActionSpec'ine
## çevirir (Parça 3: Parça 2'yi canlıya bağlayan köprü).
##
## SORUN: executor_engine artık NODE_ADD/NODE_REMOVE/PROPERTY_SET/
## SCRIPT_ATTACH/PROJECT_SETTING uygulayabiliyor (Parça 2), AMA hat
## yalnız FILE_WRITE üretiyordu — LLM "Player'a Sprite2D ekle" deyince
## bunu bir editör action'ına çeviren KÖPRÜ yoktu. Bu sınıf o köprü.
##
## PROTOKOL: LLM, çıktısında "EDITOR_ACTIONS" işaretini ve hemen
## ardından bir JSON dizisi (``` çiti içinde) verir. Örnek:
##   EDITOR_ACTIONS
##   ```json
##   [
##     {"action":"node_add","parent":".","node_type":"Sprite2D",
##      "node_name":"Player"},
##     {"action":"script_attach","node_path":"Player",
##      "script_path":"res://game/scripts/player.gd"}
##   ]
##   ```
## JSON seçildi: JSON.parse_string sağlam + headless TAM test edilebilir;
## Vector2(..) gibi belirsiz metin değerleri ayrıştırmaz.
##
## Mock policy: işaret yoksa is_editor=false (normal kod hattına bırak).
## İşaret var ama JSON bozuk/boş/bilinmeyen action → is_editor=true +
## error; pipeline bunu DÜRÜSTçE başarısız raporlar (sessiz dosya
## yazımına DÜŞMEZ — yanlış şeyi yapmaktansa hata de).

const MARKER: String = "EDITOR_ACTIONS"


## "action" string → AIActionSpec.ActionType (sihirli sayı YOK; enum
## tek doğruluk kaynağı). Bilinmeyen → -1.
func _action_type(act: String) -> int:
	match act:
		"node_add":
			return AIActionSpec.ActionType.NODE_ADD
		"node_remove":
			return AIActionSpec.ActionType.NODE_REMOVE
		"property_set":
			return AIActionSpec.ActionType.PROPERTY_SET
		"script_attach":
			return AIActionSpec.ActionType.SCRIPT_ATTACH
		"project_setting":
			return AIActionSpec.ActionType.PROJECT_SETTING
		_:
			return -1


## LLM metnini ayrıştırır.
## Dönen: {is_editor: bool, actions: Array, error: String}
## actions öğesi: {action_type: int, params: Dictionary}
func parse(text: String) -> Dictionary:
	if not text.contains(MARKER):
		return {"is_editor": false, "actions": [], "error": ""}

	var json_str: String = _extract_fence(text)
	if json_str.is_empty():
		return _err("EDITOR_ACTIONS var ama JSON bloğu (``` çiti) yok")

	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null:
		return _err("Editör direktifi JSON ayrıştırılamadı")
	if not (parsed is Array):
		return _err("Editör direktifi bir JSON dizisi olmalı")
	var arr: Array = parsed
	if arr.is_empty():
		return _err("Editör direktifi boş — uygulanacak işlem yok")

	var actions: Array = []
	for raw in arr:
		if not (raw is Dictionary):
			return _err("Her direktif bir JSON nesnesi olmalı")
		var entry: Dictionary = raw
		var act: String = str(entry.get("action", "")).strip_edges()
		var atype: int = _action_type(act)
		if atype < 0:
			return _err("Bilinmeyen editör action: '%s'" % act)
		actions.append({
			"action_type": atype,
			"params": _params_for(act, entry),
		})
	return {"is_editor": true, "actions": actions, "error": ""}


## Bir direktif nesnesinden, action tipine göre params sözlüğü kurar.
## Bilinmeyen alanlar düşürülür (uydurma yok — yalnız beklenen alanlar).
func _params_for(act: String, e: Dictionary) -> Dictionary:
	match act:
		"node_add":
			return {
				"node_type": str(e.get("node_type", "")),
				"node_name": str(e.get("node_name", "")),
				"parent": str(e.get("parent", ".")),
			}
		"node_remove":
			return {"node_path": str(e.get("node_path", ""))}
		"property_set":
			var p: Dictionary = {
				"node_path": str(e.get("node_path", "")),
				"property": str(e.get("property", "")),
			}
			# value anahtarı KORUNUR (yoksa planner dürüstçe reddeder).
			if e.has("value"):
				p["value"] = e["value"]
			return p
		"script_attach":
			return {
				"node_path": str(e.get("node_path", "")),
				"script_path": str(e.get("script_path", "")),
			}
		"project_setting":
			var ps: Dictionary = {"key": str(e.get("key", ""))}
			if e.has("value"):
				ps["value"] = e["value"]
			return ps
		_:
			return {}


## İlk ``` çiti bloğunun içeriğini çıkarır (dil etiketi satırı atlanır).
func _extract_fence(text: String) -> String:
	var fence: String = "```"
	var first: int = text.find(fence)
	if first < 0:
		return ""
	var body_start: int = text.find("\n", first)
	if body_start < 0:
		return ""
	body_start += 1
	var second: int = text.find(fence, body_start)
	if second < 0:
		return ""
	return text.substr(body_start, second - body_start).strip_edges()


func _err(reason: String) -> Dictionary:
	return {"is_editor": true, "actions": [], "error": reason}
