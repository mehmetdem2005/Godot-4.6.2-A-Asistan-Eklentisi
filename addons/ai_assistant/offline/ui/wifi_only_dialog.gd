@tool
class_name AIOfflineWifiOnlyDialog
extends RefCounted

## WifiOnlyDialog — Wi-Fi bekleme diyalogu (Madde 07 / offline / ui).
##
## Büyük bir işlem (varlık indirme, model güncelleme) mobil veride
## pahalıdır. BandwidthGovernor bunu "Wi-Fi'ye ertele" diye
## işaretler. Bu diyalog kullanıcıya sorar: "Bu işlem X MB. Wi-Fi
## beklensin mi, yoksa mobil veriyle şimdi mi?"
##
## Kullanıcının kontrolü elinde olur — sistem onun adına pahalı bir
## karar vermez.
##
## Bu view-model diyaloğun içeriğini ve seçeneklerini üretir; görsel
## diyalog Control'ü bunu gösterir.
##
## Mock policy: diyalog içeriği gerçek işlem boyutundan.

## Kullanıcının verebileceği kararlar.
enum DialogChoice { WAIT_WIFI, USE_MOBILE, CANCEL }

const CHOICE_NAMES: Dictionary = {
	DialogChoice.WAIT_WIFI: "wait_wifi",
	DialogChoice.USE_MOBILE: "use_mobile",
	DialogChoice.CANCEL: "cancel",
}


## Bekleyen işlemin adı.
var operation_label: String = ""

## İşlemin tahmini boyutu (bayt).
var operation_bytes: int = 0

## Kullanıcının verdiği karar (henüz vermediyse -1).
var _decision: int = -1


# ============================================================
# DİYALOG HAZIRLAMA
# ============================================================

## Diyaloğu bir işlem için hazırlar.
## label: işlem adı. bytes: tahmini boyut.
func prepare(label: String, bytes: int) -> void:
	operation_label = label
	operation_bytes = maxi(bytes, 0)
	_decision = -1


## Diyaloğun gösterdiği mesajı üretir.
func message_text() -> String:
	var mb: float = float(operation_bytes) / (1024.0 * 1024.0)
	return "%s için %.1f MB veri gerekli. Wi-Fi bağlantısı " % [
		operation_label, mb
	] + "beklensin mi, yoksa mobil veriyle şimdi mi indirilsin?"


## Diyalog butonlarının tanımını üretir.
## Dönen: her biri {choice, label} dizi.
func button_options() -> Array:
	return [
		{
			"choice": CHOICE_NAMES[DialogChoice.WAIT_WIFI],
			"label": "Wi-Fi Bekle",
		},
		{
			"choice": CHOICE_NAMES[DialogChoice.USE_MOBILE],
			"label": "Mobil Veriyle İndir",
		},
		{
			"choice": CHOICE_NAMES[DialogChoice.CANCEL],
			"label": "İptal",
		},
	]


# ============================================================
# KARAR
# ============================================================

## Kullanıcının kararını kaydeder.
## choice: DialogChoice değeri.
## Dönen: true = geçerli karar.
func record_decision(choice: int) -> bool:
	if not CHOICE_NAMES.has(choice):
		return false
	_decision = choice
	return true


## Karar verildi mi?
func has_decision() -> bool:
	return _decision != -1


## Verilen kararın adı. Henüz verilmediyse boş string.
func decision_name() -> String:
	if _decision == -1:
		return ""
	return CHOICE_NAMES.get(_decision, "?")


# ============================================================
# SORGULAMA
# ============================================================

## Kullanıcı işlemi şimdi yapmak istedi mi (mobil veri onayı)?
func proceeds_now() -> bool:
	return _decision == DialogChoice.USE_MOBILE


## Kullanıcı Wi-Fi beklemeyi seçti mi?
func waits_for_wifi() -> bool:
	return _decision == DialogChoice.WAIT_WIFI


## Kullanıcı işlemi iptal etti mi?
func is_cancelled() -> bool:
	return _decision == DialogChoice.CANCEL
