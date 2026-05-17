# Layer 11 — Workspace UI (Task Workspace, 9 sekme)

Sistemin GÖRÜNEN yüzü. 9 katmanlık omurga görünmezdi — bu katman
onu telefonda izlenebilir kılar.

## Mimari — mantık / görsel ayrımı

Godot UI'ı Control node'ları + sahne demek; gözle görülür, test
panelinde doğrulanamaz. Bu yüzden Layer 11 ikiye ayrıldı:

- MANTIK (test edilebilir, RefCounted):
  - workspace_state.gd — 9 sekme yönetimi + DPI-aware ölçek
  - kanban_model.gd — Kanban kolon akışı + kart taşıma kuralları
  - live_feed_model.gd — canlı olay akışı + filtreleme
  - iteration_model.gd — iteration faz akışı + ilerleme
- GÖRSEL (gözle/telefonda doğrulanır, Control):
  - workspace_panel.gd — programatik kurulan 9-sekme UI

Mantık modelleri stress + Godot testinden geçer; görsel panel
sahnede görülür. Sahte test yok — model test edilir, UI gözle.

## 9 sekme

Overview, Kanban, Live Feed, Iteration, Plan Tree, Cost,
Verifier, Checkpoints, Settings.

Bu sürüm çekirdek 3'ünü tam modeller (master plan çıkış kapısı):
Kanban + Live Feed + Iteration. Kalan 6 sekme yer tutucu —
sonraki UI oturumunda doldurulacak.

## Kanban akışı

BACKLOG -> READY -> IN_PROGRESS -> VERIFY -> DONE
                                -> BLOCKED (yan durum)
Geçersiz atlama (BACKLOG->DONE doğrudan) reddedilir.

## DPI-aware

compute_ui_scale ekran genişliği + DPI'dan ölçek hesaplar
(0.75-3.0). Dar telefonda küçültür, yüksek DPI'da büyütür.
Mehmet'in Android telefonu için kritik.

## Kalite

gdlint.py R01-R13 + stress test (workspace logic 29/30 + düzeltme 6/6).
workspace_panel.gd görsel — Godot sahnesinde doğrulanır.


## GÜNCELLEME — Kalan 6 Sekme (bu sürüm)

İlk 3 sekme modeli (Kanban, Live Feed, Iteration) vardı. Kalan 6
sekmenin modeli eklendi — Workspace 9 sekmenin hepsiyle TAM:

- overview_model.gd — Genel Bakış. Sistem durumu, görev sayaçları,
  ilerleme, maliyet özeti tek bakışta.
- plan_tree_model.gd — Plan Ağacı. Layer 3 Planner'ın hiyerarşik
  planını katlanabilir düğüm ağacı olarak gösterir.
- cost_model.gd — Maliyet. Harcama, token, sağlayıcı dağılımı,
  bütçe durumu (healthy/warning/exceeded).
- verifier_model.gd — Doğrulama. Layer 5 Verifier sonuçları:
  geçen/başarısız dosyalar, bulunan sorunlar.
- checkpoints_model.gd — Kontrol Noktaları. Geri dönülebilir
  kayıt noktaları; seçip geri yükleme isteği.
- settings_model.gd — Ayarlar. LLM modu, bütçe, otomasyon
  seviyesi, mobil tier. Geçersiz değer reddedilir.

Her model salt-veridir (RefCounted, test edilir). Görsel render
workspace_panel.gd'de — telefonda gözle doğrulanır.