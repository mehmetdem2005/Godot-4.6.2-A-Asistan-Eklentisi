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
## sanitize_target yalnız [a-z0-9_] basename, sabit res://game/ kökü +
## türe göre alt klasör (.gd→scripts, .tscn→scenes) önekine zorlar
## (path traversal / kök dışı imkânsız). Var olan dosya ASLA ezilmez —
## çakışan ad _2, _3… ile benzersizleştirilir (AAA: üretilen kod elle
## yazılan kodu bozmaz).
##
## Yaşam döngüsü: köprü sinyali dış sahipliktir. Node yanıt gelmeden
## silinirse bridge üzerindeki callable açık bırakılmaz; PREDELETE
## teardown bağlantıyı koparır ve kaynak döngüsünü engeller.

signal decomposed(tasks: Array)

## Üretilen oyunun kök dizini (AAA profesyonel yerleşim — projenin
## İÇİNDE ki Godot res:// tarayıp class_name/sahne kaydetsin, ama izole
## ve türe göre düzenli olsun). path_guard ayrıca bu köke sıkıştırır.
const GAME_ROOT: String = "res://game/"
const SCRIPTS_DIR: String = "res://game/scripts/"
const SCENES_DIR: String = "res://game/scenes/"
const RESOURCES_DIR: String = "res://game/resources/"

## Çakışma benzersizleştirme üst sınırı (sonsuz döngü koruması).
const MAX_UNIQUE_TRIES: int = 999

## Alt görev sayısı sınırları (sonsuz/boş plana karşı).
const MAX_TASKS: int = 6
const MIN_TASKS: int = 1

var _bridge: AIAgentLiveBridge = null
var _instruction: String = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_bridge()


## Köprüyü bağlar (orkestratörün anahtarlı router'ını paylaşan).
func attach_bridge(bridge: AIAgentLiveBridge) -> void:
	if _bridge == bridge:
		return
	_disconnect_bridge()
	_bridge = bridge


## İsteği alt görevlere böler (asenkron). Sonuç 'decomposed' ile gelir.
## Dönen: çağrı başlatılabildi mi (false = fallback yine yayılır).
func decompose(
	instruction: String, model: String = "", project_context: String = ""
) -> bool:
	_instruction = instruction
	if _bridge == null:
		decomposed.emit([_fallback(instruction)])
		return false
	if not _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.connect(_on_thought)
	var prompt: String = _planning_prompt(instruction)
	if not project_context.strip_edges().is_empty():
		prompt += "\n\nMEVCUT PROJE (yeni dosya adları çakışmasın):\n" \
			+ project_context
	return _bridge.think_chat(prompt, model)


func _on_thought(thought: Dictionary) -> void:
	_disconnect_bridge_signal()
	if not bool(thought.get("ok", false)):
		# Planlama çağrısı düştü — istek tek adım olarak sürdürülür.
		decomposed.emit([_fallback(_instruction)])
		return
	decomposed.emit(
		parse_plan(str(thought.get("content", "")), _instruction)
	)


func _disconnect_bridge_signal() -> void:
	if (
		_bridge != null
		and is_instance_valid(_bridge)
		and _bridge.thought_completed.is_connected(_on_thought)
	):
		_bridge.thought_completed.disconnect(_on_thought)


func _disconnect_bridge() -> void:
	_disconnect_bridge_signal()
	_bridge = null


## Modele verilen planlama yönergesi — yalnız JSON dizi istenir.
## Dizin SEÇTİRİLMEZ (kök sabit, güvenlik): yalnız dosya ADI istenir;
## yerleşim sanitize_target tarafından türe göre yapılır.
func _planning_prompt(instruction: String) -> String:
	return (
		"Aşağıdaki Godot 4.6 oyun geliştirme isteğini "
		+ str(MIN_TASKS) + "-" + str(MAX_TASKS) + " bağımsız alt göreve "
		+ "böl. Her alt görev TEK bir dosya üretmeli (GDScript .gd). "
		+ "Oyun ÇALIŞABİLİR olmalı: alt görevlerden BİRİ ana sahne "
		+ "olsun (target_file uzantısı .tscn) ve üretilen scriptleri "
		+ "birbirine bağlasın. target_file SADECE dosya adı olsun "
		+ "(yol/klasör YAZMA — yerleşimi sistem yapar). SADECE şu "
		+ "biçimde bir JSON dizi döndür, başka HİÇBİR açıklama yazma:\n"
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
	var reserved: Dictionary = {}
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
		var target: String = sanitize_target(raw_file, title, reserved)
		reserved[target] = true
		tasks.append({
			"title": title,
			"target_file": target,
		})
		if tasks.size() >= MAX_TASKS:
			break
	if tasks.is_empty():
		return [_fallback(instruction)]
	return tasks


## Model-üretimi dosya adını güvenli res://game/ yoluna zorlar.
## Yalnız [a-z0-9_] basename; uzantıya göre alt klasör (.gd→scripts,
## .tscn→scenes, diğer→resources); path traversal / kök dışı imkânsız.
## Var olan dosya ASLA ezilmez — çakışırsa _2, _3… eklenir. reserved:
## aynı plan içinde zaten atanmış yollar (model iki göreve aynı adı
## verirse plan-içi çakışma da ezilmesin — üretilen oyunda dosya
## kaybı olmasın). Varsayılan boş = bağımsız çağrı (geriye uyumlu).
func sanitize_target(
	raw: String, title: String, reserved: Dictionary = {}
) -> String:
	var base: String = raw
	var sep: int = base.rfind("/")
	if sep != -1:
		base = base.substr(sep + 1)
	var ext: String = _detect_ext(base)
	if base.to_lower().ends_with("." + ext):
		base = base.substr(0, base.length() - ext.length() - 1)
	var slug: String = _slug(base)
	if slug.is_empty():
		slug = _slug(title)
	if slug.is_empty():
		slug = "uretim"
	return _unique_path(_dir_for_ext(ext), slug, ext, reserved)


## Tek görevlik güvenli fallback (plan bölünemediğinde).
func _fallback(instruction: String) -> Dictionary:
	var slug: String = _slug(instruction)
	if slug.is_empty():
		slug = "uretim"
	return {
		"title": instruction.strip_edges(),
		"target_file": _unique_path(SCRIPTS_DIR, slug, "gd"),
	}


## Dosya adındaki uzantıyı saptar — desteklenen: gd, tscn. Aksi: gd
## (üretim varsayılanı GDScript; sözleşme tek-dosya .gd).
func _detect_ext(base: String) -> String:
	var low: String = base.to_lower()
	if low.ends_with(".tscn"):
		return "tscn"
	return "gd"


## Uzantıya göre AAA alt klasörü (türe göre düzenli yerleşim).
func _dir_for_ext(ext: String) -> String:
	match ext:
		"tscn":
			return SCENES_DIR
		"gd":
			return SCRIPTS_DIR
		_:
			return RESOURCES_DIR


## Var olan dosyayı EZMEYEN benzersiz yol üretir (AAA: üretilen kod
## elle yazılan kodu bozmaz). dir + slug(.ext); çakışırsa slug_2…
## reserved: disk dışında bu plan içinde zaten atanmış yollar da
## çakışma sayılır (plan-içi dosya kaybı önlenir).
func _unique_path(
	dir: String, slug: String, ext: String, reserved: Dictionary = {}
) -> String:
	var candidate: String = dir + slug + "." + ext
	if not FileAccess.file_exists(candidate) and not reserved.has(candidate):
		return candidate
	var n: int = 2
	while n <= MAX_UNIQUE_TRIES:
		candidate = "%s%s_%d.%s" % [dir, slug, n, ext]
		if (not FileAccess.file_exists(candidate)
				and not reserved.has(candidate)):
			return candidate
		n += 1
	# Üst sınır (pratikte ulaşılmaz) — yine de güvenli kök içinde kal.
	return dir + slug + "_x." + ext


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
