# Layer 0 — Contracts (Sözleşmeler) — PHASE 0 TAMAMLANDI

Sistemin tüm veri sözleşmeleri. Her contract AIContractBase'den türer:
serialize (to_dict/from_dict), validate, contract_type, factory create().

## Durum — Phase 0 TAMAMLANDI (22/22 contract)

### Batch 1 — Temel Görev Sistemi
validation_result, contract_base, task_lifecycle, task_spec,
iteration, feed_event

### Batch 2 — Board / Genre / Action / Snapshot / Tool
task_board, genre_profile, action_spec, state_snapshot, tool_call

### Batch 3a — VCS (Logical Commit System)
vcs_blob, vcs_tree, vcs_commit, vcs_diff

### Batch 3b — Memory / Plan / Verify / Provider / Cell / Error / Cost / Key / Edit
memory_record    — 4 katmanlı bellek kaydı (Layer 1)
plan_node        — hiyerarşik planlayıcı düğümü (Layer 3)
verification_result — 5 seviyeli verifier sonucu (Layer 5)
provider_request — LLM sağlayıcı isteği (Layer 7)
cell_message     — cell role'ler arası mesaj (Layer 9)
error_report     — hata sınıflandırma (Madde 2)
cost_record      — LLM maliyet kaydı (Madde 5)
encrypted_key_entry — şifreli API anahtarı (Madde 6)
edit_intent      — cerrahi düzenleme niyeti (Madde 19)

## Test

ZİNCİRLEME — tek panelde toplam 47 test
(Batch 1: 9 + Batch 2: 10 + Batch 3a: 10 + Batch 3b: 18).

Project > Tools > "AI Contract Testleri" > Testleri Çalıştır
Beklenen: 47/47 geçer.

## Phase 0 sonrası

Layer 0 tamamlandı. Sıradaki: Layer 1 (Memory System) implementasyonu.
Not: 22 contract bitti — bir sonraki adımda "test sıkılaştırma turu"
(edge case, negatif test, sınır değer) yapılması planlanıyor.

## Not

Saf GDScript, dış bağımlılık yok, Android editorde parse olur.
EncryptedKeyEntry: düz metin anahtar ASLA serialize edilmez/loglanmaz.
