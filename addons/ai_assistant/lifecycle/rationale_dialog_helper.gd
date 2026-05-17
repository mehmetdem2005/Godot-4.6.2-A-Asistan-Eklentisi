@tool
class_name AILifecycleRationaleHelper
extends RefCounted

## RationaleDialogHelper — gerekçe diyalog yardımcısı (Madde 10).
##
## Bir izin reddedilmişse, tekrar istemeden ÖNCE kullanıcıya "bu izin
## neden gerekli" diye açıklamak gerekir. İyi bir gerekçe metni izin
## verme oranını ciddi artırır.
##
## Bu sınıf her izin için HAZIR gerekçe metinleri sunar — açık,
## kullanıcı-dostu, oyuncunun anlayacağı dilde. Geliştirici kendi
## metnini de verebilir.
##
## Mock policy: gerekçeler sabit, kullanıcı-dostu Türkçe metinler.

## İzin -> gerekçe metni eşlemesi.
const RATIONALES: Dictionary = {
	"microphone": "Sesli sohbet ve sesli komutlar için mikrofon "
		+ "erişimi gerekli. Ses kaydı yapılmaz, sadece oyun içinde "
		+ "kullanılır.",
	"camera": "Profil fotoğrafı çekmek veya artırılmış gerçeklik "
		+ "özellikleri için kamera erişimi gerekli.",
	"storage": "Oyun kayıtlarını ve ekran görüntülerini cihaza "
		+ "kaydetmek için depolama erişimi gerekli.",
	"notifications": "Oyun olayları, günlük ödüller ve etkinlikler "
		+ "hakkında haberdar olmak için bildirim izni gerekli.",
	"location": "Konum tabanlı oyun özellikleri için konum erişimi "
		+ "gerekli. Konumunuz paylaşılmaz.",
}

## Gerekçe başlıkları.
const TITLES: Dictionary = {
	"microphone": "Mikrofon İzni",
	"camera": "Kamera İzni",
	"storage": "Depolama İzni",
	"notifications": "Bildirim İzni",
	"location": "Konum İzni",
}


## Geliştirici tarafından özelleştirilmiş gerekçeler.
var _custom_rationales: Dictionary = {}


# ============================================================
# GEREKÇE ERİŞİMİ
# ============================================================

## Bir izin için gerekçe metnini döndürür.
## Özel metin tanımlıysa o, değilse hazır metin, hiçbiri yoksa
## genel bir metin.
func get_rationale(permission: String) -> String:
	if _custom_rationales.has(permission):
		return str(_custom_rationales[permission])
	if RATIONALES.has(permission):
		return str(RATIONALES[permission])
	return "Bu özellik için '%s' izni gerekli." % permission


## Bir izin için diyalog başlığını döndürür.
func get_title(permission: String) -> String:
	if TITLES.has(permission):
		return str(TITLES[permission])
	return "İzin Gerekli"


## Tam diyalog içeriğini döndürür — başlık + metin + butonlar.
func build_dialog(permission: String) -> Dictionary:
	return {
		"title": get_title(permission),
		"message": get_rationale(permission),
		"confirm_label": "İzin Ver",
		"cancel_label": "Şimdi Değil",
	}


# ============================================================
# ÖZELLEŞTİRME
# ============================================================

## Bir izin için özel gerekçe metni ayarlar.
## Oyun kendi bağlamına uygun metin verebilir.
func set_custom_rationale(permission: String, text: String) -> void:
	if permission.is_empty() or text.is_empty():
		return
	_custom_rationales[permission] = text


## Bir izin için hazır gerekçe var mı?
func has_rationale(permission: String) -> bool:
	return RATIONALES.has(permission) \
		or _custom_rationales.has(permission)
