@tool
class_name AIAudioLoopPointHandler
extends RefCounted

## LoopPointHandler — döngü noktası yöneticisi (Madde 08 / music_layering).
##
## Oyun müziği sonsuz çalar — ama parça sonludur. Döngü gerekir.
## Naif çözüm: parça bitince baştan başlat. Sorun: çoğu müzikte bir
## GİRİŞ (intro) vardır, o tekrar çalmamalı.
##
## Çözüm: iki nokta tanımla:
##   loop_start — döngünün BAŞLADIĞI an (intro'dan sonra)
##   loop_end   — döngünün BİTTİĞİ an (buradan loop_start'a atlar)
##
## Çalma: intro bir kez -> loop_start..loop_end sonsuz tekrar.
##
## Bu sınıf "şu anki pozisyondan sonra ne olmalı" sorusunu cevaplar:
## devam et, döngü başına atla, ya da intro'yu bitir.
##
## Mock policy: döngü kararı gerçek pozisyon + döngü noktalarından.

## Parçanın toplam süresi (saniye).
var track_duration: float = 0.0

## Döngü başlangıç noktası (saniye) — intro sonrası.
var loop_start: float = 0.0

## Döngü bitiş noktası (saniye) — buradan loop_start'a atlanır.
var loop_end: float = 0.0

## Döngü etkin mi (false ise parça bir kez çalıp durur).
var loop_enabled: bool = true

## Kaç kez döngü tamamlandı.
var _loop_count: int = 0


# ============================================================
# DÖNGÜ TANIMLAMA
# ============================================================

## Döngü noktalarını ayarlar.
## start: döngü başı. end: döngü sonu. total: parça toplam süresi.
## Dönen: true = geçerli noktalar.
func configure(start: float, end: float, total: float) -> bool:
	if total <= 0.0:
		push_warning("LoopPointHandler: geçersiz parça süresi")
		return false
	if start < 0.0 or end > total or start >= end:
		push_warning("LoopPointHandler: geçersiz döngü noktaları")
		return false
	loop_start = start
	loop_end = end
	track_duration = total
	return true


## Tüm parçayı döngüye alır — intro yok, baştan sona tekrar.
func configure_full_loop(total: float) -> bool:
	return configure(0.0, total, total)


# ============================================================
# DÖNGÜ KARARI
# ============================================================

## Bir çalma pozisyonu için sıradaki adımı belirler.
## position: mevcut çalma pozisyonu (saniye).
## Dönen: {action: String, next_position: float, reason: String}
##   action: "continue" | "loop" | "stop"
func evaluate(position: float) -> Dictionary:
	# Döngü kapalı — parça sonunda dur
	if not loop_enabled:
		if position >= track_duration:
			return {
				"action": "stop", "next_position": track_duration,
				"reason": "Parça bitti, döngü kapalı",
			}
		return {
			"action": "continue", "next_position": position,
			"reason": "Çalmaya devam",
		}

	# Döngü açık — loop_end'e ulaşıldı mı
	if position >= loop_end:
		_loop_count += 1
		return {
			"action": "loop",
			"next_position": loop_start,
			"reason": "Döngü sonu — başa atlanıyor",
		}

	# Henüz döngü sonuna gelinmedi
	return {
		"action": "continue",
		"next_position": position,
		"reason": "Çalmaya devam",
	}


## Bir pozisyonun intro bölümünde mi (loop_start öncesi) olduğunu söyler.
func is_in_intro(position: float) -> bool:
	return position < loop_start


## Bir pozisyonun döngü bölgesinde mi olduğunu söyler.
func is_in_loop_region(position: float) -> bool:
	return position >= loop_start and position < loop_end


# ============================================================
# SORGULAMA
# ============================================================

## Döngü bölgesinin uzunluğu (saniye).
func loop_length() -> float:
	return loop_end - loop_start


## İntro uzunluğu (saniye).
func intro_length() -> float:
	return loop_start


## Kaç kez döngü tamamlandı?
func loop_count() -> int:
	return _loop_count


## Döngü sayacını sıfırlar — parça yeniden başlatılınca.
func reset() -> void:
	_loop_count = 0


## Durum özeti.
func summary() -> Dictionary:
	return {
		"loop_enabled": loop_enabled,
		"loop_start": loop_start,
		"loop_end": loop_end,
		"loop_length": loop_length(),
		"loop_count": _loop_count,
	}
