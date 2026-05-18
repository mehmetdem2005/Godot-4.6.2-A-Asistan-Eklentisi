@tool
class_name AIPlanDecomposer
extends Node

## PlanDecomposer — büyük BUILD isteğini alt görevlere böler (Plan C).
##
## SORUN: "envanter sistemi olan oyun yap" gibi büyük istek tek LLM
## çağrısı + tek dosyaya sıkışıyordu — gerçek otonom üretim çok-adım
## ister. Heuristik bölme kırılgan; mock-yasağı disiplinine LLM-temelli
## planlama (gerçek model kararı) uygun.
##
## ÇÖZÜM: Kendi köprüsünü (paylaşılan router) kullanan ince bir Node.
## Modele "SADECE JSON dizi döndür" planı sorar; saf, test edilebilir
## parse_plan ile ayrıştırır. Parse başarısız/boş → tek görev fallback
## (sahte plan ÜRETİLMEZ — istek aynen tek adım olur).
##
## Güvenlik: model-üretimi dosya yolu ENJEKSİYON yüzeyidir —
## sanitize_target yalnız [a-z0-9_] basename + .gd, sabit user://
## önekine zorlar (path traversal / res:// imkânsız).

signal decomposed(tasks: Array)

## Üretilen dosyaların güvenli kök dizini (res:// bu turda YOK).
const OUT_DIR: String = "user://ai_assistant/uretilen/"

## Alt görev sayısı sınırları (sonsuz/boş plana karşı).
const MAX_TASKS: int = 6
const MIN_TASKS: int = 1

var _bridge: AIAgentLiveBridge = null
var _instruction: String = ""


## Köprüyü bağlar (orkestratörün anahtarlı router'ını paylaşan).
func attach_bridge(bridge: AIAgentLiveBridge) -> void:
	_bridge = bridge


## İsteği alt görevlere böler (asenkron). Sonuç 'decomposed' ile gelir.
## Dönen: çağrı başlatılabildi mi (false = fallback yine yayılır).
func decompose(instruction: String, model: String = "") -> bool:
	_instruction = instruction
	if _bridge == null:
		decomposed.emit([_fallback(instruction)])
		return false
	if not _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.connect(_on_thought)
	return _bridge.think_chat(_planning_prompt(instruction), model)


func _on_thought(thought: Dictionary) -> void:
	if _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.disconnect(_on_thought)
	if not bool(thought.get("ok", false)):
		# Planlama çağrısı düştü — istek tek adım olarak sürdürülür.
		decomposed.emit([_fallback(_instruction)])
		return
	decomposed.emit(
		parse_plan(str(thought.get("content", "")), _instruction)
	)


## Modele verilen planlama yönergesi — yalnız JSON dizi istenir.
func _planning_prompt(instruction: String) -> String:
	return (
		"Aşağıdaki Godot 4.6 oyun geliştirme isteğini "
		+ str(MIN_TASKS) + "-" + str(MAX_TASKS) + " bağımsız alt göreve "
		+ "böl. Her alt görev TEK bir GDScript dosyası üretmeli. "
		+ "SADECE şu biçimde bir JSON dizi döndür, başka HİÇBİR "
		+ "açıklama yazma:\n"
		+ "[{\"title\":\"kısa görev adı\",\"target_file\":\"ad.gd\"}]\n"
		+ "İSTEK: " + instruction
	)


# ============================================================
# SAF AYRIŞTIRMA — ağsız test edilebilir
# ============================================================

## LLM içeriğinden alt görev listesi çıkarır. Saf fonksiyon.
## Parse başarısız / boş / sınır dışı → tek görev fallback.
## Dönen: [{title, target_file}] (target_file güvenli user:// yolu).
func parse_plan(content: String, instruction: String) -> Array:
	var start: int = content.find("[")
	var stop: int = content.rfind("]")
	if start == -1 or stop == -1 or stop <= start:
		return [_fallback(instruction)]
	var slice: String = content.substr(start, stop - start + 1)
	var parsed: Variant = JSON.parse_string(slice)
	if typeof(parsed) != TYPE_ARRAY:
		return [_fallback(instruction)]
	var tasks: Array = []
	for item in parsed:
		var title: String = ""
		var raw_file: String = ""
		if typeof(item) == TYPE_DICTIONARY:
			title = str(item.get("title", "")).strip_edges()
			raw_file = str(item.get("target_file", "")).strip_edges()
		elif typeof(item) == TYPE_STRING:
			title = str(item).strip_edges()
		if title.is_empty():
			continue
		tasks.append({
			"title": title,
			"target_file": sanitize_target(raw_file, title),
		})
		if tasks.size() >= MAX_TASKS:
			break
	if tasks.is_empty():
		return [_fallback(instruction)]
	return tasks


## Model-üretimi dosya adını güvenli user:// yoluna zorlar.
## Yalnız [a-z0-9_] basename + .gd; path traversal / res:// imkânsız.
func sanitize_target(raw: String, title: String) -> String:
	var base: String = raw
	var sep: int = base.rfind("/")
	if sep != -1:
		base = base.substr(sep + 1)
	if base.to_lower().ends_with(".gd"):
		base = base.substr(0, base.length() - 3)
	var slug: String = _slug(base)
	if slug.is_empty():
		slug = _slug(title)
	if slug.is_empty():
		slug = "uretim"
	return OUT_DIR + slug + ".gd"


## Tek görevlik güvenli fallback (plan bölünemediğinde).
func _fallback(instruction: String) -> Dictionary:
	var slug: String = _slug(instruction)
	if slug.is_empty():
		slug = "uretim"
	return {
		"title": instruction.strip_edges(),
		"target_file": OUT_DIR + slug + ".gd",
	}


## Serbest metni güvenli slug'a indirger (a-z0-9_, ≤24).
func _slug(text: String) -> String:
	var slug: String = ""
	for c in text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif c == " " and slug.length() > 0 and not slug.ends_with("_"):
			slug += "_"
		if slug.length() >= 24:
			break
	return slug
