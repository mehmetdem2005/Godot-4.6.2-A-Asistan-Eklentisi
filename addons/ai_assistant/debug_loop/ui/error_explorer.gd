@tool
class_name AIDebugErrorExplorer
extends RefCounted

## ErrorExplorer — hata gezgini (Madde 02 / debug_loop / ui).
##
## Yakalanan tüm hataların görsel listesi: her hata bir satır
## (mesaj, ciddiyet, dosya), tıklanınca detay + AI'ın önerdiği
## düzeltme. Geliştirici hataları gözden geçirir, düzeltme uygular.
##
## Bu view-model hata listesini tutar, ciddiyete göre sıralar/
## filtreler, her hata için fix önerisi durumunu yönetir.
##
## debug_loop hata yakalama + ErrorReport (mantık katmanı) ile
## beslenir.
##
## Mock policy: liste gerçek yakalanan hatalardan.

## Hata ciddiyet seviyeleri (yüksek = daha ciddi).
enum Severity { INFO, WARNING, ERROR, CRITICAL }

const SEVERITY_NAMES: Dictionary = {
	Severity.INFO: "info",
	Severity.WARNING: "warning",
	Severity.ERROR: "error",
	Severity.CRITICAL: "critical",
}

const SEVERITY_COLOR: Dictionary = {
	Severity.INFO: "#2196f3",
	Severity.WARNING: "#ff9800",
	Severity.ERROR: "#f44336",
	Severity.CRITICAL: "#b71c1c",
}


## Bir hata kaydının görsel girdisi.
class ErrorEntry extends RefCounted:
	var error_id: String = ""
	var message: String = ""
	var severity: int = AIDebugErrorExplorer.Severity.ERROR
	var file_path: String = ""
	var line: int = 0
	## AI'ın önerdiği düzeltme (yoksa boş).
	var fix_suggestion: String = ""
	## Hata çözüldü olarak işaretlendi mi.
	var resolved: bool = false

	func to_dict() -> Dictionary:
		return {
			"id": error_id, "message": message,
			"severity": severity, "file": file_path,
			"line": line, "has_fix": not fix_suggestion.is_empty(),
			"resolved": resolved,
		}


## Hata girdileri — error_id -> ErrorEntry.
var _errors: Dictionary = {}

## Aktif ciddiyet filtresi (-1 = filtre yok).
var severity_filter: int = -1

## Çözülmüş hataları gizle.
var hide_resolved: bool = false


# ============================================================
# HATA EKLEME
# ============================================================

## Bir hata kaydı ekler.
## error_id: benzersiz kimlik. message: hata mesajı.
## severity: ciddiyet. file_path/line: konum.
## Dönen: true = eklendi.
func add_error(
	error_id: String, message: String, severity: int,
	file_path: String, line: int
) -> bool:
	if error_id.is_empty():
		return false
	if not SEVERITY_NAMES.has(severity):
		return false
	var entry := ErrorEntry.new()
	entry.error_id = error_id
	entry.message = message
	entry.severity = severity
	entry.file_path = file_path
	entry.line = line
	_errors[error_id] = entry
	return true


## Bir hataya AI düzeltme önerisi ekler.
## error_id: hata kimliği. suggestion: önerilen düzeltme.
## Dönen: true = hata bulundu ve öneri eklendi.
func attach_fix(error_id: String, suggestion: String) -> bool:
	if not _errors.has(error_id):
		return false
	(_errors[error_id] as ErrorEntry).fix_suggestion = suggestion
	return true


## Bir hatayı çözüldü olarak işaretler.
func mark_resolved(error_id: String) -> bool:
	if not _errors.has(error_id):
		return false
	(_errors[error_id] as ErrorEntry).resolved = true
	return true


# ============================================================
# FİLTRELEME
# ============================================================

## Ciddiyet filtresi ayarlar. -1 = filtre yok.
func set_severity_filter(severity: int) -> void:
	if severity == -1 or SEVERITY_NAMES.has(severity):
		severity_filter = severity


## Çözülmüş hataların gizlenip gizlenmeyeceğini ayarlar.
func set_hide_resolved(hide: bool) -> void:
	hide_resolved = hide


## Bir hatanın mevcut filtrelerden geçip geçmediğini kontrol eder.
func _passes_filter(entry: ErrorEntry) -> bool:
	if severity_filter != -1 and entry.severity != severity_filter:
		return false
	if hide_resolved and entry.resolved:
		return false
	return true


# ============================================================
# SUNUM
# ============================================================

## Filtrelenmiş hata listesini ciddiyete göre sıralı üretir.
## Dönen: ErrorEntry.to_dict() + {severity_name, color} dizi.
func build_list() -> Array:
	var filtered: Array = []
	for error_id in _errors:
		var entry: ErrorEntry = _errors[error_id]
		if _passes_filter(entry):
			filtered.append(entry)

	# Ciddiyete göre sırala — en ciddi üstte
	filtered.sort_custom(func(a: ErrorEntry, b: ErrorEntry) -> bool:
		return a.severity > b.severity)

	var list: Array = []
	for entry_obj in filtered:
		var entry: ErrorEntry = entry_obj
		var row: Dictionary = entry.to_dict()
		row["severity_name"] = SEVERITY_NAMES.get(entry.severity, "?")
		row["color"] = SEVERITY_COLOR.get(entry.severity, "#9e9e9e")
		list.append(row)
	return list


## Bir hatanın detay görünümünü üretir.
## Dönen: hata detayı + fix önerisi, hata yoksa boş sözlük.
func build_detail(error_id: String) -> Dictionary:
	if not _errors.has(error_id):
		return {}
	var entry: ErrorEntry = _errors[error_id]
	return {
		"id": entry.error_id,
		"message": entry.message,
		"severity_name": SEVERITY_NAMES.get(entry.severity, "?"),
		"location": "%s:%d" % [entry.file_path, entry.line],
		"fix_suggestion": entry.fix_suggestion,
		"has_fix": not entry.fix_suggestion.is_empty(),
		"resolved": entry.resolved,
	}


# ============================================================
# SORGULAMA
# ============================================================

## Toplam hata sayısı.
func error_count() -> int:
	return _errors.size()


## Çözülmemiş hata sayısı.
func unresolved_count() -> int:
	var count: int = 0
	for error_id in _errors:
		if not (_errors[error_id] as ErrorEntry).resolved:
			count += 1
	return count


## Belirli ciddiyetteki hata sayısı.
func count_by_severity(severity: int) -> int:
	var count: int = 0
	for error_id in _errors:
		if (_errors[error_id] as ErrorEntry).severity == severity:
			count += 1
	return count


## Kritik çözülmemiş hata var mı?
func has_critical_unresolved() -> bool:
	for error_id in _errors:
		var entry: ErrorEntry = _errors[error_id]
		if entry.severity == Severity.CRITICAL and not entry.resolved:
			return true
	return false
