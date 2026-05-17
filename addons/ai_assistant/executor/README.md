# Layer 4 — Executor & Sandbox (Çalıştırma & Korumalı Kum Havuzu)

Layer 3 Planner'ın kurduğu planın ACTION düğümlerini GERÇEKTEN çalıştırır —
dosya oluşturur, yazar, siler, taşır. Sıfır-taviz güvenlik.

## Dosyalar

- path_guard.gd — Yol güvenliği. Her yol işlemi buradan geçer.
  "Deny by default": res://+user:// dışı yasak, path traversal yasak,
  sistem yolları reddedilir, kendi kodunu değiştiremez, .godot korunur.
- operation_journal.gd — Write-ahead log. Her işlem ÖNCE journal'a
  yazılır, SONRA uygulanır. Çökme olursa yarım iş tespit edilir.
- undo_stack.gd — Geri-alma yığını. Her yazma öncesi eski hâl
  snapshot'lanır. Content-addressed (aynı içerik bir kez saklanır).
- sandboxed_file_op.gd — Gerçek dosya I/O. Her çağrı PathGuard +
  Journal + Undo zincirinden geçer. Atomik yazım (.tmp + rename).
- executor_engine.gd — Layer 4 ana motoru. ACTION düğümlerini
  çalıştırır, sonucu AIVerificationResult olarak raporlar.
- _executor_test.gd — sıkı testler (gerçek dosya I/O dahil).

## Güvenlik zinciri (her yazma işlemi)

1. PathGuard       — yol güvenli mi? değilse reddet
2. UndoStack       — eski hâli snapshot'la (geri-alınabilirlik)
3. OperationJournal — PENDING kaydı düş (çökme dayanıklılığı)
4. Gerçek I/O      — atomik yazım
5. Journal güncelle — DONE / FAILED

## Risk kapısı

Yıkıcı işlemler (FILE_DELETE, NODE_REMOVE, PROJECT_SETTING) varsayılan
olarak onaysız ÇALIŞMAZ — SKIP raporlanır. Layer 8 HITL gelince
insan onayı ile çalışacak. allow_high_risk bayrağı ile açılabilir.

## Mock policy

İşlem gerçekten yapılır. Desteklenmeyen action tipi için SAHTE BAŞARI
dönmez — açıkça SKIP/NOT_IMPLEMENTED raporlanır.

## Kalite

gdlint.py statik analiz + stress test:
PathGuard 22/22 saldırı engellendi, Executor logic 19/19.


## Phase 4 Derinleştirme — Ek Güvenlik Katmanları

- resource_quota.gd — Disk kotası: toplam bayt, dosya sayısı, tek dosya
  boyut limiti. Kontrolden çıkmış döngü diski dolduramaz.
- rate_limiter.gd — Sliding-window hız limiti. Saniyede sınırsız işlem
  yok — runaway loop koruması. Zaman dışarıdan verilir (deterministik test).
- integrity_verifier.gd — Yazımdan SONRA doğrulama: dosya var mı,
  içerik MD5 eşleşiyor mu, boyut doğru mu. "Yazdım" yetmez, "doğru yazdım".
- transaction_batch.gd — All-or-nothing atomik işlem grubu. 20 dosyadan
  12.'si hata verirse, önceki 11 geri alınır. Ya hepsi, ya hiçbiri.

ExecutorEngine entegrasyonu: her write işlemi artık hız limiti +
kota kontrolünden geçer, yazımdan sonra bütünlük doğrulanır.
create_batch() ile atomik grup açılır.
