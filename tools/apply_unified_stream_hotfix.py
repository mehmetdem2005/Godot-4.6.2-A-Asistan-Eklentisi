from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCREEN = ROOT / "addons/ai_assistant/ai_studio_screen.gd"
TRANSPORT = ROOT / "addons/ai_assistant/router/streaming_http_transport.gd"
STREAM_TEST = ROOT / "addons/ai_assistant/router/_deepseek_reasoning_stream_test.gd"
WORKSPACE_TEST = ROOT / "addons/ai_assistant/pilot_cell/_phase13_live_workspace_test.gd"
MANIFEST = ROOT / "release/readiness_manifest.json"
WORKFLOW = ROOT / ".github/workflows/godot-4.6.3-quality-gate.yml"
SELF = ROOT / "tools/apply_unified_stream_hotfix.py"
TRIGGER = ROOT / ".github/workflows/apply-unified-stream-hotfix.yml"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def replace_section(text: str, start: str, end: str, new: str, label: str) -> str:
    start_i = text.find(start)
    if start_i < 0:
        raise RuntimeError(f"{label}: start marker missing")
    end_i = text.find(end, start_i)
    if end_i < 0:
        raise RuntimeError(f"{label}: end marker missing")
    return text[:start_i] + new + text[end_i:]


screen = SCREEN.read_text(encoding="utf-8")
screen = replace_once(
    screen,
    'var _answer_stream_key: String = ""\n',
    'var _answer_stream_key: String = ""\n'
    'var _timeline_stream_key: String = ""\n'
    'var _live_reasoning_text: String = ""\n'
    'var _live_answer_text: String = ""\n'
    'var _answer_streamed: bool = false\n',
    "stream timeline state",
)
screen = replace_once(
    screen,
    '\t_stream_panel = _build_stream_panel()\n'
    '\t_stream_panel.visible = false\n'
    '\t_root_layout.add_child(_stream_panel)\n\n',
    '\t# Düşünme, ana yanıt, ajan olayları ve görevler tek RichTextLabel\n'
    '\t# zaman çizelgesinde akar. Ayrı stream panelleri oluşturulmaz.\n'
    '\t_stream_panel = null\n'
    '\t_reasoning_log = null\n'
    '\t_answer_stream_log = null\n\n',
    "remove separate stream panels",
)

stream_chunk = '''func _append_stream_chunk(kind: String, text: String, label: String) -> void:
\tvar clean_text: String = _safe_stream_text(text)
\tif clean_text.is_empty() or _chat_log == null:
\t\treturn
\tvar normalized_kind: String = "reasoning" if kind == "reasoning" else "content"
\tvar block_key: String = normalized_kind + "::" + label
\tif _timeline_stream_key != block_key:
\t\tif _chat_log.get_parsed_text().length() > 0:
\t\t\t_chat_log.add_text("\\n")
\t\tvar title: String = "Düşünme" if normalized_kind == "reasoning" else "AI Yanıt"
\t\tvar color := (
\t\t\tColor(0.77, 0.53, 0.84)
\t\t\tif normalized_kind == "reasoning"
\t\t\telse Color(0.31, 0.79, 0.69)
\t\t)
\t\t_chat_log.push_color(color)
\t\t_chat_log.push_bold()
\t\t_chat_log.add_text("%s — %s:" % [title, label])
\t\t_chat_log.pop()
\t\t_chat_log.pop()
\t\t_chat_log.add_text("\\n")
\t\t_timeline_stream_key = block_key
\tif normalized_kind == "reasoning":
\t\t_reasoning_stream_key = label
\t\t_live_reasoning_text += clean_text
\telse:
\t\t_answer_stream_key = label
\t\t_live_answer_text += clean_text
\t\t_answer_streamed = true
\t_chat_log.add_text(clean_text)


func _safe_stream_text(value: Variant) -> String:
\tif value == null:
\t\treturn ""
\tvar clean_text: String = str(value)
\tif clean_text in ["<null>", "null", "Null", "NULL"]:
\t\treturn ""
\treturn clean_text


'''
screen = replace_section(
    screen,
    "func _append_stream_chunk(kind: String, text: String, label: String) -> void:\n",
    "func _clear_stream_panels() -> void:\n",
    stream_chunk,
    "unified stream chunk renderer",
)

clear_stream = '''func _clear_stream_panels() -> void:
\t_reasoning_stream_key = ""
\t_answer_stream_key = ""
\t_timeline_stream_key = ""
\t_live_reasoning_text = ""
\t_live_answer_text = ""
\t_answer_streamed = false


'''
screen = replace_section(
    screen,
    "func _clear_stream_panels() -> void:\n",
    "func _on_tasks_updated(registry: Array) -> void:\n",
    clear_stream,
    "stream state reset",
)

screen = replace_once(
    screen,
    '\tif stage == "chat":\n'
    '\t\t_append_message("assistant", str(result.get("message", "")))\n',
    '\tif stage == "chat":\n'
    '\t\tvar final_message: String = str(result.get("message", ""))\n'
    '\t\tif _answer_streamed:\n'
    '\t\t\t# Final metin zaten token token tek zaman çizelgesine yazıldı.\n'
    '\t\t\t# Yalnız konuşma geçmişine kaydet; ekranda ikinci kez basma.\n'
    '\t\t\t_ctrl.add_message("assistant", final_message)\n'
    '\t\t\tif _chat_log != null:\n'
    '\t\t\t\t_chat_log.add_text("\\n\\n")\n'
    '\t\telse:\n'
    '\t\t\t_append_message("assistant", final_message)\n',
    "avoid duplicate streamed answer",
)
screen = replace_once(
    screen,
    'func _append_message(role: String, text: String) -> void:\n'
    '\t_ctrl.add_message(role, text)\n'
    '\t_redraw_chat()\n',
    'func _append_message(role: String, text: String) -> void:\n'
    '\t_ctrl.add_message(role, text)\n'
    '\t# Tam redraw canlı token metnini silerdi. Yeni mesajı aynı tek\n'
    '\t# zaman çizelgesine artımlı olarak ekle.\n'
    '\tif _chat_log != null:\n'
    '\t\t_timeline_stream_key = ""\n'
    '\t\t_draw_message(role, text)\n',
    "incremental timeline messages",
)
SCREEN.write_text(screen, encoding="utf-8")

transport = TRANSPORT.read_text(encoding="utf-8")
transport = replace_once(
    transport,
    '\tif chunk_json.has("model"):\n'
    '\t\t_model = str(chunk_json.get("model", _model))\n',
    '\tif chunk_json.has("model"):\n'
    '\t\tvar model_text: String = _stream_text(chunk_json.get("model", null))\n'
    '\t\tif not model_text.is_empty():\n'
    '\t\t\t_model = model_text\n',
    "safe model field",
)
transport = replace_once(
    transport,
    '\tvar choices: Array = chunk_json.get("choices", []) as Array\n'
    '\tif choices.is_empty():\n'
    '\t\treturn\n'
    '\tvar choice: Dictionary = choices[0] as Dictionary\n'
    '\tvar delta: Dictionary = choice.get("delta", {}) as Dictionary\n'
    '\tvar reasoning: String = str(delta.get("reasoning_content", ""))\n'
    '\tvar content: String = str(delta.get("content", ""))\n',
    '\tvar choices_value: Variant = chunk_json.get("choices", [])\n'
    '\tif not choices_value is Array:\n'
    '\t\treturn\n'
    '\tvar choices: Array = choices_value as Array\n'
    '\tif choices.is_empty() or not choices[0] is Dictionary:\n'
    '\t\treturn\n'
    '\tvar choice: Dictionary = choices[0] as Dictionary\n'
    '\tvar delta_value: Variant = choice.get("delta", {})\n'
    '\tif not delta_value is Dictionary:\n'
    '\t\treturn\n'
    '\tvar delta: Dictionary = delta_value as Dictionary\n'
    '\tvar reasoning: String = _stream_text(delta.get("reasoning_content", null))\n'
    '\tvar content: String = _stream_text(delta.get("content", null))\n',
    "null-safe delta extraction",
)
transport = replace_once(
    transport,
    '\tvar finish_value: Variant = choice.get("finish_reason", null)\n'
    '\tif finish_value != null and not str(finish_value).is_empty():\n'
    '\t\t_finish_reason = str(finish_value)\n\n\nfunc _finish_from_connection_end() -> void:\n',
    '\tvar finish_text: String = _stream_text(choice.get("finish_reason", null))\n'
    '\tif not finish_text.is_empty():\n'
    '\t\t_finish_reason = finish_text\n\n\nfunc _stream_text(value: Variant) -> String:\n'
    '\tif value == null:\n'
    '\t\treturn ""\n'
    '\tif typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:\n'
    '\t\treturn ""\n'
    '\tvar text: String = str(value)\n'
    '\tif text in ["<null>", "null", "Null", "NULL"]:\n'
    '\t\treturn ""\n'
    '\treturn text\n\n\nfunc _finish_from_connection_end() -> void:\n',
    "safe stream text helper",
)
TRANSPORT.write_text(transport, encoding="utf-8")

stream_test = STREAM_TEST.read_text(encoding="utf-8")
stream_test = replace_once(
    stream_test,
    '\tvar content_valid: Dictionary = AILiveAgentEvent.validate(content_event)\n'
    '\ttransport.free()\n',
    '\tvar content_valid: Dictionary = AILiveAgentEvent.validate(content_event)\n'
    '\tvar null_is_empty: bool = transport._stream_text(null).is_empty()\n'
    '\tvar null_sentinel_is_empty: bool = transport._stream_text("<null>").is_empty()\n'
    '\ttransport.free()\n',
    "stream null test setup",
)
stream_test = replace_once(
    stream_test,
    '\t\t_b("Olay", _check(\n'
    '\t\t\t"Content chunk olayı geçerli",\n'
    '\t\t\tbool(content_valid.get("ok", false))\n'
    '\t\t)),\n'
    '\t]\n',
    '\t\t_b("Olay", _check(\n'
    '\t\t\t"Content chunk olayı geçerli",\n'
    '\t\t\tbool(content_valid.get("ok", false))\n'
    '\t\t)),\n'
    '\t\t_b("Taşıyıcı", _check(\n'
    '\t\t\t"JSON null stream değeri boş metne çevrilir",\n'
    '\t\t\tnull_is_empty\n'
    '\t\t)),\n'
    '\t\t_b("Taşıyıcı", _check(\n'
    '\t\t\t"Null sentinel kullanıcı metnine sızmaz",\n'
    '\t\t\tnull_sentinel_is_empty\n'
    '\t\t)),\n'
    '\t]\n',
    "stream null test cases",
)
STREAM_TEST.write_text(stream_test, encoding="utf-8")

workspace_test = WORKSPACE_TEST.read_text(encoding="utf-8")
workspace_test = replace_once(
    workspace_test,
    '\tresults.append(_b("LiveEvent", _test_secret_metadata_dropped()))\n',
    '\tresults.append(_b("LiveEvent", _test_secret_metadata_dropped()))\n'
    '\tresults.append(_b("UI", _test_single_timeline_stream()))\n'
    '\tresults.append(_b("UI", _test_null_sentinel_not_rendered()))\n',
    "workspace UI test registration",
)
ui_tests = '''func _test_single_timeline_stream() -> Dictionary:
\tvar name := "Düşünme ve ana yanıt tek zaman çizelgesinde akar"
\tvar screen := AIStudioScreen.new()
\tscreen._build_ui()
\tscreen._append_stream_chunk("reasoning", "önce analiz", "Architect")
\tscreen._append_stream_chunk("content", "son cevap", "Architect")
\tvar chat_log := screen.get("_chat_log") as RichTextLabel
\tvar parsed: String = chat_log.get_parsed_text() if chat_log != null else ""
\tvar ok: bool = (
\t\tscreen.get("_stream_panel") == null
\t\tand screen.get("_reasoning_log") == null
\t\tand screen.get("_answer_stream_log") == null
\t\tand parsed.contains("Düşünme — Architect")
\t\tand parsed.contains("AI Yanıt — Architect")
\t\tand parsed.contains("önce analiz")
\t\tand parsed.contains("son cevap")
\t)
\tscreen.free()
\treturn _ok(name) if ok else _fail(name, "ayrı panel kaldı veya tek timeline eksik")


func _test_null_sentinel_not_rendered() -> Dictionary:
\tvar name := "Null stream sentinel zaman çizelgesine yazılmaz"
\tvar screen := AIStudioScreen.new()
\tscreen._build_ui()
\tscreen._append_stream_chunk("content", "<null>", "DeepSeek")
\tvar chat_log := screen.get("_chat_log") as RichTextLabel
\tvar parsed: String = chat_log.get_parsed_text() if chat_log != null else ""
\tvar ok: bool = not parsed.contains("<null>") and not parsed.contains("AI Yanıt — DeepSeek")
\tscreen.free()
\treturn _ok(name) if ok else _fail(name, "null sentinel kullanıcıya göründü")


'''
workspace_test = replace_once(
    workspace_test,
    "func _test_missing_file_fails() -> Dictionary:\n",
    ui_tests + "func _test_missing_file_fails() -> Dictionary:\n",
    "workspace UI tests",
)
WORKSPACE_TEST.write_text(workspace_test, encoding="utf-8")

manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest["automatic"]["expected_test_count"] = 1036
manifest["automatic"]["gates"]["unified_stream_timeline"] = True
manifest["automatic"]["gates"]["null_stream_sanitization"] = True
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
workflow = replace_once(
    workflow,
    'grep -Fq -- "--- 66 geçti, 0 başarısız (toplam 66) ---"',
    'grep -Fq -- "--- 68 geçti, 0 başarısız (toplam 68) ---"',
    "adaptive aggregate marker",
)
workflow = replace_once(
    workflow,
    '            "✓ Reasoning chunk olayı geçerli"\n',
    '            "✓ Reasoning chunk olayı geçerli"\n'
    '            "✓ JSON null stream değeri boş metne çevrilir"\n'
    '            "✓ Null sentinel kullanıcı metnine sızmaz"\n',
    "stream null markers",
)
WORKFLOW.write_text(workflow, encoding="utf-8")

for temporary in (SELF, TRIGGER):
    if temporary.exists():
        temporary.unlink()

print("Unified stream timeline and null sanitizer hotfix applied")
