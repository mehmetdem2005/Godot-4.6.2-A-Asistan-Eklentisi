@tool
class_name AICellAgent
extends RefCounted

## CellAgent — tek ajan temel sınıfı (Layer 9 / Pilot Cell).
##
## Pilot Cell'deki 14 rolün her biri bir CellAgent örneğidir. Bu sınıf
## bir ajanın ortak iskeletini tutar:
##   - Kimlik (hangi rol)
##   - Gelen kutusu (kendisine yönelik AICellMessage'lar)
##   - Bir görevi "işleme" sözleşmesi (process_task)
##   - Reflection: kendi çıktısını eleştirme
##
## ÖNEMLİ: Bu sürümde ajan ZEKÂSI iskelettir — gerçek LLM çağrısı
## (Layer 7 Router üzerinden) sonraki Pilot Cell oturumlarında her
## role özel prompt'la eklenecek. Şimdilik process_task bir
## "iş tanımı" üretir; orkestrasyon ve mesaj akışı tam çalışır.
##
## Mock policy: ajan sahte "tamamlandı" demez — yapamadığı işi
## NEEDS_LLM / NOT_IMPLEMENTED olarak işaretler.

## Bir ajan görev işleme sonucu.
enum WorkStatus { DONE, NEEDS_LLM, FAILED, ESCALATED }

const WORK_STATUS_NAMES: Dictionary = {
	WorkStatus.DONE: "done",
	WorkStatus.NEEDS_LLM: "needs_llm",
	WorkStatus.FAILED: "failed",
	WorkStatus.ESCALATED: "escalated",
}


## Bir ajanın bir görevi işleme çıktısı.
class WorkResult extends RefCounted:
	var status: int = AICellAgent.WorkStatus.NEEDS_LLM
	var role: int = 0
	var output: String = ""            ## Üretilen çıktı (kod, tasarım, rapor)
	var summary: String = ""           ## Kısa özet
	var artifacts: Dictionary = {}     ## Yapılandırılmış çıktı
	var needs_reflection: bool = false ## Bu çıktı gözden geçirilmeli mi
	var escalate_reason: String = ""   ## ESCALATED ise neden

	func is_success() -> bool:
		return status == AICellAgent.WorkStatus.DONE

	func to_dict() -> Dictionary:
		return {
			"status": AICellAgent.WORK_STATUS_NAMES.get(status, "?"),
			"role": role,
			"role_name": AICellRoles.role_name(role),
			"summary": summary,
			"needs_reflection": needs_reflection,
			"escalate_reason": escalate_reason,
		}


## Bu ajanın rolü.
var role: int = AICellRoles.Role.PRODUCT_MANAGER

## Gelen kutusu — bu ajana yönelik AICellMessage'lar.
var _inbox: Array = []

## İşlenmiş mesajlar — geçmiş.
var _processed: Array = []

## Ajanın düşünme mekanizması (Layer 9 zekâsı).
var brain: AIAgentBrain


func _init(p_role: int = AICellRoles.Role.PRODUCT_MANAGER) -> void:
	role = p_role
	brain = AIAgentBrain.new()


## Bu ajanın beynine bir Router bağlar — LLM çağrıları için.
func attach_router(router: AIProviderRouter) -> void:
	brain.attach_router(router)


## Ajanın canlı modunu ayarlar (true = gerçek LLM çağrısı).
func set_live_mode(value: bool) -> void:
	brain.set_live_mode(value)


## Bu ajanın rol adı.
func role_name() -> String:
	return AICellRoles.role_name(role)


# ============================================================
# MESAJLAŞMA
# ============================================================

## Bu ajana bir mesaj teslim eder (gelen kutusuna ekler).
func receive(message: AICellMessage) -> void:
	if message == null:
		push_warning("CellAgent.receive: null mesaj")
		return
	_inbox.append(message)


## Gelen kutusundaki mesaj sayısı.
func inbox_count() -> int:
	return _inbox.size()


## Gelen kutusunda bekleyen mesaj var mı?
func has_pending() -> bool:
	return not _inbox.is_empty()


## Gelen kutusundaki sıradaki mesajı alır ve kutudan çıkarır.
## Boşsa null.
func pull_message() -> AICellMessage:
	if _inbox.is_empty():
		return null
	var msg: AICellMessage = _inbox.pop_front()
	_processed.append(msg)
	return msg


# ============================================================
# GÖREV İŞLEME
# ============================================================

## Bir görevi işler. Ajanın beynini (AgentBrain) kullanarak görevi
## "düşünür". Beyin canlı modda ise gerçek LLM çağrısı yapılır;
## değilse istek hazırlanır ama çağrılmaz (NEEDS_LLM) — sahte
## tamamlama YOK.
##
## task_description: ne yapılacak. context: önceki rollerden gelen veri.
## Dönen: WorkResult.
func process_task(task_description: String, context: Dictionary = {}) -> WorkResult:
	var result := WorkResult.new()
	result.role = role

	if task_description.strip_edges().is_empty():
		result.status = WorkStatus.FAILED
		result.summary = "Boş görev tanımı"
		return result

	# Beyin ile düşün
	var thought: AIAgentBrain.ThoughtResult = brain.think(
		role, task_description, context
	)

	if thought.success:
		# Gerçek LLM cevabı alındı — ham metni rol-özel ayrıştır
		var parser := AIOutputParser.new()
		var parsed: AIOutputParser.ParsedOutput = parser.parse(
			role, thought.content
		)
		result.status = WorkStatus.DONE
		result.output = thought.content
		result.summary = "%s tamamladı: %s" % [
			role_name(), task_description.left(50)
		]
		result.artifacts = {
			"role": role_name(),
			"llm_content": thought.content,
			"parsed_kind": AIOutputParser.PARSED_KIND_NAMES.get(
				parsed.kind, "?"
			),
			"structured": parsed.structured,
			"items": parsed.items,
			"verdict": parsed.verdict,
			"parse_note": parsed.note,
		}
	else:
		# LLM çağrısı yapılamadı (canlı mod kapalı / router yok / hata)
		# Sahte tamamlama YOK — açıkça NEEDS_LLM
		result.status = WorkStatus.NEEDS_LLM
		result.summary = "%s: %s" % [role_name(), thought.status_note]
		result.output = ""
		result.artifacts = {
			"role": role_name(),
			"duty": AICellRoles.role_duty(role),
			"task": task_description,
			"context_keys": context.keys(),
			"brain_note": thought.status_note,
			"request_prepared": thought.prepared_request != null,
		}
	return result


## Bir çıktının reflection (öz-eleştiri) turundan geçmesi gerekip
## gerekmediğine karar verir. Kod üreten roller her zaman gözden
## geçirilir; diğerleri duruma göre.
func should_reflect(result: WorkResult) -> bool:
	if AICellRoles.is_code_generating(role):
		return true
	# Başarısız veya escalate edilen iş de gözden geçirilir
	return not result.is_success()


# ============================================================
# DURUM
# ============================================================

## İşlenmiş mesaj sayısı.
func processed_count() -> int:
	return _processed.size()


## Ajan durum özeti.
func status() -> Dictionary:
	return {
		"role": role_name(),
		"inbox": _inbox.size(),
		"processed": _processed.size(),
		"is_code_generating": AICellRoles.is_code_generating(role),
		"is_engineer": AICellRoles.is_engineer(role),
	}


## Gelen kutusunu ve geçmişi temizler.
func reset() -> void:
	_inbox.clear()
	_processed.clear()
