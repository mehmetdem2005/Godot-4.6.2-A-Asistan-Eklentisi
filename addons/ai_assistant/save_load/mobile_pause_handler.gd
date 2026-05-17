@tool
class_name AISaveMobilePauseHandler
extends RefCounted

## MobilePauseHandler — mobil duraklatma kaydı (Madde 09 / autosave).
##
## Android'de en kritik kayıt anı: uygulama arka plana atıldığında.
## Telefon araması gelir, kullanıcı başka uygulamaya geçer — ve
## sistem oyunu HER AN öldürebilir. O ölmeden ÖNCE kaydetmek şart.
##
## Bu, normal otomatik kayıttan farklı: zamanı yok, ANINDA ve
## KESİN olmalı. Lifecycle (Madde 10) "arka plana geçildi" der;
## bu sınıf "acil kayıt gerekli mi, ne kadar hızlı" kararını verir.
##
## Acil kayıt minimal olmalı — tam kayıt uzun sürebilir, sistem
## o kadar beklemez. Sadece kritik durum (oyuncu konumu, ilerleme)
## hızlıca yazılır.
##
## Mock policy: karar gerçek yaşam döngüsü olayından.

## Duraklatma kaydının aciliyeti.
enum SaveUrgency { NONE, NORMAL, EMERGENCY }

const URGENCY_NAMES: Dictionary = {
	SaveUrgency.NONE: "none",
	SaveUrgency.NORMAL: "normal",
	SaveUrgency.EMERGENCY: "emergency",
}


## Son kayıttan bu yana oyun durumu değişti mi (kirli mi).
var _state_dirty: bool = false

## Acil kayıt yapıldı mı (bu duraklatma döngüsünde).
var _emergency_save_done: bool = false

## Toplam acil kayıt sayısı.
var _emergency_count: int = 0


# ============================================================
# DURUM
# ============================================================

## Oyun durumunun değiştiğini işaretler — kayıt gerekecek.
func mark_dirty() -> void:
	_state_dirty = true


## Bir kayıt tamamlandığında durumu temiz işaretler.
func mark_clean() -> void:
	_state_dirty = false


## Oyun durumu kirli mi (kaydedilmemiş değişiklik var mı)?
func is_dirty() -> bool:
	return _state_dirty


# ============================================================
# YAŞAM DÖNGÜSÜ OLAYLARI
# ============================================================

## Uygulama arka plana atılıyor — acil kayıt kararı.
## Lifecycle'ın APP_PAUSE olayında çağrılır.
## Dönen: {urgency: String, should_save: bool, scope: String, reason}
##   scope: "minimal" (sadece kritik) | "full" | ""
func on_app_background() -> Dictionary:
	# Durum temizse — kaydedilecek bir şey yok
	if not _state_dirty:
		return {
			"urgency": URGENCY_NAMES[SaveUrgency.NONE],
			"should_save": false,
			"scope": "",
			"reason": "Kaydedilmemiş değişiklik yok",
		}

	# Durum kirli — acil minimal kayıt
	_emergency_save_done = true
	_emergency_count += 1
	return {
		"urgency": URGENCY_NAMES[SaveUrgency.EMERGENCY],
		"should_save": true,
		"scope": "minimal",
		"reason": "Arka plana geçiliyor — acil minimal kayıt",
	}


## Uygulama ön plana geri geliyor — duraklatma döngüsünü sıfırlar.
func on_app_resume() -> void:
	_emergency_save_done = false


## Uygulama normal duraklatılıyor (kısa kesinti, henüz arka plan değil).
## Bu daha az acil — normal kayıt yeterli.
## Dönen: {urgency: String, should_save: bool}
func on_app_pause() -> Dictionary:
	if not _state_dirty:
		return {
			"urgency": URGENCY_NAMES[SaveUrgency.NONE],
			"should_save": false,
		}
	return {
		"urgency": URGENCY_NAMES[SaveUrgency.NORMAL],
		"should_save": true,
	}


# ============================================================
# SORGULAMA
# ============================================================

## Bu duraklatma döngüsünde acil kayıt yapıldı mı?
func emergency_save_done() -> bool:
	return _emergency_save_done


## Toplam acil kayıt sayısı.
func emergency_count() -> int:
	return _emergency_count


## Durum özeti.
func summary() -> Dictionary:
	return {
		"state_dirty": _state_dirty,
		"emergency_save_done": _emergency_save_done,
		"emergency_count": _emergency_count,
	}
