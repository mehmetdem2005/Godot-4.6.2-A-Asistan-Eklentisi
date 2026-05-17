@tool
class_name AICellMessageBus
extends RefCounted

## CellMessageBus — ajanlar arası mesaj veri yolu (Layer 9 / Pilot Cell).
##
## 14 ajan birbirine doğrudan bağlı değil — hepsi bu veri yolu üzerinden
## konuşur. Bir ajan mesaj gönderir, bus onu doğru alıcının gelen
## kutusuna düşürür. Bu, gevşek bağlama sağlar: roller birbirini
## tanımadan haberleşir.
##
## Mesaj tipleri (AICellMessage.MessageType):
##   HANDOFF    — iş teslimi (sıradaki role)
##   FEEDBACK   — geri bildirim (reflection)
##   REQUEST    — yardım isteği
##   REPORT     — durum raporu
##   ESCALATION — üst role yükseltme
##
## Mock policy: bus gerçek mesajları taşır — kayıp/uydurma yok.

## Kayıtlı ajanlar — rol enum -> AICellAgent.
var _agents: Dictionary = {}

## Tüm mesaj trafiği — denetim/replay için kronolojik kayıt.
var _traffic: Array = []

## Konuşma sayacı — her yeni pipeline akışına bir conversation id.
var _conversation_counter: int = 0


# ============================================================
# AJAN KAYDI
# ============================================================

## Bir ajanı veri yoluna kaydeder. Rolü zaten kayıtlıysa üzerine yazar.
func register(agent: AICellAgent) -> void:
	if agent == null:
		push_warning("MessageBus.register: null ajan")
		return
	_agents[agent.role] = agent


## Bir rolün ajanı kayıtlı mı?
func has_agent(role: int) -> bool:
	return _agents.has(role)


## Bir rolün ajanını döndürür. Yoksa null.
func get_agent(role: int) -> AICellAgent:
	return _agents.get(role, null)


## Kayıtlı ajan sayısı.
func agent_count() -> int:
	return _agents.size()


# ============================================================
# MESAJ GÖNDERME
# ============================================================

## Bir mesajı alıcı role yönlendirir.
## Dönen: {ok: bool, reason: String}
func send(message: AICellMessage) -> Dictionary:
	if message == null:
		return {"ok": false, "reason": "Null mesaj"}

	var to_role: int = AICellRoles.role_from_name(message.to_role)
	if to_role < 0:
		return {"ok": false, "reason": "Geçersiz alıcı rol: " + message.to_role}
	if not _agents.has(to_role):
		return {
			"ok": false,
			"reason": "Alıcı ajan kayıtlı değil: " + message.to_role,
		}

	# Mesajı alıcının gelen kutusuna düşür
	(_agents[to_role] as AICellAgent).receive(message)
	# Trafiğe kaydet
	_traffic.append(message)
	return {"ok": true, "reason": ""}


## İki rol arası mesaj oluşturup gönderir — kısa yol.
## Dönen: {ok, reason, message}
func send_between(
	from_role: int, to_role: int, message_type: int,
	subject: String, body: String, conversation_ref: String = ""
) -> Dictionary:
	var message := AICellMessage.create(
		AICellRoles.role_name(from_role),
		AICellRoles.role_name(to_role),
		message_type
	)
	message.subject = subject
	message.body = body
	message.conversation_ref = conversation_ref
	var result: Dictionary = send(message)
	result["message"] = message
	return result


# ============================================================
# KONUŞMA YÖNETİMİ
# ============================================================

## Yeni bir konuşma kimliği üretir — bir pipeline akışını gruplar.
func new_conversation() -> String:
	_conversation_counter += 1
	return AIContractBase.generate_id("conv")


## Belirli bir konuşmaya ait mesajları döndürür.
func conversation_messages(conversation_ref: String) -> Array:
	var result: Array = []
	for m in _traffic:
		if (m as AICellMessage).conversation_ref == conversation_ref:
			result.append(m)
	return result


# ============================================================
# TRAFİK / DENETİM
# ============================================================

## Tüm mesaj trafiği — kronolojik.
func all_traffic() -> Array:
	return _traffic


## Belirli tipte mesajları döndürür (örn. tüm ESCALATION'lar).
func messages_of_type(message_type: int) -> Array:
	var result: Array = []
	for m in _traffic:
		if (m as AICellMessage).message_type == message_type:
			result.append(m)
	return result


## Toplam mesaj sayısı.
func traffic_count() -> int:
	return _traffic.size()


## Veri yolu durum özeti.
func status() -> Dictionary:
	return {
		"registered_agents": _agents.size(),
		"total_messages": _traffic.size(),
		"escalations": messages_of_type(
			AICellMessage.MessageType.ESCALATION
		).size(),
	}


## Trafiği temizler — ajanlar kayıtlı kalır.
func clear_traffic() -> void:
	_traffic.clear()


## Her şeyi sıfırlar — ajanlar + trafik.
func reset() -> void:
	_agents.clear()
	_traffic.clear()
	_conversation_counter = 0
