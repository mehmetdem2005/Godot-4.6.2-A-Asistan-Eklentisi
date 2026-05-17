@tool
class_name AIScopeCreepDetector
extends RefCounted

## ScopeCreepDetector — kapsam taşması dedektörü (Surgical Edit / doğrulama).
##
## LLM'in bir başka kötü alışkanlığı: "tek satır düzelt" denince
## 200 satır değiştirmek. Niyet bir fonksiyonu düzeltmekti ama LLM
## "bu arada şunu da iyileştireyim" diyerek başka yerlere dokundu.
##
## Bu dedektör değişikliğin BEKLENEN KAPSAM içinde kalıp kalmadığını
## kontrol eder. ScopeExtractor LLM'e belli bir pencere vermişti;
## değişiklik o pencerenin dışına taşıyorsa = scope creep.
##
## Ölçüm: kaç satır değişti, beklenen kapsama göre oran ne.
##
## Mock policy: taşma gerçek satır karşılaştırmasından ölçülür.

## Kapsam taşması seviyesi.
enum CreepLevel { NONE, MINOR, MAJOR }

const CREEP_LEVEL_NAMES: Dictionary = {
	CreepLevel.NONE: "none",
	CreepLevel.MINOR: "minor",
	CreepLevel.MAJOR: "major",
}

## Beklenen kapsamın bu katından fazla değişim — MAJOR taşma.
const MAJOR_CREEP_MULTIPLIER: float = 2.0

## Beklenen kapsamın bu katından fazla — MINOR taşma.
const MINOR_CREEP_MULTIPLIER: float = 1.3


## Kapsam taşması analiz sonucu.
class ScopeCreepReport extends RefCounted:
	var level: int = AIScopeCreepDetector.CreepLevel.NONE
	var changed_lines: int = 0
	var expected_lines: int = 0        ## Beklenen değişim kapsamı
	var creep_ratio: float = 0.0       ## changed / expected
	var note: String = ""

	## Düzenleme kapsam içinde mi (taşma yok/küçük)?
	func is_within_scope() -> bool:
		return level != AIScopeCreepDetector.CreepLevel.MAJOR

	func to_dict() -> Dictionary:
		return {
			"level": AIScopeCreepDetector.CREEP_LEVEL_NAMES.get(level, "?"),
			"changed_lines": changed_lines,
			"expected_lines": expected_lines,
			"creep_ratio": creep_ratio,
			"within_scope": is_within_scope(),
			"note": note,
		}


# ============================================================
# TESPİT
# ============================================================

## Bir düzenlemenin kapsam taşmasını ölçer.
## before / after: düzenleme öncesi ve sonrası tam içerik.
## expected_change_lines: beklenen değişim kapsamı (intent'ten gelir).
## Dönen: ScopeCreepReport.
func detect(
	before: String, after: String, expected_change_lines: int
) -> ScopeCreepReport:
	var report := ScopeCreepReport.new()
	report.expected_lines = maxi(expected_change_lines, 1)

	# Gerçekte kaç satır değişti
	report.changed_lines = _count_changed_lines(before, after)

	# Beklenene göre oran
	report.creep_ratio = (
		float(report.changed_lines) / float(report.expected_lines)
	)

	# Seviye belirle
	if report.creep_ratio > MAJOR_CREEP_MULTIPLIER:
		report.level = CreepLevel.MAJOR
		report.note = (
			"Büyük kapsam taşması: %d satır değişti, ~%d bekleniyordu"
			% [report.changed_lines, report.expected_lines]
		)
	elif report.creep_ratio > MINOR_CREEP_MULTIPLIER:
		report.level = CreepLevel.MINOR
		report.note = (
			"Küçük kapsam taşması: beklenenden biraz fazla değişim"
		)
	else:
		report.level = CreepLevel.NONE
		report.note = "Değişiklik beklenen kapsam içinde"
	return report


## Belirli bir satır aralığı dışına değişiklik taşıp taşmadığını
## kontrol eder — daha kesin kapsam denetimi.
## allowed_start / allowed_end: izin verilen değişim aralığı (1-tabanlı).
func detect_outside_range(
	before: String, after: String, allowed_start: int, allowed_end: int
) -> ScopeCreepReport:
	var report := ScopeCreepReport.new()
	var before_lines: PackedStringArray = before.split("\n")
	var after_lines: PackedStringArray = after.split("\n")

	# İzin verilen aralık DIŞINDA değişen satır var mı
	var outside_changes: int = 0
	var min_len: int = mini(before_lines.size(), after_lines.size())
	for i in range(min_len):
		var line_no: int = i + 1
		if line_no >= allowed_start and line_no <= allowed_end:
			continue  # izin verilen aralık — değişebilir
		if before_lines[i] != after_lines[i]:
			outside_changes += 1

	report.changed_lines = outside_changes
	report.expected_lines = 0  # aralık dışı: hiç değişim beklenmiyor
	if outside_changes == 0:
		report.level = CreepLevel.NONE
		report.note = "Değişiklik izin verilen aralıkta kaldı"
	elif outside_changes <= 2:
		report.level = CreepLevel.MINOR
		report.note = "%d satır izin verilen aralık dışında" % outside_changes
	else:
		report.level = CreepLevel.MAJOR
		report.note = (
			"%d satır izin verilen aralık dışında değişti — kapsam taşması"
			% outside_changes
		)
	return report


# ============================================================
# DAHİLİ
# ============================================================

## İki içerik arasında değişen satır sayısını sayar.
## Satır-tabanlı: öncesinde olmayan her sonraki satır + tersi.
func _count_changed_lines(before: String, after: String) -> int:
	var before_lines: PackedStringArray = before.split("\n")
	var after_lines: PackedStringArray = after.split("\n")

	# Öncesi satırları çoklukla say (aynı satır birden çok olabilir)
	var before_counts: Dictionary = {}
	for line in before_lines:
		before_counts[line] = int(before_counts.get(line, 0)) + 1

	# Sonrasında öncesinde dengi olmayan satırlar
	var changed: int = 0
	for line in after_lines:
		var avail: int = int(before_counts.get(line, 0))
		if avail > 0:
			before_counts[line] = avail - 1
		else:
			changed += 1
	# Silinen satırlar da değişim — kalan before_counts
	var deleted: int = 0
	for line in before_counts:
		deleted += int(before_counts[line])
	return changed + deleted
