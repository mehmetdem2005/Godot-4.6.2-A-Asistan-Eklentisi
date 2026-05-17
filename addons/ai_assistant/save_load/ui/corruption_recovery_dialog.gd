@tool
class_name AISaveCorruptionDialog
extends RefCounted

## CorruptionRecoveryDialog — bozulma kurtarma diyalogu (Madde 09 / ui).
##
## Bir kayıt bozuk bulunduğunda kullanıcıya gösterilen diyalog.
## corruption_recovery (mantık katmanı) bir kurtarma stratejisi
## önerir; bu diyalog onu kullanıcıya açıklar ve seçenek sunar:
## yedekten geri yükle / yeni oyun başlat / iptal.
##
## Bu view-model diyaloğun içeriğini kurtarma planından üretir —
## hangi mesaj, hangi butonlar gösterilecek.
##
## corruption_recovery + backup_restorer (mantık katmanı) ile
## beslenir.
##
## Mock policy: diyalog içeriği gerçek kurtarma planından.

## Kullanıcının verebileceği kararlar.
enum RecoveryChoice { RESTORE_BACKUP, NEW_GAME, CANCEL }

const CHOICE_NAMES: Dictionary = {
	RecoveryChoice.RESTORE_BACKUP: "restore_backup",
	RecoveryChoice.NEW_GAME: "new_game",
	RecoveryChoice.CANCEL: "cancel",
}


## Bozulan slotun kimliği.
var slot_id: String = ""

## Yedekten geri yükleme mümkün mü.
var has_backup: bool = false

## Kullanıcının kararı (henüz vermediyse -1).
var _decision: int = -1


# ============================================================
# DİYALOG HAZIRLAMA
# ============================================================

## Diyaloğu bir bozuk slot için hazırlar.
## p_slot_id: bozuk slot. p_has_backup: kurtarılabilir yedek var mı.
func prepare(p_slot_id: String, p_has_backup: bool) -> void:
	slot_id = p_slot_id
	has_backup = p_has_backup
	_decision = -1


## Diyaloğun gösterdiği mesajı üretir.
func message_text() -> String:
	if has_backup:
		return "'%s' kaydı bozuk. Daha eski bir yedek bulundu — " % \
			slot_id + "geri yüklemek ister misiniz?"
	return "'%s' kaydı bozuk ve kurtarılabilir yedek yok. " % \
		slot_id + "Yeni bir oyun başlatmanız gerekiyor."


## Diyalog butonlarının tanımını üretir.
## Yedek varsa "geri yükle" seçeneği eklenir.
## Dönen: her biri {choice, label} dizi.
func button_options() -> Array:
	var options: Array = []
	if has_backup:
		options.append({
			"choice": CHOICE_NAMES[RecoveryChoice.RESTORE_BACKUP],
			"label": "Yedekten Geri Yükle",
		})
	options.append({
		"choice": CHOICE_NAMES[RecoveryChoice.NEW_GAME],
		"label": "Yeni Oyun",
	})
	options.append({
		"choice": CHOICE_NAMES[RecoveryChoice.CANCEL],
		"label": "İptal",
	})
	return options


# ============================================================
# KARAR
# ============================================================

## Kullanıcının kararını kaydeder.
## choice: RecoveryChoice değeri.
## Dönen: {recorded: bool, reason: String}
func record_decision(choice: int) -> Dictionary:
	if not CHOICE_NAMES.has(choice):
		return {"recorded": false, "reason": "Geçersiz seçim"}
	# Yedek yokken "geri yükle" seçilemez
	if choice == RecoveryChoice.RESTORE_BACKUP and not has_backup:
		return {
			"recorded": false,
			"reason": "Yedek yok — geri yükleme seçilemez",
		}
	_decision = choice
	return {"recorded": true, "reason": "Karar kaydedildi"}


# ============================================================
# SORGULAMA
# ============================================================

## Karar verildi mi?
func has_decision() -> bool:
	return _decision != -1


## Verilen kararın adı. Henüz verilmediyse boş string.
func decision_name() -> String:
	if _decision == -1:
		return ""
	return CHOICE_NAMES.get(_decision, "?")


## Kullanıcı yedekten geri yüklemeyi seçti mi?
func chose_restore() -> bool:
	return _decision == RecoveryChoice.RESTORE_BACKUP


## Kullanıcı yeni oyun başlatmayı seçti mi?
func chose_new_game() -> bool:
	return _decision == RecoveryChoice.NEW_GAME
