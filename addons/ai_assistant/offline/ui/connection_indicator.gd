@tool
class_name AIOfflineConnectionIndicator
extends RefCounted

## ConnectionIndicator — bağlantı göstergesi (Madde 07 / offline / ui).
##
## MİMARİ NOTU (tüm UI modüllerinde geçerli):
##   Godot UI'ı Control node + sahne demek — gözle görülür, test
##   panelinde doğrulanamaz. AMA UI'ın ALTINDAKİ MANTIK (hangi ikon,
##   hangi renk, hangi metin gösterilecek) saf veridir — test edilir.
##   Bu sınıf o view-model katmanı; hiçbir Control'e dokunmaz. Görsel
##   düğüm bunu okur ve çizer.
##
## Üst bar mini bağlantı durumu: çevrimiçi/çevrimdışı/yavaş — küçük
## bir ikon + renk. Oyuncu/geliştirici bir bakışta durumu görür.
##
## Mock policy: gösterge gerçek bağlantı durumundan beslenir.

## Görsel bağlantı durumları.
enum IndicatorState { ONLINE, OFFLINE, SLOW, METERED, CONNECTING }

const STATE_NAMES: Dictionary = {
	IndicatorState.ONLINE: "online",
	IndicatorState.OFFLINE: "offline",
	IndicatorState.SLOW: "slow",
	IndicatorState.METERED: "metered",
	IndicatorState.CONNECTING: "connecting",
}

## Her durum için görsel sunum — ikon adı, renk (hex), etiket.
const STATE_PRESENTATION: Dictionary = {
	IndicatorState.ONLINE: {
		"icon": "wifi", "color": "#4caf50", "label": "Çevrimiçi",
	},
	IndicatorState.OFFLINE: {
		"icon": "wifi_off", "color": "#f44336", "label": "Çevrimdışı",
	},
	IndicatorState.SLOW: {
		"icon": "wifi_slow", "color": "#ff9800", "label": "Yavaş Bağlantı",
	},
	IndicatorState.METERED: {
		"icon": "data_usage", "color": "#ffc107", "label": "Mobil Veri",
	},
	IndicatorState.CONNECTING: {
		"icon": "sync", "color": "#9e9e9e", "label": "Bağlanıyor",
	},
}


## Mevcut gösterge durumu.
var state: int = IndicatorState.CONNECTING


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Bağlantı bilgilerinden gösterge durumunu hesaplar.
## is_online: bağlantı var mı. is_slow: bağlantı yavaş mı.
## is_metered: mobil/ölçülü bağlantı mı.
func update_from_connection(
	is_online: bool, is_slow: bool, is_metered: bool
) -> void:
	if not is_online:
		state = IndicatorState.OFFLINE
	elif is_slow:
		state = IndicatorState.SLOW
	elif is_metered:
		state = IndicatorState.METERED
	else:
		state = IndicatorState.ONLINE


## Göstergeyi "bağlanıyor" durumuna alır.
func set_connecting() -> void:
	state = IndicatorState.CONNECTING


# ============================================================
# SUNUM — görsel düğüm bunları okur
# ============================================================

## Mevcut durumun görsel sunumu — {icon, color, label}.
func presentation() -> Dictionary:
	return STATE_PRESENTATION.get(
		state, STATE_PRESENTATION[IndicatorState.CONNECTING]
	).duplicate()


## Gösterilecek ikon adı.
func icon_name() -> String:
	return str(presentation()["icon"])


## Gösterilecek renk (hex).
func color_hex() -> String:
	return str(presentation()["color"])


## Gösterilecek etiket metni.
func label_text() -> String:
	return str(presentation()["label"])


## Mevcut durumun adı.
func state_name() -> String:
	return STATE_NAMES.get(state, "?")


# ============================================================
# SORGULAMA
# ============================================================

## Gösterge bir sorun (çevrimdışı/yavaş) gösteriyor mu?
func shows_problem() -> bool:
	return state == IndicatorState.OFFLINE \
		or state == IndicatorState.SLOW


## Kullanıcı dikkat etmeli mi (sorun veya mobil veri)?
func needs_attention() -> bool:
	return shows_problem() or state == IndicatorState.METERED
