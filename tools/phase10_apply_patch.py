from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORCH = ROOT / "addons/ai_assistant/pilot_cell/pipeline_orchestrator.gd"
SCREEN = ROOT / "addons/ai_assistant/ai_studio_screen.gd"
RUNNER = ROOT / "tools/ci_contract_runner.gd"
MANIFEST = ROOT / "release/readiness_manifest.json"
SELF = ROOT / "tools/phase10_apply_patch.py"
WORKFLOW = ROOT / ".github/workflows/phase10-live-routing-patch.yml"


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


orch = ORCH.read_text(encoding="utf-8")
orch = replace_once(
    orch,
    "var _planner: AIHierarchicalPlanner = null\n",
    "var _planner: AIHierarchicalPlanner = null\n"
    "var _org_chart: AIAgentOrgChart = null\n"
    "var _task_router: AIAgentTaskRouter = null\n",
    "organization fields",
)
orch = replace_once(
    orch,
    "\t_planner = AIHierarchicalPlanner.new()\n",
    "\t_planner = AIHierarchicalPlanner.new()\n"
    "\t_org_chart = AIAgentOrgChart.new()\n"
    "\t_task_router = AIAgentTaskRouter.new(_org_chart)\n",
    "organization init",
)

prepare_method = '''func _prepare_task_assignment(
\ttask_id: int, title: String, target: String, kind: String,
\tattempt: int, error: String, failed_code: String
) -> Dictionary:
\tvar description: String = _bp_goal
\tif kind == "repair":
\t\tdescription = "Onarım: %s\\n%s" % [error, failed_code.left(2000)]
\tvar work_order: AIAgentWorkOrder = _task_router.route({
\t\t"id": str(task_id),
\t\t"title": title,
\t\t"description": description,
\t\t"target_file": target,
\t})
\tvar validation: Dictionary = work_order.validate(_org_chart)
\tif not bool(validation.get("ok", false)):
\t\treturn {
\t\t\t"ok": false,
\t\t\t"error": "WorkOrder doğrulanamadı: " + str(validation.get("errors", [])),
\t\t}
\tvar primary: AIAgentRoleProfile = _org_chart.role(work_order.primary_role_id)
\tif primary == null:
\t\treturn {"ok": false, "error": "Birincil ajan rolü bulunamadı"}
\tvar entry: Dictionary = {
\t\t"id": task_id,
\t\t"title": title,
\t\t"target_file": target,
\t\t"kind": kind,
\t\t"attempt": attempt,
\t\t"status": "bekliyor",
\t\t"error": error,
\t\t"failed_code": failed_code,
\t\t"primary_role_id": work_order.primary_role_id,
\t\t"primary_role_title": primary.title,
\t\t"department": work_order.department,
\t\t"reviewer_ids": Array(work_order.reviewer_ids),
\t\t"escalation_role_id": work_order.escalation_role_id,
\t\t"assignment_confidence": work_order.confidence,
\t\t"assignment_rationale": work_order.rationale,
\t\t"high_risk": work_order.high_risk,
\t\t"work_order": work_order.to_dict(),
\t\t"work_order_context": work_order.prompt_context(_org_chart),
\t}
\treturn {"ok": true, "entry": entry, "planner_role": primary.title}


## Salt-okunur görev yönlendirme önizlemesi — UI/test/diagnostics.
func route_task_preview(task: Dictionary) -> Dictionary:
\treturn _task_router.route(task).to_dict()


func organization_chart() -> AIAgentOrgChart:
\treturn _org_chart


'''
orch = replace_once(
    orch,
    "## Bir görevi planner ağacına + kuyruğa + registry'ye ekler.\n",
    prepare_method + "## Bir görevi planner ağacına + kuyruğa + registry'ye ekler.\n",
    "prepare assignment insertion",
)

enqueue_new = '''func _enqueue_task(
\ttitle: String, target: String, kind: String,
\tattempt: int, error: String, failed_code: String
) -> bool:
\tif _bp_seq >= MAX_TOTAL_TASKS:
\t\treturn false
\tvar next_id: int = _bp_seq + 1
\tvar prepared: Dictionary = _prepare_task_assignment(
\t\tnext_id, title, target, kind, attempt, error, failed_code
\t)
\tif not bool(prepared.get("ok", false)):
\t\tpush_error("PipelineOrchestrator: " + str(prepared.get("error", "WorkOrder hatası")))
\t\treturn false
\t_bp_seq = next_id
\tvar entry: Dictionary = prepared["entry"]
\tvar node: AIPlanNode = _planner.add_task(
\t\ttitle, _bp_milestone_id, str(prepared["planner_role"])
\t)
\t_planner.add_action("Yaz: " + target, node.id)
\tentry["node_id"] = node.id
\t_bp_registry.append(entry)
\t_bp_queue.append(entry)
\treturn true
'''
orch = replace_section(
    orch,
    "func _enqueue_task(\n",
    "\n\nfunc _run_next_task()",
    enqueue_new,
    "enqueue task",
)
orch = replace_once(
    orch,
    "\tpipeline_progress.emit(label)\n\t_emit_tasks()\n",
    "\tvar assigned_title: String = str(_bp_current.get(\"primary_role_title\", \"\"))\n"
    "\tif not assigned_title.is_empty():\n"
    "\t\tlabel = \"[%s] %s\" % [assigned_title, label]\n"
    "\tpipeline_progress.emit(label)\n\t_emit_tasks()\n",
    "progress agent label",
)
orch = replace_once(
    orch,
    "\tif not _bp_classes.is_empty():\n",
    "\tvar org_context: String = str(t.get(\"work_order_context\", \"\")).strip_edges()\n"
    "\tif not org_context.is_empty():\n"
    "\t\tinstruction = org_context + \"\\n\\n\" + instruction\n"
    "\tif not _bp_classes.is_empty():\n",
    "organization prompt context",
)
registry_new = '''func task_registry() -> Array:
\tvar out: Array = []
\tfor e in _bp_registry:
\t\tout.append({
\t\t\t"id": int(e["id"]),
\t\t\t"title": str(e["title"]),
\t\t\t"target_file": str(e["target_file"]),
\t\t\t"kind": str(e["kind"]),
\t\t\t"attempt": int(e["attempt"]),
\t\t\t"status": str(e["status"]),
\t\t\t"error": str(e["error"]),
\t\t\t"primary_role_id": str(e.get("primary_role_id", "")),
\t\t\t"primary_role_title": str(e.get("primary_role_title", "")),
\t\t\t"department": str(e.get("department", "")),
\t\t\t"reviewer_ids": (e.get("reviewer_ids", []) as Array).duplicate(),
\t\t\t"escalation_role_id": str(e.get("escalation_role_id", "")),
\t\t\t"assignment_confidence": float(e.get("assignment_confidence", 0.0)),
\t\t\t"assignment_rationale": str(e.get("assignment_rationale", "")),
\t\t\t"high_risk": bool(e.get("high_risk", false)),
\t\t})
\treturn out
'''
orch = replace_section(
    orch,
    "func task_registry() -> Array:\n",
    "\n\nfunc _emit_tasks()",
    registry_new,
    "task registry",
)
orch = replace_once(
    orch,
    '''\t\tvar applied: Dictionary = _dispatch_output(
\t\t\tstr(t["target_file"]), str(res.get("content", "")),
\t\t\tstr(res.get("role_name", "CodeEngineer"))
\t\t)
''',
    '''\t\tvar actor_role: String = str(t.get(
\t\t\t"primary_role_title", res.get("role_name", "CodeEngineer")
\t\t))
\t\tvar applied: Dictionary = _dispatch_output(
\t\t\tstr(t["target_file"]), str(res.get("content", "")), actor_role
\t\t)
''',
    "assigned actor role",
)
orch = replace_once(
    orch,
    '''\treturn {
\t\t"bridge_attached": _bridge != null,
\t\t"plan_progress": _planner.progress(),
\t}
''',
    '''\treturn {
\t\t"bridge_attached": _bridge != null,
\t\t"plan_progress": _planner.progress(),
\t\t"organization_roles": _org_chart.role_count(),
\t\t"organization_valid": bool(_org_chart.validate().get("ok", false)),
\t}
''',
    "pipeline status organization",
)
ORCH.write_text(orch, encoding="utf-8")

screen = SCREEN.read_text(encoding="utf-8")
screen = replace_once(
    screen,
    '''\t\t_tasks_log.append_text(
\t\t\t"   [color=#9CDCFE]%s[/color]\\n" % str(t.get("target_file", ""))
\t\t)
\t\tvar err: String = str(t.get("error", ""))
''',
    '''\t\t_tasks_log.append_text(
\t\t\t"   [color=#9CDCFE]%s[/color]\\n" % str(t.get("target_file", ""))
\t\t)
\t\tvar agent_title: String = str(t.get("primary_role_title", ""))
\t\tvar department: String = str(t.get("department", ""))
\t\tif not agent_title.is_empty():
\t\t\t_tasks_log.append_text(
\t\t\t\t"   [color=#DCDCAA]Ajan:[/color] %s  [color=#888888](%s)[/color]\\n"
\t\t\t\t% [agent_title, department]
\t\t\t)
\t\tvar reviewers: Array = t.get("reviewer_ids", []) as Array
\t\tif not reviewers.is_empty():
\t\t\tvar reviewer_names := PackedStringArray()
\t\t\tfor reviewer in reviewers:
\t\t\t\treviewer_names.append(str(reviewer))
\t\t\t_tasks_log.append_text(
\t\t\t\t"   [color=#C586C0]Denetçi:[/color] %s\\n"
\t\t\t\t% ", ".join(reviewer_names)
\t\t\t)
\t\tif bool(t.get("high_risk", false)):
\t\t\t_tasks_log.append_text(
\t\t\t\t"   [color=#F44747]Yüksek risk — güvenlik incelemesi zorunlu[/color]\\n"
\t\t\t)
\t\tvar err: String = str(t.get("error", ""))
''',
    "task UI assignment metadata",
)
SCREEN.write_text(screen, encoding="utf-8")

runner = RUNNER.read_text(encoding="utf-8")
runner = replace_once(
    runner,
    "##   - hiyerarşik AAA ajan organizasyonu\n",
    "##   - hiyerarşik AAA ajan organizasyonu\n##   - canlı görev kuyruğu ajan routing entegrasyonu\n",
    "runner package comment",
)
runner = replace_once(
    runner,
    "\tvar organization_report: Dictionary = AIAgentOrganizationTest.build_report()\n",
    "\tvar organization_report: Dictionary = AIAgentOrganizationTest.build_report()\n"
    "\tvar live_routing_report: Dictionary = AILiveAgentRoutingTest.build_report()\n",
    "runner report creation",
)
runner = replace_once(
    runner,
    "\t\torganization_report,\n\t]\n",
    "\t\torganization_report,\n\t\tlive_routing_report,\n\t]\n",
    "runner report list",
)
RUNNER.write_text(runner, encoding="utf-8")

manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest["automatic"]["expected_test_count"] = 936
manifest["automatic"]["gates"]["live_hierarchical_agent_routing"] = True
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# One-shot helper artifacts must not remain in the product branch.
for temp in (SELF, WORKFLOW):
    if temp.exists():
        temp.unlink()

print("Phase 10 live routing patch applied")
