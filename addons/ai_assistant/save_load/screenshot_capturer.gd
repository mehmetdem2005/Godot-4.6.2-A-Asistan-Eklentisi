@tool
class_name AISaveScreenshotCapturer
extends RefCounted

## ScreenshotCapturer — ekran görüntüsü yakalayıcı (Madde 09).
##
## Kayıt slotları sadece metin değil — oyuncu hangi kaydı yükleyeceğini
## küçük bir önizleme görseliyle (thumbnail) anlar. "Şu mağaranın
## önündeki kayıt" — görsel hafıza metinden güçlü.
##
## Gerçek ekran yakalama Godot Viewport işidir (sahnesiz yapılamaz),
## o ince sarmalayıcıya kalır. Bu sınıf yakalamanın METADATA'sını ve
## thumbnail dosya YOLU mantığını yönetir — test edilebilir kısım.
##
## Thumbnail küçük olmalı (disk + yükleme hızı): tipik 256x144.
## Her kayıt slotunun yanında thumb.jpg olarak durur.
##
## Mock policy: yol/metadata gerçek slot bilgisinden.

## Önerilen thumbnail boyutu.
const THUMB_WIDTH: int = 256
const THUMB_HEIGHT: int = 144

## Thumbnail dosya adı (her slot klasöründe).
const THUMB_FILENAME: String = "thumb.jpg"

## JPEG kalitesi (0-1) — küçük dosya için orta kalite.
const THUMB_QUALITY: float = 0.7


# ============================================================
# YOL ÜRETİMİ
# ============================================================

## Bir kayıt slotu için thumbnail dosya yolunu üretir.
## slot_path: slotun klasör yolu (örn. "user://saves/slot_1").
func thumb_path(slot_path: String) -> String:
	var base: String = slot_path
	# Sondaki / temizle
	if base.ends_with("/"):
		base = base.substr(0, base.length() - 1)
	return base + "/" + THUMB_FILENAME


## Bir slot için thumbnail var olmalı mı kontrolü — yol döndürür.
func expected_thumb_path(slot_path: String) -> String:
	return thumb_path(slot_path)


# ============================================================
# YAKALAMA İSTEĞİ
# ============================================================

## Bir thumbnail yakalama isteği oluşturur — sarmalayıcı için tarif.
## slot_path: hedef slot. source_width/height: kaynak görüntü boyutu.
## Dönen: {target_path, width, height, quality, scale_needed}
func make_capture_request(
	slot_path: String, source_width: int, source_height: int
) -> Dictionary:
	# Kaynak thumbnail'den büyükse ölçekleme gerekir
	var scale_needed: bool = source_width > THUMB_WIDTH \
		or source_height > THUMB_HEIGHT
	return {
		"target_path": thumb_path(slot_path),
		"width": THUMB_WIDTH,
		"height": THUMB_HEIGHT,
		"quality": THUMB_QUALITY,
		"scale_needed": scale_needed,
	}


## Kaynak boyutu thumbnail'e sığdıracak ölçek oranını hesaplar.
## En-boy oranını korur — görüntü bozulmaz.
## Dönen: ölçek çarpanı (0-1 arası).
func compute_scale(source_width: int, source_height: int) -> float:
	if source_width <= 0 or source_height <= 0:
		return 1.0
	var scale_x: float = float(THUMB_WIDTH) / float(source_width)
	var scale_y: float = float(THUMB_HEIGHT) / float(source_height)
	# Küçük olan oran — her iki boyut da sığsın
	var scale: float = minf(scale_x, scale_y)
	# Büyütme yapma — sadece küçült (1.0 üstü kırpılır)
	return minf(scale, 1.0)


# ============================================================
# METADATA
# ============================================================

## Bir thumbnail için metadata sözlüğü üretir.
## Kayıt slotu metadata'sına gömülür.
func make_metadata(slot_path: String, captured: bool) -> Dictionary:
	return {
		"thumb_path": thumb_path(slot_path),
		"thumb_width": THUMB_WIDTH,
		"thumb_height": THUMB_HEIGHT,
		"has_thumbnail": captured,
	}


## Bir slotun thumbnail'i olup olmadığını metadata'dan okur.
func has_thumbnail(metadata: Dictionary) -> bool:
	return bool(metadata.get("has_thumbnail", false))
