@tool
class_name AIAudioBusArchitect
extends RefCounted

## BusArchitect — ses bus mimarı (Madde 08 / Audio System).
##
## Profesyonel oyun sesinde her ses bir "bus"tan geçer: Master altında
## Music, SFX, UI, Ambient, Voice gibi kanallar. Bu yapı sayesinde
## "tüm müziği kıs", "SFX'i sustur" gibi global kontroller mümkün olur.
##
## Bu sınıf bus AĞACINI TASARLAR — hangi bus hangi bus'a bağlı, her
## birinin varsayılan sesi ne. Gerçek AudioServer kurulumu ince bir
## Node sarmalayıcının işi; bu model test edilebilir konfigürasyondur.
##
## Standart oyun bus hiyerarşisi:
##   Master
##   ├── Music    (müzik)
##   ├── SFX      (ses efektleri)
##   ├── UI       (arayüz sesleri)
##   ├── Ambient  (ortam sesi)
##   └── Voice    (diyalog/ses)
##
## Mock policy: bus konfigürasyonu açıkça tanımlanır; varsayılan
## değerler makul ses mühendisliği değerleridir.

## Standart bus adları.
const MASTER: String = "Master"
const STANDARD_BUSES: Array = ["Music", "SFX", "UI", "Ambient", "Voice"]

## Ses sınırları (desibel).
const MIN_DB: float = -80.0   ## Bu değer pratikte "sessiz"
const MAX_DB: float = 6.0     ## Üstü kırpılma riski


## Bir ses bus'ının konfigürasyonu.
class BusConfig extends RefCounted:
	var bus_name: String = ""
	var send_to: String = ""           ## Hangi bus'a yönlendirilir
	var volume_db: float = 0.0         ## Varsayılan ses (dB)
	var muted: bool = false

	func to_dict() -> Dictionary:
		return {
			"bus_name": bus_name,
			"send_to": send_to,
			"volume_db": volume_db,
			"muted": muted,
		}


## Bus konfigürasyonları — bus_name -> BusConfig.
var _buses: Dictionary = {}


func _init() -> void:
	_build_standard_tree()


# ============================================================
# STANDART AĞAÇ
# ============================================================

## Standart oyun bus ağacını kurar: Master + 5 alt bus.
func _build_standard_tree() -> void:
	_buses.clear()
	# Master — kök, kimseye yönlenmez
	var master := BusConfig.new()
	master.bus_name = MASTER
	master.send_to = ""
	_buses[MASTER] = master
	# Alt buslar — hepsi Master'a yönlenir
	for bus_name in STANDARD_BUSES:
		var bus := BusConfig.new()
		bus.bus_name = bus_name
		bus.send_to = MASTER
		_buses[bus_name] = bus


# ============================================================
# BUS YÖNETİMİ
# ============================================================

## Bir bus ekler.
## bus_name: yeni bus adı. send_to: yönlendirileceği bus.
## Dönen: eklenen BusConfig (veya null — geçersiz).
func add_bus(bus_name: String, send_to: String) -> BusConfig:
	if bus_name.is_empty():
		push_warning("BusArchitect: boş bus adı")
		return null
	if _buses.has(bus_name):
		push_warning("BusArchitect: bus zaten var: " + bus_name)
		return null
	# Yönlendirilen bus var olmalı
	if not _buses.has(send_to):
		push_warning("BusArchitect: hedef bus yok: " + send_to)
		return null
	var bus := BusConfig.new()
	bus.bus_name = bus_name
	bus.send_to = send_to
	_buses[bus_name] = bus
	return bus


## Bir bus'ı döndürür. Yoksa null.
func get_bus(bus_name: String) -> BusConfig:
	return _buses.get(bus_name, null)


## Bir bus var mı?
func has_bus(bus_name: String) -> bool:
	return _buses.has(bus_name)


## Toplam bus sayısı.
func bus_count() -> int:
	return _buses.size()


# ============================================================
# SES AYARLAMA
# ============================================================

## Bir bus'ın sesini ayarlar (dB). Sınır dışı değer kırpılır.
## Dönen: true = bus var ve ayarlandı.
func set_volume(bus_name: String, volume_db: float) -> bool:
	if not _buses.has(bus_name):
		return false
	var bus: BusConfig = _buses[bus_name]
	bus.volume_db = clampf(volume_db, MIN_DB, MAX_DB)
	return true


## Bir bus'ı susturur/açar.
func set_muted(bus_name: String, muted: bool) -> bool:
	if not _buses.has(bus_name):
		return false
	(_buses[bus_name] as BusConfig).muted = muted
	return true


# ============================================================
# AĞAÇ DOĞRULAMA
# ============================================================

## Bus ağacının geçerli olup olmadığını kontrol eder.
## Geçerli: tek Master kökü, döngü yok, her send_to var olan bir bus.
## Dönen: {valid: bool, issues: PackedStringArray}
func validate_tree() -> Dictionary:
	var issues: PackedStringArray = PackedStringArray()

	# Master var mı
	if not _buses.has(MASTER):
		issues.append("Master bus eksik")

	# Her bus'ın send_to'su geçerli mi + döngü kontrolü
	for bus_name in _buses:
		var bus: BusConfig = _buses[bus_name]
		if bus_name == MASTER:
			if not bus.send_to.is_empty():
				issues.append("Master bir bus'a yönlenmemeli")
			continue
		if bus.send_to.is_empty():
			issues.append("%s: yönlendirme hedefi yok" % bus_name)
		elif not _buses.has(bus.send_to):
			issues.append("%s: hedef bus yok (%s)" % [
				bus_name, bus.send_to
			])
		# Döngü — bu bus'tan Master'a ulaşılabiliyor mu
		if not _reaches_master(bus_name):
			issues.append("%s: Master'a ulaşmıyor (döngü?)" % bus_name)

	return {"valid": issues.is_empty(), "issues": issues}


## Bir bus'tan yönlendirme zinciri Master'a ulaşıyor mu?
func _reaches_master(start_bus: String) -> bool:
	var visited: Dictionary = {}
	var current: String = start_bus
	while current != "" and current != MASTER:
		if visited.has(current):
			return false  # döngü
		visited[current] = true
		var bus: BusConfig = _buses.get(current, null)
		if bus == null:
			return false
		current = bus.send_to
	return current == MASTER


## Bus ağacı özeti.
func summary() -> Dictionary:
	return {
		"bus_count": _buses.size(),
		"valid": validate_tree()["valid"],
	}
