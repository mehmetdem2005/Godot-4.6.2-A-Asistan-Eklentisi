@tool
class_name AIAgentMessage
extends RefCounted

## Ajanlar arası taşınan değişmez mesaj sözleşmesi.
## Mesajlar araç çalıştırmaz; yalnız koordinasyon runtime'ında kuyruklanır.

const VALID_KINDS: PackedStringArray = [
	"assignment", "review_request", "review_result", "status",
	"question", "answer", "escalation", "memory_note", "lock_notice",
]
const VALID_PRIORITIES: PackedStringArray = ["low", "normal", "high", "critical"]
const DEFAULT_TTL_MS: int = 15 * 60 * 1000
const MAX_PAYLOAD_CHARS: int = 32000

var message_id: String = ""
var correlation_id: String = ""
var sender_role_id: String = ""
var recipient_role_id: String = ""
var department: String = ""
var kind: String = "status"
var priority: String = "normal"
var subject: String = ""
var body: String = ""
var payload: Dictionary = {}
var created_at_ms: int = 0
var expires_at_ms: int = 0
var requires_ack: bool = false
var acknowledged: bool = false


static func create(
	id: String,
	sender: String,
	recipient: String,
	message_kind: String,
	message_subject: String,
	message_body: String,
	data: Dictionary = {},
	message_priority: String = "normal",
	correlation: String = "",
	ack_required: bool = false,
	ttl_ms: int = DEFAULT_TTL_MS
) -> AIAgentMessage:
	var message := AIAgentMessage.new()
	message.message_id = id.strip_edges()
	message.sender_role_id = sender.strip_edges()
	message.recipient_role_id = recipient.strip_edges()
	message.kind = message_kind.strip_edges()
	message.subject = message_subject.strip_edges()
	message.body = message_body
	message.payload = data.duplicate(true)
	message.priority = message_priority.strip_edges()
	message.correlation_id = correlation.strip_edges()
	message.requires_ack = ack_required
	message.created_at_ms = Time.get_ticks_msec()
	message.expires_at_ms = message.created_at_ms + maxi(1000, ttl_ms)
	return message


func validate(chart: AIAgentOrgChart = null) -> Dictionary:
	var errors := PackedStringArray()
	if message_id.is_empty():
		errors.append("message_id boş")
	if sender_role_id.is_empty() or recipient_role_id.is_empty():
		errors.append("sender/recipient boş")
	if sender_role_id == recipient_role_id and kind != "memory_note":
		errors.append("ajan kendine bu mesaj türünü gönderemez")
	if not VALID_KINDS.has(kind):
		errors.append("geçersiz mesaj türü: " + kind)
	if not VALID_PRIORITIES.has(priority):
		errors.append("geçersiz öncelik: " + priority)
	if subject.is_empty():
		errors.append("konu boş")
	if body.length() + JSON.stringify(payload).length() > MAX_PAYLOAD_CHARS:
		errors.append("mesaj payload sınırı aşıldı")
	if expires_at_ms <= created_at_ms:
		errors.append("geçersiz TTL")
	if chart != null:
		if not chart.has_role(sender_role_id):
			errors.append("gönderen rol yok: " + sender_role_id)
		if not chart.has_role(recipient_role_id):
			errors.append("alıcı rol yok: " + recipient_role_id)
	return {"ok": errors.is_empty(), "errors": Array(errors)}


func is_expired(now_ms: int = -1) -> bool:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	return now >= expires_at_ms


func acknowledge() -> bool:
	if not requires_ack or acknowledged:
		return false
	acknowledged = true
	return true


func to_dict() -> Dictionary:
	return {
		"message_id": message_id,
		"correlation_id": correlation_id,
		"sender_role_id": sender_role_id,
		"recipient_role_id": recipient_role_id,
		"department": department,
		"kind": kind,
		"priority": priority,
		"subject": subject,
		"body": body,
		"payload": payload.duplicate(true),
		"created_at_ms": created_at_ms,
		"expires_at_ms": expires_at_ms,
		"requires_ack": requires_ack,
		"acknowledged": acknowledged,
	}
