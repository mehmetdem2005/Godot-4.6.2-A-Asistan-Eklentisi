@tool
class_name AIDebugGodot4APIMapper
extends RefCounted

## Godot4APIMapper — Godot 3→4 API haritalayıcı (Madde 02 / Debug Loop).
##
## Godot 4'e geçişte API'nin yarısı değişti. AI (eğitim verisinde
## çoğu Godot 3 olan) sürekli eski API'yi yazıyor: `OS.get_ticks_msec`,
## `Engine.get_idle_frames`, eski sinyal bağlama... Sonra "nonexistent
## function" hatası. Mehmet'in geçmiş oturumlardaki EN SIK derdi buydu.
##
## Bu sınıf, LLM ÇAĞIRMADAN, bilinen 3→4 değişimlerini tanır ve
## doğru karşılığı söyler. Hızlı, deterministik, ücretsiz — API
## hataları çoğu zaman LLM bile gerektirmez.
##
## Mock policy: harita sabit, doğrulanmış Godot 4 API gerçekleri.

## Godot 3 -> Godot 4 metod/sınıf değişimleri.
## eski_ad -> {yeni: yeni_ad, not: açıklama}
const API_MAP: Dictionary = {
	"get_ticks_msec": {
		"new": "Time.get_ticks_msec",
		"note": "OS.get_ticks_msec() -> Time.get_ticks_msec()",
	},
	"get_ticks_usec": {
		"new": "Time.get_ticks_usec",
		"note": "OS.get_ticks_usec() -> Time.get_ticks_usec()",
	},
	"get_idle_frames": {
		"new": "Engine.get_process_frames",
		"note": "get_idle_frames -> get_process_frames",
	},
	"instance": {
		"new": "instantiate",
		"note": "PackedScene.instance() -> instantiate()",
	},
	"empty": {
		"new": "is_empty",
		"note": "Array/String .empty() -> .is_empty()",
	},
	"is_action_just_pressed": {
		"new": "is_action_just_pressed",
		"note": "Aynı kaldı — Input üzerinden çağrılmalı",
	},
	"connect": {
		"new": "connect (Callable ile)",
		"note": "connect(\"sig\", obj, \"method\") -> "
			+ "connect(\"sig\", Callable(obj, \"method\"))",
	},
	"get_node_or_null": {
		"new": "get_node_or_null",
		"note": "Aynı kaldı — geçerli Godot 4 API",
	},
	"set_as_toplevel": {
		"new": "set_as_top_level",
		"note": "set_as_toplevel -> set_as_top_level",
	},
	"raise": {
		"new": "move_to_front",
		"note": "CanvasItem.raise() -> move_to_front()",
	},
	"rotation_degrees": {
		"new": "rotation_degrees",
		"note": "Hâlâ var ama radyan rotation tercih edilir",
	},
	"linear_velocity": {
		"new": "linear_velocity",
		"note": "Aynı — ama _physics_process içinde kullanın",
	},
}

## Godot 4'te kaldırılan / yeniden adlandırılan sınıflar.
const CLASS_MAP: Dictionary = {
	"KinematicBody2D": "CharacterBody2D",
	"KinematicBody": "CharacterBody3D",
	"Spatial": "Node3D",
	"YSort": "Node2D (y_sort_enabled özelliği)",
	"ARVROrigin": "XROrigin3D",
	"ARVRCamera": "XRCamera3D",
	"Reference": "RefCounted",
	"VisualServer": "RenderingServer",
}


# ============================================================
# METOD HARİTASI
# ============================================================

## Bir metod adının Godot 3→4 karşılığı var mı?
func has_method_mapping(old_method: String) -> bool:
	return API_MAP.has(old_method)


## Bir eski metod için Godot 4 karşılığını döndürür.
## Dönen: {found: bool, new_name: String, note: String}
func map_method(old_method: String) -> Dictionary:
	if not API_MAP.has(old_method):
		return {"found": false, "new_name": "", "note": ""}
	var entry: Dictionary = API_MAP[old_method]
	return {
		"found": true,
		"new_name": str(entry["new"]),
		"note": str(entry["note"]),
	}


# ============================================================
# SINIF HARİTASI
# ============================================================

## Bir sınıf adının Godot 3→4 karşılığı var mı?
func has_class_mapping(old_class: String) -> bool:
	return CLASS_MAP.has(old_class)


## Bir eski sınıf için Godot 4 karşılığını döndürür.
## Dönen: {found: bool, new_name: String}
func map_class(old_class: String) -> Dictionary:
	if not CLASS_MAP.has(old_class):
		return {"found": false, "new_name": ""}
	return {"found": true, "new_name": str(CLASS_MAP[old_class])}


# ============================================================
# HATA ANALİZİ
# ============================================================

## Bir hata sembolü için Godot 3→4 düzeltme önerisi arar.
## symbol: hatadaki sembol (metod veya sınıf adı).
## Dönen: {fixable: bool, suggestion: String, kind: String}
##   kind: "method" | "class" | ""
func suggest_fix(symbol: String) -> Dictionary:
	# Önce metod haritası
	var method: Dictionary = map_method(symbol)
	if method["found"]:
		return {
			"fixable": true,
			"suggestion": str(method["note"]),
			"kind": "method",
		}
	# Sonra sınıf haritası
	var cls: Dictionary = map_class(symbol)
	if cls["found"]:
		return {
			"fixable": true,
			"suggestion": "%s sınıfı Godot 4'te '%s' oldu" % [
				symbol, cls["new_name"]
			],
			"kind": "class",
		}
	# Bilinen bir 3→4 değişimi değil
	return {"fixable": false, "suggestion": "", "kind": ""}


## Bir API hatasının LLM olmadan düzeltilebilir olup olmadığı.
func is_known_migration(symbol: String) -> bool:
	return has_method_mapping(symbol) or has_class_mapping(symbol)


## Toplam bilinen değişim sayısı.
func mapping_count() -> int:
	return API_MAP.size() + CLASS_MAP.size()
