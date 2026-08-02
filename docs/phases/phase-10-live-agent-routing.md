# Faz 10 — Canlı hiyerarşik ajan yönlendirmesi

## Amaç

Faz 9'da doğrulanan 25 rollü şirket ağacını gerçek `AIPipelineOrchestrator` görev kuyruğuna bağlamak. Bu entegrasyon yalnız görev sahipliği, reviewer görünürlüğü ve prompt bağlamı ekler; mevcut Verifier → HITL → Executor güvenlik hattını değiştirmez.

## Canlı akış

```text
Decomposer alt görevi
        ↓
AIAgentTaskRouter
        ↓
AIAgentWorkOrder.validate
        ↓
Planner task owner = uzman ajan başlığı
        ↓
Registry = ajan + departman + reviewer + risk metadata
        ↓
WorkOrder bağlamı LLM talimatına eklenir
        ↓
Architect → CodeEngineer → Reviewer rol zinciri
        ↓
ActionSpec actor = atanmış uzman ajan
        ↓
Verifier → HITL → Executor
```

## Görev registry metadata'sı

Her canlı görev artık şunları taşır:

- `primary_role_id`
- `primary_role_title`
- `department`
- `reviewer_ids`
- `escalation_role_id`
- `assignment_confidence`
- `assignment_rationale`
- `high_risk`
- tam `work_order`
- `work_order_context`

UI Görevler ekranında uzman ajan, departman, bağımsız denetçiler ve yüksek risk uyarısı gösterilir.

## Yetki sınırı

- WorkOrder doğrudan Executor çağırmaz.
- Yönetici ajanlar mutasyon yapmaz.
- LLM talimatı gerçek değişikliğin yalnız HITL ve Executor üzerinden yapılacağını açıkça belirtir.
- `ActionSpec.actor_role`, sabit `CodeEngineer` yerine atanmış uzman başlığını kullanır.
- Yüksek riskli işlerde Security Reviewer metadata'sı korunur.
- Mevcut path guard, verifier, insan onayı ve rollback davranışı değişmez.

## Testler

Faz 10, 10 yeni entegrasyon testi ekler:

1. orkestratörün 25 rollü organizasyonu taşıması,
2. pipeline status organizasyon sayısı,
3. gameplay canlı routing,
4. gameplay bağımsız reviewer,
5. scene canlı routing,
6. yüksek risk security reviewer,
7. `_prepare_task_assignment` gerçek router kullanımı,
8. registry metadata bütünlüğü,
9. WorkOrder prompt Executor/HITL sınırı,
10. ActionSpec actor için uzman başlığı.

Beklenen genel toplam: **936 test**.
