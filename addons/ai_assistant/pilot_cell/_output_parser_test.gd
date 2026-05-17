@tool
class_name AIOutputParserTest
extends RefCounted

## Pilot Cell — OutputParser Self-Test
##
## Sıkı testler: rol-özel çıktı ayrıştırma. Plan maddeleri, task
## listesi, kod düzenleme, inceleme kararı + savunmacı davranış.
##
## Kritik ilke testleri: parser yapılandırılmış format bulamazsa
## ham metni KORUR ve structured=false der — ASLA veri uydurmaz.


static func run_all() -> Array:
	var results: Array = []

	# Plan maddeleri (PM, Architect)
	results.append(_b("Parser: Plan", _test_plan_items()))
	results.append(_b("Parser: Plan", _test_plan_no_items()))
	results.append(_b("Parser: Plan", _test_plan_empty()))

	# Task listesi (DeliveryManager)
	results.append(_b("Parser: Task", _test_task_numbered()))
	results.append(_b("Parser: Task", _test_task_indexing()))
	results.append(_b("Parser: Task", _test_task_no_tasks()))

	# Kod düzenleme (Code/Scene/Shader/Asset)
	results.append(_b("Parser: Code", _test_code_search_replace()))
	results.append(_b("Parser: Code", _test_code_fence()))
	results.append(_b("Parser: Code", _test_code_no_structure()))

	# İnceleme (QA, Reviewer)
	results.append(_b("Parser: Review", _test_review_pass()))
	results.append(_b("Parser: Review", _test_review_fail()))
	results.append(_b("Parser: Review", _test_review_turkish()))
	results.append(_b("Parser: Review", _test_review_undecided()))
	results.append(_b("Parser: Review", _test_review_fail_wins()))

	# Yönlendirme + savunmacı davranış
	results.append(_b("Parser: Route", _test_routing()))
	results.append(_b("Parser: Route", _test_raw_preserved()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# PLAN MADDELERİ
# ============================================================

static func _test_plan_items() -> Dictionary:
	var name := "Plan maddeleri çıkarma"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.PRODUCT_MANAGER,
		"Hedefler:\n- Hızlı ana menü\n- 3 buton\n- Mobil dostu"
	)
	if parsed.kind != AIOutputParser.ParsedKind.PLAN_ITEMS:
		return _fail(name, "kind PLAN_ITEMS olmalı")
	if not parsed.structured:
		return _fail(name, "maddeli çıktı structured olmalı")
	if parsed.items.size() != 3:
		return _fail(name, "3 madde bekleniyordu, %d" % parsed.items.size())
	return _ok(name)


static func _test_plan_no_items() -> Dictionary:
	var name := "Plan maddesiz — uydurma yok"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.ARCHITECT,
		"Bu sadece düz bir paragraf, hiç madde işaretçisi yok."
	)
	# Madde yoksa structured=false — ama ham metin korunmalı
	if parsed.structured:
		return _fail(name, "maddesiz çıktı structured olmamalı (uydurma yok)")
	if parsed.raw_text.is_empty():
		return _fail(name, "ham metin korunmalı")
	return _ok(name)


static func _test_plan_empty() -> Dictionary:
	var name := "Plan boş çıktı"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.PRODUCT_MANAGER, ""
	)
	if parsed.structured:
		return _fail(name, "boş çıktı structured olmamalı")
	return _ok(name)


# ============================================================
# TASK LİSTESİ
# ============================================================

static func _test_task_numbered() -> Dictionary:
	var name := "Task numaralı liste"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.DELIVERY_MANAGER,
		"1. Menü scriptini yaz\n2. Butonları ekle\n3. Test et"
	)
	if parsed.kind != AIOutputParser.ParsedKind.TASK_LIST:
		return _fail(name, "kind TASK_LIST olmalı")
	if parsed.items.size() != 3:
		return _fail(name, "3 task bekleniyordu")
	return _ok(name)


static func _test_task_indexing() -> Dictionary:
	var name := "Task indeksleme"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.DELIVERY_MANAGER,
		"- ilk iş\n- ikinci iş"
	)
	if parsed.items.is_empty():
		return _fail(name, "task çıkmadı")
	# İlk task index 1, metin doğru
	var first: Dictionary = parsed.items[0]
	if int(first["index"]) != 1:
		return _fail(name, "ilk task index 1 olmalı")
	if str(first["text"]) != "ilk iş":
		return _fail(name, "task metni yanlış")
	return _ok(name)


static func _test_task_no_tasks() -> Dictionary:
	var name := "Task tasksız çıktı"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.DELIVERY_MANAGER,
		"Bu metinde hiç numaralı task yok."
	)
	if parsed.structured:
		return _fail(name, "tasksız çıktı structured olmamalı")
	return _ok(name)


# ============================================================
# KOD DÜZENLEME
# ============================================================

static func _test_code_search_replace() -> Dictionary:
	var name := "Kod SEARCH/REPLACE tespiti"
	var parser := AIOutputParser.new()
	var content: String = (
		"<<<<<<< SEARCH\n\treturn 1\n=======\n\treturn 2\n>>>>>>> REPLACE"
	)
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.CODE_ENGINEER, content
	)
	if not parsed.structured:
		return _fail(name, "SEARCH/REPLACE structured olmalı")
	if parsed.items.is_empty():
		return _fail(name, "edit item çıkmalı")
	if str(parsed.items[0]["type"]) != "search_replace":
		return _fail(name, "tip search_replace olmalı")
	return _ok(name)


static func _test_code_fence() -> Dictionary:
	var name := "Kod markdown fence"
	var parser := AIOutputParser.new()
	var content: String = "İşte kod:\n```gdscript\nfunc f():\n\tpass\n```"
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.SCENE_ENGINEER, content
	)
	if not parsed.structured:
		return _fail(name, "kod bloğu structured olmalı")
	if not str(parsed.items[0]["content"]).contains("func f()"):
		return _fail(name, "kod içeriği çıkarılmalı")
	return _ok(name)


static func _test_code_no_structure() -> Dictionary:
	var name := "Kod yapısız çıktı — uydurma yok"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.CODE_ENGINEER,
		"Sadece açıklama metni, kod bloğu veya SEARCH/REPLACE yok."
	)
	# Yapılandırılmış format yok — structured=false, ham metin korunur
	if parsed.structured:
		return _fail(name, "yapısız kod çıktısı structured olmamalı")
	if parsed.raw_text.is_empty():
		return _fail(name, "ham metin korunmalı")
	return _ok(name)


# ============================================================
# İNCELEME
# ============================================================

static func _test_review_pass() -> Dictionary:
	var name := "Review PASS kararı"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.QA_ENGINEER,
		"Sonuç: PASS\n- Tüm kriterler karşılandı"
	)
	if parsed.verdict != "pass":
		return _fail(name, "PASS kararı tespit edilmeli")
	if not parsed.structured:
		return _fail(name, "kararlı inceleme structured olmalı")
	return _ok(name)


static func _test_review_fail() -> Dictionary:
	var name := "Review FAIL kararı + bulgular"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.REVIEWER,
		"FAIL — eksikler var:\n- Buton bağlantısı yok\n- Test eksik"
	)
	if parsed.verdict != "fail":
		return _fail(name, "FAIL kararı tespit edilmeli")
	if parsed.items.size() != 2:
		return _fail(name, "2 bulgu çıkmalı")
	return _ok(name)


static func _test_review_turkish() -> Dictionary:
	var name := "Review Türkçe karar"
	var parser := AIOutputParser.new()
	# "başarısız"
	var fail_parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.QA_ENGINEER, "Bu çıktı başarısız oldu."
	)
	if fail_parsed.verdict != "fail":
		return _fail(name, "'başarısız' fail olmalı")
	# "onaylandı"
	var pass_parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.QA_ENGINEER, "İnceleme tamam, onaylandı."
	)
	if pass_parsed.verdict != "pass":
		return _fail(name, "'onaylandı' pass olmalı")
	return _ok(name)


static func _test_review_undecided() -> Dictionary:
	var name := "Review kararsız çıktı"
	var parser := AIOutputParser.new()
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.QA_ENGINEER,
		"Bu sadece nötr bir yorum, net karar yok."
	)
	if not parsed.verdict.is_empty():
		return _fail(name, "kararsız çıktıda verdict boş olmalı")
	if parsed.structured:
		return _fail(name, "kararsız inceleme structured olmamalı")
	return _ok(name)


static func _test_review_fail_wins() -> Dictionary:
	var name := "Review fail+pass — fail kazanır"
	var parser := AIOutputParser.new()
	# Hem pass hem fail geçiyor — güvenli taraf fail
	var parsed: AIOutputParser.ParsedOutput = parser.parse(
		AICellRoles.Role.REVIEWER,
		"Bazı testler pass oldu ama genel sonuç fail."
	)
	if parsed.verdict != "fail":
		return _fail(name, "fail+pass çakışmasında fail kazanmalı")
	return _ok(name)


# ============================================================
# YÖNLENDİRME + SAVUNMACI DAVRANIŞ
# ============================================================

static func _test_routing() -> Dictionary:
	var name := "Parser role göre yönlendirir"
	var parser := AIOutputParser.new()
	var sample: String = "- a\n- b"
	# PM -> plan_items
	if parser.parse(AICellRoles.Role.PRODUCT_MANAGER, sample).kind != \
			AIOutputParser.ParsedKind.PLAN_ITEMS:
		return _fail(name, "PM PLAN_ITEMS'a gitmeli")
	# DeliveryManager -> task_list
	if parser.parse(AICellRoles.Role.DELIVERY_MANAGER, sample).kind != \
			AIOutputParser.ParsedKind.TASK_LIST:
		return _fail(name, "DM TASK_LIST'e gitmeli")
	# CodeEngineer -> code_edit
	if parser.parse(AICellRoles.Role.CODE_ENGINEER, sample).kind != \
			AIOutputParser.ParsedKind.CODE_EDIT:
		return _fail(name, "CodeEngineer CODE_EDIT'e gitmeli")
	# TechWriter -> raw_text
	if parser.parse(AICellRoles.Role.TECH_WRITER, sample).kind != \
			AIOutputParser.ParsedKind.RAW_TEXT:
		return _fail(name, "TechWriter RAW_TEXT'e gitmeli")
	return _ok(name)


static func _test_raw_preserved() -> Dictionary:
	var name := "Ham metin her zaman korunur"
	var parser := AIOutputParser.new()
	var original: String = "Herhangi bir LLM çıktısı metni burada."
	# Hangi rol olursa olsun, raw_text orijinali tutmalı
	for role in [AICellRoles.Role.PRODUCT_MANAGER,
			AICellRoles.Role.CODE_ENGINEER, AICellRoles.Role.QA_ENGINEER]:
		var parsed: AIOutputParser.ParsedOutput = parser.parse(role, original)
		if parsed.raw_text != original:
			return _fail(name, "ham metin korunmadı: %s" % \
				AICellRoles.role_name(role))
	return _ok(name)
