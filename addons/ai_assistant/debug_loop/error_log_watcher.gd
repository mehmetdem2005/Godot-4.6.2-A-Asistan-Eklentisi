@tool
class_name AIErrorLogWatcher
extends RefCounted

## ErrorLogWatcher — Godot log dosyasını artımlı okur ve hata
## satırlarını çıkarır (Parça 4: otonom hata düzeltme — kullanıcı
## isteği "outbot/script loglarında hata olursa bana sormadan düzelt").
##
## SORUN: debug_loop sınıflandırma + retry + circuit breaker MANTIK'ı
## tamdı ama gerçek Godot hata kaynağına BAĞLI değildi. Editör Output
## paneli için kararlı bir public API yok; çözüm: user://logs/godot.log
## (Godot'un kendi log dosyası) artımlı oku, hata satırlarını
## AIDebugErrorClassifier ile tanı.
##
## SAF: bu sınıf sadece DOSYA okur ve veri döner; LLM çağırmaz,
## düzeltme uygulamaz (o iş Router'da). Headless TAM test edilebilir.
##
## Rotasyon güvenli: dosya boyutu küçülürse cursor 0'a sıfırlanır
## (yeni log başlamış). Dosya yoksa boş dönüş — sahte hata YOK.

## Bir Godot hata satırını tetikleyen önekler (hep büyük harf görünür).
const ERROR_PREFIXES: Array = [
	"SCRIPT ERROR",
	"USER ERROR",
	"ERROR:",
	"USER SCRIPT ERROR",
	"CORE ERROR",
]

var _log_path: String = ""
var _cursor: int = 0
var _classifier: AIDebugErrorClassifier = null


func _init(p_log_path: String = "") -> void:
	_log_path = p_log_path
	_classifier = AIDebugErrorClassifier.new()


func set_log_path(p_path: String) -> void:
	_log_path = p_path
	_cursor = 0


func cursor() -> int:
	return _cursor


## Cursor'dan itibaren yeni satırları okuyup hata olaylarını döner.
## Her olay: {raw, line_no, file_path, category, signature}.
## file_path: hata satırında dosya yolu varsa (./ veya res://) çıkarılır.
## signature: kararlı imza (kategori + sembol + dosya); satırdan
## bağımsız — circuit breaker bu imzayı kullanır.
func poll() -> Array:
	var events: Array = []
	if _log_path.is_empty() or not FileAccess.file_exists(_log_path):
		return events

	var f: FileAccess = FileAccess.open(_log_path, FileAccess.READ)
	if f == null:
		return events
	var size: int = int(f.get_length())
	# Rotasyon: dosya küçülmüş → yeniden başla (sahte fark üretme)
	if size < _cursor:
		_cursor = 0
	if size == _cursor:
		f.close()
		return events
	f.seek(_cursor)
	var fresh: String = f.get_buffer(size - _cursor).get_string_from_utf8()
	_cursor = size
	f.close()

	var lines: PackedStringArray = fresh.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		if not _looks_like_error(line):
			continue
		var follow: String = ""
		if i + 1 < lines.size():
			follow = lines[i + 1]
		events.append(_make_event(line, follow))
	return events


## Bir satır hata mı?
func _looks_like_error(line: String) -> bool:
	var trimmed: String = line.strip_edges()
	for pref in ERROR_PREFIXES:
		if trimmed.begins_with(pref):
			return true
	return false


## Hata satırı (+ olası "   at: ..." takip satırı) → olay sözlüğü.
func _make_event(line: String, follow_line: String) -> Dictionary:
	var cls: AIDebugErrorClassifier.ErrorClass = _classifier.classify(line)
	var file_path: String = _extract_file_path(line)
	if file_path.is_empty():
		file_path = _extract_file_path(follow_line)
	var line_no: int = cls.line
	if line_no < 0:
		line_no = _extract_line_no(follow_line)
	var sig: String = "%s|%s|%s" % [
		cls.category_name(), cls.symbol, file_path
	]
	return {
		"raw": line.strip_edges(),
		"line_no": line_no,
		"file_path": file_path,
		"category": cls.category_name(),
		"signature": sig,
	}


## Bir metin parçasından res:// veya ./ ile başlayan .gd yolu çıkarır.
## ':' protokolün kendi karakteri olduğu için yalnız önekten SONRA
## durak aranır (yoksa "res://" içindeki ':' yolu zamansız keser).
func _extract_file_path(text: String) -> String:
	for token in ["res://", "./"]:
		var idx: int = text.find(token)
		if idx < 0:
			continue
		var rest: String = text.substr(idx)
		var search_from: int = token.length()
		var end: int = rest.length()
		for stop in [" ", ")", ":", "\n", "\r", "\t", ","]:
			var sidx: int = rest.find(stop, search_from)
			if sidx > 0 and sidx < end:
				end = sidx
		var path: String = rest.substr(0, end)
		if path.ends_with(".gd"):
			if path.begins_with("./"):
				path = "res://" + path.substr(2)
			return path
	return ""


## ".gd:42" örüntüsünden satır numarası çıkarır.
func _extract_line_no(text: String) -> int:
	var marker: String = ".gd:"
	var idx: int = text.find(marker)
	if idx < 0:
		return -1
	var rest: String = text.substr(idx + marker.length())
	var digits: String = ""
	for ch in rest:
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	if digits.is_empty():
		return -1
	return int(digits)
