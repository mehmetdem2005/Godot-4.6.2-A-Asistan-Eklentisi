@tool
class_name AISaveConflictResolver
extends RefCounted

## ConflictResolver — çakışma çözücü (Madde 09 / cloud_stubs).
##
## Bulut senkronizasyonun en zor kısmı: ÇAKIŞMA. Oyuncu telefonda
## oynar (çevrimdışı), sonra tablette oynar — şimdi iki farklı kayıt
## var. Hangisi geçerli?
##
## Bu sınıf yerel ve bulut kaydını karşılaştırır, bir çözüm önerir:
##   USE_LOCAL    — yerel daha yeni/ilerlemiş
##   USE_CLOUD    — bulut daha yeni/ilerlemiş
##   IDENTICAL    — ikisi aynı, çakışma yok
##   ASK_USER     — net karar yok, oyuncu seçmeli
##
## "Mock yasak": belirsizken sahte karar vermez — ASK_USER der,
## oyuncuya bırakır. Veri kaybı riski varsa otomatik seçim yapmaz.
##
## Mock policy: karar gerçek zaman damgası + ilerleme metriğinden.

## Çakışma çözüm kararı.
enum Resolution { USE_LOCAL, USE_CLOUD, IDENTICAL, ASK_USER }

const RESOLUTION_NAMES: Dictionary = {
	Resolution.USE_LOCAL: "use_local",
	Resolution.USE_CLOUD: "use_cloud",
	Resolution.IDENTICAL: "identical",
	Resolution.ASK_USER: "ask_user",
}

## İki kaydın zaman damgası bu süreden fazla farklıysa "belirgin
## fark" — net karar verilebilir (saniye).
const SIGNIFICANT_TIME_GAP: int = 60


## Bir çakışma çözüm sonucu.
class ResolutionResult extends RefCounted:
	var resolution: int = AISaveConflictResolver.Resolution.ASK_USER
	var reason: String = ""
	var local_newer: bool = false
	var time_gap_seconds: int = 0

	func resolution_name() -> String:
		return AISaveConflictResolver.RESOLUTION_NAMES.get(
			resolution, "?"
		)

	func needs_user_decision() -> bool:
		return resolution == AISaveConflictResolver.Resolution.ASK_USER

	func to_dict() -> Dictionary:
		return {
			"resolution": resolution_name(),
			"reason": reason,
			"time_gap_seconds": time_gap_seconds,
		}


# ============================================================
# ÇAKIŞMA ÇÖZÜMÜ
# ============================================================

## Yerel ve bulut kaydını karşılaştırıp çözüm önerir.
## local_meta: yerel kayıt metadata'sı {timestamp, playtime, progress}.
## cloud_meta: bulut kayıt metadata'sı (aynı yapı).
## Dönen: ResolutionResult.
func resolve(
	local_meta: Dictionary, cloud_meta: Dictionary
) -> ResolutionResult:
	var result := ResolutionResult.new()

	var local_time: int = int(local_meta.get("timestamp", 0))
	var cloud_time: int = int(cloud_meta.get("timestamp", 0))
	var gap: int = absi(local_time - cloud_time)
	result.time_gap_seconds = gap
	result.local_newer = local_time > cloud_time

	# --- Aynı kayıt — çakışma yok ---
	if gap == 0 and _progress_equal(local_meta, cloud_meta):
		result.resolution = Resolution.IDENTICAL
		result.reason = "Kayıtlar aynı — çakışma yok"
		return result

	# --- Zaman farkı belirgin — daha yeni olan kazanır ---
	if gap >= SIGNIFICANT_TIME_GAP:
		if local_time > cloud_time:
			result.resolution = Resolution.USE_LOCAL
			result.reason = "Yerel kayıt belirgin şekilde daha yeni"
		else:
			result.resolution = Resolution.USE_CLOUD
			result.reason = "Bulut kaydı belirgin şekilde daha yeni"
		return result

	# --- Zaman yakın ama ilerleme farklı olabilir ---
	# İlerleme net üstünse onu seç, değilse kullanıcıya sor
	var local_progress: float = float(local_meta.get("progress", 0.0))
	var cloud_progress: float = float(cloud_meta.get("progress", 0.0))

	if local_progress > cloud_progress and \
			absf(local_progress - cloud_progress) > 0.1:
		result.resolution = Resolution.USE_LOCAL
		result.reason = "Zaman yakın ama yerel ilerleme daha fazla"
		return result
	if cloud_progress > local_progress and \
			absf(local_progress - cloud_progress) > 0.1:
		result.resolution = Resolution.USE_CLOUD
		result.reason = "Zaman yakın ama bulut ilerlemesi daha fazla"
		return result

	# --- Net karar yok — kullanıcıya bırak ---
	result.resolution = Resolution.ASK_USER
	result.reason = "Kayıtlar yakın — hangisinin tutulacağını oyuncu seçmeli"
	return result


## İki kaydın ilerlemesi eşit mi?
func _progress_equal(local_meta: Dictionary, cloud_meta: Dictionary) -> bool:
	var local_progress: float = float(local_meta.get("progress", 0.0))
	var cloud_progress: float = float(cloud_meta.get("progress", 0.0))
	return is_equal_approx(local_progress, cloud_progress)


# ============================================================
# SORGULAMA
# ============================================================

## Bir çakışma otomatik çözülebilir mi (kullanıcı gerekmez)?
func is_auto_resolvable(
	local_meta: Dictionary, cloud_meta: Dictionary
) -> bool:
	var result: ResolutionResult = resolve(local_meta, cloud_meta)
	return not result.needs_user_decision()
