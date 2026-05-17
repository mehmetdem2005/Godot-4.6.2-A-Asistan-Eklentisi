# Layer 3 — Planner (Hiyerarşik Planlama)

Kullanıcı isteğini çalıştırılabilir hiyerarşik plana çevirir.
Goal -> Milestone -> Task -> Action.

## Dosyalar

- dag_resolver.gd — Bağımlılık grafı: döngü tespiti, topolojik sıralama,
  hazır düğüm tespiti. Mock policy: döngü varsa sahte sıra üretmez.
- plan_tree.gd — Hiyerarşik ağaç: düğüm ekleme, parent/child gezinme,
  yaprak tespiti, bütünlük doğrulama. Tek-kök kuralı.
- hierarchical_planner.gd — Layer 3 ana motoru. DAG + Tree birleşir.
- _planner_test.gd — 24 sıkı test (döngü, topo sıra, hiyerarşi, edge case).

## İki eksen

- DİKEY (PlanTree): hiyerarşi — GOAL içinde MILESTONE, içinde TASK...
- YATAY (DAGResolver): bağımlılık — "mesh" task'ı "sahne" task'ından sonra.

İkisi HierarchicalPlanner'da birleşir.

## Garantiler

- Döngü yaratan bağımlılık reddedilir (eklenir, kontrol edilir, geri alınır).
- Topolojik sıra deterministik (Kahn algoritması + sıralı kuyruk).
- Tek kök: ikinci GOAL reddedilir.
- Var olmayan parent'a bağlı düğüm reddedilir.

## NOT

Bu katman plan YAPISINI yönetir. LLM ile gerçek plan ÜRETİMİ (hedefi
otomatik adımlara bölme) Layer 7 entegrasyonunda eklenecek.

## Kalite

gdlint.py statik analiz + stress test (DAG 18/18, Planner 18/18).
