@tool
class_name AIIntegrityVerifier
extends RefCounted

## IntegrityVerifier — yazım sonrası bütünlük doğrulama (Layer 4).
##
## "Dosyayı yazdım" demek yetmez — "yazdığım DOĞRU" kanıtı gerekir.
## Executor bir dosya yazdıktan sonra bu sınıf doğrular:
##   1. Dosya gerçekten disk üzerinde var mı
##   2. İçerik MD5'i beklenen ile eşleşiyor mu (bit-bit doğruluk)
##   3. Boyut beklenen ile eşleşiyor mu
##
## Bu, sessiz veri bozulmasını yakalar: disk hatası, eksik yazım,
## kodlama sorunu. Mock policy: doğrulanmamış başarı, başarı sayılmaz.

## Bir dosyanın beklenen içerikle eşleşip eşleşmediğini doğrular.
## path: kontrol edilecek dosya. expected_content: ne yazılmış olmalı.
## Dönen: {ok: bool, reason: String, checks: Dictionary}
## checks: her bireysel kontrolün sonucu (exists/hash/size).
static func verify_written(path: String, expected_content: String) -> Dictionary:
	var checks: Dictionary = {
		"exists": false,
		"hash_match": false,
		"size_match": false,
	}

	# 1. Dosya var mı
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: dosya yazılmamış — %s" % path,
			"checks": checks,
		}
	checks["exists"] = true

	# Dosyayı oku
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: dosya okunamadı — %s" % path,
			"checks": checks,
		}
	var actual_content: String = f.get_as_text()
	f.close()

	# 2. İçerik hash eşleşmesi — bit-bit doğruluk
	var expected_hash: String = expected_content.md5_text()
	var actual_hash: String = actual_content.md5_text()
	checks["hash_match"] = (expected_hash == actual_hash)

	# 3. Boyut eşleşmesi (UTF-8 bayt uzunluğu)
	var expected_size: int = expected_content.to_utf8_buffer().size()
	var actual_size: int = actual_content.to_utf8_buffer().size()
	checks["size_match"] = (expected_size == actual_size)

	# Tüm kontroller geçmeli
	if not checks["hash_match"]:
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: içerik bozuk (hash uyuşmuyor) — %s" % path,
			"checks": checks,
		}
	if not checks["size_match"]:
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: boyut uyuşmuyor (%d != %d) — %s" % [
				actual_size, expected_size, path
			],
			"checks": checks,
		}

	return {"ok": true, "reason": "", "checks": checks}


## Bir dosyanın SİLİNDİĞİNİ doğrular — gerçekten yok olmuş mu.
## Dönen: {ok: bool, reason: String}
static func verify_deleted(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: dosya hâlâ var (silinmemiş) — %s" % path,
		}
	return {"ok": true, "reason": ""}


## Bir taşıma işlemini doğrular — kaynak yok, hedef var olmalı.
## Dönen: {ok: bool, reason: String}
static func verify_moved(from_path: String, to_path: String) -> Dictionary:
	if FileAccess.file_exists(from_path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: kaynak hâlâ var — %s" % from_path,
		}
	if not FileAccess.file_exists(to_path):
		return {
			"ok": false,
			"reason": "Doğrulama başarısız: hedef oluşmamış — %s" % to_path,
		}
	return {"ok": true, "reason": ""}


## Bir dosyanın MD5 imzasını döndürür — sonraki karşılaştırmalar için.
## Dosya yoksa boş string.
static func file_signature(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_md5(path)
