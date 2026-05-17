@tool
class_name AIVerifierModel
extends RefCounted

## VerifierModel — Doğrulama sekmesi modeli (Layer 11 / Workspace).
##
## Layer 5 Verifier üretilen kodu denetler (sözdizimi, semantik).
## Bu model doğrulama sonuçlarını UI'da gösterilebilir biçime getirir:
## hangi dosya geçti, hangisi başarısız, ne hata var.
##
## Mock policy: doğrulama sonuçları gerçek Verifier'dan eklenir;
## model sonuç uydurmaz.

## Bir doğrulama sonucunun genel durumu.
enum VerifyOutcome { PASSED, FAILED, SKIPPED }

const OUTCOME_NAMES: Dictionary = {
	VerifyOutcome.PASSED: "Geçti",
	VerifyOutcome.FAILED: "Başarısız",
	VerifyOutcome.SKIPPED: "Atlandı",
}


## Tek bir dosyanın doğrulama kaydı.
class VerifyEntry extends RefCounted:
	var file_path: String = ""
	var outcome: int = AIVerifierModel.VerifyOutcome.PASSED
	var issues: PackedStringArray = PackedStringArray()  ## Bulunan sorunlar
	var level: String = ""             ## syntactic | semantic

	func is_passing() -> bool:
		return outcome == AIVerifierModel.VerifyOutcome.PASSED

	func to_dict() -> Dictionary:
		return {
			"file_path": file_path,
			"outcome": AIVerifierModel.OUTCOME_NAMES.get(outcome, "?"),
			"issue_count": issues.size(),
			"level": level,
		}


## Doğrulama kayıtları.
var _entries: Array = []


# ============================================================
# KAYIT
# ============================================================

## Bir doğrulama sonucu ekler.
## file_path: denetlenen dosya. outcome: PASSED/FAILED/SKIPPED.
## issues: bulunan sorunlar. level: doğrulama seviyesi.
func record(
	file_path: String, outcome: int, issues: PackedStringArray,
	level: String = ""
) -> void:
	var entry := VerifyEntry.new()
	entry.file_path = file_path
	if OUTCOME_NAMES.has(outcome):
		entry.outcome = outcome
	entry.issues = issues
	entry.level = level
	_entries.append(entry)


# ============================================================
# SORGULAMA
# ============================================================

## Toplam doğrulama kaydı.
func entry_count() -> int:
	return _entries.size()


## Belirli sonuçtaki kayıtlar.
func entries_with_outcome(outcome: int) -> Array:
	var matched: Array = []
	for entry in _entries:
		if (entry as VerifyEntry).outcome == outcome:
			matched.append(entry)
	return matched


## Geçen dosya sayısı.
func passed_count() -> int:
	return entries_with_outcome(VerifyOutcome.PASSED).size()


## Başarısız dosya sayısı.
func failed_count() -> int:
	return entries_with_outcome(VerifyOutcome.FAILED).size()


## Toplam bulunan sorun sayısı.
func total_issues() -> int:
	var total: int = 0
	for entry in _entries:
		total += (entry as VerifyEntry).issues.size()
	return total


## Tüm doğrulamalar geçti mi (başarısız yok)?
func all_passing() -> bool:
	return failed_count() == 0 and not _entries.is_empty()


## Doğrulama başarı oranı (0.0 - 1.0).
func pass_ratio() -> float:
	if _entries.is_empty():
		return 0.0
	return float(passed_count()) / float(_entries.size())


## Başarısız kayıtların dosya + sorun listesi — UI için.
func failure_details() -> Array:
	var details: Array = []
	for entry in entries_with_outcome(VerifyOutcome.FAILED):
		var e: VerifyEntry = entry
		details.append({
			"file": e.file_path,
			"issues": e.issues,
		})
	return details


# ============================================================
# UI
# ============================================================

## UI'da gösterilecek özet kartları.
func summary_cards() -> Array:
	return [
		{"label": "Toplam", "value": str(entry_count())},
		{"label": "Geçti", "value": str(passed_count())},
		{"label": "Başarısız", "value": str(failed_count())},
		{"label": "Sorun", "value": str(total_issues())},
		{"label": "Oran", "value": "%d%%" % int(pass_ratio() * 100.0)},
	]


## Tam durum.
func to_dict() -> Dictionary:
	return {
		"entry_count": entry_count(),
		"passed": passed_count(),
		"failed": failed_count(),
		"total_issues": total_issues(),
		"pass_ratio": pass_ratio(),
		"all_passing": all_passing(),
	}


## Kayıtları temizler.
func clear() -> void:
	_entries.clear()
