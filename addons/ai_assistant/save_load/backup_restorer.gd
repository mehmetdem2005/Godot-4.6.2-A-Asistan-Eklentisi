@tool
class_name AISaveBackupRestorer
extends RefCounted

## BackupRestorer — yedekten geri yükleme (Madde 09 / Save/Load / backup).
##
## Ana kayıt bozulduğunda yedekler devreye girer. Ama hangi yedek?
## En yenisi de bozuk olabilir. Bu sınıf yedekleri EN YENİDEN EN
## ESKİYE doğra dener — ilk SAĞLAM olanı bulur.
##
## "Mock yasak": her yedeği "sağlam" varsaymaz. Her aday için
## bütünlük kontrolü (dışarıdan verilen) sonucuna bakar — gerçekten
## sağlam olanı seçer, yoksa açıkça "kurtarılamaz" der.
##
## Bu sınıf geri-yükleme STRATEJİSİNİ üretir; gerçek okuma/doğrulama
## integrity_verifier + atomic_writer'ın işi.
##
## Mock policy: seçim gerçek bütünlük sonuçlarından.

## Bir geri-yükleme sonucu.
class RestoreResult extends RefCounted:
	var success: bool = false
	var chosen_backup: String = ""    ## Seçilen sağlam yedek
	var chosen_index: int = -1        ## Yedek indeksi
	var tried_count: int = 0          ## Kaç yedek denendi
	var reason: String = ""

	func to_dict() -> Dictionary:
		return {
			"success": success,
			"chosen_backup": chosen_backup,
			"chosen_index": chosen_index,
			"tried_count": tried_count,
		}


## Yedek rotasyon yardımcısı.
var _rotator: AISaveBackupRotator


func _init(rotator: AISaveBackupRotator = null) -> void:
	if rotator != null:
		_rotator = rotator
	else:
		_rotator = AISaveBackupRotator.new()


# ============================================================
# GERİ YÜKLEME SEÇİMİ
# ============================================================

## En yeni sağlam yedeği seçer.
## base_path: ana kayıt yolu.
## integrity_results: yedek indeksi -> sağlam mı (bool).
##   Çağıran her yedeğin bütünlüğünü kontrol edip bu sözlüğü verir.
## Dönen: RestoreResult.
func select_restore_source(
	base_path: String, integrity_results: Dictionary
) -> RestoreResult:
	var result := RestoreResult.new()

	# En yeniden en eskiye doğru dene (index 1 = en yeni)
	for index in range(1, _rotator.backup_count + 1):
		# Bu yedek için bütünlük sonucu var mı
		if not integrity_results.has(index):
			continue
		result.tried_count += 1
		# Sağlam mı
		if bool(integrity_results[index]):
			result.success = true
			result.chosen_index = index
			result.chosen_backup = _rotator.backup_name(
				base_path, index
			)
			result.reason = "Yedek %d sağlam — geri yüklenecek" % index
			return result

	# Hiçbir yedek sağlam değil
	result.success = false
	result.reason = "Hiçbir yedek kurtarılamadı (%d denendi)" % \
		result.tried_count
	return result


# ============================================================
# SORGULAMA
# ============================================================

## Herhangi bir sağlam yedek var mı?
func has_recoverable_backup(integrity_results: Dictionary) -> bool:
	for index in integrity_results:
		if bool(integrity_results[index]):
			return true
	return false


## Kaç sağlam yedek var?
func recoverable_count(integrity_results: Dictionary) -> int:
	var count: int = 0
	for index in integrity_results:
		if bool(integrity_results[index]):
			count += 1
	return count
