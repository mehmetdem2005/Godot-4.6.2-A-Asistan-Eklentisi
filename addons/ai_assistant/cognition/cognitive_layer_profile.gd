@tool
class_name AICognitiveLayerProfile
extends RefCounted

## Adaptif düşünme grafiğindeki bir bilişsel katmanın değişmez profili.

var index: int = 0
var layer_id: String = ""
var title: String = ""
var purpose: String = ""
var parallelizable: bool = false
var mandatory: bool = true
var min_confidence: float = 0.70
var max_branches: int = 1
var preferred_roles: Array[int] = []


static func create(
	layer_index: int,
	id: String,
	layer_title: String,
	layer_purpose: String,
	can_parallelize: bool,
	is_mandatory: bool,
	confidence_floor: float,
	branch_limit: int,
	roles: Array[int]
) -> AICognitiveLayerProfile:
	var profile := AICognitiveLayerProfile.new()
	profile.index = layer_index
	profile.layer_id = id.strip_edges()
	profile.title = layer_title.strip_edges()
	profile.purpose = layer_purpose.strip_edges()
	profile.parallelizable = can_parallelize
	profile.mandatory = is_mandatory
	profile.min_confidence = clampf(confidence_floor, 0.0, 1.0)
	profile.max_branches = clampi(branch_limit, 1, 16)
	profile.preferred_roles = roles.duplicate()
	return profile


func to_dict() -> Dictionary:
	return {
		"index": index,
		"layer_id": layer_id,
		"title": title,
		"purpose": purpose,
		"parallelizable": parallelizable,
		"mandatory": mandatory,
		"min_confidence": min_confidence,
		"max_branches": max_branches,
		"preferred_roles": preferred_roles.duplicate(),
	}
