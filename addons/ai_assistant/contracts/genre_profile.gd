@tool
class_name AIGenreProfile
extends AIContractBase

## GenreProfile — oyun türü profili.
##
## Sistem her oyun türüne uyum sağlayabilir. Genre'ye özel bilgi
## (hangi sistemler, hangi node pattern'leri, hangi input action'lar,
## performans önceliği) bu profilde toplanır.
##
## 9 yerleşik genre Phase 1'de hazır gelir; kullanıldıkça yeni profiller
## öğrenilir (procedural library ile).

# --- Kimlik ---
var genre_id: String = ""            ## Benzersiz tür kimliği (örn: "fps_3d")
var display_name: String = ""        ## İnsan-okunabilir ad (örn: "Birinci Şahıs Nişancı")

# --- Çekirdek sistemler ---
var core_systems: PackedStringArray = PackedStringArray()
## Bu türün gerektirdiği ana sistemler (örn: "first_person_camera", "weapon_system")

# --- Node pattern'leri ---
var default_node_patterns: Dictionary = {}
## system_name -> node tree blueprint (serbest yapı)

# --- Girdi ---
var typical_input_actions: PackedStringArray = PackedStringArray()
## Bu türde yaygın input action'lar (örn: "move_forward", "jump", "shoot")

# --- Performans ---
var performance_emphasis: String = "balanced"
## frame_rate_priority | memory_priority | balanced

var default_renderer: String = "Forward Mobile"
## Android hedefi için her zaman Forward Mobile

# --- Asset ---
var common_assets: PackedStringArray = PackedStringArray()
## Bu türde sık kullanılan asset kategorileri

# --- Yapı ---
var recommended_structure: Dictionary = {}
## Önerilen klasör/dosya düzeni

# --- Yetenek bayrakları ---
var supports_multiplayer: bool = false  ## Phase 2+ (Madde 13)
var monetization_friendly: bool = false ## Phase 2+ (Madde 15)

# --- Meta ---
var is_builtin: bool = true           ## Yerleşik mi yoksa öğrenilmiş mi
var version: int = 1


func contract_type() -> String:
	return "GenreProfile"


## Yeni bir genre profili oluşturur (factory).
static func create(p_genre_id: String, p_display_name: String) -> AIGenreProfile:
	var g := AIGenreProfile.new()
	g.genre_id = p_genre_id
	g.display_name = p_display_name
	g.default_renderer = "Forward Mobile"
	return g


## Bu profilin belirli bir sisteme sahip olup olmadığını kontrol eder.
func has_system(system_name: String) -> bool:
	return core_systems.has(system_name)


func _to_dict_impl() -> Dictionary:
	return {
		"genre_id": genre_id,
		"display_name": display_name,
		"core_systems": core_systems,
		"default_node_patterns": default_node_patterns,
		"typical_input_actions": typical_input_actions,
		"performance_emphasis": performance_emphasis,
		"default_renderer": default_renderer,
		"common_assets": common_assets,
		"recommended_structure": recommended_structure,
		"supports_multiplayer": supports_multiplayer,
		"monetization_friendly": monetization_friendly,
		"is_builtin": is_builtin,
		"version": version,
	}


func _from_dict_impl(data: Dictionary) -> void:
	genre_id = data.get("genre_id", "")
	display_name = data.get("display_name", "")
	core_systems = PackedStringArray(data.get("core_systems", []))
	default_node_patterns = data.get("default_node_patterns", {})
	typical_input_actions = PackedStringArray(data.get("typical_input_actions", []))
	performance_emphasis = data.get("performance_emphasis", "balanced")
	default_renderer = data.get("default_renderer", "Forward Mobile")
	common_assets = PackedStringArray(data.get("common_assets", []))
	recommended_structure = data.get("recommended_structure", {})
	supports_multiplayer = bool(data.get("supports_multiplayer", false))
	monetization_friendly = bool(data.get("monetization_friendly", false))
	is_builtin = bool(data.get("is_builtin", true))
	version = int(data.get("version", 1))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, genre_id, "genre_id")
	require_non_empty_string(result, display_name, "display_name")
	require_in_set(
		result,
		performance_emphasis,
		["frame_rate_priority", "memory_priority", "balanced"],
		"performance_emphasis"
	)
	# Android hedefi: Forward+ desteklenmiyor
	if default_renderer == "Forward Plus" or default_renderer == "Forward+":
		result.add_error(
			"Forward+ renderer Android hedefinde desteklenmiyor — 'Forward Mobile' kullan"
		)
