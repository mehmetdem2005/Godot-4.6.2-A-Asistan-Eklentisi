@tool
class_name AICellMessage
extends AIContractBase

## CellMessage — Pilot Cell role'leri arası mesaj (Layer 9).
##
## Cell role'ler (PM, Architect, Engineer'lar, QA...) birbirleriyle yapılandırılmış
## mesajlar üzerinden konuşur. Bir rol iş teslim eder, diğeri geri bildirim verir.
##
## Reflection loop: QA -> Engineer feedback mesajları bu tip üzerinden akar.

## Mesaj tipleri.
enum MessageType {
	HANDOFF,      ## İş teslimi (bir sonraki role)
	FEEDBACK,     ## Geri bildirim (reflection loop)
	REQUEST,      ## Bilgi/yardım isteği
	REPORT,       ## Durum raporu
	ESCALATION,   ## Üst role'e yükseltme (çözülemeyen sorun)
}

const MESSAGE_TYPE_NAMES: Dictionary = {
	MessageType.HANDOFF: "handoff",
	MessageType.FEEDBACK: "feedback",
	MessageType.REQUEST: "request",
	MessageType.REPORT: "report",
	MessageType.ESCALATION: "escalation",
}

# --- Kimlik ---
var id: String = ""
var conversation_ref: String = ""    ## Aynı konuşmaya ait mesajları gruplar
var task_ref: String = ""

# --- Yönlendirme ---
var from_role: String = ""           ## Gönderen cell role
var to_role: String = ""             ## Alıcı cell role
var message_type: int = MessageType.HANDOFF

# --- İçerik ---
var subject: String = ""             ## Kısa konu
var body: String = ""                ## Mesaj gövdesi
var payload: Dictionary = {}         ## Yapılandırılmış veri (artifact, spec, vs.)

# --- Reflection loop ---
var iteration_round: int = 0         ## Reflection turu (0 = ilk, max 3)
var requires_response: bool = false  ## Yanıt bekleniyor mu

# --- Zaman ---
var sent_at: String = ""


func contract_type() -> String:
	return "CellMessage"


## Yeni bir cell mesajı oluşturur (factory).
static func create(
	p_from_role: String, p_to_role: String, p_type: int
) -> AICellMessage:
	var m := AICellMessage.new()
	m.id = AIContractBase.generate_id("msg")
	m.from_role = p_from_role
	m.to_role = p_to_role
	m.message_type = p_type
	m.sent_at = AIContractBase.now_iso()
	return m


## Mesaj tipinin string adı.
func message_type_name() -> String:
	return MESSAGE_TYPE_NAMES.get(message_type, "handoff")


## Bu mesaj bir reflection feedback mı?
func is_feedback() -> bool:
	return message_type == MessageType.FEEDBACK


## Bu mesaj bir escalation mı (çözülemeyen sorun yukarı taşınıyor)?
func is_escalation() -> bool:
	return message_type == MessageType.ESCALATION


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"conversation_ref": conversation_ref,
		"task_ref": task_ref,
		"from_role": from_role,
		"to_role": to_role,
		"message_type": MESSAGE_TYPE_NAMES.get(message_type, "handoff"),
		"subject": subject,
		"body": body,
		"payload": payload,
		"iteration_round": iteration_round,
		"requires_response": requires_response,
		"sent_at": sent_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	conversation_ref = data.get("conversation_ref", "")
	task_ref = data.get("task_ref", "")
	from_role = data.get("from_role", "")
	to_role = data.get("to_role", "")
	message_type = _parse_type(data.get("message_type", "handoff"))
	subject = data.get("subject", "")
	body = data.get("body", "")
	payload = data.get("payload", {})
	iteration_round = int(data.get("iteration_round", 0))
	requires_response = bool(data.get("requires_response", false))
	sent_at = data.get("sent_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, from_role, "from_role")
	require_non_empty_string(result, to_role, "to_role")
	# Bir rol kendine mesaj göndermemeli
	if from_role == to_role:
		result.add_warning("from_role ve to_role aynı (%s)" % from_role)
	# Reflection turu sınırı (max 3 — sonsuz döngü koruması)
	if iteration_round > 3:
		result.add_warning(
			"iteration_round 3'ü aştı (%d) — reflection loop limiti" % iteration_round
		)
	if iteration_round < 0:
		result.add_error("iteration_round negatif olamaz")


static func _parse_type(s: String) -> int:
	for key in MESSAGE_TYPE_NAMES:
		if MESSAGE_TYPE_NAMES[key] == s:
			return key
	return MessageType.HANDOFF
