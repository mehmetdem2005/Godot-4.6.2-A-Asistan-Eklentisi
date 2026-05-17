@tool
class_name AIAgentBrain
extends RefCounted

## AgentBrain — ajan düşünme mekanizması (Layer 9 / Pilot Cell zekâsı).
##
## CellAgent bir ajanın İSKELETİ (gelen kutusu, görev alma). AgentBrain
## o ajanın ZEKÂSI: bir görevi alıp gerçekten "düşünme" işlemi.
##
## Akış:
##   1. RolePrompts'tan rolün sistem promptunu + görev mesajını al
##   2. Bir AIProviderRequest kur (Layer 0 contract)
##   3. Layer 7 Router'a gönder
##   4. LLM cevabını işle, WorkResult döndür
##
## ÖNEMLİ — live_mode:
##   Layer 7'deki desenle aynı. Container'da / anahtar yokken gerçek
##   ağ çağrısı yapılamaz. live_mode=false iken Brain deterministik
##   bir "hazırlandı ama LLM bekliyor" sonucu döndürür — sahte cevap
##   ÜRETMEZ. API anahtarı gelince live_mode=true, Brain gerçekten
##   düşünür.
##
## Mock policy: live_mode=false iken Brain asla sahte LLM çıktısı
## uydurmaz; isteğin hazır olduğunu ama çağrının yapılamadığını
## açıkça raporlar.

## Bağlı Router — LLM çağrıları buradan geçer.
var _router: AIProviderRouter = null

## Canlı mod — true ise gerçek LLM çağrısı yapılır.
## false (varsayılan): istek hazırlanır ama çağrılmaz (anahtar yok).
var live_mode: bool = false


## Bir düşünme işleminin sonucu.
class ThoughtResult extends RefCounted:
	var role: int = 0
	var llm_called: bool = false       ## Gerçek LLM çağrısı yapıldı mı
	var success: bool = false          ## Cevap başarıyla alındı mı
	var content: String = ""           ## LLM cevabı (veya boş)
	var prepared_request: AIProviderRequest = null  ## Kurulan istek
	var status_note: String = ""       ## İnsan-okunur durum

	func to_dict() -> Dictionary:
		return {
			"role": AICellRoles.role_name(role),
			"llm_called": llm_called,
			"success": success,
			"status_note": status_note,
			"content_length": content.length(),
		}


## Router'ı bağlar — ajan beyni bunsuz çalışamaz (live modda).
func attach_router(router: AIProviderRouter) -> void:
	_router = router


## Canlı modu açar/kapatır.
func set_live_mode(value: bool) -> void:
	live_mode = value


# ============================================================
# DÜŞÜNME
# ============================================================

## Bir rol için bir görevi "düşünür".
##
## role: hangi rol (AICellRoles.Role).
## task: yapılacak iş. context: önceki rollerden gelen veri.
## Dönen: ThoughtResult.
func think(role: int, task: String, context: Dictionary = {}) -> ThoughtResult:
	var result := ThoughtResult.new()
	result.role = role

	# Rolün promptu var mı
	if not AIRolePrompts.has_prompt(role):
		result.status_note = "Rol için prompt tanımlı değil: %s" % (
			AICellRoles.role_name(role)
		)
		return result

	# --- İsteği kur ---
	var request: AIProviderRequest = _build_request(role, task, context)
	result.prepared_request = request

	# --- Canlı mod değilse: istek hazır, çağrı yok ---
	if not live_mode:
		result.status_note = (
			"İstek hazırlandı — canlı mod kapalı, LLM çağrılmadı "
			+ "(API anahtarı gelince live_mode=true)"
		)
		return result

	# --- Router yoksa çağrı yapılamaz ---
	if _router == null:
		result.status_note = "Router bağlı değil — LLM çağrısı yapılamaz"
		return result

	# --- Gerçek LLM çağrısı ---
	result.llm_called = true
	var route_result: Dictionary = _router.route(request)
	var response: AIProviderResponse = route_result.get("response", null)

	if response == null:
		result.status_note = "Router yanıt döndürmedi"
		return result
	if not response.ok:
		result.status_note = "LLM çağrısı başarısız: " + response.error_message
		return result

	# Başarılı — cevabı al
	result.success = true
	result.content = response.content
	result.status_note = "LLM cevabı alındı"
	return result


## Bir rol + görev için AIProviderRequest kurar.
func _build_request(
	role: int, task: String, context: Dictionary
) -> AIProviderRequest:
	var purpose: int = AIRolePrompts.purpose_for(role)
	var request := AIProviderRequest.create(
		purpose, AICellRoles.role_name(role)
	)
	# Sistem promptu — rolün kimliği
	var system: String = AIRolePrompts.system_prompt(role)
	request.add_message("system", system)
	# Kullanıcı mesajı — görev + bağlam
	var task_msg: String = AIRolePrompts.build_task_message(
		role, task, context
	)
	request.add_message("user", task_msg)
	return request


# ============================================================
# DURUM
# ============================================================

## Beyin gerçek düşünmeye hazır mı (canlı mod + router)?
func is_ready_to_think() -> bool:
	return live_mode and _router != null


## Beyin durum özeti.
func status() -> Dictionary:
	return {
		"live_mode": live_mode,
		"router_attached": _router != null,
		"ready": is_ready_to_think(),
	}
