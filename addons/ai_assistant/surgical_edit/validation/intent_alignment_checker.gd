@tool
class_name AIIntentAlignmentChecker
extends RefCounted

## IntentAlignmentChecker — niyet uyum denetleyicisi (Surgical Edit).
##
## Surgical Edit'in son doğrulama katmanı. Önceki dedektörler "format
## bozuldu mu", "yorum kayboldu mu", "kapsam taştı mı" diye bakar.
## Bu denetleyici daha üst soruyu sorar: YAPILAN DÜZENLEME, İSTENEN
## NİYETLE UYUŞUYOR MU?
##
## Örnek uyumsuzluklar:
##   - Niyet DELETE_CODE'du ama içerik büyüdü -> şüpheli
##   - Niyet ADD_TO_EXISTING'di ama içerik küçüldü -> şüpheli
##   - Niyet MODIFY_EXISTING_FUNCTION'dı ama hiç değişiklik yok -> şüpheli
##   - Niyet FIX_BUG_AT_LINE'dı ama dosya iki katına çıktı -> şüpheli
##
## Bu, niyet ile sonucun YÖNÜNÜ karşılaştırır — kesin doğruluk değil,
## "beklenen yönde mi" kontrolü. Sapma varsa işaretler, insan/QA bakar.
##
## Mock policy: uyum gerçek niyet + gerçek değişimden değerlendirilir.

## Uyum sonucu.
enum Alignment { ALIGNED, SUSPICIOUS, MISALIGNED }

const ALIGNMENT_NAMES: Dictionary = {
	Alignment.ALIGNED: "aligned",
	Alignment.SUSPICIOUS: "suspicious",
	Alignment.MISALIGNED: "misaligned",
}


## Niyet uyum analiz sonucu.
class AlignmentReport extends RefCounted:
	var alignment: int = AIIntentAlignmentChecker.Alignment.ALIGNED
	var intent_type: int = 0
	var size_before: int = 0           ## Satır sayısı öncesi
	var size_after: int = 0            ## Satır sayısı sonrası
	var size_delta: int = 0
	var note: String = ""

	## Düzenleme niyetle uyumlu mu (uyuşmazlık yok)?
	func is_aligned() -> bool:
		return alignment == AIIntentAlignmentChecker.Alignment.ALIGNED

	func to_dict() -> Dictionary:
		return {
			"alignment": AIIntentAlignmentChecker.ALIGNMENT_NAMES.get(
				alignment, "?"
			),
			"size_before": size_before,
			"size_after": size_after,
			"size_delta": size_delta,
			"note": note,
		}


# ============================================================
# UYUM DENETİMİ
# ============================================================

## Bir düzenlemenin niyetle uyumunu denetler.
## intent_type: AIEditIntent.IntentType. before / after: içerik.
## Dönen: AlignmentReport.
func check(intent_type: int, before: String, after: String) -> AlignmentReport:
	var report := AlignmentReport.new()
	report.intent_type = intent_type
	report.size_before = _line_count(before)
	report.size_after = _line_count(after)
	report.size_delta = report.size_after - report.size_before

	# Hiç değişiklik yok mu — bazı niyetler için bu sorun
	var no_change: bool = before == after

	match intent_type:
		AIEditIntent.IntentType.DELETE_CODE:
			_check_delete(report, no_change)
		AIEditIntent.IntentType.ADD_TO_EXISTING, \
		AIEditIntent.IntentType.ADD_NEW_FILE:
			_check_add(report, no_change)
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION, \
		AIEditIntent.IntentType.MODIFY_FUNCTION_SIGNATURE, \
		AIEditIntent.IntentType.FIX_BUG_AT_LINE:
			_check_modify(report, no_change)
		AIEditIntent.IntentType.RENAME_SYMBOL:
			_check_rename(report, no_change)
		_:
			# REFACTOR, REPLACE_FILE — geniş değişim normal
			report.alignment = Alignment.ALIGNED
			report.note = "Niyet geniş değişime izin verir"
	return report


## DELETE_CODE — içerik küçülmeli.
func _check_delete(report: AlignmentReport, no_change: bool) -> void:
	if no_change:
		report.alignment = Alignment.MISALIGNED
		report.note = "Silme niyeti ama hiçbir şey silinmedi"
	elif report.size_delta > 0:
		report.alignment = Alignment.SUSPICIOUS
		report.note = "Silme niyeti ama içerik büyüdü"
	else:
		report.alignment = Alignment.ALIGNED
		report.note = "Silme niyetiyle uyumlu — içerik küçüldü"


## ADD — içerik büyümeli.
func _check_add(report: AlignmentReport, no_change: bool) -> void:
	if no_change:
		report.alignment = Alignment.MISALIGNED
		report.note = "Ekleme niyeti ama hiçbir şey eklenmedi"
	elif report.size_delta < 0:
		report.alignment = Alignment.SUSPICIOUS
		report.note = "Ekleme niyeti ama içerik küçüldü"
	else:
		report.alignment = Alignment.ALIGNED
		report.note = "Ekleme niyetiyle uyumlu — içerik büyüdü"


## MODIFY / FIX — değişiklik olmalı ama ölçülü.
func _check_modify(report: AlignmentReport, no_change: bool) -> void:
	if no_change:
		report.alignment = Alignment.MISALIGNED
		report.note = "Değiştirme niyeti ama hiçbir değişiklik yok"
		return
	# Değişiklik dosyayı iki katına çıkardıysa şüpheli (scope creep işareti)
	if report.size_before > 0:
		var growth: float = float(report.size_after) / float(report.size_before)
		if growth > 2.0 or growth < 0.5:
			report.alignment = Alignment.SUSPICIOUS
			report.note = "Değiştirme niyeti ama boyut çok değişti (%.1fx)" % growth
			return
	report.alignment = Alignment.ALIGNED
	report.note = "Değiştirme niyetiyle uyumlu"


## RENAME — boyut neredeyse aynı kalmalı (sadece adlar değişir).
func _check_rename(report: AlignmentReport, no_change: bool) -> void:
	if no_change:
		report.alignment = Alignment.MISALIGNED
		report.note = "Yeniden adlandırma niyeti ama değişiklik yok"
	elif absi(report.size_delta) > 2:
		report.alignment = Alignment.SUSPICIOUS
		report.note = (
			"Yeniden adlandırma niyeti ama satır sayısı değişti "
			+ "(%d satır) — sadece ad değişmeliydi" % report.size_delta
		)
	else:
		report.alignment = Alignment.ALIGNED
		report.note = "Yeniden adlandırma niyetiyle uyumlu"


# ============================================================
# DAHİLİ
# ============================================================

## Bir içeriğin satır sayısı.
func _line_count(content: String) -> int:
	if content.is_empty():
		return 0
	return content.split("\n").size()
