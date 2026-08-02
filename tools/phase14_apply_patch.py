from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "addons/ai_assistant/pilot_cell/agent_live_bridge.gd"
RUNNER = ROOT / "addons/ai_assistant/pilot_cell/adaptive_role_graph_runner.gd"
EVENT = ROOT / "addons/ai_assistant/pilot_cell/live_agent_event.gd"
SCREEN = ROOT / "addons/ai_assistant/ai_studio_screen.gd"
ADAPTER = ROOT / "addons/ai_assistant/router/deepseek_v4_adapter.gd"
TESTS = ROOT / "addons/ai_assistant/cognition/_adaptive_deep_deliberation_test.gd"
MANIFEST = ROOT / "release/readiness_manifest.json"
SELF = ROOT / "tools/phase14_apply_patch.py"
WORKFLOW = ROOT / ".github/workflows/phase14-reasoning-stream-patch.yml"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


# DeepSeek request body: true SSE plus final usage chunk.
adapter = ADAPTER.read_text(encoding="utf-8")
adapter = replace_once(
    adapter,
    '\t\t"stream": false,\n',
    '\t\t"stream": true,\n\t\t"stream_options": {"include_usage": true},\n',
    "adapter streaming flags",
)
ADAPTER.write_text(adapter, encoding="utf-8")


# Live bridge: use streaming transport and expose provider chunks.
bridge = BRIDGE.read_text(encoding="utf-8")
bridge = replace_once(
    bridge,
    'signal thought_progress(step: String)\n',
    'signal thought_progress(step: String)\n\n'
    '## DeepSeek SSE parçası. kind: reasoning | content.\n'
    'signal thought_stream(kind: String, text: String, metadata: Dictionary)\n',
    "bridge stream signal",
)
bridge = replace_once(
    bridge,
    '\t\t_transport = AIHTTPTransport.new()\n',
    '\t\t_transport = AIStreamingHTTPTransport.new()\n',
    "bridge streaming transport",
)
bridge = replace_once(
    bridge,
    '\t\tadd_child(_transport)\n\n\n## Router\'ı bağlar',
    '\t\tadd_child(_transport)\n\t_connect_stream_transport()\n\n\n## Router\'ı bağlar',
    "bridge ready connection",
)
bridge = replace_once(
    bridge,
    'func attach_transport(transport: AIHTTPTransport) -> void:\n\t_transport = transport\n',
    'func attach_transport(transport: AIHTTPTransport) -> void:\n'
    '\t_transport = transport\n'
    '\t_connect_stream_transport()\n',
    "bridge injected transport connection",
)
bridge = replace_once(
    bridge,
    '## Hazır bir isteği yönlendirir (cache/ağ) ve sonucu sinyalle döndürür.\n',
    '''func _connect_stream_transport() -> void:
\tif not (_transport is AIStreamingHTTPTransport):
\t\treturn
\tvar streaming := _transport as AIStreamingHTTPTransport
\tif not streaming.stream_delta.is_connected(_on_transport_stream_delta):
\t\tstreaming.stream_delta.connect(_on_transport_stream_delta)


func _on_transport_stream_delta(
\tkind: String, text: String, metadata: Dictionary
) -> void:
\tif text.is_empty():
\t\treturn
\tthought_stream.emit(kind, text, metadata.duplicate(true))


## Hazır bir isteği yönlendirir (cache/ağ) ve sonucu sinyalle döndürür.
''',
    "bridge helpers",
)
bridge = replace_once(
    bridge,
    '\treturn _result_from_response(role, response)\n',
    '''\tvar mapped: Dictionary = _result_from_response(role, response)
\tmapped["reasoning_content"] = str(raw_result.get("reasoning_content", ""))
\tmapped["streamed"] = bool(raw_result.get("streamed", false))
\treturn mapped
''',
    "bridge final reasoning metadata",
)
bridge = replace_once(
    bridge,
    '\t\t"content": content,\n\t\t"llm_called": true,\n',
    '\t\t"content": content,\n\t\t"reasoning_content": "",\n\t\t"streamed": false,\n\t\t"llm_called": true,\n',
    "bridge result fields",
)
BRIDGE.write_text(bridge, encoding="utf-8")


# Live event supports raw provider chunk event types without trimming spaces.
event = EVENT.read_text(encoding="utf-8")
event = replace_once(
    event,
    'const TYPE_FAILED: String = "failed"\n',
    'const TYPE_FAILED: String = "failed"\n'
    'const TYPE_REASONING_CHUNK: String = "reasoning_chunk"\n'
    'const TYPE_CONTENT_CHUNK: String = "content_chunk"\n',
    "event chunk constants",
)
event = replace_once(
    event,
    '\tTYPE_FAILED,\n]\n\nconst MAX_TEXT_CHARS: int = 1200\n',
    '\tTYPE_FAILED,\n\tTYPE_REASONING_CHUNK,\n\tTYPE_CONTENT_CHUNK,\n]\n\n'
    'const MAX_TEXT_CHARS: int = 1200\n'
    'const MAX_STREAM_CHUNK_CHARS: int = 4096\n',
    "event valid chunk types",
)
event = replace_once(
    event,
    '\t\t"text": safe_excerpt(text),\n',
    '\t\t"text": (safe_stream_chunk(text) if event_type in '
    '[TYPE_REASONING_CHUNK, TYPE_CONTENT_CHUNK] else safe_excerpt(text)),\n',
    "event chunk sanitizer",
)
event = replace_once(
    event,
    '\tif str(event.get("text", "")).length() > MAX_TEXT_CHARS + 32:\n'
    '\t\terrors.append("event metni sınırı aşıyor")\n',
    '''\tvar text_limit: int = (
\t\tMAX_STREAM_CHUNK_CHARS
\t\tif event_type in [TYPE_REASONING_CHUNK, TYPE_CONTENT_CHUNK]
\t\telse MAX_TEXT_CHARS + 32
\t)
\tif str(event.get("text", "")).length() > text_limit:
\t\terrors.append("event metni sınırı aşıyor")
''',
    "event validation limit",
)
event = replace_once(
    event,
    'static func _sanitize_label(raw: String) -> String:\n',
    '''static func safe_stream_chunk(raw_text: String) -> String:
\tvar text: String = raw_text.replace("\\r\\n", "\\n").replace("\\r", "\\n")
\ttext = _redact_secrets(text)
\tif text.length() <= MAX_STREAM_CHUNK_CHARS:
\t\treturn text
\treturn text.left(MAX_STREAM_CHUNK_CHARS)


static func _sanitize_label(raw: String) -> String:
''',
    "event stream sanitizer function",
)
EVENT.write_text(event, encoding="utf-8")


# Adaptive workers forward each provider chunk with node/role ownership.
runner = RUNNER.read_text(encoding="utf-8")
runner = replace_once(
    runner,
    '\t\tworker.thought_progress.connect(_on_worker_progress.bind(index))\n',
    '\t\tworker.thought_progress.connect(_on_worker_progress.bind(index))\n'
    '\t\tworker.thought_stream.connect(_on_worker_stream.bind(index))\n',
    "runner worker stream connection",
)
runner = replace_once(
    runner,
    'func _on_worker_progress(step: String, worker_index: int) -> void:\n',
    '''func _on_worker_stream(
\tkind: String, text: String, metadata: Dictionary, worker_index: int
) -> void:
\tif not _running or not _worker_node_ids.has(worker_index):
\t\treturn
\tvar current := _graph.node(str(_worker_node_ids[worker_index]))
\tif current == null:
\t\treturn
\tvar event_type: String = (
\t\tAILiveAgentEvent.TYPE_REASONING_CHUNK
\t\tif kind == "reasoning"
\t\telse AILiveAgentEvent.TYPE_CONTENT_CHUNK
\t)
\t_emit_agent_event(
\t\tevent_type,
\t\tcurrent,
\t\tworker_index,
\t\ttext,
\t\tcurrent.confidence,
\t\tmetadata
\t)


func _on_worker_progress(step: String, worker_index: int) -> void:
''',
    "runner stream handler",
)
RUNNER.write_text(runner, encoding="utf-8")


# Unified UI gets two DeepSeek-like streaming panels.
screen = SCREEN.read_text(encoding="utf-8")
screen = replace_once(
    screen,
    'var _settings_panel: VBoxContainer = null\n',
    'var _settings_panel: VBoxContainer = null\n'
    'var _stream_panel: VBoxContainer = null\n'
    'var _reasoning_log: RichTextLabel = null\n'
    'var _answer_stream_log: RichTextLabel = null\n'
    'var _reasoning_stream_key: String = ""\n'
    'var _answer_stream_key: String = ""\n',
    "screen stream fields",
)
screen = replace_once(
    screen,
    '\t_settings_panel.visible = false\n\t_root_layout.add_child(_settings_panel)\n\n\t_chat_log = RichTextLabel.new()\n',
    '\t_settings_panel.visible = false\n\t_root_layout.add_child(_settings_panel)\n\n'
    '\t_stream_panel = _build_stream_panel()\n'
    '\t_stream_panel.visible = false\n'
    '\t_root_layout.add_child(_stream_panel)\n\n'
    '\t_chat_log = RichTextLabel.new()\n',
    "screen panel insertion",
)
screen = replace_once(
    screen,
    'func _on_viewport_resized() -> void:\n',
    '''func _build_stream_panel() -> VBoxContainer:
\tvar panel := VBoxContainer.new()
\tpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
\tpanel.add_theme_constant_override("separation", 4)

\tvar reasoning_title := Label.new()
\treasoning_title.text = "DeepSeek Düşünme (reasoning_content)"
\treasoning_title.add_theme_font_size_override("font_size", 13)
\tpanel.add_child(reasoning_title)

\t_reasoning_log = RichTextLabel.new()
\t_reasoning_log.bbcode_enabled = false
\t_reasoning_log.scroll_following = true
\t_reasoning_log.selection_enabled = true
\t_reasoning_log.custom_minimum_size = Vector2(0, 120)
\t_reasoning_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
\tpanel.add_child(_reasoning_log)

\tvar answer_title := Label.new()
\tanswer_title.text = "Canlı Yanıt"
\tanswer_title.add_theme_font_size_override("font_size", 13)
\tpanel.add_child(answer_title)

\t_answer_stream_log = RichTextLabel.new()
\t_answer_stream_log.bbcode_enabled = false
\t_answer_stream_log.scroll_following = true
\t_answer_stream_log.selection_enabled = true
\t_answer_stream_log.custom_minimum_size = Vector2(0, 90)
\tpanel.add_child(_answer_stream_log)
\treturn panel


func _on_viewport_resized() -> void:
''',
    "screen panel builder",
)
screen = replace_once(
    screen,
    '\t_model_picker.custom_minimum_size = Vector2(0, touch)\n',
    '\t_model_picker.custom_minimum_size = Vector2(0, touch)\n'
    '\tif _reasoning_log != null:\n'
    '\t\t_reasoning_log.custom_minimum_size = Vector2(0, 96 if compact else 140)\n'
    '\tif _answer_stream_log != null:\n'
    '\t\t_answer_stream_log.custom_minimum_size = Vector2(0, 72 if compact else 100)\n',
    "screen responsive stream sizes",
)
screen = replace_once(
    screen,
    '\t_bridge.attach_router(router)\n\t_orch = AIPipelineOrchestrator.new()\n',
    '\t_bridge.attach_router(router)\n'
    '\tif not _bridge.thought_stream.is_connected(_on_chat_stream):\n'
    '\t\t_bridge.thought_stream.connect(_on_chat_stream)\n'
    '\t_orch = AIPipelineOrchestrator.new()\n',
    "screen chat bridge stream connection",
)
screen = replace_once(
    screen,
    '\tvar event_type: String = str(event.get("type", ""))\n'
    '\tvar node_id: String = str(event.get("node_id", ""))\n',
    '\tvar event_type: String = str(event.get("type", ""))\n'
    '\tvar node_id: String = str(event.get("node_id", ""))\n'
    '\tif event_type in [AILiveAgentEvent.TYPE_REASONING_CHUNK, '
    'AILiveAgentEvent.TYPE_CONTENT_CHUNK]:\n'
    '\t\tvar stream_kind: String = "reasoning" if event_type == '
    'AILiveAgentEvent.TYPE_REASONING_CHUNK else "content"\n'
    '\t\tvar stream_label: String = "%s · Katman %d · %s" % [\n'
    '\t\t\tstr(event.get("role_name", "Ajan")),\n'
    '\t\t\tint(event.get("layer", 0)),\n'
    '\t\t\tstr(event.get("title", "Çalışma")),\n'
    '\t\t]\n'
    '\t\t_append_stream_chunk(stream_kind, str(event.get("text", "")), stream_label)\n'
    '\t\treturn\n',
    "screen agent stream handling",
)
screen = replace_once(
    screen,
    'func _on_tasks_updated(registry: Array) -> void:\n',
    '''func _on_chat_stream(kind: String, text: String, _metadata: Dictionary) -> void:
\t_append_stream_chunk(kind, text, "DeepSeek V4 Pro — MAX")


func _append_stream_chunk(kind: String, text: String, label: String) -> void:
\tif text.is_empty() or _stream_panel == null:
\t\treturn
\t_stream_panel.visible = true
\tvar target: RichTextLabel = (
\t\t_reasoning_log if kind == "reasoning" else _answer_stream_log
\t)
\tif target == null:
\t\treturn
\tvar current_key: String = (
\t\t_reasoning_stream_key if kind == "reasoning" else _answer_stream_key
\t)
\tif current_key != label:
\t\tif target.get_parsed_text().length() > 0:
\t\t\ttarget.add_text("\\n\\n")
\t\ttarget.add_text("[" + label + "]\\n")
\t\tif kind == "reasoning":
\t\t\t_reasoning_stream_key = label
\t\telse:
\t\t\t_answer_stream_key = label
\ttarget.add_text(text)


func _clear_stream_panels() -> void:
\t_reasoning_stream_key = ""
\t_answer_stream_key = ""
\tif _reasoning_log != null:
\t\t_reasoning_log.clear()
\tif _answer_stream_log != null:
\t\t_answer_stream_log.clear()
\tif _stream_panel != null:
\t\t_stream_panel.visible = false


func _on_tasks_updated(registry: Array) -> void:
''',
    "screen stream methods",
)
screen = replace_once(
    screen,
    '\t_opened_scene_path = ""\n\t_update_active_agents_label()\n',
    '\t_opened_scene_path = ""\n\t_clear_stream_panels()\n\t_update_active_agents_label()\n',
    "screen stream reset",
)
SCREEN.write_text(screen, encoding="utf-8")


# Add the Phase 14 tests to the already registered cognition package.
tests = TESTS.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    '## Faz 12–13 — adaptif düşünme grafiği ile tek ekran canlı ajan ve\n'
    '## gerçek Godot artefakt sözleşmeleri için 52 deterministik test.\n',
    '## Faz 12–14 — adaptif düşünme, tek ekran, artefakt ve DeepSeek\n'
    '## reasoning/content SSE akışı için 66 deterministik test.\n',
    "test package comment",
)
tests = replace_once(
    tests,
    '\tresults.append_array(AIPhase13LiveWorkspaceTest.run_all())\n',
    '\tresults.append_array(AIPhase13LiveWorkspaceTest.run_all())\n'
    '\tresults.append_array(AIDeepSeekReasoningStreamTest.run_all())\n',
    "test package inclusion",
)
TESTS.write_text(tests, encoding="utf-8")


manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest["automatic"]["expected_test_count"] = 1032
manifest["automatic"]["gates"]["deepseek_reasoning_sse_stream"] = True
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for temp in (SELF, WORKFLOW):
    if temp.exists():
        temp.unlink()

print("Phase 14 reasoning stream patch applied")
