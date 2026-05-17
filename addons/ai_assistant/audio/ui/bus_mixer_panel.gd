@tool
class_name AIAudioBusMixerPanel
extends RefCounted

## BusMixerPanel — bus mikseri paneli (Madde 08 / audio / ui).
##
## Ses bus ağacını (Master/Music/SFX/UI...) görsel bir mikser olarak
## sunar: her bus için ses kaydırıcısı, sustur/yalnız düğmeleri,
## efekt listesi.
##
## Bu view-model mikserin durumunu tutar: her bus'ın ses seviyesi,
## sustur/yalnız durumu. Görsel mikser Control'ü bunu okur ve
## kaydırıcıları çizer.
##
## Mock policy: durum gerçek bus ayarlarından.

## Bir mikser kanalının durumu.
class ChannelStrip extends RefCounted:
	var bus_name: String = ""
	var volume_db: float = 0.0        ## Ses seviyesi (desibel)
	var muted: bool = false
	var soloed: bool = false

	func to_dict() -> Dictionary:
		return {
			"bus": bus_name, "volume_db": volume_db,
			"muted": muted, "soloed": soloed,
		}


## Ses seviyesi sınırları (dB).
const MIN_DB: float = -60.0
const MAX_DB: float = 6.0


## Mikser kanalları — bus_name -> ChannelStrip.
var _channels: Dictionary = {}

## Kanal sırası — görsel düzen için.
var _channel_order: Array = []


# ============================================================
# KANAL TANIMLAMA
# ============================================================

## Mikser'e bir bus kanalı ekler.
## bus_name: bus adı.
func add_channel(bus_name: String) -> void:
	if bus_name.is_empty() or _channels.has(bus_name):
		return
	var strip := ChannelStrip.new()
	strip.bus_name = bus_name
	_channels[bus_name] = strip
	_channel_order.append(bus_name)


## Standart bus ağacı kanallarını ekler.
func add_standard_channels() -> void:
	for bus_name in ["Master", "Music", "SFX", "UI", "Ambient"]:
		add_channel(bus_name)


# ============================================================
# KANAL KONTROLÜ
# ============================================================

## Bir kanalın ses seviyesini ayarlar (dB).
func set_volume(bus_name: String, volume_db: float) -> bool:
	if not _channels.has(bus_name):
		return false
	var strip: ChannelStrip = _channels[bus_name]
	strip.volume_db = clampf(volume_db, MIN_DB, MAX_DB)
	return true


## Bir kanalı susturur/açar.
func set_muted(bus_name: String, muted: bool) -> bool:
	if not _channels.has(bus_name):
		return false
	(_channels[bus_name] as ChannelStrip).muted = muted
	return true


## Bir kanalı "yalnız" yapar/kaldırır.
## Yalnız = sadece bu kanal duyulur, diğerleri sessiz.
func set_soloed(bus_name: String, soloed: bool) -> bool:
	if not _channels.has(bus_name):
		return false
	(_channels[bus_name] as ChannelStrip).soloed = soloed
	return true


# ============================================================
# EFEKTİF SES — solo/mute mantığı
# ============================================================

## Mikser'de "yalnız" yapılmış kanal var mı?
func has_solo() -> bool:
	for bus_name in _channels:
		if (_channels[bus_name] as ChannelStrip).soloed:
			return true
	return false


## Bir kanalın şu an gerçekten duyulup duyulmadığını hesaplar.
## Mute kapatır; solo varsa sadece solo'lu kanallar duyulur.
func is_audible(bus_name: String) -> bool:
	if not _channels.has(bus_name):
		return false
	var strip: ChannelStrip = _channels[bus_name]
	# Susturulmuş — duyulmaz
	if strip.muted:
		return false
	# Mikser'de solo varsa — sadece solo kanallar duyulur
	if has_solo():
		return strip.soloed
	return true


# ============================================================
# SUNUM
# ============================================================

## Tüm kanalların görsel listesini üretir.
## Dönen: her biri {bus, volume_db, muted, soloed, audible} dizi.
func build_strips() -> Array:
	var strips: Array = []
	for bus_name in _channel_order:
		var strip: ChannelStrip = _channels[bus_name]
		var row: Dictionary = strip.to_dict()
		row["audible"] = is_audible(bus_name)
		strips.append(row)
	return strips


## Mikser kanal sayısı.
func channel_count() -> int:
	return _channels.size()


## Bir kanalı döndürür. Yoksa null.
func get_channel(bus_name: String) -> ChannelStrip:
	return _channels.get(bus_name, null)
