@tool
class_name AILifecycleTemplates
extends RefCounted

## LifecycleTemplates — yaşam döngüsü şablonları (Madde 10 / templates).
##
## Her oyun aynı yaşam döngüsü diyaloglarına ihtiyaç duyar: duraklat
## menüsü, çıkış onayı, izin gerekçesi, pil uyarısı, düşük bellek
## uyarısı. Geliştirici bunları sıfırdan tasarlamamalı.
##
## Bu sınıf 5 hazır şablonun VERİ MODELİNİ üretir: başlık, mesaj,
## butonlar, eylemler. Görsel UI (gerçek Control düğümleri) UI
## katmanının işi — bu sınıf içerik/yapı tanımıdır, test edilebilir.
##
## Plan notu: Madde 10 templates grubu — pause_menu,
## back_button_confirmation, permission_rationale,
## battery_warning_overlay, low_memory_warning.
##
## Mock policy: şablonlar sabit, kullanıcı-dostu Türkçe içerik.

## Şablon tipleri.
enum TemplateType { PAUSE_MENU, EXIT_CONFIRM, PERMISSION_RATIONALE, BATTERY_WARNING, LOW_MEMORY_WARNING }

const TYPE_NAMES: Dictionary = {
	TemplateType.PAUSE_MENU: "pause_menu",
	TemplateType.EXIT_CONFIRM: "exit_confirm",
	TemplateType.PERMISSION_RATIONALE: "permission_rationale",
	TemplateType.BATTERY_WARNING: "battery_warning",
	TemplateType.LOW_MEMORY_WARNING: "low_memory_warning",
}


# ============================================================
# DURAKLAT MENÜSÜ
# ============================================================

## Duraklat menüsü veri modeli üretir.
## Standart oyun duraklat menüsü — devam/ayarlar/ana menü.
func pause_menu() -> Dictionary:
	return {
		"type": TYPE_NAMES[TemplateType.PAUSE_MENU],
		"title": "Duraklatıldı",
		"buttons": [
			{"id": "resume", "label": "Devam Et", "action": "resume_game"},
			{"id": "settings", "label": "Ayarlar",
				"action": "open_settings"},
			{"id": "main_menu", "label": "Ana Menü",
				"action": "confirm_quit_to_menu"},
		],
		"pauses_game": true,
	}


# ============================================================
# ÇIKIŞ ONAYI
# ============================================================

## Çıkış onay diyaloğu veri modeli üretir.
## Geri tuşu ana menüde basıldığında / oyundan çıkışta.
func exit_confirmation() -> Dictionary:
	return {
		"type": TYPE_NAMES[TemplateType.EXIT_CONFIRM],
		"title": "Çıkmak istediğine emin misin?",
		"message": "Kaydedilmemiş ilerlemen kaybolabilir.",
		"buttons": [
			{"id": "cancel", "label": "İptal", "action": "dismiss"},
			{"id": "confirm", "label": "Çık", "action": "quit_app"},
		],
		"default_button": "cancel",
	}


# ============================================================
# İZİN GEREKÇESİ
# ============================================================

## İzin gerekçe diyaloğu veri modeli üretir.
## permission_label: izin adı. rationale: gerekçe metni.
func permission_rationale(
	permission_label: String, rationale: String
) -> Dictionary:
	return {
		"type": TYPE_NAMES[TemplateType.PERMISSION_RATIONALE],
		"title": "%s İzni" % permission_label,
		"message": rationale,
		"buttons": [
			{"id": "deny", "label": "Şimdi Değil", "action": "dismiss"},
			{"id": "grant", "label": "İzin Ver",
				"action": "request_permission"},
		],
		"default_button": "grant",
	}


# ============================================================
# PİL UYARISI
# ============================================================

## Pil uyarısı overlay veri modeli üretir.
## battery_percent: mevcut pil yüzdesi.
func battery_warning(battery_percent: float) -> Dictionary:
	return {
		"type": TYPE_NAMES[TemplateType.BATTERY_WARNING],
		"title": "Pil Düşük",
		"message": "Pil seviyesi %%%d. Oyun otomatik kaydedildi. "
			% int(battery_percent)
			+ "Güç tasarrufu modu öneriliyor.",
		"buttons": [
			{"id": "dismiss", "label": "Tamam", "action": "dismiss"},
			{"id": "power_save", "label": "Güç Tasarrufu",
				"action": "enable_power_save"},
		],
		"auto_dismiss_seconds": 5.0,
		"severity": "warning",
	}


# ============================================================
# DÜŞÜK BELLEK UYARISI
# ============================================================

## Düşük bellek uyarısı veri modeli üretir.
## Sistem belleği kritikse — oyuncuya bilgi, otomatik kayıt yapıldı.
func low_memory_warning() -> Dictionary:
	return {
		"type": TYPE_NAMES[TemplateType.LOW_MEMORY_WARNING],
		"title": "Bellek Düşük",
		"message": "Cihaz belleği azaldı. Oyun kaydedildi. "
			+ "Sorun yaşarsanız diğer uygulamaları kapatın.",
		"buttons": [
			{"id": "dismiss", "label": "Tamam", "action": "dismiss"},
		],
		"auto_dismiss_seconds": 4.0,
		"severity": "warning",
	}


# ============================================================
# GENEL ERİŞİM
# ============================================================

## Bir şablon tipi için varsayılan model üretir.
## type: TemplateType.
## Dönen: şablon veri modeli, geçersiz tip için boş sözlük.
func build(template_type: int) -> Dictionary:
	match template_type:
		TemplateType.PAUSE_MENU:
			return pause_menu()
		TemplateType.EXIT_CONFIRM:
			return exit_confirmation()
		TemplateType.PERMISSION_RATIONALE:
			return permission_rationale("İzin", "Bu özellik için gerekli")
		TemplateType.BATTERY_WARNING:
			return battery_warning(15.0)
		TemplateType.LOW_MEMORY_WARNING:
			return low_memory_warning()
		_:
			return {}


## Tüm şablon tipi adları.
func template_type_names() -> Array:
	return TYPE_NAMES.values()


## Toplam şablon tipi sayısı.
func template_count() -> int:
	return TYPE_NAMES.size()
