@tool
class_name AIPlanNode
extends AIContractBase

## PlanNode — hiyerarşik plan düğümü (Layer 3).
##
## Planner, kullanıcı isteğini hiyerarşik bir ağaca böler:
##   Goal (hedef) -> Milestone (kilometre taşı) -> Task (görev) -> Action (eylem)
##
## Her PlanNode bu ağaçta bir düğümdür. Bağımlılıklar DAG (yönlü çevrimsiz graf)
## oluşturur — döngü olmamalı.

## Plan düğümü seviyeleri.
enum Level {
	GOAL,       ## En üst — kullanıcının nihai hedefi
	MILESTONE,  ## Ara hedef
	TASK,       ## Somut görev (bir cell role'e atanır)
	ACTION,     ## Atomik eylem
}

const LEVEL_NAMES: Dictionary = {
	Level.GOAL: "goal",
	Level.MILESTONE: "milestone",
	Level.TASK: "task",
	Level.ACTION: "action",
}

# --- Kimlik ---
var id: String = ""
var parent_id: String = ""           ## Üst düğüm (GOAL'un parent'ı yok)
var level: int = Level.TASK

# --- İçerik ---
var title: String = ""               ## Kısa başlık
var description: String = ""          ## Detaylı açıklama
var children_ids: PackedStringArray = PackedStringArray()  ## Alt düğümler

# --- Bağımlılık (DAG) ---
var depends_on: PackedStringArray = PackedStringArray()  ## Beklenen düğüm id'leri

# --- Atama ---
var assigned_role: String = ""        ## TASK seviyesinde: hangi cell role
var estimated_effort: int = 1         ## Tahmini efor (göreceli birim)

# --- Durum ---
var is_completed: bool = false
var order: int = 0                    ## Kardeşler arası sıra


func contract_type() -> String:
	return "PlanNode"


## Yeni bir plan düğümü oluşturur (factory).
static func create(p_level: int, p_title: String) -> AIPlanNode:
	var n := AIPlanNode.new()
	n.id = AIContractBase.generate_id("plan")
	n.level = p_level
	n.title = p_title
	return n


## Seviyenin string adı.
func level_name() -> String:
	return LEVEL_NAMES.get(level, "task")


## Bu düğüm kök mü (GOAL, parent'ı yok)?
func is_root() -> bool:
	return parent_id.is_empty()


## Bu düğüm yaprak mı (alt düğümü yok)?
func is_leaf() -> bool:
	return children_ids.is_empty()


## Bir alt düğüm ekler.
func add_child(child_id: String) -> void:
	if not children_ids.has(child_id):
		children_ids.append(child_id)


## Bu düğümün bir sonraki olması gereken seviyeyi döndürür.
## GOAL -> MILESTONE -> TASK -> ACTION. ACTION'ın altı yok.
func expected_child_level() -> int:
	match level:
		Level.GOAL:
			return Level.MILESTONE
		Level.MILESTONE:
			return Level.TASK
		Level.TASK:
			return Level.ACTION
		_:
			return -1  # ACTION'ın çocuğu olamaz


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"parent_id": parent_id,
		"level": LEVEL_NAMES.get(level, "task"),
		"title": title,
		"description": description,
		"children_ids": children_ids,
		"depends_on": depends_on,
		"assigned_role": assigned_role,
		"estimated_effort": estimated_effort,
		"is_completed": is_completed,
		"order": order,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	parent_id = data.get("parent_id", "")
	level = _parse_level(data.get("level", "task"))
	title = data.get("title", "")
	description = data.get("description", "")
	children_ids = PackedStringArray(data.get("children_ids", []))
	depends_on = PackedStringArray(data.get("depends_on", []))
	assigned_role = data.get("assigned_role", "")
	estimated_effort = int(data.get("estimated_effort", 1))
	is_completed = bool(data.get("is_completed", false))
	order = int(data.get("order", 0))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, title, "title")
	# Kendine bağımlılık = DAG ihlali
	if depends_on.has(id):
		result.add_error("PlanNode kendine bağımlı olamaz (DAG ihlali)")
	# Kendine parent olamaz
	if parent_id == id:
		result.add_error("PlanNode kendi parent'ı olamaz")
	# ACTION'ın alt düğümü olmamalı
	if level == Level.ACTION and not children_ids.is_empty():
		result.add_error("ACTION seviyesi alt düğüm içeremez")
	# TASK seviyesi rol ataması bekler
	if level == Level.TASK and assigned_role.is_empty():
		result.add_warning("TASK seviyesi düğümün atanmış rolü yok")
	if estimated_effort < 0:
		result.add_error("estimated_effort negatif olamaz")


static func _parse_level(s: String) -> int:
	for key in LEVEL_NAMES:
		if LEVEL_NAMES[key] == s:
			return key
	return Level.TASK
