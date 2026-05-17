@tool
class_name AIOfflineFallbackRouter
extends RefCounted

## ProceduralFallbackRouter — geri-çekilme yönlendiricisi (Madde 07).
##
## Offline sistemin beyni. Bir iş geldiğinde karar verir: bu iş NASIL
## yapılsın? Üç yol var:
##   USE_NETWORK   — bağlantı iyi, normal şekilde ağa çık
##   USE_CACHE     — bağlantı yok ama önbellekte cevap var
##   USE_TEMPLATE  — ne ağ ne önbellek; şablon/prosedürel fallback
##   QUEUE         — şimdi yapılamaz, online olunca için kuyruğa al
##   REJECT        — hiçbir yolla yapılamaz
##
## Bu router connection_monitor + cache + capability_mapper'ı
## birleştirip tek bir net karar üretir. "Mock yasak" ilkesi:
## yapılamayan iş için sahte başarı yok — açıkça QUEUE/REJECT der.
##
## Mock policy: karar gerçek bağlantı + önbellek durumundan.

## Bir iş için yönlendirme kararı.
enum Route { USE_NETWORK, USE_CACHE, USE_TEMPLATE, QUEUE, REJECT }

const ROUTE_NAMES: Dictionary = {
	Route.USE_NETWORK: "use_network",
	Route.USE_CACHE: "use_cache",
	Route.USE_TEMPLATE: "use_template",
	Route.QUEUE: "queue",
	Route.REJECT: "reject",
}


## Bir yönlendirme kararı sonucu.
class RouteDecision extends RefCounted:
	var route: int = AIOfflineFallbackRouter.Route.REJECT
	var capability: String = ""
	var reason: String = ""

	func route_name() -> String:
		return AIOfflineFallbackRouter.ROUTE_NAMES.get(route, "?")

	func to_dict() -> Dictionary:
		return {
			"route": route_name(),
			"capability": capability,
			"reason": reason,
		}


## Bağlantı izleyici.
var _connection: AIOfflineConnectionMonitor

## Yetenek haritalayıcı.
var _capabilities: AIOfflineCapabilityMapper


func _init(
	connection: AIOfflineConnectionMonitor = null,
	capabilities: AIOfflineCapabilityMapper = null
) -> void:
	if connection != null:
		_connection = connection
	else:
		_connection = AIOfflineConnectionMonitor.new()
	if capabilities != null:
		_capabilities = capabilities
	else:
		_capabilities = AIOfflineCapabilityMapper.new()


# ============================================================
# YÖNLENDİRME
# ============================================================

## Bir iş için yönlendirme kararı verir.
## capability: yapılacak işin yeteneği (capability_mapper'dan).
## has_cache: bu iş için önbellekte sonuç var mı.
## has_template: bu iş için şablon fallback var mı.
## queueable: iş kuyruğa alınabilir mi (online olunca yapılır).
## Dönen: RouteDecision.
func route(
	capability: String, has_cache: bool = false,
	has_template: bool = false, queueable: bool = false
) -> RouteDecision:
	var decision := RouteDecision.new()
	decision.capability = capability

	var online: bool = _connection.should_attempt_network()
	var req: int = _capabilities.requirement_of(capability)

	# --- ALWAYS yetenekler — her zaman doğrudan yapılır ---
	if req == AIOfflineCapabilityMapper.Requirement.ALWAYS:
		decision.route = Route.USE_TEMPLATE if has_template \
			else Route.USE_NETWORK
		# ALWAYS işler ağ gerektirmez; "use_network" burada
		# "doğrudan yap" anlamında — şablon varsa onu tercih et
		if has_template:
			decision.reason = "Her zaman çalışır — şablon ile"
		else:
			decision.reason = "Her zaman çalışır — doğrudan"
		return decision

	# --- Bağlantı varsa: ağı kullan ---
	if online:
		decision.route = Route.USE_NETWORK
		decision.reason = "Bağlantı var — ağ kullanılıyor"
		return decision

	# --- Çevrimdışı: önbellek var mı ---
	if has_cache:
		decision.route = Route.USE_CACHE
		decision.reason = "Çevrimdışı — önbellekten karşılanıyor"
		return decision

	# --- Çevrimdışı, önbellek yok: şablon var mı ---
	if has_template:
		decision.route = Route.USE_TEMPLATE
		decision.reason = "Çevrimdışı — şablon fallback kullanılıyor"
		return decision

	# --- Hiçbiri yok: kuyruğa alınabilir mi ---
	if queueable:
		decision.route = Route.QUEUE
		decision.reason = "Çevrimdışı — kuyruğa alındı, online olunca işlenir"
		return decision

	# --- Hiçbir yol yok: reddet (sahte başarı yok) ---
	decision.route = Route.REJECT
	decision.reason = "Çevrimdışı ve fallback yok — iş yapılamıyor"
	return decision


# ============================================================
# SORGULAMA
# ============================================================

## Bir iş şu an herhangi bir yolla yapılabilir mi?
func is_actionable(
	capability: String, has_cache: bool = false,
	has_template: bool = false, queueable: bool = false
) -> bool:
	var decision: RouteDecision = route(
		capability, has_cache, has_template, queueable
	)
	return decision.route != Route.REJECT


## Bağlantı izleyiciye erişim.
func connection() -> AIOfflineConnectionMonitor:
	return _connection
