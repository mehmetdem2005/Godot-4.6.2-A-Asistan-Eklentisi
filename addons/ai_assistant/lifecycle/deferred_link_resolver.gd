@tool
class_name AILifecycleDeferredLink
extends RefCounted

## DeferredLinkResolver — ertelenmiş link çözücü (Madde 10 / deep_links).
##
## Deep link bazen HEMEN işlenemez. Senaryo: kullanıcı bir etkinlik
## linki tıklar ama oyunu ilk kez yüklüyordur — link, oyun yüklenip
## hesap kurulana kadar BEKLEMELİDİR.
##
## "Ertelenmiş deep link" (deferred deep link): link saklanır, oyun
## hazır olunca işlenir. Klasik kullanım: davet linkiyle gelen yeni
## kullanıcı, kurulum bitince doğru yere gider.
##
## Bu sınıf bekleyen linki saklar, oyun hazır olunca çözer. Link
## ESKİYEBİLİR — çok eski bir link artık geçersiz olabilir.
##
## Plan notu: Madde 10'da Phase 2+ stub; temel saklama/çözme mantığı.
##
## Mock policy: çözüm gerçek bekleyen link durumundan.

## Ertelenmiş bir link kaydı.
class DeferredLink extends RefCounted:
	var link: String = ""
	var stored_at_unix: int = 0
	var resolved: bool = false

	func to_dict() -> Dictionary:
		return {
			"link": link, "stored_at": stored_at_unix,
			"resolved": resolved,
		}


## Ertelenmiş linkler bu süreden eskiyse geçersiz (saniye, 7 gün).
const LINK_EXPIRY_SECONDS: int = 604800


## Bekleyen ertelenmiş link (yoksa null).
var _pending: DeferredLink = null


# ============================================================
# LINK SAKLAMA
# ============================================================

## Bir linki ertelenmiş olarak saklar — sonra işlenmek üzere.
## link: saklanacak link. current_unix: şu anki zaman.
## Dönen: true = saklandı.
func defer_link(link: String, current_unix: int) -> bool:
	if link.strip_edges().is_empty():
		return false
	var deferred := DeferredLink.new()
	deferred.link = link
	deferred.stored_at_unix = current_unix
	deferred.resolved = false
	_pending = deferred
	return true


## Bekleyen bir ertelenmiş link var mı?
func has_pending() -> bool:
	return _pending != null and not _pending.resolved


# ============================================================
# ÇÖZÜMLEME
# ============================================================

## Bekleyen linkin süresi dolmuş mu?
## current_unix: şu anki zaman.
func is_expired(current_unix: int) -> bool:
	if _pending == null:
		return false
	return (current_unix - _pending.stored_at_unix) \
		>= LINK_EXPIRY_SECONDS


## Bekleyen ertelenmiş linki çözer — oyun hazır olunca çağrılır.
## current_unix: şu anki zaman — eskime kontrolü.
## Dönen: {resolved: bool, link: String, reason: String}
func resolve(current_unix: int) -> Dictionary:
	# Bekleyen link yok
	if not has_pending():
		return {
			"resolved": false, "link": "",
			"reason": "Bekleyen ertelenmiş link yok",
		}

	# Link eskimiş mi
	if is_expired(current_unix):
		var stale_link: String = _pending.link
		_pending = null
		return {
			"resolved": false, "link": stale_link,
			"reason": "Ertelenmiş link süresi dolmuş — atıldı",
		}

	# Çözülebilir — linki döndür ve işaretle
	var resolved_link: String = _pending.link
	_pending.resolved = true
	return {
		"resolved": true,
		"link": resolved_link,
		"reason": "Ertelenmiş link çözüldü",
	}


## Bekleyen linki çözmeden iptal eder.
func clear_pending() -> void:
	_pending = null


# ============================================================
# SORGULAMA
# ============================================================

## Bekleyen linkin metnini döndürür. Yoksa boş.
func pending_link() -> String:
	if _pending == null:
		return ""
	return _pending.link
