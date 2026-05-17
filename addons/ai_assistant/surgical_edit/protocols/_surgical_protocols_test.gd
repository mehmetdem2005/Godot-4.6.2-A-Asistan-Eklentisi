@tool
class_name AISurgicalProtocolsTest
extends RefCounted

## Surgical Edit — Protokoller Self-Test
##
## Sıkı testler: 5 düzenleme protokolü.
## InsertAtAnchor (çapaya ekleme), DeleteBlock (blok silme),
## ProjectWideRename (sembol yeniden adlandırma), MultiStepEdit
## (çok adımlı atomik), ExplicitReplace (kontrollü tam değişim).
##
## Ortak ilke: belirsiz/bulunamayan hedef -> ret. Sahte başarı yok.


static func run_all() -> Array:
	var results: Array = []

	# InsertAtAnchor
	results.append(_b("Surgical: Insert", _test_insert_after()))
	results.append(_b("Surgical: Insert", _test_insert_before()))
	results.append(_b("Surgical: Insert", _test_insert_anchor_missing()))
	results.append(_b("Surgical: Insert", _test_insert_ambiguous()))
	results.append(_b("Surgical: Insert", _test_insert_at_line()))

	# DeleteBlock
	results.append(_b("Surgical: Delete", _test_delete_block()))
	results.append(_b("Surgical: Delete", _test_delete_missing()))
	results.append(_b("Surgical: Delete", _test_delete_ambiguous()))
	results.append(_b("Surgical: Delete", _test_delete_empties_file()))
	results.append(_b("Surgical: Delete", _test_delete_line_range()))

	# ProjectWideRename
	results.append(_b("Surgical: Rename", _test_rename_basic()))
	results.append(_b("Surgical: Rename", _test_rename_word_boundary()))
	results.append(_b("Surgical: Rename", _test_rename_not_found()))
	results.append(_b("Surgical: Rename", _test_rename_across_files()))

	# MultiStepEdit
	results.append(_b("Surgical: MultiStep", _test_multistep_sequence()))
	results.append(_b("Surgical: MultiStep", _test_multistep_atomic()))
	results.append(_b("Surgical: MultiStep", _test_multistep_empty()))

	# ExplicitReplace
	results.append(_b("Surgical: Explicit", _test_explicit_new_file()))
	results.append(_b("Surgical: Explicit", _test_explicit_needs_approval()))
	results.append(_b("Surgical: Explicit", _test_explicit_small_change()))
	results.append(_b("Surgical: Explicit", _test_explicit_approved()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# INSERT AT ANCHOR
# ============================================================

static func _test_insert_after() -> Dictionary:
	var name := "Insert çapa sonrası"
	var h := AIInsertAtAnchorHandler.new()
	var result: AIInsertAtAnchorHandler.InsertResult = h.apply(
		"func a():\n\tpass", "func a():\n\tpass",
		"func b():\n\tpass", AIInsertAtAnchorHandler.InsertPosition.AFTER_ANCHOR
	)
	if not result.ok:
		return _fail(name, "geçerli ekleme başarısız: %s" % result.rejected_reason)
	if not result.new_content.contains("func b()"):
		return _fail(name, "eklenen içerik yok")
	return _ok(name)


static func _test_insert_before() -> Dictionary:
	var name := "Insert çapa öncesi"
	var h := AIInsertAtAnchorHandler.new()
	var result: AIInsertAtAnchorHandler.InsertResult = h.apply(
		"son satır", "son satır", "yeni satır",
		AIInsertAtAnchorHandler.InsertPosition.BEFORE_ANCHOR
	)
	if not result.ok:
		return _fail(name, "öncesine ekleme başarısız")
	# Yeni içerik çapadan önce gelmeli
	if result.new_content.find("yeni satır") > result.new_content.find("son satır"):
		return _fail(name, "yeni içerik çapadan önce olmalı")
	return _ok(name)


static func _test_insert_anchor_missing() -> Dictionary:
	var name := "Insert çapa bulunamaz"
	var h := AIInsertAtAnchorHandler.new()
	var result: AIInsertAtAnchorHandler.InsertResult = h.apply(
		"bir kod", "var olmayan çapa", "yeni",
		AIInsertAtAnchorHandler.InsertPosition.AFTER_ANCHOR
	)
	if result.ok:
		return _fail(name, "bulunamayan çapa kabul edilmemeli")
	return _ok(name)


static func _test_insert_ambiguous() -> Dictionary:
	var name := "Insert belirsiz çapa"
	var h := AIInsertAtAnchorHandler.new()
	# 'tekrar' iki kez geçiyor
	var result: AIInsertAtAnchorHandler.InsertResult = h.apply(
		"tekrar\ntekrar", "tekrar", "yeni",
		AIInsertAtAnchorHandler.InsertPosition.AFTER_ANCHOR
	)
	if result.ok:
		return _fail(name, "belirsiz çapa kabul edilmemeli")
	return _ok(name)


static func _test_insert_at_line() -> Dictionary:
	var name := "Insert satır numarasına"
	var h := AIInsertAtAnchorHandler.new()
	var result: AIInsertAtAnchorHandler.InsertResult = h.apply_at_line(
		"a\nb\nc", 2, "X",
		AIInsertAtAnchorHandler.InsertPosition.BEFORE_ANCHOR
	)
	if not result.ok:
		return _fail(name, "satıra ekleme başarısız")
	if result.new_content != "a\nX\nb\nc":
		return _fail(name, "ekleme yeri yanlış")
	return _ok(name)


# ============================================================
# DELETE BLOCK
# ============================================================

static func _test_delete_block() -> Dictionary:
	var name := "Delete blok silme"
	var h := AIDeleteBlockHandler.new()
	var result: AIDeleteBlockHandler.DeleteResult = h.delete_text_block(
		"tut bunu\nSIL_BU\nbunu da tut", "SIL_BU\n"
	)
	if not result.ok:
		return _fail(name, "blok silme başarısız")
	if result.new_content.contains("SIL_BU"):
		return _fail(name, "blok silinmedi")
	return _ok(name)


static func _test_delete_missing() -> Dictionary:
	var name := "Delete bulunamayan blok"
	var h := AIDeleteBlockHandler.new()
	var result: AIDeleteBlockHandler.DeleteResult = h.delete_text_block(
		"bir kod", "var olmayan blok"
	)
	if result.ok:
		return _fail(name, "bulunamayan blok silinmemeli")
	return _ok(name)


static func _test_delete_ambiguous() -> Dictionary:
	var name := "Delete belirsiz blok"
	var h := AIDeleteBlockHandler.new()
	var result: AIDeleteBlockHandler.DeleteResult = h.delete_text_block(
		"aynı\naynı", "aynı"
	)
	if result.ok:
		return _fail(name, "belirsiz blok silinmemeli")
	return _ok(name)


static func _test_delete_empties_file() -> Dictionary:
	var name := "Delete dosya boşaltma reddi"
	var h := AIDeleteBlockHandler.new()
	# Tüm içeriği silmeye çalış
	var result: AIDeleteBlockHandler.DeleteResult = h.delete_text_block(
		"tüm içerik", "tüm içerik"
	)
	if result.ok:
		return _fail(name, "dosyayı boşaltan silme reddedilmeli")
	return _ok(name)


static func _test_delete_line_range() -> Dictionary:
	var name := "Delete satır aralığı"
	var h := AIDeleteBlockHandler.new()
	var result: AIDeleteBlockHandler.DeleteResult = h.delete_line_range(
		"a\nb\nc\nd", 2, 3
	)
	if not result.ok:
		return _fail(name, "satır aralığı silme başarısız")
	if result.new_content != "a\nd":
		return _fail(name, "yanlış satırlar silindi")
	return _ok(name)


# ============================================================
# PROJECT WIDE RENAME
# ============================================================

static func _test_rename_basic() -> Dictionary:
	var name := "Rename temel yeniden adlandırma"
	var h := AIProjectWideRenameHandler.new()
	var result: AIProjectWideRenameHandler.RenameResult = h.rename_in_source(
		"var health = 100\nhealth += 10", "health", "hp"
	)
	if not result.ok:
		return _fail(name, "yeniden adlandırma başarısız")
	if result.replacements != 2:
		return _fail(name, "2 değişiklik bekleniyordu, %d" % result.replacements)
	return _ok(name)


static func _test_rename_word_boundary() -> Dictionary:
	var name := "Rename kelime sınırı duyarlı"
	var h := AIProjectWideRenameHandler.new()
	# 'health' değişmeli ama 'healthbar' değişmemeli
	var result: AIProjectWideRenameHandler.RenameResult = h.rename_in_source(
		"var health = 1\nvar healthbar = 2", "health", "hp"
	)
	if not result.ok:
		return _fail(name, "yeniden adlandırma başarısız")
	if result.replacements != 1:
		return _fail(name, "sadece tam sembol değişmeli (healthbar korunur)")
	if not result.new_content.contains("healthbar"):
		return _fail(name, "healthbar bozulmamalı")
	return _ok(name)


static func _test_rename_not_found() -> Dictionary:
	var name := "Rename bulunamayan sembol"
	var h := AIProjectWideRenameHandler.new()
	var result: AIProjectWideRenameHandler.RenameResult = h.rename_in_source(
		"bir kod", "olmayanSembol", "yeni"
	)
	if result.ok:
		return _fail(name, "bulunamayan sembol reddedilmeli")
	return _ok(name)


static func _test_rename_across_files() -> Dictionary:
	var name := "Rename çok dosya"
	var h := AIProjectWideRenameHandler.new()
	var files: Dictionary = {
		"a.gd": "var score = 0",
		"b.gd": "score = score + 1",
		"c.gd": "hiç ilgisi yok",
	}
	var result: Dictionary = h.rename_across_files(files, "score", "puan")
	if not result["ok"]:
		return _fail(name, "çok dosya yeniden adlandırma başarısız")
	# a.gd'de 1, b.gd'de 2, c.gd'de 0 = 3
	if int(result["total_replacements"]) != 3:
		return _fail(name, "3 toplam değişiklik bekleniyordu")
	return _ok(name)


# ============================================================
# MULTI STEP EDIT
# ============================================================

static func _test_multistep_sequence() -> Dictionary:
	var name := "MultiStep sıralı adımlar"
	var h := AIMultiStepEditHandler.new()
	var sr1: String = (
		AISearchReplaceHandler.SEARCH_MARKER + "\n\treturn 1\n"
		+ AISearchReplaceHandler.SEPARATOR + "\n\treturn 2\n"
		+ AISearchReplaceHandler.REPLACE_MARKER
	)
	var steps: Array = [
		h.make_search_replace_step(sr1, "değeri değiştir"),
	]
	var result: AIMultiStepEditHandler.MultiStepResult = h.apply_steps(
		"func f():\n\treturn 1\n", steps
	)
	if not result.ok:
		return _fail(name, "adım dizisi başarısız: %s" % result.rejected_reason)
	if result.steps_applied != 1:
		return _fail(name, "1 adım uygulanmalıydı")
	return _ok(name)


static func _test_multistep_atomic() -> Dictionary:
	var name := "MultiStep atomik geri alma"
	var h := AIMultiStepEditHandler.new()
	# İkinci adım başarısız olacak — bulunamayan SEARCH
	var good_sr: String = (
		AISearchReplaceHandler.SEARCH_MARKER + "\n\treturn 1\n"
		+ AISearchReplaceHandler.SEPARATOR + "\n\treturn 2\n"
		+ AISearchReplaceHandler.REPLACE_MARKER
	)
	var bad_sr: String = (
		AISearchReplaceHandler.SEARCH_MARKER + "\nvar olmayan kod\n"
		+ AISearchReplaceHandler.SEPARATOR + "\nyeni\n"
		+ AISearchReplaceHandler.REPLACE_MARKER
	)
	var steps: Array = [
		h.make_search_replace_step(good_sr),
		h.make_search_replace_step(bad_sr),
	]
	var original: String = "func f():\n\treturn 1\n"
	var result: AIMultiStepEditHandler.MultiStepResult = h.apply_steps(
		original, steps
	)
	if result.ok:
		return _fail(name, "başarısız adımlı dizi ok olmamalı")
	# Atomik: orijinal içerik korunmalı, yarım düzenleme yok
	if result.new_content != original:
		return _fail(name, "başarısızlıkta orijinal korunmalı (atomik)")
	if result.failed_step != 1:
		return _fail(name, "başarısız adım indeksi 1 olmalı")
	return _ok(name)


static func _test_multistep_empty() -> Dictionary:
	var name := "MultiStep boş dizi"
	var h := AIMultiStepEditHandler.new()
	var result: AIMultiStepEditHandler.MultiStepResult = h.apply_steps(
		"kod", []
	)
	if result.ok:
		return _fail(name, "boş adım dizisi reddedilmeli")
	return _ok(name)


# ============================================================
# EXPLICIT REPLACE
# ============================================================

static func _test_explicit_new_file() -> Dictionary:
	var name := "Explicit onaylı yeni dosya"
	var h := AIExplicitReplaceHandler.new()
	var result: AIExplicitReplaceHandler.ReplaceResult = h.apply(
		"", "yeni dosya tam içeriği", true
	)
	if not result.ok:
		return _fail(name, "onaylı yeni dosya başarısız")
	if not result.is_new_file:
		return _fail(name, "yeni dosya işaretlenmeli")
	return _ok(name)


static func _test_explicit_needs_approval() -> Dictionary:
	var name := "Explicit onaysız — onay bekler"
	var h := AIExplicitReplaceHandler.new()
	# Onaysız yeni dosya
	var result: AIExplicitReplaceHandler.ReplaceResult = h.apply(
		"", "içerik", false
	)
	if result.ok:
		return _fail(name, "onaysız değişim uygulanmamalı")
	if not result.needs_approval:
		return _fail(name, "onay gerekli işaretlenmeli")
	return _ok(name)


static func _test_explicit_small_change() -> Dictionary:
	var name := "Explicit küçük değişim — surgical öner"
	var h := AIExplicitReplaceHandler.new()
	# 20 satırlık dosya, sadece 1 satır değişiyor — full rewrite gereksiz
	var old_lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		old_lines.append("satir_%d" % i)
	var old_content: String = "\n".join(old_lines)
	var new_content: String = old_content.replace("satir_5", "DEGISTI")
	var result: AIExplicitReplaceHandler.ReplaceResult = h.apply(
		old_content, new_content, true
	)
	# Küçük değişim — reddedilmeli (surgical edit önerilir)
	if result.ok:
		return _fail(name, "küçük değişim tam-replace ile yapılmamalı")
	return _ok(name)


static func _test_explicit_approved() -> Dictionary:
	var name := "Explicit büyük değişim + onay"
	var h := AIExplicitReplaceHandler.new()
	# 20 satır, hepsi değişiyor — full rewrite haklı
	var old_lines: PackedStringArray = PackedStringArray()
	var new_lines: PackedStringArray = PackedStringArray()
	for i in range(20):
		old_lines.append("eski_%d" % i)
		new_lines.append("yeni_%d" % i)
	var result: AIExplicitReplaceHandler.ReplaceResult = h.apply(
		"\n".join(old_lines), "\n".join(new_lines), true
	)
	if not result.ok:
		return _fail(name, "büyük değişim + onay uygulanmalı")
	return _ok(name)
