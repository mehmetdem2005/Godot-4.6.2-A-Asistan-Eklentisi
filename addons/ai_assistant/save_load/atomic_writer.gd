@tool
class_name AISaveAtomicWriter
extends RefCounted

## AtomicWriter — atomik kayıt yazıcı (Madde 09 / Save-Load).
##
## Save/Load'ın 1 NUMARALI invariant'ı: "yarım save imkansız".
## Senaryo: oyuncu kaydederken telefonun pili biter / oyun çöker.
## Eğer doğrudan kayıt dosyasına yazıyorsak, dosya yarım kalır —
## oyuncunun tüm ilerlemesi bozulur. KABUL EDİLEMEZ.
##
## Çözüm — atomik yazma deseni:
##   1. Veriyi GEÇİCİ dosyaya yaz (save.json.tmp)
##   2. Yazma tam bittiyse, geçici dosyayı asıl dosyaya RENAME et
##   3. Rename işletim sistemi düzeyinde atomiktir — ya olur ya olmaz
##
## Sonuç: asıl kayıt dosyası her zaman ya eski tam hali ya yeni tam
## hali — asla yarım. Çökme tmp dosyasını bırakır, asıl dosya sağlam.
##
## WAL kurtarma: başlangıçta ortada kalmış .tmp varsa temizlenir.
##
## Mock policy: yazma gerçek dosya sistemine yapılır; başarı
## gerçekten diske yazıldığında raporlanır.

## Geçici dosya uzantısı.
const TEMP_SUFFIX: String = ".tmp"


## Bir yazma işleminin sonucu.
class WriteResult extends RefCounted:
	var ok: bool = false
	var path: String = ""
	var bytes_written: int = 0
	var error: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"path": path,
			"bytes_written": bytes_written,
			"error": error,
		}


# ============================================================
# ATOMİK YAZMA
# ============================================================

## Bir içeriği atomik olarak diske yazar.
## path: hedef dosya yolu. content: yazılacak metin.
## Dönen: WriteResult.
##
## Adımlar: tmp'ye yaz -> doğrula -> rename. Herhangi bir adım
## başarısızsa asıl dosyaya DOKUNULMAZ.
func write(path: String, content: String) -> WriteResult:
	var result := WriteResult.new()
	result.path = path

	if path.strip_edges().is_empty():
		result.error = "Hedef yol boş"
		return result

	var temp_path: String = path + TEMP_SUFFIX

	# --- Adım 1: geçici dosyaya yaz ---
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		result.error = "Geçici dosya açılamadı: %s (kod %d)" % [
			temp_path, FileAccess.get_open_error()
		]
		return result
	temp_file.store_string(content)
	temp_file.close()

	# --- Adım 2: geçici dosyayı doğrula — gerçekten yazıldı mı ---
	if not FileAccess.file_exists(temp_path):
		result.error = "Geçici dosya yazıldıktan sonra bulunamadı"
		return result
	var verify := FileAccess.open(temp_path, FileAccess.READ)
	if verify == null:
		result.error = "Geçici dosya doğrulama için açılamadı"
		return result
	var written: String = verify.get_as_text()
	verify.close()
	if written != content:
		result.error = "Geçici dosya içeriği yazılanla eşleşmiyor"
		# Bozuk tmp'yi temizle
		_remove_if_exists(temp_path)
		return result

	# --- Adım 3: atomik rename — tmp asıl dosyanın yerine geçer ---
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		result.error = "Hedef dizin açılamadı"
		_remove_if_exists(temp_path)
		return result
	var rename_err: int = dir.rename(temp_path, path)
	if rename_err != OK:
		result.error = "Atomik rename başarısız (kod %d)" % rename_err
		_remove_if_exists(temp_path)
		return result

	result.bytes_written = content.to_utf8_buffer().size()
	result.ok = true
	return result


# ============================================================
# WAL KURTARMA
# ============================================================

## Bir dizinde ortada kalmış .tmp dosyalarını temizler.
## Çökme sonrası başlangıçta çağrılır — yarım yazma kalıntıları
## asıl kayıtları etkilememeli.
## Dönen: temizlenen .tmp dosya sayısı.
func recover_orphan_temps(directory: String) -> int:
	var dir := DirAccess.open(directory)
	if dir == null:
		return 0
	var cleaned: int = 0
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(TEMP_SUFFIX):
			var full_path: String = directory.path_join(file_name)
			if dir.remove(full_path) == OK:
				cleaned += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return cleaned


## Bir dosyada yarım yazma (.tmp) kalıntısı var mı kontrol eder.
func has_orphan_temp(path: String) -> bool:
	return FileAccess.file_exists(path + TEMP_SUFFIX)


# ============================================================
# DAHİLİ
# ============================================================

## Bir dosya varsa siler — sessizce.
func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		var dir := DirAccess.open(path.get_base_dir())
		if dir != null:
			dir.remove(path)
