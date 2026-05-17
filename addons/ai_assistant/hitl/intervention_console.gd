@tool
class_name AIInterventionConsole
extends RefCounted

## InterventionConsole — müdahale konsolu (Layer 8 / HITL).
##
## CheckpointGate riskli işlemlerde checkpoint üretir. Bunlar birikir.
## Bu sınıf, insanın o bekleyen kararları GÖRÜP YÖNETMESİ için kuyruk
## arayüzüdür — UI'ın bağlanacağı katman.
##
## Sağladıkları:
##   - Bekleyen checkpoint kuyruğu (risk önceliğine göre sıralı)
##   - Sıradaki kararı alma (en riskli önce)
##   - Toplu işlem (hepsini onayla/reddet — dikkatli kullanım)
##   - Abone bildirimi (yeni checkpoint gelince UI haberdar olur)
##   - Karar geçmişi
##
## Mock policy: konsol sadece gerçek checkpoint'leri yönetir.

## Bağlı checkpoint kapısı.
var _gate: AICheckpointGate

## Yeni checkpoint geldiğinde haber verilecek aboneler (Callable).
var _subscribers: Array = []

## Karar geçmişi — çözülmüş checkpoint'ler kronolojik.
var _history: Array = []


func _init(gate: AICheckpointGate = null) -> void:
	if gate != null:
		_gate = gate
	else:
		_gate = AICheckpointGate.new()


## Bağlı checkpoint kapısını döndürür.
func gate() -> AICheckpointGate:
	return _gate


# ============================================================
# KUYRUK
# ============================================================

## Bekleyen checkpoint'leri RİSK ÖNCELİĞİNE göre sıralı döndürür.
## En riskli (CRITICAL) başta — insan önce onları görür.
func queue() -> Array:
	var pending: Array = _gate.pending_checkpoints().duplicate()
	# Risk seviyesi azalan sırada — yüksek risk önce
	pending.sort_custom(func(a, b):
		return a.risk_level > b.risk_level
	)
	return pending


## Kuyruktaki sıradaki (en öncelikli) checkpoint. Boşsa null.
func next_pending() -> AICheckpointGate.Checkpoint:
	var q: Array = queue()
	if q.is_empty():
		return null
	return q[0]


## Bekleyen karar var mı?
func has_pending() -> bool:
	return _gate.pending_count() > 0


## Bekleyen karar sayısı.
func pending_count() -> int:
	return _gate.pending_count()


# ============================================================
# KARAR VERME
# ============================================================

## Bir checkpoint'i onaylar.
func approve(checkpoint_id: String, note: String = "") -> Dictionary:
	return _decide(checkpoint_id, AICheckpointGate.Decision.APPROVE, note, "")


## Bir checkpoint'i reddeder.
func reject(checkpoint_id: String, note: String = "") -> Dictionary:
	return _decide(checkpoint_id, AICheckpointGate.Decision.REJECT, note, "")


## Bir checkpoint'i değiştirerek onaylar — yeni içerik verir.
func modify(
	checkpoint_id: String, modified_content: String, note: String = ""
) -> Dictionary:
	return _decide(
		checkpoint_id, AICheckpointGate.Decision.MODIFY, note, modified_content
	)


## Karar uygular ve geçmişe ekler.
func _decide(
	checkpoint_id: String, decision: int, note: String, modified: String
) -> Dictionary:
	var result: Dictionary = _gate.resolve(
		checkpoint_id, decision, note, modified
	)
	if result["ok"]:
		_history.append(result["checkpoint"])
	return result


## Tüm bekleyenleri tek kararla çözer — DİKKATLİ kullanım.
## decision: APPROVE veya REJECT (MODIFY toplu olamaz — içerik gerekir).
## Dönen: {resolved_count: int, results: Array}
func resolve_all(decision: int, note: String = "") -> Dictionary:
	if decision == AICheckpointGate.Decision.MODIFY:
		push_warning("InterventionConsole: MODIFY toplu uygulanamaz")
		return {"resolved_count": 0, "results": []}

	var results: Array = []
	# Kopya üzerinde gez — resolve listeyi değiştirir
	var pending: Array = _gate.pending_checkpoints().duplicate()
	for checkpoint in pending:
		var r: Dictionary = _decide(
			(checkpoint as AICheckpointGate.Checkpoint).id, decision, note, ""
		)
		results.append(r)
	return {"resolved_count": results.size(), "results": results}


# ============================================================
# YENİ CHECKPOINT BİLDİRİMİ
# ============================================================

## Bir abone ekler — yeni checkpoint oluşunca Checkpoint ile çağrılır.
func subscribe(callback: Callable) -> void:
	if not callback.is_valid():
		push_warning("InterventionConsole.subscribe: geçersiz callable")
		return
	if not _subscribers.has(callback):
		_subscribers.append(callback)


## Bir aboneyi çıkarır.
func unsubscribe(callback: Callable) -> void:
	var idx: int = _subscribers.find(callback)
	if idx >= 0:
		_subscribers.remove_at(idx)


## Yeni bir checkpoint'in oluştuğunu abonelere bildirir.
## (CheckpointGate.evaluate sonrası HITLCoordinator çağırır.)
func notify_new_checkpoint(checkpoint: AICheckpointGate.Checkpoint) -> void:
	var current: Array = _subscribers.duplicate()
	for callback in current:
		if (callback as Callable).is_valid():
			(callback as Callable).call(checkpoint)


# ============================================================
# GEÇMİŞ VE DURUM
# ============================================================

## Karar geçmişi — çözülmüş checkpoint'ler.
func history() -> Array:
	return _history


## Onaylanma oranı — kaç karardan kaçı onaylandı/değiştirildi.
func approval_rate() -> float:
	if _history.is_empty():
		return 0.0
	var cleared: int = 0
	for c in _history:
		if (c as AICheckpointGate.Checkpoint).is_cleared():
			cleared += 1
	return float(cleared) / float(_history.size())


## Konsol durum özeti.
func status() -> Dictionary:
	return {
		"pending": pending_count(),
		"history_count": _history.size(),
		"approval_rate": approval_rate(),
		"subscribers": _subscribers.size(),
	}
