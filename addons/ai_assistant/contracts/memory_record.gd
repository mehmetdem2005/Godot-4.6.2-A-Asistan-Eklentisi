@tool
class_name AIMemoryRecord
extends AIContractBase

## MemoryRecord — bellek sistemi kaydı (Layer 1).
##
## Sistem 4 katmanlı belleğe sahiptir:
##   - working: anlık çalışma belleği (kısa ömürlü)
##   - episodic: olay/deneyim belleği (ne yaptık, ne oldu)
##   - semantic: kavram/bilgi belleği (Godot API, pattern'ler)
##   - procedural: nasıl-yapılır belleği (öğrenilmiş prosedürler)
##
## Her kayıt bir katmana aittir, önem (salience) skoru taşır ve zamanla zayıflar.

## Bellek katmanları.
enum Layer {
	WORKING,     ## Anlık çalışma belleği — kısa ömürlü
	EPISODIC,    ## Olay/deneyim belleği
	SEMANTIC,    ## Kavram/bilgi belleği
	PROCEDURAL,  ## Nasıl-yapılır belleği
}

const LAYER_NAMES: Dictionary = {
	Layer.WORKING: "working",
	Layer.EPISODIC: "episodic",
	Layer.SEMANTIC: "semantic",
	Layer.PROCEDURAL: "procedural",
}

# --- Kimlik ---
var id: String = ""
var layer: int = Layer.WORKING

# --- İçerik ---
var content: String = ""             ## Belleğin metinsel içeriği
var structured_data: Dictionary = {} ## Yapılandırılmış ek veri

# --- Önem ve zayıflama ---
var salience: float = 0.5            ## Önem skoru (0.0-1.0)
var access_count: int = 0            ## Kaç kez erişildi (sık erişim = önemli)
var decay_rate: float = 0.01         ## Zamanla zayıflama hızı

# --- Bağlam ---
var tags: PackedStringArray = PackedStringArray()
var source_ref: String = ""          ## Hangi task/iteration/commit'ten geldi
var genre_id: String = ""

# --- Zaman ---
var created_at: String = ""
var last_accessed_at: String = ""


func contract_type() -> String:
	return "MemoryRecord"


## Yeni bir bellek kaydı oluşturur (factory).
static func create(p_layer: int, p_content: String) -> AIMemoryRecord:
	var m := AIMemoryRecord.new()
	m.id = AIContractBase.generate_id("mem")
	m.layer = p_layer
	m.content = p_content
	m.created_at = AIContractBase.now_iso()
	m.last_accessed_at = m.created_at
	return m


## Katmanın string adı.
func layer_name() -> String:
	return LAYER_NAMES.get(layer, "working")


## Bu belleğe erişildiğinde çağrılır — erişim sayısını ve önemi artırır.
func mark_accessed() -> void:
	access_count += 1
	last_accessed_at = AIContractBase.now_iso()
	# Sık erişilen bellek önem kazanır (üst sınır 1.0)
	salience = minf(1.0, salience + 0.05)


## Belleğin etkin önemini hesaplar (decay uygulanmış).
## elapsed_days: kayıttan bu yana geçen gün sayısı.
func effective_salience(elapsed_days: float) -> float:
	# Working memory hızlı zayıflar; procedural neredeyse hiç.
	var decay: float = decay_rate * elapsed_days
	# Erişim sayısı zayıflamayı azaltır
	var access_bonus: float = minf(0.3, access_count * 0.02)
	return clampf(salience - decay + access_bonus, 0.0, 1.0)


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"layer": LAYER_NAMES.get(layer, "working"),
		"content": content,
		"structured_data": structured_data,
		"salience": salience,
		"access_count": access_count,
		"decay_rate": decay_rate,
		"tags": tags,
		"source_ref": source_ref,
		"genre_id": genre_id,
		"created_at": created_at,
		"last_accessed_at": last_accessed_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	layer = _parse_layer(data.get("layer", "working"))
	content = data.get("content", "")
	structured_data = data.get("structured_data", {})
	salience = float(data.get("salience", 0.5))
	access_count = int(data.get("access_count", 0))
	decay_rate = float(data.get("decay_rate", 0.01))
	tags = PackedStringArray(data.get("tags", []))
	source_ref = data.get("source_ref", "")
	genre_id = data.get("genre_id", "")
	created_at = data.get("created_at", "")
	last_accessed_at = data.get("last_accessed_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, content, "content")
	require_in_range(result, salience, 0.0, 1.0, "salience")
	if access_count < 0:
		result.add_error("access_count negatif olamaz")
	if decay_rate < 0.0:
		result.add_error("decay_rate negatif olamaz")


static func _parse_layer(s: String) -> int:
	for key in LAYER_NAMES:
		if LAYER_NAMES[key] == s:
			return key
	return Layer.WORKING
