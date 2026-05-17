@tool
class_name AILifecyclePermissionFlow
extends RefCounted

## PermissionRequestFlow — izin isteme akışı (Madde 10 / Lifecycle).
##
## İzin istemek tek adım değil, bir AKIŞTIR. Doğru yapılırsa
## kullanıcı izni verir; yanlış yapılırsa kalıcı reddeder.
##
## İyi akış:
##   1. İzin zaten var mı? -> varsa hiçbir şey yapma
##   2. Kalıcı reddedilmiş mi? -> ayarlara yönlendir
##   3. Daha önce reddedilmiş mi? -> ÖNCE gerekçe (rationale) göster
##      ("Mikrofon sesli sohbet için gerekli") sonra iste
##   4. Hiç sorulmamış mı? -> doğrudan iste
##
## Bu sınıf akışın HANGİ ADIMDA olduğunu belirler — gerçek izin
## diyaloğu ince sarmalayıcının işi. Test edilebilir karar mantığı.
##
## Mock policy: akış kararı gerçek izin durumundan.

## Akışın bir sonraki adımı.
enum FlowStep { ALREADY_GRANTED, SHOW_RATIONALE, REQUEST_DIRECTLY, REDIRECT_TO_SETTINGS }

const STEP_NAMES: Dictionary = {
	FlowStep.ALREADY_GRANTED: "already_granted",
	FlowStep.SHOW_RATIONALE: "show_rationale",
	FlowStep.REQUEST_DIRECTLY: "request_directly",
	FlowStep.REDIRECT_TO_SETTINGS: "redirect_to_settings",
}


## İzin yöneticisi.
var _manager: AILifecyclePermissionManager


func _init(manager: AILifecyclePermissionManager = null) -> void:
	if manager != null:
		_manager = manager
	else:
		_manager = AILifecyclePermissionManager.new()


## İzin yöneticisine erişim.
func manager() -> AILifecyclePermissionManager:
	return _manager


# ============================================================
# AKIŞ KARARI
# ============================================================

## Bir izin için akışın bir sonraki adımını belirler.
## permission: istenecek izin.
## Dönen: {step: String, action: String}
func next_step(permission: String) -> Dictionary:
	var status: int = _manager.get_status(permission)

	# Zaten verilmiş — hiçbir şey yapma
	if status == AILifecyclePermissionManager.PermStatus.GRANTED:
		return {
			"step": STEP_NAMES[FlowStep.ALREADY_GRANTED],
			"action": "İzin zaten var, işleme devam",
		}

	# Kalıcı reddedilmiş — ayarlara yönlendir
	if status == AILifecyclePermissionManager.PermStatus.DENIED_PERMANENTLY:
		return {
			"step": STEP_NAMES[FlowStep.REDIRECT_TO_SETTINGS],
			"action": "Kullanıcıyı uygulama ayarlarına yönlendir",
		}

	# Daha önce reddedilmiş — önce gerekçe göster
	if status == AILifecyclePermissionManager.PermStatus.DENIED:
		return {
			"step": STEP_NAMES[FlowStep.SHOW_RATIONALE],
			"action": "Önce neden gerekli olduğunu açıkla, sonra iste",
		}

	# Hiç sorulmamış (UNKNOWN) — doğrudan iste
	return {
		"step": STEP_NAMES[FlowStep.REQUEST_DIRECTLY],
		"action": "İzni doğrudan iste",
	}


## Bir izin isteğinin sonucunu işler — sistem cevabını duruma çevirir.
## permission: istenen izin. granted: kullanıcı verdi mi.
## dont_ask_again: kullanıcı "bir daha sorma" işaretledi mi.
## Dönen: kaydedilen yeni durum (String).
func handle_result(
	permission: String, granted: bool, dont_ask_again: bool = false
) -> String:
	var new_status: int
	if granted:
		new_status = AILifecyclePermissionManager.PermStatus.GRANTED
	elif dont_ask_again:
		# Reddetti + "bir daha sorma" — kalıcı red
		new_status = AILifecyclePermissionManager.PermStatus \
			.DENIED_PERMANENTLY
	else:
		new_status = AILifecyclePermissionManager.PermStatus.DENIED
	_manager.set_status(permission, new_status)
	return _manager.status_name(permission)


# ============================================================
# SORGULAMA
# ============================================================

## Bir izin için gerekçe gösterilmeli mi?
func needs_rationale(permission: String) -> bool:
	var step: Dictionary = next_step(permission)
	return step["step"] == STEP_NAMES[FlowStep.SHOW_RATIONALE]


## Bir izin isteği gerekli mi (zaten verilmemişse)?
func request_needed(permission: String) -> bool:
	var step: Dictionary = next_step(permission)
	return step["step"] != STEP_NAMES[FlowStep.ALREADY_GRANTED]
