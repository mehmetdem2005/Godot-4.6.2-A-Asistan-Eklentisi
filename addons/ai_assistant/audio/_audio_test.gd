@tool
class_name AIAudioTest
extends RefCounted

## Madde 08 — Audio System Çekirdek Self-Test
##
## Sıkı testler: bus_architecture (BusArchitect, VolumeManager,
## EQPreset), playback (AudioPool, PlaybackDispatcher), spatial
## (SpatialAudio).


static func run_all() -> Array:
	var results: Array = []

	# BusArchitect
	results.append(_b("Audio: Bus", _test_bus_standard_tree()))
	results.append(_b("Audio: Bus", _test_bus_add()))
	results.append(_b("Audio: Bus", _test_bus_volume_clamp()))
	results.append(_b("Audio: Bus", _test_bus_validation()))
	results.append(_b("Audio: Bus", _test_bus_cycle_detection()))

	# VolumeManager
	results.append(_b("Audio: Volume", _test_volume_conversion()))
	results.append(_b("Audio: Volume", _test_volume_silence()))
	results.append(_b("Audio: Volume", _test_volume_roundtrip()))

	# EQPreset
	results.append(_b("Audio: EQ", _test_eq_presets()))
	results.append(_b("Audio: EQ", _test_eq_sanitize()))
	results.append(_b("Audio: EQ", _test_eq_blend()))

	# AudioPool
	results.append(_b("Audio: Pool", _test_pool_acquire()))
	results.append(_b("Audio: Pool", _test_pool_full_reject()))
	results.append(_b("Audio: Pool", _test_pool_voice_stealing()))
	results.append(_b("Audio: Pool", _test_pool_release()))

	# PlaybackDispatcher
	results.append(_b("Audio: Dispatch", _test_dispatch_play()))
	results.append(_b("Audio: Dispatch", _test_dispatch_category_bus()))
	results.append(_b("Audio: Dispatch", _test_dispatch_invalid()))

	# SpatialAudio
	results.append(_b("Audio: Spatial", _test_spatial_distance()))
	results.append(_b("Audio: Spatial", _test_spatial_reverb_zone()))
	results.append(_b("Audio: Spatial", _test_spatial_occlusion()))
	results.append(_b("Audio: Spatial", _test_spatial_combined()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# BUS ARCHITECT
# ============================================================

static func _test_bus_standard_tree() -> Dictionary:
	var name := "Bus standart ağaç"
	var arch := AIAudioBusArchitect.new()
	# Master + 5 standart bus = 6
	if arch.bus_count() != 6:
		return _fail(name, "6 bus bekleniyordu, %d" % arch.bus_count())
	if not arch.has_bus("Master"):
		return _fail(name, "Master bus olmalı")
	if not arch.has_bus("Music"):
		return _fail(name, "Music bus olmalı")
	return _ok(name)


static func _test_bus_add() -> Dictionary:
	var name := "Bus ekleme + doğrulama"
	var arch := AIAudioBusArchitect.new()
	# Geçerli ekleme
	if arch.add_bus("Footsteps", "SFX") == null:
		return _fail(name, "geçerli bus eklenmeli")
	# Çift bus reddi
	if arch.add_bus("Music", "Master") != null:
		return _fail(name, "var olan bus tekrar eklenemez")
	# Olmayan hedef reddi
	if arch.add_bus("Yeni", "OlmayanBus") != null:
		return _fail(name, "olmayan hedefe yönlendirme reddedilmeli")
	return _ok(name)


static func _test_bus_volume_clamp() -> Dictionary:
	var name := "Bus ses sınırlama"
	var arch := AIAudioBusArchitect.new()
	# Sınır üstü değer kırpılmalı
	arch.set_volume("Music", 999.0)
	var bus: AIAudioBusArchitect.BusConfig = arch.get_bus("Music")
	if bus.volume_db > AIAudioBusArchitect.MAX_DB:
		return _fail(name, "ses MAX_DB'ye kırpılmalı")
	return _ok(name)


static func _test_bus_validation() -> Dictionary:
	var name := "Bus ağaç doğrulama"
	var arch := AIAudioBusArchitect.new()
	var validation: Dictionary = arch.validate_tree()
	if not validation["valid"]:
		return _fail(name, "standart ağaç geçerli olmalı")
	return _ok(name)


static func _test_bus_cycle_detection() -> Dictionary:
	var name := "Bus döngü tespiti"
	var arch := AIAudioBusArchitect.new()
	# Yapay döngü kur: Music -> SFX, SFX -> Music
	arch.get_bus("Music").send_to = "SFX"
	arch.get_bus("SFX").send_to = "Music"
	var validation: Dictionary = arch.validate_tree()
	if validation["valid"]:
		return _fail(name, "döngülü ağaç geçersiz olmalı")
	return _ok(name)


# ============================================================
# VOLUME MANAGER
# ============================================================

static func _test_volume_conversion() -> Dictionary:
	var name := "Volume yüzde-dB çevrimi"
	var vm := AIAudioVolumeManager.new()
	# %100 -> 0 dB civarı
	var db_at_100: float = vm.percent_to_db(100.0)
	if absf(db_at_100) > 0.5:
		return _fail(name, "%100 yaklaşık 0 dB olmalı")
	# Çevrim monoton: yüksek yüzde = yüksek dB
	if vm.percent_to_db(80.0) <= vm.percent_to_db(40.0):
		return _fail(name, "yüksek yüzde yüksek dB vermeli")
	return _ok(name)


static func _test_volume_silence() -> Dictionary:
	var name := "Volume sessizlik"
	var vm := AIAudioVolumeManager.new()
	vm.set_volume_percent("SFX", 0.0)
	if not vm.is_silent("SFX"):
		return _fail(name, "%0 ses sessiz sayılmalı")
	# -80 dB civarı
	if vm.percent_to_db(0.0) > -79.0:
		return _fail(name, "%0 yaklaşık -80 dB olmalı")
	return _ok(name)


static func _test_volume_roundtrip() -> Dictionary:
	var name := "Volume kalıcılık round-trip"
	var vm := AIAudioVolumeManager.new()
	vm.set_volume_percent("Music", 42.0)
	var data: Dictionary = vm.to_dict()
	var loaded := AIAudioVolumeManager.new()
	loaded.from_dict(data)
	if absf(loaded.get_volume_percent("Music") - 42.0) > 0.01:
		return _fail(name, "ses ayarı round-trip'te korunmalı")
	return _ok(name)


# ============================================================
# EQ PRESET
# ============================================================

static func _test_eq_presets() -> Dictionary:
	var name := "EQ profiller tanımlı"
	var eq := AIAudioEQPreset.new()
	if not eq.has_preset("flat"):
		return _fail(name, "flat profili olmalı")
	if not eq.has_preset("underwater"):
		return _fail(name, "underwater profili olmalı")
	# Tanımsız profil flat döner
	var unknown: Dictionary = eq.get_preset("olmayan")
	if unknown.is_empty():
		return _fail(name, "tanımsız profil flat dönmeli")
	return _ok(name)


static func _test_eq_sanitize() -> Dictionary:
	var name := "EQ özel profil sınırlama"
	var eq := AIAudioEQPreset.new()
	# Sınır dışı kazanç — kırpılmalı
	var sanitized: Dictionary = eq.sanitize_custom({"bass": 999.0})
	if float(sanitized["bass"]) > AIAudioEQPreset.MAX_GAIN:
		return _fail(name, "kazanç MAX_GAIN'e kırpılmalı")
	# Tüm 6 bant olmalı
	if sanitized.size() != AIAudioEQPreset.BANDS.size():
		return _fail(name, "tüm bantlar doldurulmalı")
	return _ok(name)


static func _test_eq_blend() -> Dictionary:
	var name := "EQ profil geçişi"
	var eq := AIAudioEQPreset.new()
	# t=0 -> from, t=1 -> to
	var at_zero: Dictionary = eq.blend("flat", "combat", 0.0)
	var combat: Dictionary = eq.get_preset("combat")
	var flat: Dictionary = eq.get_preset("flat")
	if absf(float(at_zero["mid"]) - float(flat["mid"])) > 0.01:
		return _fail(name, "t=0 başlangıç profili olmalı")
	var at_one: Dictionary = eq.blend("flat", "combat", 1.0)
	if absf(float(at_one["mid"]) - float(combat["mid"])) > 0.01:
		return _fail(name, "t=1 hedef profili olmalı")
	return _ok(name)


# ============================================================
# AUDIO POOL
# ============================================================

static func _test_pool_acquire() -> Dictionary:
	var name := "Pool yuva tahsisi"
	var pool := AIAudioPool.new(4)
	if pool.busy_count() != 0:
		return _fail(name, "havuz boş başlamalı")
	var acquire: Dictionary = pool.acquire("ses1", 5)
	if not acquire["ok"]:
		return _fail(name, "boş havuzdan tahsis başarılı olmalı")
	if pool.busy_count() != 1:
		return _fail(name, "tahsis sonrası 1 meşgul olmalı")
	return _ok(name)


static func _test_pool_full_reject() -> Dictionary:
	var name := "Pool dolu — düşük öncelik reddi"
	var pool := AIAudioPool.new(2)
	# 2 yuvayı yüksek öncelikle doldur
	pool.acquire("s1", 5)
	pool.acquire("s2", 5)
	# Düşük öncelikli yeni ses — kurban yok, reddedilmeli
	var rejected: Dictionary = pool.acquire("s3", 3)
	if rejected["ok"]:
		return _fail(name, "dolu havuzda düşük öncelik reddedilmeli")
	return _ok(name)


static func _test_pool_voice_stealing() -> Dictionary:
	var name := "Pool voice stealing"
	var pool := AIAudioPool.new(2)
	pool.acquire("s1", 3)
	pool.acquire("s2", 3)
	# Yüksek öncelikli yeni ses — düşük öncelikliyi kesmeli
	var steal: Dictionary = pool.acquire("önemli", 9)
	if not steal["ok"]:
		return _fail(name, "yüksek öncelikli ses yuva almalı")
	if not steal["stole"]:
		return _fail(name, "voice stealing gerçekleşmeli")
	return _ok(name)


static func _test_pool_release() -> Dictionary:
	var name := "Pool yuva serbest bırakma"
	var pool := AIAudioPool.new(3)
	var acquire: Dictionary = pool.acquire("ses", 5)
	var slot: int = int(acquire["slot_index"])
	if not pool.release(slot):
		return _fail(name, "geçerli yuva bırakılmalı")
	if pool.busy_count() != 0:
		return _fail(name, "bırakma sonrası meşgul 0 olmalı")
	# Geçersiz yuva
	if pool.release(999):
		return _fail(name, "geçersiz yuva bırakılamaz")
	return _ok(name)


# ============================================================
# PLAYBACK DISPATCHER
# ============================================================

static func _test_dispatch_play() -> Dictionary:
	var name := "Dispatch ses çalma"
	var dispatcher := AIAudioPlaybackDispatcher.new()
	var result: AIAudioPlaybackDispatcher.PlaybackResult = dispatcher.play(
		"patlama", AIAudioPlaybackDispatcher.SoundCategory.SFX
	)
	if not result.ok:
		return _fail(name, "geçerli çalma başarılı olmalı")
	if result.bus != "SFX":
		return _fail(name, "SFX kategorisi SFX bus'a gitmeli")
	return _ok(name)


static func _test_dispatch_category_bus() -> Dictionary:
	var name := "Dispatch kategori-bus eşlemesi"
	var dispatcher := AIAudioPlaybackDispatcher.new()
	# UI sesi UI bus'a
	var ui: AIAudioPlaybackDispatcher.PlaybackResult = dispatcher.play_ui(
		"buton_tık"
	)
	if ui.bus != "UI":
		return _fail(name, "UI sesi UI bus'a gitmeli")
	return _ok(name)


static func _test_dispatch_invalid() -> Dictionary:
	var name := "Dispatch geçersiz girdi reddi"
	var dispatcher := AIAudioPlaybackDispatcher.new()
	# Boş ses kimliği
	var empty: AIAudioPlaybackDispatcher.PlaybackResult = dispatcher.play(
		"", AIAudioPlaybackDispatcher.SoundCategory.SFX
	)
	if empty.ok:
		return _fail(name, "boş ses kimliği reddedilmeli")
	return _ok(name)


# ============================================================
# SPATIAL AUDIO
# ============================================================

static func _test_spatial_distance() -> Dictionary:
	var name := "Spatial mesafe zayıflama"
	var sp := AIAudioSpatial.new()
	# Üstünde — tam ses
	if absf(sp.distance_attenuation(0.0, 100.0) - 1.0) > 0.01:
		return _fail(name, "mesafe 0'da tam ses olmalı")
	# Menzil dışı — sessiz
	if sp.distance_attenuation(150.0, 100.0) != 0.0:
		return _fail(name, "menzil dışı sessiz olmalı")
	# Ara mesafe — kısık ama duyulur
	var mid: float = sp.distance_attenuation(50.0, 100.0)
	if mid <= 0.0 or mid >= 1.0:
		return _fail(name, "ara mesafe kısmi ses olmalı")
	return _ok(name)


static func _test_spatial_reverb_zone() -> Dictionary:
	var name := "Spatial reverb bölgesi"
	var sp := AIAudioSpatial.new()
	var box_min := Vector3(0, 0, 0)
	var box_max := Vector3(10, 10, 10)
	# İçerideki nokta
	if not sp.is_in_reverb_zone(Vector3(5, 5, 5), box_min, box_max):
		return _fail(name, "kutu içi nokta bölgede olmalı")
	# Dışarıdaki nokta
	if sp.is_in_reverb_zone(Vector3(15, 5, 5), box_min, box_max):
		return _fail(name, "kutu dışı nokta bölgede olmamalı")
	return _ok(name)


static func _test_spatial_occlusion() -> Dictionary:
	var name := "Spatial occlusion"
	var sp := AIAudioSpatial.new()
	# Engelsiz — tam ses
	if absf(sp.occlusion_factor(0) - 1.0) > 0.01:
		return _fail(name, "engelsiz tam ses olmalı")
	# Engel ses kısar
	var one: float = sp.occlusion_factor(1, 0.5)
	var two: float = sp.occlusion_factor(2, 0.5)
	if not (one < 1.0 and two < one):
		return _fail(name, "her engel sesi daha çok kısmalı")
	# Boğukluk — engelsiz 0
	if sp.occlusion_muffling(0) != 0.0:
		return _fail(name, "engelsiz boğukluk olmamalı")
	return _ok(name)


static func _test_spatial_combined() -> Dictionary:
	var name := "Spatial birleşik hesap"
	var sp := AIAudioSpatial.new()
	# Yakın + engelsiz — yüksek ses, boğukluk yok
	var clear: Dictionary = sp.compute_spatial(10.0, 100.0, 0)
	if float(clear["volume"]) <= 0.0:
		return _fail(name, "yakın engelsiz ses duyulmalı")
	if float(clear["muffling"]) != 0.0:
		return _fail(name, "engelsiz boğukluk olmamalı")
	# Uzak + engelli — düşük ses
	var blocked: Dictionary = sp.compute_spatial(80.0, 100.0, 3)
	if float(blocked["volume"]) >= float(clear["volume"]):
		return _fail(name, "uzak+engelli ses daha kısık olmalı")
	return _ok(name)
