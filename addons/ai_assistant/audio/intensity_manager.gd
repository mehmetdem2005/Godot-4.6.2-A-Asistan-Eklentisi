@tool
class_name AIAudioIntensityManager
extends RefCounted

## IntensityManager — yoğunluk yöneticisi (Madde 08 / music_layering).
##
## Katmanlı müziğin beyni. Modern oyun müziği tek parça değil —
## birden fazla KATMAN (stem): temel ritim, melodi, gerilim teli,
## davul. Aksiyon arttıkça katman eklenir, sakinleşince çıkarılır.
##
## Bu sınıf "şu an oyun ne kadar yoğun" değerini izler ve hangi
## katmanların AKTİF olması gerektiğini söyler:
##   CALM    — sadece temel katman (keşif, menü)
##   BUILD   — temel + melodi (gerilim yükseliyor)
##   COMBAT  — temel + melodi + davul (çatışma)
##   INTENSE — tüm katmanlar (boss, kritik an)
##
## Yoğunluk yumuşak değişir — ani sıçrama müzikte sırıtır. Bu sınıf
## hedef yoğunluğa doğru kademeli geçiş sağlar.
##
## Mock policy: katman kararı gerçek yoğunluk değerinden.

## Yoğunluk seviyeleri.
enum IntensityLevel { CALM, BUILD, COMBAT, INTENSE }

const LEVEL_NAMES: Dictionary = {
	IntensityLevel.CALM: "calm",
	IntensityLevel.BUILD: "build",
	IntensityLevel.COMBAT: "combat",
	IntensityLevel.INTENSE: "intense",
}

## Her seviyede aktif olan katman sayısı.
const LEVEL_LAYERS: Dictionary = {
	IntensityLevel.CALM: 1,
	IntensityLevel.BUILD: 2,
	IntensityLevel.COMBAT: 3,
	IntensityLevel.INTENSE: 4,
}

## Yoğunluk değeri eşikleri (0-1).
const BUILD_THRESHOLD: float = 0.30
const COMBAT_THRESHOLD: float = 0.60
const INTENSE_THRESHOLD: float = 0.85


## Mevcut yoğunluk değeri (0-1) — yumuşak geçen.
var current_intensity: float = 0.0

## Hedef yoğunluk — oyun bunu set eder, current buna kayar.
var target_intensity: float = 0.0

## Yoğunluğun saniyede ne kadar değişebileceği — yumuşaklık.
var transition_rate: float = 0.5


# ============================================================
# YOĞUNLUK KONTROLÜ
# ============================================================

## Hedef yoğunluğu ayarlar — oyun olayları bunu çağırır.
## value: 0 (sakin) - 1 (en yoğun).
func set_target(value: float) -> void:
	target_intensity = clampf(value, 0.0, 1.0)


## Zamanı ilerletir — current'ı target'a doğru yumuşakça kaydırır.
## delta_seconds: geçen süre.
func tick(delta_seconds: float) -> void:
	if delta_seconds < 0.0:
		return
	var max_change: float = transition_rate * delta_seconds
	current_intensity = move_toward(
		current_intensity, target_intensity, max_change
	)


# ============================================================
# SEVİYE HESABI
# ============================================================

## Mevcut yoğunluğun hangi seviyeye denk geldiğini hesaplar.
func current_level() -> int:
	if current_intensity >= INTENSE_THRESHOLD:
		return IntensityLevel.INTENSE
	if current_intensity >= COMBAT_THRESHOLD:
		return IntensityLevel.COMBAT
	if current_intensity >= BUILD_THRESHOLD:
		return IntensityLevel.BUILD
	return IntensityLevel.CALM


## Mevcut seviyenin adı.
func level_name() -> String:
	return LEVEL_NAMES.get(current_level(), "?")


## Şu an kaç katman aktif olmalı?
func active_layer_count() -> int:
	return int(LEVEL_LAYERS.get(current_level(), 1))


## Belirli bir katman (0-indexli) şu an aktif mi?
## layer_index 0 = temel katman (her zaman aktif).
func is_layer_active(layer_index: int) -> bool:
	return layer_index < active_layer_count()


# ============================================================
# SORGULAMA
# ============================================================

## Yoğunluk hedefe ulaştı mı (geçiş tamam)?
func is_settled() -> bool:
	return is_equal_approx(current_intensity, target_intensity)


## Yoğunluk artıyor mu?
func is_rising() -> bool:
	return target_intensity > current_intensity


## Durum özeti.
func summary() -> Dictionary:
	return {
		"current_intensity": current_intensity,
		"target_intensity": target_intensity,
		"level": level_name(),
		"active_layers": active_layer_count(),
		"settled": is_settled(),
	}
