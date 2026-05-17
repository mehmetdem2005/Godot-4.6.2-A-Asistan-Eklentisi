@tool
class_name AILifecycleMemoryMonitor
extends RefCounted

## MemoryPressureHandler — bellek baskısı izleyici (Madde 10).
##
## Mobil cihazda bellek kısıtlı. Android, bellek azaldığında uygulamayı
## uyarır — tepki vermezsen sistem uygulamayı öldürür. Bu sınıf bellek
## durumunu SEVİYELENDİRİR ve uygun tepkiyi önerir.
##
## Seviyeler:
##   NORMAL   — sorun yok
##   MODERATE — önbellekleri küçült (önlem)
##   CRITICAL — agresif temizlik, gereksiz her şeyi bırak
##
## Bu sınıf gerçek belleği OS'tan okumaz (o ince sarmalayıcının işi);
## kendisine bildirilen bellek değerini seviyelendirir — test
## edilebilir saf mantık.
##
## Mock policy: seviye gerçek bellek değerinden hesaplanır.

## Bellek baskı seviyeleri.
enum PressureLevel { NORMAL, MODERATE, CRITICAL }

const LEVEL_NAMES: Dictionary = {
	PressureLevel.NORMAL: "normal",
	PressureLevel.MODERATE: "moderate",
	PressureLevel.CRITICAL: "critical",
}

## Kullanım oranı eşikleri (0.0 - 1.0).
const MODERATE_THRESHOLD: float = 0.75
const CRITICAL_THRESHOLD: float = 0.90


## Son hesaplanan seviye.
var current_level: int = PressureLevel.NORMAL


# ============================================================
# SEVİYELENDİRME
# ============================================================

## Bellek kullanım oranından baskı seviyesini hesaplar.
## usage_ratio: kullanılan / toplam bellek (0.0 - 1.0).
## Dönen: PressureLevel.
func evaluate(usage_ratio: float) -> int:
	var ratio: float = clampf(usage_ratio, 0.0, 1.0)
	if ratio >= CRITICAL_THRESHOLD:
		current_level = PressureLevel.CRITICAL
	elif ratio >= MODERATE_THRESHOLD:
		current_level = PressureLevel.MODERATE
	else:
		current_level = PressureLevel.NORMAL
	return current_level


## Mevcut seviyenin adı.
func level_name() -> String:
	return LEVEL_NAMES.get(current_level, "?")


# ============================================================
# TEPKİ ÖNERİSİ
# ============================================================

## Mevcut seviye için önerilen tepkileri döndürür.
## Dönen: tepki adımları (PackedStringArray).
func recommended_actions() -> PackedStringArray:
	match current_level:
		PressureLevel.CRITICAL:
			return PackedStringArray([
				"Tüm önbellekleri boşalt",
				"Kullanılmayan dokuları sil",
				"Acil kayıt yap (sistem uygulamayı öldürebilir)",
				"Düşük kaliteye geç",
			])
		PressureLevel.MODERATE:
			return PackedStringArray([
				"Doku önbelleğini küçült",
				"Uzaktaki sahne parçalarını boşalt",
			])
		_:
			return PackedStringArray()


## Acil kayıt gerekli mi? (CRITICAL seviyede sistem öldürebilir)
func needs_emergency_save() -> bool:
	return current_level == PressureLevel.CRITICAL


## Önbellek temizliği gerekli mi? (MODERATE ve üstü)
func needs_cache_trim() -> bool:
	return current_level != PressureLevel.NORMAL


## Durum özeti.
func summary() -> Dictionary:
	return {
		"level": level_name(),
		"needs_emergency_save": needs_emergency_save(),
		"needs_cache_trim": needs_cache_trim(),
	}
