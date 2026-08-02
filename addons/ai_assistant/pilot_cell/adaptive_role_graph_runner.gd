@tool
class_name AIAdaptiveRoleGraphRunner
extends Node

## Seri Architect→CodeEngineer→Reviewer zincirinin yerine geçen gerçek
## paralel düşünme runtime'ı. Her worker kendi AIAgentLiveBridge ve
## AIHTTPTransport örneğine sahiptir; yalnız dependency DAG beklenir.

signal chain_progress(step: String)
signal chain_completed(result: Dictionary)
signal graph_updated(snapshot: Dictionary)
## UI'ya güvenli, başlıklı ve bounded canlı ajan olayları taşır.
signal agent_event(event: Dictionary)

const MAX_WORKERS: int = 6
const MAX_MODEL: String = "deepseek-v4-pro"

var _router: AIProviderRouter = null
var _workers: Array[AIAgentLiveBridge] = []
var _worker_node_ids: Dictionary = {}
var _graph: AIAdaptiveDeliberationGraph = null
var _policy: AIAdaptiveReasoningPolicy = null
var _consensus: AIEvidenceConsensusEngine = null

var _task: String = ""
var _model: String = ""
var _mode: String = "full"
var _running: bool = false
var _max_parallel: int = 4
var _parallel_peak: int = 0
var _transcript: Array = []
var _last_consensus: Dictionary = {}


func _init() -> void:
	_policy = AIAdaptiveReasoningPolicy.new()
	_consensus = AIEvidenceConsensusEngine.new()
	_graph = AIAdaptiveDeliberationGraph.new(_policy)


func attach_bridge(bridge: AIAgentLiveBridge) -> void:
	_router = null if bridge == null else bridge.router()
	_rebuild_workers()


func run(task: String, model: String = "", mode: String = "full") -> bool:
	if _running:
		_finish(false, "Adaptif düşünme grafiği zaten çalışıyor", {})
		return false
	if _router == null:
		_finish(false, "Router bağlı değil", {})
		return false
	_task = task.strip_edges()
	_model = MAX_MODEL if model.strip_edges().is_empty() else model.strip_edges()
	_mode = mode.strip_edges()
	_transcript = []
	_last_consensus = {}
	_parallel_peak = 0
	if _task.is_empty():
		_finish(false, "Görev boş", {})
		return false
	if _workers.is_empty():
		_rebuild_workers()
	if _workers.is_empty():
		_finish(false, "Paralel worker havuzu kurulamadı", {})
		return false
	var target_path: String = _extract_target_path(_task)
	var built: Dictionary = _graph.build(
		_task, target_path, _mode, _is_high_risk(_task)
	)
	if not bool(built.get("ok", false)):
		_finish(false, "Düşünme grafiği kurulamadı: " + str(built.get("reason", "")), {})
		return false
	_max_parallel = clampi(
		int(built.get("parallelism", 4)), 1, mini(MAX_WORKERS, _workers.size())
	)
	_running = true
	chain_progress.emit(
		"Derin düşünme grafiği başladı: %d düğüm, 13+ katman, %d paralel worker"
		% [int(built.get("nodes", 0)), _max_parallel]
	)
	_emit_graph()
	call_deferred("_dispatch_ready")
	return true


func is_running() -> bool:
	return _running


func graph_snapshot() -> Dictionary:
	return {
		"running": _running,
		"nodes": _graph.all_nodes(),
		"metrics": _graph.metrics(),
		"consensus": _last_consensus.duplicate(true),
		"parallel_peak": _parallel_peak,
		"worker_count": _workers.size(),
	}


func _rebuild_workers() -> void:
	for worker in _workers:
		if is_instance_valid(worker):
			worker.queue_free()
	_workers.clear()
	_worker_node_ids.clear()
	if _router == null:
		return
	for index in MAX_WORKERS:
		var worker := AIAgentLiveBridge.new()
		worker.name = "AdaptiveThoughtWorker%d" % (index + 1)
		add_child(worker)
		worker.attach_router(_router)
		worker.thought_completed.connect(_on_worker_completed.bind(index))
		worker.thought_progress.connect(_on_worker_progress.bind(index))
		_workers.append(worker)


func _dispatch_ready() -> void:
	if not _running:
		return
	var free_workers: Array[int] = _free_worker_indices()
	var capacity: int = mini(free_workers.size(), _max_parallel - _worker_node_ids.size())
	if capacity > 0:
		var ready: Array[AIDeliberationNode] = _graph.ready_nodes(capacity)
		for index in mini(ready.size(), free_workers.size()):
			_dispatch_node(ready[index], free_workers[index])
	_parallel_peak = maxi(_parallel_peak, _worker_node_ids.size())
	_emit_graph()
	if _worker_node_ids.is_empty():
		if _graph.all_terminal():
			_evaluate_finished_wave()
		elif _graph.ready_nodes(1).is_empty():
			_finish(false, "Düşünme grafiği ilerleyemiyor: dependency deadlock", {})


func _dispatch_node(current: AIDeliberationNode, worker_index: int) -> void:
	if not _graph.mark_running(current.node_id):
		return
	_worker_node_ids[worker_index] = current.node_id
	var worker: AIAgentLiveBridge = _workers[worker_index]
	var prompt: String = (
		"BİLİŞSEL KATMAN %d/%d — %s\n"
		% [current.layer_index + 1, AIAdaptiveReasoningPolicy.MAX_DEPTH, current.title]
		+ current.prompt + "\n\n"
		+ "Çok derin düşün; ilk cevabı kabul etme. Varsayım, karşı kanıt, trade-off, "
		+ "başarısızlık koşulu ve güven düzeyini açıkça değerlendir. "
		+ "İç muhakemeni ham biçimde açıklamak yerine sonuç, kanıt ve karar gerekçesi ver."
	)
	chain_progress.emit(
		"[Katman %d] %s — %s paralel düşünüyor"
		% [current.layer_index + 1, AICellRoles.role_name(current.role), current.title]
	)
	_emit_agent_event(
		AILiveAgentEvent.TYPE_STARTED,
		current,
		worker_index,
		"Çalışma başladı. " + current.prompt,
		0.0,
		{"model": MAX_MODEL, "state": "running"}
	)
	var started: bool = worker.think_live(
		current.role,
		prompt,
		_graph.context_for(current.node_id),
		MAX_MODEL
	)
	if not started:
		_worker_node_ids.erase(worker_index)
		_graph.mark_failed(current.node_id, "Canlı düşünme başlatılamadı")
		_emit_agent_event(
			AILiveAgentEvent.TYPE_FAILED,
			current,
			worker_index,
			"Canlı düşünme başlatılamadı",
			0.0
		)


func _on_worker_completed(result: Dictionary, worker_index: int) -> void:
	if not _running or not _worker_node_ids.has(worker_index):
		return
	var node_id: String = str(_worker_node_ids[worker_index])
	_worker_node_ids.erase(worker_index)
	var current := _graph.node(node_id)
	if current == null:
		call_deferred("_dispatch_ready")
		return
	if bool(result.get("ok", false)):
		var content: String = str(result.get("content", ""))
		var confidence: float = _consensus.confidence_from_output(
			content, AICellRoles.role_name(current.role)
		)
		_graph.mark_completed(node_id, content, confidence)
		_transcript.append({
			"node_id": node_id,
			"layer": current.layer_id,
			"role": AICellRoles.role_name(current.role),
			"content": content,
			"confidence": confidence,
			"latency_ms": int(result.get("latency_ms", 0)),
			"input_tokens": int(result.get("input_tokens", 0)),
			"output_tokens": int(result.get("output_tokens", 0)),
		})
		_emit_agent_event(
			AILiveAgentEvent.TYPE_COMPLETED,
			current,
			worker_index,
			content,
			confidence,
			{
				"latency_ms": int(result.get("latency_ms", 0)),
				"input_tokens": int(result.get("input_tokens", 0)),
				"output_tokens": int(result.get("output_tokens", 0)),
				"model": str(result.get("model", MAX_MODEL)),
			}
		)
	else:
		var reason: String = str(result.get("status_note", "Ajan düşünmesi başarısız"))
		_graph.mark_failed(node_id, reason)
		_transcript.append({
			"node_id": node_id,
			"layer": current.layer_id,
			"role": AICellRoles.role_name(current.role),
			"error": reason,
		})
		_emit_agent_event(
			AILiveAgentEvent.TYPE_FAILED,
			current,
			worker_index,
			reason,
			0.0,
			{"http_status": int(result.get("http_status", 0))}
		)
	chain_progress.emit(
		"[Katman %d] %s tamamlandı — güven %.2f"
		% [current.layer_index + 1, current.title, current.confidence]
	)
	_emit_graph()
	call_deferred("_dispatch_ready")


func _on_worker_progress(step: String, worker_index: int) -> void:
	if not _running or not _worker_node_ids.has(worker_index):
		return
	var current := _graph.node(str(_worker_node_ids[worker_index]))
	if current != null:
		chain_progress.emit("[%s] %s" % [current.title, step])
		_emit_agent_event(
			AILiveAgentEvent.TYPE_PROGRESS,
			current,
			worker_index,
			step,
			current.confidence
		)


func _evaluate_finished_wave() -> void:
	var verification_nodes: Array[AIDeliberationNode] = []
	for item in _graph.verification_outputs():
		var current := _graph.node(str(item.get("node_id", "")))
		if current != null:
			verification_nodes.append(current)
	_last_consensus = _consensus.evaluate(verification_nodes)
	var metrics: Dictionary = _graph.metrics()
	var deepen_round: int = int(metrics.get("deepen_rounds", 0))
	var should_deepen: bool = _policy.should_deepen(
		float(_last_consensus.get("confidence", 0.0)),
		float(_last_consensus.get("disagreement", 1.0)),
		int(metrics.get("failed", 0)),
		deepen_round,
		bool(_last_consensus.get("security_veto", false))
	)
	if should_deepen:
		var deepened: Dictionary = _graph.append_deepening_round(
			"güven=%.2f, anlaşmazlık=%.2f, failed=%d, security_veto=%s"
			% [
				float(_last_consensus.get("confidence", 0.0)),
				float(_last_consensus.get("disagreement", 1.0)),
				int(metrics.get("failed", 0)),
				str(_last_consensus.get("security_veto", false)),
			]
		)
		if bool(deepened.get("ok", false)):
			chain_progress.emit(
				"Uzman anlaşmazlığı/belirsizlik nedeniyle grafik derinleşti — tur %d"
				% int(deepened.get("round", 0))
			)
			_emit_graph()
			call_deferred("_dispatch_ready")
			return
	var output: String = _graph.final_output()
	if output.strip_edges().is_empty():
		_finish(false, "Nihai artefakt üretilemedi", _last_consensus)
		return
	var accepted: bool = _consensus.should_accept(_last_consensus)
	var note: String = (
		"Adaptif grafik tamamlandı: %d katman potansiyeli, tepe %d paralel ajan, "
		+ "güven %.2f, anlaşmazlık %.2f"
	) % [
		AIAdaptiveReasoningPolicy.MAX_DEPTH,
		_parallel_peak,
		float(_last_consensus.get("confidence", 0.0)),
		float(_last_consensus.get("disagreement", 0.0)),
	]
	_finish(accepted, note, _last_consensus)


func _finish(ok: bool, note: String, consensus_report: Dictionary) -> void:
	_running = false
	var content: String = _graph.final_output()
	var metrics: Dictionary = _graph.metrics()
	chain_completed.emit({
		"ok": ok,
		"content": content,
		"transcript": _transcript.duplicate(true),
		"status_note": note,
		"role_name": "AdaptiveDeepCouncil",
		"graph_metrics": metrics,
		"consensus": consensus_report.duplicate(true),
		"parallel_peak": _parallel_peak,
		"cognitive_depth": 13 + int(metrics.get("deepen_rounds", 0)) * 4,
	})


func _emit_agent_event(
	event_type: String,
	current: AIDeliberationNode,
	worker_index: int,
	text: String,
	confidence: float,
	metadata: Dictionary = {}
) -> void:
	if current == null:
		return
	var event: Dictionary = AILiveAgentEvent.create(
		event_type,
		current.node_id,
		current.layer_index + 1,
		AICellRoles.role_name(current.role),
		current.title,
		text,
		confidence,
		worker_index,
		metadata
	)
	var validation: Dictionary = AILiveAgentEvent.validate(event)
	if bool(validation.get("ok", false)):
		agent_event.emit(event)


func _emit_graph() -> void:
	graph_updated.emit(graph_snapshot())


func _free_worker_indices() -> Array[int]:
	var out: Array[int] = []
	for index in _workers.size():
		if not _worker_node_ids.has(index):
			out.append(index)
	return out


func _extract_target_path(text: String) -> String:
	for line in text.split("\n"):
		var clean: String = str(line).strip_edges()
		if clean.begins_with("HEDEF DOSYA:"):
			return clean.trim_prefix("HEDEF DOSYA:").strip_edges()
		if clean.begins_with("res://"):
			return clean.split(" ")[0]
	return ""


func _is_high_risk(text: String) -> bool:
	var lower: String = text.to_lower()
	for term in [
		"delete", "sil", "remove", "project.godot", "project settings",
		"secret", "api key", "authorization", "permission", "yetki",
		"network", "server", "multiplayer", "download", "shell", "exec",
	]:
		if lower.contains(str(term)):
			return true
	return false
