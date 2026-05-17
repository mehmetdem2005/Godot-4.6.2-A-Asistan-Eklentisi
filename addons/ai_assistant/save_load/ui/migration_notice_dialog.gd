@tool
class_name AISaveMigrationDialog
extends RefCounted

## MigrationNoticeDialog — geçiş bildirim diyalogu (Madde 09 / ui).
##
## Eski bir kayıt yeni oyun sürümünde açıldığında, kayıt güncel
## şemaya taşınır (migration). Bu diyalog kullanıcıyı bilgilendirir:
## "Kaydınız eski sürümden — güncellendi."
##
## Çoğu durumda bilgilendirme yeterli (otomatik geçiş başarılı). Ama
## geçiş başarısız olursa diyalog uyarı verir.
##
## Bu view-model diyaloğun içeriğini geçiş sonucundan üretir.
##
## migration_engine + version_compatibility_checker (mantık katmanı)
## ile beslenir.
##
## Mock policy: diyalog içeriği gerçek geçiş sonucundan.

## Diyalog türü — geçiş sonucuna göre.
enum NoticeType { MIGRATION_SUCCESS, MIGRATION_FAILED, VERSION_TOO_NEW }

const NOTICE_NAMES: Dictionary = {
	NoticeType.MIGRATION_SUCCESS: "migration_success",
	NoticeType.MIGRATION_FAILED: "migration_failed",
	NoticeType.VERSION_TOO_NEW: "version_too_new",
}


## Diyalog türü.
var notice_type: int = NoticeType.MIGRATION_SUCCESS

## Kaydın eski sürümü.
var from_version: int = 0

## Hedef (güncel) sürüm.
var to_version: int = 0


# ============================================================
# DİYALOG HAZIRLAMA
# ============================================================

## Başarılı geçiş bildirimi hazırlar.
## p_from: eski sürüm. p_to: yeni sürüm.
func prepare_success(p_from: int, p_to: int) -> void:
	notice_type = NoticeType.MIGRATION_SUCCESS
	from_version = p_from
	to_version = p_to


## Başarısız geçiş bildirimi hazırlar.
func prepare_failure(p_from: int, p_to: int) -> void:
	notice_type = NoticeType.MIGRATION_FAILED
	from_version = p_from
	to_version = p_to


## "Kayıt çok yeni" bildirimi hazırlar.
## (kayıt oyundan yeni — downgrade durumu, yüklenemez)
func prepare_too_new(p_from: int, p_to: int) -> void:
	notice_type = NoticeType.VERSION_TOO_NEW
	from_version = p_from
	to_version = p_to


# ============================================================
# SUNUM
# ============================================================

## Diyaloğun başlığını üretir.
func title_text() -> String:
	match notice_type:
		NoticeType.MIGRATION_SUCCESS:
			return "Kayıt Güncellendi"
		NoticeType.MIGRATION_FAILED:
			return "Kayıt Güncellenemedi"
		NoticeType.VERSION_TOO_NEW:
			return "Uyumsuz Kayıt"
		_:
			return "Bilgi"


## Diyaloğun mesajını üretir.
func message_text() -> String:
	match notice_type:
		NoticeType.MIGRATION_SUCCESS:
			return "Kaydınız eski bir sürümden (v%d) güncel " % \
				from_version + "sürüme (v%d) taşındı." % to_version
		NoticeType.MIGRATION_FAILED:
			return "Kaydınız (v%d) güncel sürüme taşınamadı. " % \
				from_version + "Yedekten geri yükleme denenebilir."
		NoticeType.VERSION_TOO_NEW:
			return "Bu kayıt (v%d) oyunun bu sürümünden (v%d) " % [
				from_version, to_version
			] + "daha yeni. Oyunu güncelleyin."
		_:
			return ""


## Diyalog butonlarının tanımını üretir.
func button_options() -> Array:
	match notice_type:
		NoticeType.MIGRATION_SUCCESS:
			# Sadece bilgilendirme — tek buton
			return [{"choice": "ok", "label": "Devam Et"}]
		NoticeType.MIGRATION_FAILED:
			# Yedek seçeneği sun
			return [
				{"choice": "restore", "label": "Yedekten Geri Yükle"},
				{"choice": "cancel", "label": "İptal"},
			]
		NoticeType.VERSION_TOO_NEW:
			return [{"choice": "ok", "label": "Tamam"}]
		_:
			return [{"choice": "ok", "label": "Tamam"}]


# ============================================================
# SORGULAMA
# ============================================================

## Bu sadece bir bilgilendirme mi (kullanıcı eylemi gerekmez)?
func is_informational() -> bool:
	return notice_type == NoticeType.MIGRATION_SUCCESS \
		or notice_type == NoticeType.VERSION_TOO_NEW


## Diyalog bir sorun mu bildiriyor?
func is_problem() -> bool:
	return notice_type == NoticeType.MIGRATION_FAILED \
		or notice_type == NoticeType.VERSION_TOO_NEW


## Diyalog türünün adı.
func notice_name() -> String:
	return NOTICE_NAMES.get(notice_type, "?")
