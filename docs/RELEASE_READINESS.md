# Release Readiness — AI Asistan 1.1.0-rc.1

Durum: **Release candidate — birleşmeye hazır değil**  
Hedef motor: **Godot 4.6.3.stable**  
Konsolidasyon dalı: `agent/phase-08-release-consolidation`  
Makine kaynağı: `release/readiness_manifest.json`

## 1. Neden tek konsolidasyon PR'ı

Faz 2–8 dalları stacked ve kümülatiftir. Her dal bir önceki fazın head commit'ini temel alır. Bu PR'ları varsayılan dala tek tek birleştirmek:

- aynı commitlerin birden fazla PR üzerinden tekrar görünmesine,
- ara tabanların yanlış sırayla birleşmesine,
- manuel kapılar tamamlanmadan kısmi release durumuna,
- rollback'in birden fazla merge commit'e bölünmesine

neden olabilir.

Karar: Manuel kapılar tamamlandıktan sonra yalnız Faz 8 PR'ı varsayılan dala retarget edilir ve tek squash release PR'ı olarak incelenir. Faz 1'in ayrı dokümanı Faz 8 dalına ayrıca kopyalanmıştır.

## 2. Faz zinciri

| Faz | PR | Otomatik kapsam | Manuel kapı |
|---|---:|---|---|
| 1 — güvenlik envanteri | #14 | tamamlandı | yok |
| 2 — editör mutasyon çekirdeği | #16 | tamamlandı | Faz 4 harness ile birleşik |
| 3 — Godot 4.6.3 CI | #18 | tamamlandı | yok |
| 4 — runtime hygiene / Undo-Redo | #20 | tamamlandı | `SMOKE_OK: 3/3 smoke testi geçti` |
| 5 — DeepSeek V4 geçişi | #22 | tamamlandı | Faz 6 runner ile birleşik |
| 6 — canlı V4 ve metadata | #24 | tamamlandı | `V4_LIVE_OK` |
| 7 — Android/mobile hardening | #26 | tamamlandı | `ANDROID_SMOKE_OK: 6/6` |
| 8 — release konsolidasyonu | #28 | otomatik kapsam tamamlandı | final kullanıcı birleşme kararı |

## 3. Otomatik kanıt geçmişi

| Faz | Godot Actions run | Test sonucu | Ek kapılar |
|---|---:|---:|---|
| 4 | `30744041708` | 862/862 | runtime hygiene |
| 5 | `30744499528` | 869/869 | 7 V4 sözleşmesi |
| 6 | `30744736885` | 872/872 | metadata/redaksiyon |
| 7 | `30745093568` | 886/886 | 12 mobil + 2 gerçek repo audit |
| 8 | `30745482272` | 896/896 | 10 release-readiness + manifest sayı kapısı |

Her CI koşusu şu ortak kapıları içerir:

- exact Godot `4.6.3.stable`
- resmî release asset digest doğrulaması
- plugin import/parse/compile
- contract testleri
- secret leakage taraması
- editör mutasyon mimari invariant'ları
- runtime hygiene
- Android repo audit'i

## 4. Açık manuel kapılar

### 4.1 Masaüstü editör Undo/Redo

Prosedür: `tools/editor_smoke/README.md`

Beklenen:

```text
SMOKE_OK: 3/3 smoke testi geçti
```

Node ekleme, property değiştirme ve script bağlama için do → undo → redo → cleanup undo doğrulanmalıdır.

### 4.2 DeepSeek V4 Pro canlı E2E

Prosedür: `tools/DEEPSEEK_V4_LIVE_TEST.md`

Beklenen:

```text
V4_LIVE_OK
```

Model kimliği, HTTP 2xx, usage, finish reason, gecikme, request kimliği ve secret redaksiyonu birlikte geçmelidir.

### 4.3 Android Godot editörü

Prosedür: `tools/ANDROID_EDITOR_SMOKE.md`

Beklenen:

```text
ANDROID_SMOKE_OK: 6/6
```

Portre, landscape, klavye, ayarlar, workspace sekmeleri ve secret görünürlüğü gerçek cihazda doğrulanmalıdır.

## 5. Manifest güncelleme kuralı

Manuel kanıt PR'a eklendikten sonra ilgili `release/readiness_manifest.json` kaydında:

```json
"status": "passed"
```

yapılır. Üç kapı da `passed` olmadan:

```json
"merge_ready": false
```

kalmalıdır.

Üç kapı tamamlandıktan sonra `merge_ready=true` yapılır ve final CI tekrar çalıştırılır. `AIReleaseReadinessAudit`, beyan edilen değer ile hesaplanan değerin eşleşmesini zorunlu tutar.

## 6. Final birleşme prosedürü

1. Üç manuel kapının kanıtını PR #28'e ekle.
2. Manifest durumlarını `passed`, `merge_ready` değerini `true` yap.
3. PR #28 üzerinde final Godot 4.6.3 CI'ı çalıştır.
4. Secret leakage, parse/compile, contract, release audit ve runtime hygiene sonuçlarının tamamını incele.
5. PR #28 tabanını `claude/godot-ai-game-builder-FRhQk` dalına retarget et.
6. Varsayılan dala karşı diff'i yeniden incele; beklenmeyen dosya silme veya yetki genişlemesi olmamalı.
7. Kullanıcının açık birleşme kararı olmadan merge etme.
8. Onay verilirse tek squash merge kullan.
9. Release commit/tag oluşturulduktan sonra eski stacked PR'ları `superseded by #28` notuyla kapat.

## 7. Rollback prosedürü

Release sonrası kritik regresyonda:

1. Yeni değişiklik eklemeyi durdur.
2. Release squash commit'ini tek bir revert PR ile geri al.
3. Phase 7 doğrulanmış tabanı `d9565c48f756420f2fd93e2aad773cf23d530d81` referans olarak kullan.
4. API anahtarı veya secret sızıntısı varsa anahtarı sağlayıcı tarafında iptal et; yalnız repo geçmişinden silmeye güvenme.
5. İlgili regression contract testini eklemeden yeniden yayınlama.
6. Manual gate kanıtlarını yeni release adayı için yeniden al; önceki cihaz/sağlayıcı kanıtını otomatik devralma.

## 8. Bilinen açık riskler

- Canlı `EditorUndoRedoManager` davranışı gerçek masaüstü Godot editöründe henüz kanıtlanmadı.
- DeepSeek V4 Pro gerçek anahtarlı çağrı kanıtı henüz kaydedilmedi.
- Android Godot 4.6.3 editöründe responsive/klavye davranışı henüz kaydedilmedi.
- Varsayılan dal adı ve branch protection ayarları otomatik değiştirilmedi.
- Depoda açık lisans dosyası yoksa dağıtım hakkı otomatik varsayılmamalıdır.

## 9. Release kararı

Sekiz fazın otomatik geliştirme ve doğrulama kapsamı tamamlandı. Release candidate yine de üç manuel kapı ve açık kullanıcı birleşme kararı olmadan üretim sürümü veya birleşmeye hazır sayılmaz.
