# Faz 9 — Hiyerarşik AAA ajan ağacı

## Amaç

Mevcut `AIPipelineOrchestrator` içindeki Architect → CodeEngineer → Reviewer rol zincirini bozmadan, gerçek şirket tipi görev yönlendirme çekirdeği eklemek.

Bu faz yalnız organizasyon ve atama sözleşmesini kurar. Yeni dosya yazma, silme, internet veya editör mutasyon yetkisi açmaz. Gerçek değişiklikler mevcut Verifier → HITL → Executor sınırında kalır.

## Kanonik organizasyon

```text
Chief Orchestrator
├── Product Director
│   ├── Requirements Analyst
│   └── Acceptance Criteria Analyst
├── Technical Director
│   ├── Principal System Architect
│   ├── Godot Gameplay Engineer
│   ├── UI/UX Engineer
│   ├── Multiplayer Engineer
│   ├── Performance Engineer
│   └── Asset Integration Engineer
├── Implementation Director
│   ├── Code Implementer
│   ├── Scene Implementer
│   └── Resource Implementer
├── Quality Director
│   ├── Independent Code Reviewer
│   ├── Test Automation Engineer
│   ├── Security Reviewer
│   └── Mobile Performance Reviewer
└── Release Director
    ├── CI Engineer
    ├── Android Release Engineer
    ├── Versioning Engineer
    └── Rollback Engineer
```

Toplam 25 rol vardır.

## Güvenlik kuralları

- Chief Orchestrator ve departman yöneticileri doğrudan mutasyon yapamaz.
- Uygulayıcı ajanlar kendi çıktılarını onaylayamaz.
- Onay rolleri uygulama yapamaz.
- Uygulayıcı iş emirleri en az bir bağımsız denetçi taşır.
- Yüksek riskli görevlerde Security Reviewer zorunludur veya görev doğrudan Security Reviewer'a escalation olarak gider.
- Release rolleri oyun koduna doğrudan yazamaz.
- Organizasyon katmanı yalnız `*.propose`, read ve delegation araç kimlikleri taşır; `Executor` çağırmaz.
- Organizasyon döngüsü, eksik parent ve dört seviyeden derin yapı reddedilir.

## Görev yönlendirme

`AIAgentTaskRouter` çevrimdışı ve deterministik olarak şunları ayırır:

- gameplay/GDScript
- UI/UX ve responsive düzen
- scene/node/Inspector
- multiplayer/network/server authority
- performance/profiling/mobile optimization
- asset/resource/import
- requirements/acceptance
- architecture/dependencies
- CI/export/version/rollback
- security/secret/permission

Sonuç `AIAgentWorkOrder` olarak üretilir:

```text
task_id
primary_role_id
department
reviewer_ids
escalation_role_id
required_capabilities
confidence
rationale
high_risk
```

WorkOrder doğrudan araç çalıştırmaz. Prompt bağlamı, gerçek mutasyonun yalnız Executor ve HITL üzerinden yapılacağını açıkça taşır.

## Otomatik doğrulama

Faz 9, CI'a 20 yeni sözleşme testi ekler:

- ağaç bütünlüğü
- rol sayısı ve departman yöneticileri
- köke bağlantı/döngü sınırı
- yönetici ve uygulayıcı görev ayrılığı
- release kod-yazma yasağı
- dokuz farklı domain routing senaryosu
- yüksek risk/security escalation
- self-review yasağı
- WorkOrder doğrulaması
- Executor/HITL prompt sınırı

Beklenen genel toplam: **926 test**.

## Bu fazın bilinçli sınırı

Bu çekirdek henüz `AIPipelineOrchestrator._enqueue_task()` içine bağlanmamıştır. Böylece organizasyon modeli önce bağımsız ve güvenli biçimde doğrulanır. Sonraki fazda görev registry kayıtlarına `primary_role_id`, `department`, `reviewer_ids` ve `work_order` bağlamı eklenecek; mevcut Executor yetkileri değiştirilmeyecektir.
