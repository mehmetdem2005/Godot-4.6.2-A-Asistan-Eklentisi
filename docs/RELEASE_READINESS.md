# Release Readiness — AI Asistan 1.1.0-rc.1

Durum: **Release candidate — birleşmeye hazır değil**  
Hedef motor: **Godot 4.6.3.stable**  
Konsolidasyon dalı: `agent/phase-08-release-consolidation`  
Makine kaynağı: `release/readiness_manifest.json`

## 1. Üretim profili

Canlı DeepSeek trafiği tek profile sabitlenmiştir:

- model: `deepseek-v4-pro`,
- bağlam: `1.000.000` token,
- maksimum çıktı: `384.000` token,
- thinking: `enabled`,
- reasoning effort: `max`,
- uzun istek timeout: 1.800 saniye,
- yanıt gövdesi limiti: 64 MiB,
- yalnız HTTPS, gzip ve threaded HTTP.

Eski `deepseek-chat`, `deepseek-reasoner` ve Flash değerleri yalnız geriye uyumluluk girdisidir. Canlı router bunların tamamını ağdan önce V4 Pro Max profiline zorlar.

## 2. Neden tek konsolidasyon PR'ı

Faz 2–8 dalları stacked ve kümülatiftir. Ara PR'ları varsayılan dala tek tek birleştirmek aynı commitlerin tekrar görünmesine, yanlış taban sırasına ve parçalı rollback'e yol açabilir.

Karar: Dış kapılar tamamlandıktan sonra yalnız Faz 8 PR'ı varsayılan dala retarget edilir ve tek squash release PR'ı olarak incelenir. Kullanıcının açık birleşme kararı olmadan merge yapılmaz.

## 3. Faz zinciri

| Faz | PR | Otomatik kapsam | Dış kapı |
|---|---:|---|---|
| 1 — güvenlik envanteri | #14 | tamamlandı | yok |
| 2 — editör mutasyon çekirdeği | #16 | tamamlandı | Faz 4 ile kanıtlandı |
| 3 — Godot 4.6.3 CI | #18 | tamamlandı | yok |
| 4 — runtime hygiene / Undo-Redo | #20 | tamamlandı | **geçti** |
| 5 — DeepSeek V4 geçişi | #22 | tamamlandı | Faz 6 ile birleşik |
| 6 — canlı V4 ve metadata | #24 | tamamlandı | gerçek API çağrısı bekliyor |
| 7 — Android/mobile hardening | #26 | tamamlandı | gerçek Android editörü bekliyor |
| 8 — release konsolidasyonu | #28 | tamamlandı | final kullanıcı kararı |

## 4. Final otomatik kanıt

Son tamamlanmış kalite koşusu:

- commit: `a8f7bc04440c579272e5f7c713b3ec8e7c5cc997`,
- Actions run: `30747036616`,
- artifact: `8833211445`,
- Godot: `4.6.3.stable`,
- secret leakage: geçti,
- architecture invariants: geçti,
- plugin import/parse/compile: geçti,
- gerçek `EditorUndoRedoManager` smoke: **3/3 geçti**,
- production proje dosyaları smoke sırasında değişmedi,
- runtime hygiene: geçti.

Test dağılımı:

| Paket | Sonuç |
|---|---:|
| Ana contract paketi | 872/872 |
| Mobile hardening | 12/12 |
| Gerçek repo Android audit | 2/2 |
| Release readiness | 10/10 |
| DeepSeek V4 Pro Max | 10/10 |
| **Toplam** | **906/906** |

CI manifestteki beklenen test sayısı ile gerçek toplamı birebir karşılaştırır. Sayı veya paketlerden biri değişirse release kapısı kırılır.

## 5. Kapanan masaüstü editör kapısı

İzole proje kopyasında gerçek Godot editörü ve gerçek `EditorUndoRedoManager` kullanılarak:

```text
SMOKE_OK: 3/3 smoke testi geçti
```

kanıtı alındı. Do → undo → redo → cleanup zinciri şu işlemlerde doğrulandı:

- node ekleme,
- property değiştirme,
- script bağlama.

Fixture test sonunda byte-for-byte başlangıç durumuna döndü; production `project.godot` ve eklenti dosyaları değişmedi. Manifestte bu kapı `passed` durumundadır.

## 6. Açık dış kapılar

### 6.1 DeepSeek V4 Pro Max gerçek E2E

Prosedür: `tools/DEEPSEEK_V4_LIVE_TEST.md`  
Workflow: `DeepSeek V4 Pro Max Live Gate`

Başarı için:

```text
V4_MAX_PROFILE_OK
V4_LIVE_OK
```

birlikte bulunmalıdır. Repository secret adı `DEEPSEEK_API_KEY` olmalıdır. Anahtar repo, log veya artifact içine yazılmaz.

### 6.2 Android Godot editörü

Prosedür: `tools/ANDROID_EDITOR_SMOKE.md`

Beklenen:

```text
ANDROID_SMOKE_OK: 6/6
```

Portre, landscape, yazılım klavyesi, ayarlar, workspace sekmeleri ve secret görünürlüğü gerçek Android cihazdaki Godot 4.6.3 editöründe doğrulanmalıdır. Masaüstü emülatörü veya salt headless test gerçek cihaz kanıtı yerine kullanılamaz.

## 7. Merge-ready kuralı

İki açık dış kapı `passed` olmadan:

```json
"merge_ready": false
```

kalır. Bütün kapılar tamamlandıktan sonra `merge_ready=true` yapılır ve final Godot 4.6.3 kalite koşusu yeniden çalıştırılır. `AIReleaseReadinessAudit`, beyan edilen değer ile hesaplanan durumu eşleştirir; sahte hazır beyanını reddeder.

## 8. Final birleşme prosedürü

1. Gerçek V4 Pro Max ve Android cihaz kanıtlarını PR #28'e ekle.
2. Manifestte kalan kapıları `passed`, `merge_ready` değerini `true` yap.
3. Final 906+ testlik Godot 4.6.3 kalite koşusunu çalıştır.
4. Secret leakage, parse/compile, contract, editor smoke, release audit ve runtime hygiene sonuçlarını incele.
5. PR #28 tabanını `claude/godot-ai-game-builder-FRhQk` dalına retarget et.
6. Varsayılan dala karşı diff'i yeniden incele; beklenmeyen silme veya yetki genişlemesi olmamalı.
7. Kullanıcının açık kararı olmadan merge etme.
8. Onay verilirse tek squash merge kullan.
9. Release commit/tag sonrası eski stacked PR'ları `superseded by #28` notuyla kapat.

## 9. Rollback prosedürü

1. Yeni değişiklik eklemeyi durdur.
2. Release squash commit'ini tek revert PR ile geri al.
3. Faz 7 doğrulanmış tabanı `d9565c48f756420f2fd93e2aad773cf23d530d81` referans olarak kullan.
4. Secret sızıntısı varsa anahtarı sağlayıcı tarafında iptal et; yalnız Git geçmişi temizliğine güvenme.
5. Regresyon sözleşme testi eklenmeden yeniden yayınlama.
6. Gerçek cihaz ve sağlayıcı kanıtlarını yeni release adayı için yeniden al.

## 10. Bilinen açık riskler

- DeepSeek V4 Pro Max gerçek anahtarlı çağrı kanıtı henüz kaydedilmedi.
- Android Godot 4.6.3 editör responsive/klavye kanıtı henüz kaydedilmedi.
- Varsayılan dal ve branch protection otomatik değiştirilmedi.
- Açık lisans dosyası yoksa dağıtım hakkı otomatik varsayılmamalıdır.

## 11. Release kararı

Kod, otomatik testler ve masaüstü editör mutasyon kapısı üretim adayı seviyesindedir. Ancak gerçek sağlayıcı ve gerçek Android cihaz kanıtı olmadan sürüm dürüst biçimde `release-candidate` ve `merge_ready=false` kalır.
