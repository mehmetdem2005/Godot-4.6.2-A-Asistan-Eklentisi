@tool
class_name AILODPolicy
extends RefCounted

## LODPolicy — detay seviyesi politikası (Layer 10 / Quality Gates).
##
## LOD (Level of Detail): uzaktaki nesneler daha az detayla çizilir.
## Mobilde kritik — kameraya 50 metre uzaktaki ağacın 10000 vertex'i
## olması israftır; 500 vertex yeterli, fark görünmez.
##
## Bu sınıf LOD kurallarını yönetir:
##   - Mesafe eşikleri (hangi uzaklıkta hangi seviye)
##   - Her seviyenin vertex azaltma oranı
##   - Bir mesh için LOD gerekli mi kararı
##
## Godot 4 otomatik LOD sağlar ama eşikler içeriğe göre ayarlanmalı;
## bu sınıf üretilen sahne için makul eşikler önerir.
##
## Mock policy: politika gerçek mesafe/vertex hesabından üretilir.

## LOD seviyeleri — artan uzaklık, azalan detay.
enum LODLevel { LOD0_FULL, LOD1_HIGH, LOD2_MEDIUM, LOD3_LOW, LOD4_IMPOSTOR }

const LOD_LEVEL_NAMES: Dictionary = {
	LODLevel.LOD0_FULL: "lod0_full",
	LODLevel.LOD1_HIGH: "lod1_high",
	LODLevel.LOD2_MEDIUM: "lod2_medium",
	LODLevel.LOD3_LOW: "lod3_low",
	LODLevel.LOD4_IMPOSTOR: "lod4_impostor",
}

## Her LOD seviyesinin vertex koruma oranı (LOD0 = %100).
const LOD_VERTEX_RATIO: Dictionary = {
	LODLevel.LOD0_FULL: 1.0,
	LODLevel.LOD1_HIGH: 0.6,
	LODLevel.LOD2_MEDIUM: 0.3,
	LODLevel.LOD3_LOW: 0.12,
	LODLevel.LOD4_IMPOSTOR: 0.03,
}

## Varsayılan mesafe eşikleri (metre) — bu mesafeden SONRA o seviye.
## Mobil için muhafazakar: detay erken düşer, performans kazanılır.
const DEFAULT_DISTANCE_THRESHOLDS: Dictionary = {
	LODLevel.LOD1_HIGH: 15.0,
	LODLevel.LOD2_MEDIUM: 35.0,
	LODLevel.LOD3_LOW: 70.0,
	LODLevel.LOD4_IMPOSTOR: 130.0,
}

## Bir mesh'in LOD'a değmesi için minimum vertex sayısı.
## Bunun altındaki basit mesh'lere LOD eklemek gereksiz.
const LOD_WORTHWHILE_THRESHOLD: int = 500


## Aktif mesafe eşikleri (ayarlanabilir).
var distance_thresholds: Dictionary = DEFAULT_DISTANCE_THRESHOLDS.duplicate()


# ============================================================
# LOD KARARLARI
# ============================================================

## Bir mesafeye uygun LOD seviyesini döndürür.
func level_for_distance(distance: float) -> int:
	if distance >= float(distance_thresholds.get(LODLevel.LOD4_IMPOSTOR, 130.0)):
		return LODLevel.LOD4_IMPOSTOR
	if distance >= float(distance_thresholds.get(LODLevel.LOD3_LOW, 70.0)):
		return LODLevel.LOD3_LOW
	if distance >= float(distance_thresholds.get(LODLevel.LOD2_MEDIUM, 35.0)):
		return LODLevel.LOD2_MEDIUM
	if distance >= float(distance_thresholds.get(LODLevel.LOD1_HIGH, 15.0)):
		return LODLevel.LOD1_HIGH
	return LODLevel.LOD0_FULL


## Bir mesh'in LOD'a değer olup olmadığını söyler.
## Basit mesh'lere (< eşik vertex) LOD eklemek gereksiz karmaşıklık.
func is_lod_worthwhile(vertex_count: int) -> bool:
	return vertex_count >= LOD_WORTHWHILE_THRESHOLD


## Belirli bir LOD seviyesinde bir mesh'in tahmini vertex sayısı.
func vertices_at_level(base_vertices: int, level: int) -> int:
	var ratio: float = LOD_VERTEX_RATIO.get(level, 1.0)
	return int(round(float(base_vertices) * ratio))


## Bir mesh için tam LOD zinciri önerir.
## base_vertices: LOD0'daki vertex sayısı.
## Dönen: [{level, distance_from, vertices}] — LOD0'dan başlayarak.
func build_lod_chain(base_vertices: int) -> Array:
	var chain: Array = []
	if not is_lod_worthwhile(base_vertices):
		# Basit mesh — tek seviye yeterli
		chain.append({
			"level": LOD_LEVEL_NAMES[LODLevel.LOD0_FULL],
			"distance_from": 0.0,
			"vertices": base_vertices,
		})
		return chain

	var levels: Array = [
		LODLevel.LOD0_FULL, LODLevel.LOD1_HIGH, LODLevel.LOD2_MEDIUM,
		LODLevel.LOD3_LOW, LODLevel.LOD4_IMPOSTOR,
	]
	for level in levels:
		var dist_from: float = 0.0
		if level != LODLevel.LOD0_FULL:
			dist_from = float(distance_thresholds.get(level, 0.0))
		chain.append({
			"level": LOD_LEVEL_NAMES[level],
			"distance_from": dist_from,
			"vertices": vertices_at_level(base_vertices, level),
		})
	return chain


## Bir LOD zincirinin toplam vertex tasarrufunu hesaplar.
## Tüm nesneler LOD2'de varsayılırsa ne kadar kazanılır (kaba tahmin).
func estimated_savings(base_vertices: int) -> Dictionary:
	var full: int = base_vertices
	var typical: int = vertices_at_level(base_vertices, LODLevel.LOD2_MEDIUM)
	return {
		"full_vertices": full,
		"typical_vertices": typical,
		"saved": full - typical,
		"saved_ratio": 1.0 - LOD_VERTEX_RATIO[LODLevel.LOD2_MEDIUM],
	}


# ============================================================
# AYAR
# ============================================================

## Bir LOD seviyesinin mesafe eşiğini ayarlar.
func set_threshold(level: int, distance: float) -> void:
	if LOD_LEVEL_NAMES.has(level) and level != LODLevel.LOD0_FULL:
		distance_thresholds[level] = distance


## Eşikleri varsayılana sıfırlar.
func reset_thresholds() -> void:
	distance_thresholds = DEFAULT_DISTANCE_THRESHOLDS.duplicate()


## Bir LOD seviyesinin adı.
static func level_name(level: int) -> String:
	return LOD_LEVEL_NAMES.get(level, "?")
