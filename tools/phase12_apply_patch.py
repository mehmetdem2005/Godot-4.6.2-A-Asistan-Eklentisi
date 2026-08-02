from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH = ROOT / "addons/ai_assistant/cognition/adaptive_deliberation_graph.gd"
PIPELINE = ROOT / "addons/ai_assistant/pilot_cell/pipeline_orchestrator.gd"
RUNNER = ROOT / "tools/ci_contract_runner.gd"
MANIFEST = ROOT / "release/readiness_manifest.json"
SELF = ROOT / "tools/phase12_apply_patch.py"
WORKFLOW = ROOT / ".github/workflows/phase12-adaptive-deliberation-patch.yml"


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


graph = GRAPH.read_text(encoding="utf-8")
graph = replace_once(
    graph,
    "## 13 katmanlı, bağımlılık tabanlı ve çalışma sırasında derinleşebilen\n",
    "## 13 temel + iki meta turla 21 katmana derinleşebilen, bağımlılık tabanlı\n",
    "graph depth comment",
)

deepen = '''func append_deepening_round(reason: String) -> Dictionary:
\tif _deepen_round >= AIAdaptiveReasoningPolicy.MAX_DEEPEN_ROUNDS:
\t\treturn {"ok": false, "reason": "derinleşme sınırı"}
\tif _nodes.size() + 8 > AIAdaptiveReasoningPolicy.MAX_NODES:
\t\treturn {"ok": false, "reason": "düğüm bütçesi"}
\t_deepen_round += 1
\tvar round: int = _deepen_round
\tvar base_layer: int = 13 + (round - 1) * 4
\tvar previous_final: String = _final_node_id
\tvar probe_ids: Array = []
\tprobe_ids.append(_add(
\t\tbase_layer,
\t\t"deep_skeptic_%d" % round,
\t\t"meta_skeptic",
\t\tAICellRoles.Role.REVIEWER,
\t\t"Derin skeptic turu %d" % round,
\t\t"Önceki nihai çözümün yanlış olabileceğini varsay. En güçlü karşı kanıtı, model hatasını ve kaçırılan varsayımları bul. Derinleşme nedeni: " + reason,
\t\t[previous_final]
\t).node_id)
\tprobe_ids.append(_add(
\t\tbase_layer,
\t\t"deep_alternative_%d" % round,
\t\t"meta_alternative",
\t\tAICellRoles.Role.ARCHITECT,
\t\t"Alternatif paradigma turu %d" % round,
\t\t"Önceki çözümden yapısal olarak farklı, daha güvenli bir paradigma üret ve hangi kanıtla üstün olduğunu açıkla.",
\t\t[previous_final]
\t).node_id)
\tprobe_ids.append(_add(
\t\tbase_layer,
\t\t"deep_test_%d" % round,
\t\t"meta_test",
\t\tAICellRoles.Role.TEST_ENGINEER,
\t\t"Derin test turu %d" % round,
\t\t"Önceki çözümü çürütecek property-based, concurrency ve failure-injection senaryoları üret.",
\t\t[previous_final]
\t).node_id)
\tvar synth := _add(
\t\tbase_layer + 1,
\t\t"deep_synthesis_%d" % round,
\t\t"meta_synthesis",
\t\tAICellRoles.Role.ARCHITECT,
\t\t"Paradigma-üstü yeniden sentez %d" % round,
\t\t"Skeptic, alternatif ve test kanıtlarını birleştirerek önceki çözümden daha güçlü ve gerekçeli bir karar üret.",
\t\tprobe_ids
\t)
\tvar revised := _add(
\t\tbase_layer + 2,
\t\t"deep_final_%d" % round,
\t\t"final_generation",
\t\tAICellRoles.Role.CODE_ENGINEER,
\t\t"Derinleştirilmiş nihai artefakt %d" % round,
\t\t"Yeniden senteze göre nihai artefaktı baştan değerlendir ve tam, uygulanabilir çıktıyı üret.",
\t\t[synth.node_id, previous_final]
\t)
\t_final_node_id = revised.node_id
\tvar roles: Array[int] = [
\t\tAICellRoles.Role.REVIEWER,
\t\tAICellRoles.Role.TEST_ENGINEER,
\t\tAICellRoles.Role.QA_ENGINEER,
\t]
\tfor index in roles.size():
\t\t_add(
\t\t\tbase_layer + 3,
\t\t\t"deep_verify_%d_%d" % [round, index + 1],
\t\t\t"final_verification",
\t\t\troles[index],
\t\t\t"Derin final doğrulama %d.%d" % [round, index + 1],
\t\t\t"Revize artefaktı bağımsız doğrula. PASS/FAIL, kanıt ve kalan riskleri ver.",
\t\t\t[revised.node_id]
\t\t)
\treturn {
\t\t"ok": true,
\t\t"round": round,
\t\t"depth": 13 + round * 4,
\t\t"final_node_id": revised.node_id,
\t}


'''
graph = replace_section(
    graph,
    "func append_deepening_round(reason: String) -> Dictionary:\n",
    "func metrics() -> Dictionary:\n",
    deepen,
    "deepening function",
)
graph = replace_once(
    graph,
    '''\treturn {
\t\t"nodes": _nodes.size(),
\t\t"depth": 13,
''',
    '''\treturn {
\t\t"nodes": _nodes.size(),
\t\t"depth": 13 + _deepen_round * 4,
''',
    "dynamic graph depth",
)
GRAPH.write_text(graph, encoding="utf-8")

pipeline = PIPELINE.read_text(encoding="utf-8")
pipeline = replace_once(
    pipeline,
    "var _chain: AIRoleChainRunner = null\n",
    "var _chain: AIAdaptiveRoleGraphRunner = null\n",
    "adaptive chain type",
)
pipeline = replace_once(
    pipeline,
    '''## ASENKRON ÇOK-ADIMLI ZİNCİR (Plan C): büyük BUILD isteği →
## Decomposer (alt görevler) → her görev için çoklu rol hattı
## (Architect→CodeEngineer→Reviewer) → kod çıkar → SENKRON çekirdek
''',
    '''## ASENKRON ADAPTİF DÜŞÜNME GRAFİĞİ: büyük BUILD isteği →
## Decomposer (alt görevler) → her görev için 13–21 bilişsel katman,
## paralel uzman konseyleri, hipotezler, red-team ve uzlaşma → SENKRON çekirdek
''',
    "build plan comment",
)
pipeline = replace_once(
    pipeline,
    '''\t# Yardımcı köprü: decomposer + zincir SIRAYLA kullanır (tek köprü,
\t# çakışmasız — decomposer biter, sonra zincir başlar).
''',
    '''\t# Decomposer bu yardımcı köprüyü kullanır. Adaptif runner yalnız
\t# router'ı paylaşır ve her paralel düşünme kolu için ayrı bridge/transport kurar.
''',
    "aux bridge comment",
)
pipeline = replace_once(
    pipeline,
    "\t_chain = AIRoleChainRunner.new()\n",
    "\t_chain = AIAdaptiveRoleGraphRunner.new()\n",
    "adaptive runner creation",
)
pipeline = replace_once(
    pipeline,
    '''\tvar mode: String = (
\t\t"repair" if str(_bp_current["kind"]) == "repair" else "full"
\t)
\t_chain.run(instruction, _bp_model, mode)
''',
    '''\tvar mode: String = (
\t\t"repair" if str(_bp_current["kind"]) == "repair" else "full"
\t)
\tpipeline_progress.emit(
\t\t"Adaptif derin konsey: bağımsız düşünme kolları paralel başlatılıyor"
\t)
\t_chain.run(instruction, _bp_model, mode)
''',
    "adaptive progress label",
)
PIPELINE.write_text(pipeline, encoding="utf-8")

runner = RUNNER.read_text(encoding="utf-8")
runner = replace_once(
    runner,
    "##   - ajan mailbox/event/memory/lock coordination runtime\n",
    "##   - ajan mailbox/event/memory/lock coordination runtime\n##   - 13–21 katmanlı adaptif paralel deliberation graph\n",
    "CI package comment",
)
runner = replace_once(
    runner,
    "\tvar coordination_report: Dictionary = AIAgentCoordinationRuntimeTest.build_report()\n",
    "\tvar coordination_report: Dictionary = AIAgentCoordinationRuntimeTest.build_report()\n"
    "\tvar deep_deliberation_report: Dictionary = AIAdaptiveDeepDeliberationTest.build_report()\n",
    "CI deep report",
)
runner = replace_once(
    runner,
    "\t\tcoordination_report,\n\t]\n",
    "\t\tcoordination_report,\n\t\tdeep_deliberation_report,\n\t]\n",
    "CI report list",
)
RUNNER.write_text(runner, encoding="utf-8")

manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest["automatic"]["expected_test_count"] = 1006
manifest["automatic"]["gates"]["adaptive_parallel_deep_deliberation"] = True
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for temp in (SELF, WORKFLOW):
    if temp.exists():
        temp.unlink()

print("Phase 12 adaptive deep deliberation patch applied")
