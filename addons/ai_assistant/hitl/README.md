# Layer 8 — HITL (Human-in-the-Loop)

Sistem otonom çalışabiliyor (LLM'e bağlı, kod üretip dosya yazıyor).
Ama tam otonom tehlikeli. Bu katman insan kontrolünü ekler.

Phase 4'te Executor'da bir kapı bırakmıştık: yıkıcı işlemler
"HITL bekliyor" diye SKIP ediliyordu. Layer 8 O KAPIYI doldurur.

## Dosyalar

- risk_assessor.gd — İşlemin risk seviyesini hesaplar (LOW/MEDIUM/
  HIGH/CRITICAL). Yıkıcı mı, geri-alınabilir mi, kritik yola mı
  dokunuyor — puanlar, eşiği geçeni insana sorar.
- diff_viewer.gd — Değişikliği LCS-tabanlı diff ile okunur sunar
  (eklenen/silinen/değişmeyen satır). İnsan ne onayladığını görür.
- checkpoint_gate.gd — Risk eşiği geçince durur, checkpoint oluşturur,
  insan kararını bekler (APPROVE/REJECT/MODIFY).
- intervention_console.gd — Bekleyen kararların kuyruğu, risk
  önceliğine göre sıralı. UI'ın bağlanacağı katman.
- hitl_coordinator.gd — Layer 8 ana motoru. Executor entegrasyon
  noktası: gate_action() işlem öncesi çağrılır.
- _hitl_test.gd — 26 sıkı test.

## Risk eşiği

Varsayılan eşik HIGH: yıkıcı işlemler insana sorulur, normal yazma
otomatik geçer. Eşik ayarlanabilir (set_approval_threshold).

## Executor entegrasyonu

Executor bir işlemden önce:
  coord.gate_action(action, açıklama) çağırır
  -> cleared=true  : işlem devam eder
  -> cleared=false : checkpoint oluştu, insan beklenir
İnsan karar verdikten sonra:
  coord.check_resolution(checkpoint_id)
  -> cleared=true  : işlem yapılabilir (MODIFY ise yeni içerikle)
  -> cleared=false : işlem iptal (reddedildi)

## Önemli — sahte onay yok

Riskli bir işlem GERÇEK insan kararı olmadan asla geçmez. HITL
devre dışı bırakılabilir (set_enabled false) ama bu açık bir
tercihtir — varsayılan AÇIK.

## Kalite

gdlint.py R01-R13 + stress test (HITL logic 26/26).
