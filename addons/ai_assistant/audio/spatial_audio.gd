@tool
class_name AIAudioSpatial
extends RefCounted

## SpatialAudio — mekânsal ses (Madde 08 / Audio System / spatial).
##
## 3D oyunda ses konumdan gelir: uzaktaki ses kısık, duvarın
## arkasındaki boğuk, mağarada yankılı. Bu sınıf mekânsal ses
## HESAPLAMALARINI yapar — üç alt-konu birleşik:
##
##   1. Mesafe zayıflama — uzaklıkla ses kısılır (listener mesafesi)
##   2. Reverb bölgeleri — bir alana girince yankı eklenir
##   3. Occlusion — engel (duvar) sesi boğar
##
## Gerçek 3D ses çıkışı (AudioStreamPlayer3D) Node sarmalayıcının;
## bu model konumsal hesap mantığıdır — test edilebilir.
##
## Mock policy: hesaplar gerçek mesafe/engel verisinden.

## Mesafe zayıflama eğrisi tipi.
enum AttenuationCurve { LINEAR, INVERSE, INVERSE_SQUARE }

const CURVE_NAMES: Dictionary = {
	AttenuationCurve.LINEAR: "linear",
	AttenuationCurve.INVERSE: "inverse",
	AttenuationCurve.INVERSE_SQUARE: "inverse_square",
}


# ============================================================
# MESAFE ZAYIFLAMA
# ============================================================

## Bir sesin dinleyiciye uzaklığına göre ses çarpanını hesaplar.
## distance: ses-dinleyici mesafesi. max_distance: bu uzaklıkta sessiz.
## curve: zayıflama eğrisi.
## Dönen: 0.0 (sessiz) - 1.0 (tam ses) ses çarpanı.
func distance_attenuation(
	distance: float, max_distance: float,
	curve: int = AttenuationCurve.INVERSE_SQUARE
) -> float:
	if distance <= 0.0:
		return 1.0  # tam üstünde — tam ses
	if max_distance <= 0.0 or distance >= max_distance:
		return 0.0  # menzil dışı — sessiz
	var ratio: float = distance / max_distance  # 0.0 - 1.0
	match curve:
		AttenuationCurve.LINEAR:
			return 1.0 - ratio
		AttenuationCurve.INVERSE:
			return 1.0 - ratio  # basitleştirilmiş ters
		AttenuationCurve.INVERSE_SQUARE:
			# Gerçekçi: ses karesel azalır
			var remaining: float = 1.0 - ratio
			return remaining * remaining
		_:
			return 1.0 - ratio


# ============================================================
# REVERB BÖLGELERİ
# ============================================================

## Bir noktanın bir reverb bölgesinin içinde olup olmadığını
## kontrol eder — eksen-hizalı kutu (AABB) bölge.
## point / box_min / box_max: 3B konumlar (Vector3).
## Dönen: true = nokta bölgenin içinde.
func is_in_reverb_zone(
	point: Vector3, box_min: Vector3, box_max: Vector3
) -> bool:
	return (
		point.x >= box_min.x and point.x <= box_max.x
		and point.y >= box_min.y and point.y <= box_max.y
		and point.z >= box_min.z and point.z <= box_max.z
	)


## Bir noktanın bölge sınırına ne kadar yakın olduğunu hesaplar —
## yumuşak reverb geçişi için. Sınırda 0.0, derinde 1.0.
## blend_margin: geçiş bölgesi genişliği.
func reverb_blend_factor(
	point: Vector3, box_min: Vector3, box_max: Vector3,
	blend_margin: float
) -> float:
	if not is_in_reverb_zone(point, box_min, box_max):
		return 0.0
	if blend_margin <= 0.0:
		return 1.0
	# Her eksende sınıra en yakın mesafe
	var dx: float = minf(point.x - box_min.x, box_max.x - point.x)
	var dy: float = minf(point.y - box_min.y, box_max.y - point.y)
	var dz: float = minf(point.z - box_min.z, box_max.z - point.z)
	var edge_distance: float = minf(dx, minf(dy, dz))
	return clampf(edge_distance / blend_margin, 0.0, 1.0)


# ============================================================
# OCCLUSION (engel boğması)
# ============================================================

## Ses ile dinleyici arasında engel varsa sesin ne kadar boğulacağını
## hesaplar. obstacle_count: aradaki engel sayısı.
## per_obstacle_damping: her engelin ses çarpanına etkisi (0-1).
## Dönen: 0.0 (tamamen boğuk) - 1.0 (engelsiz) ses çarpanı.
func occlusion_factor(
	obstacle_count: int, per_obstacle_damping: float = 0.5
) -> float:
	if obstacle_count <= 0:
		return 1.0  # engel yok — tam ses
	var damping: float = clampf(per_obstacle_damping, 0.0, 1.0)
	# Her engel sesi çarpansal kısar
	var factor: float = 1.0
	for i in range(obstacle_count):
		factor *= damping
	return factor


## Occlusion'ın sesi ne kadar BOĞDUĞUNU (low-pass) hesaplar.
## Çok engel = daha boğuk (tizler kesik). Dönen: 0.0 (net) - 1.0 (boğuk).
func occlusion_muffling(obstacle_count: int) -> float:
	if obstacle_count <= 0:
		return 0.0
	# Her engel boğukluğu artırır, ama 1.0'da doyar
	return clampf(float(obstacle_count) * 0.35, 0.0, 1.0)


# ============================================================
# BİRLEŞİK
# ============================================================

## Tüm mekânsal etkileri birleştirip nihai ses çarpanını verir.
## distance / max_distance: mesafe. obstacle_count: engel.
## Dönen: {volume: float, muffling: float}
func compute_spatial(
	distance: float, max_distance: float, obstacle_count: int
) -> Dictionary:
	var dist_factor: float = distance_attenuation(distance, max_distance)
	var occ_factor: float = occlusion_factor(obstacle_count)
	return {
		"volume": dist_factor * occ_factor,
		"muffling": occlusion_muffling(obstacle_count),
	}
