@tool
class_name AILifecycleURLRouter
extends RefCounted

## URLRouter — link yönlendirici (Madde 10 / deep_links).
##
## intent_handler bir linki ayrıştırır (şema/host/yol). Bu sınıf
## ayrıştırılmış linki bir OYUN EYLEMİNE yönlendirir: hangi ekran
## açılacak, hangi parametrelerle.
##
## Bir yönlendirme tablosu tutar: host -> oyun eylemi. "event"
## host'u etkinlik ekranına, "shop" mağazaya, "friend" arkadaş
## davetine gider.
##
## Bilinmeyen host güvenli şekilde reddedilir — rastgele bir link
## oyunu beklenmedik duruma sokmamalı.
##
## Plan notu: Madde 10'da bu Phase 2+ olarak işaretli; burada temel
## yönlendirme mantığı kuruluyor, gerçek ekran açma UI katmanının işi.
##
## Mock policy: yönlendirme gerçek tablo eşleşmesinden.

## Bir yönlendirme sonucu.
class RouteResult extends RefCounted:
	var matched: bool = false
	var action: String = ""            ## Oyun eylemi (örn. "open_event")
	var target: String = ""            ## Hedef (örn. etkinlik kimliği)
	var params: Dictionary = {}
	var reason: String = ""

	func to_dict() -> Dictionary:
		return {
			"matched": matched, "action": action,
			"target": target,
		}


## Yönlendirme tablosu — host -> oyun eylemi.
var _routes: Dictionary = {}


func _init() -> void:
	_register_default_routes()


## Oyunlar için yaygın varsayılan yönlendirmeleri kaydeder.
func _register_default_routes() -> void:
	_routes["event"] = "open_event"
	_routes["shop"] = "open_shop"
	_routes["friend"] = "accept_friend_invite"
	_routes["reward"] = "claim_reward"
	_routes["level"] = "open_level"
	_routes["news"] = "open_news"


# ============================================================
# YÖNLENDİRME TANIMI
# ============================================================

## Bir host için yönlendirme tanımlar/değiştirir.
## host: link host'u. action: oyun eylemi.
func register_route(host: String, action: String) -> bool:
	if host.is_empty() or action.is_empty():
		return false
	_routes[host] = action
	return true


## Bir host yönlendirme tablosunda var mı?
func has_route(host: String) -> bool:
	return _routes.has(host)


## Kayıtlı yönlendirme sayısı.
func route_count() -> int:
	return _routes.size()


# ============================================================
# YÖNLENDİRME
# ============================================================

## Ayrıştırılmış bir linki bir oyun eylemine yönlendirir.
## parsed: IntentHandler'dan gelen ParsedLink.
## Dönen: RouteResult.
func route(parsed: AILifecycleIntentHandler.ParsedLink) -> RouteResult:
	var result := RouteResult.new()

	# Link geçerli değilse yönlendirme yok
	if not parsed.valid:
		result.reason = "Geçersiz link yönlendirilemez: " + parsed.error
		return result

	# Host yönlendirme tablosunda var mı
	if not _routes.has(parsed.host):
		result.reason = "Bilinmeyen host — yönlendirme yok: " \
			+ parsed.host
		return result

	# Eşleşti — eylemi belirle
	result.matched = true
	result.action = str(_routes[parsed.host])
	result.params = parsed.params.duplicate()
	# İlk yol parçası genelde hedef kimliktir (event/halloween)
	if not parsed.path_segments.is_empty():
		result.target = parsed.path_segments[0]
	result.reason = "Yönlendirildi: %s -> %s" % [
		parsed.host, result.action
	]
	return result


## Bir host için oyun eylemini döndürür. Yoksa boş string.
func action_for(host: String) -> String:
	return str(_routes.get(host, ""))
