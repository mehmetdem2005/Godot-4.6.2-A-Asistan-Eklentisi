@tool
class_name AIOfflineTemplateLibrary
extends RefCounted

## TemplateLibrary — şablon kütüphanesi (Madde 07 / Offline / fallback).
##
## LLM yokken bile kod üretilebilmeli. Bu kütüphane HAZIR kod
## şablonları tutar — GDScript boilerplate'leri. İnternet gidince
## sistem "yeni LLM cevabı üretemem" der ama "işte standart bir
## state machine şablonu" diyebilir.
##
## Şablonlar parametrelidir: {class_name} gibi yer tutucular gerçek
## değerlerle doldurulur. Bu LLM kadar zeki değil ama OFFLINE'da
## anlamlı bir fallback — sıfırdan boş ekran değil.
##
## Mock policy: şablonlar sabit, gerçek çalışan GDScript iskeletleri.

## Şablon kategorileri.
const CAT_NODE: String = "node"
const CAT_RESOURCE: String = "resource"
const CAT_STATE_MACHINE: String = "state_machine"
const CAT_SINGLETON: String = "singleton"

## Hazır şablonlar — id -> {category, description, body}.
## Body'de {class_name} ve {base} yer tutucuları doldurulur.
const TEMPLATES: Dictionary = {
	"empty_node": {
		"category": CAT_NODE,
		"description": "Boş Node betiği iskeleti",
		"body": "@tool\nclass_name {class_name}\nextends {base}\n\n\n"
			+ "func _ready() -> void:\n\tpass\n",
	},
	"resource_class": {
		"category": CAT_RESOURCE,
		"description": "Veri tutan Resource sınıfı",
		"body": "@tool\nclass_name {class_name}\nextends Resource\n\n\n"
			+ "@export var id: String = \"\"\n",
	},
	"state_machine": {
		"category": CAT_STATE_MACHINE,
		"description": "Basit durum makinesi iskeleti",
		"body": "@tool\nclass_name {class_name}\nextends {base}\n\n\n"
			+ "enum State { IDLE, ACTIVE, DONE }\n\n"
			+ "var current_state: int = State.IDLE\n\n\n"
			+ "func change_state(new_state: int) -> void:\n"
			+ "\tcurrent_state = new_state\n",
	},
	"singleton": {
		"category": CAT_SINGLETON,
		"description": "Autoload singleton iskeleti",
		"body": "@tool\nextends Node\n\n## Autoload olarak kaydedilir.\n\n\n"
			+ "func _ready() -> void:\n\tpass\n",
	},
}


# ============================================================
# ŞABLON ERİŞİMİ
# ============================================================

## Bir şablon tanımlı mı?
func has_template(template_id: String) -> bool:
	return TEMPLATES.has(template_id)


## Tüm şablon kimlikleri.
func template_ids() -> Array:
	return TEMPLATES.keys()


## Bir şablonun açıklamasını döndürür.
func describe(template_id: String) -> String:
	if not TEMPLATES.has(template_id):
		return ""
	return str(TEMPLATES[template_id]["description"])


## Belirli kategorideki şablonları döndürür.
func templates_in_category(category: String) -> Array:
	var matched: Array = []
	for template_id in TEMPLATES:
		if str(TEMPLATES[template_id]["category"]) == category:
			matched.append(template_id)
	return matched


# ============================================================
# ÜRETİM
# ============================================================

## Bir şablondan kod üretir — yer tutucuları doldurur.
## template_id: şablon kimliği. params: {placeholder: value}.
## Dönen: {ok: bool, code: String, reason: String}
func generate(template_id: String, params: Dictionary) -> Dictionary:
	if not TEMPLATES.has(template_id):
		return {
			"ok": false, "code": "",
			"reason": "Bilinmeyen şablon: " + template_id,
		}

	var body: String = str(TEMPLATES[template_id]["body"])

	# Varsayılan yer tutucu değerleri
	var class_name_value: String = str(params.get("class_name", "MyClass"))
	var base_value: String = str(params.get("base", "Node"))

	# Yer tutucuları doldur
	body = body.replace("{class_name}", class_name_value)
	body = body.replace("{base}", base_value)

	return {
		"ok": true,
		"code": body,
		"reason": "Şablondan üretildi: " + template_id,
	}


## Bir şablonun ham gövdesini (doldurulmamış) döndürür.
func raw_body(template_id: String) -> String:
	if not TEMPLATES.has(template_id):
		return ""
	return str(TEMPLATES[template_id]["body"])


## Toplam şablon sayısı.
func template_count() -> int:
	return TEMPLATES.size()
