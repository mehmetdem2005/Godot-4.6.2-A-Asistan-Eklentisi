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
| 6 — canlı V4 ve metadata | #24 | tamamlandı | repository secret bekliyor |
| 7 — Android/mobile hardening | #26 | tamamlandı | gerçek Android editörü bekliyor |
| 8 — release konsolidasyonu | #28 | tamamlandı | final kullanıcı kararı |

## 4. Son kanıtlanmış otomatik kalite koşusu

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

kanıtı alındı. Do → undo → redo → cleanup zinciri node ekleme, property değiştirme ve script bağlama işlemlerinde doğrulandı.

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

Son otomatik deneme:

- run: `30747328540`,
- commit: `7c174d2e73cc0e89c60d6218a5aff026e6c71667`,
- repository secret kontrolü: **başarısız**,
- gerçek V4 Pro Max çağrısı: **çalıştırılmadı**, 
- secret leakage adımı: çağrı olmadığı için **çalıştırılmadı**.

Bu sonuç sağlayıcı veya kod hatası değildir; repository'de `DEEPSEEK_API_KEY` secret bulunmadığını kanıtlar. Secret eklenmeden kapı yeniden çalıştırılamaz ve manifest `passed` yapılamaz.

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

1. `DEEPSEEK_API_KEY` repository secret eklenir ve canlı workflow çalıştırılır.
2. Gerçek Android cihaz smoke kanıtı PR #28'e eklenir.
3. Manifestte kalan kapılar `passed`, `merge_ready` değeri `true` yapılır.
4. Final 906+ testlik Godot 4.6.3 kalite koşusu çalıştırılır.
5. Secret leakage, parse/compile, contract, editor smoke, release audit ve runtime hygiene sonuçları incelenir.
6. PR #28 tabanı `claude/godot-ai-game-builder-FRhQk` dalına retarget edilir.
7. Varsayılan dala karşı diff yeniden incelenir; beklenmeyen silme veya yetki genişlemesi olmamalı.
8. Kullanıcının açık kararı olmadan merge edilmez.
9. Onay verilirse tek squash merge kullanılır.
10. Release commit/tag sonrası eski stacked PR'lar `superseded by #28` notuyla kapatılır.

## 9. Rollback prosedürü

1. Yeni değişiklik eklemeyi durdur.
2. Release squash commit'ini tek revert PR ile geri al.
3. Faz 7 doğrulanmış tabanı `d9565c48f756420f2fd93e2aad773cf23d530d81` referans olarak kullan.
4. Secret sızıntısı varsa anahtarı sağlayıcı tarafında iptal et; yalnız Git geçmişi temizliğine güvenme.
5. Regresyon sözleşme testi eklenmeden yeniden yayınlama.
6. Gerçek cihaz ve sağlayıcı kanıtlarını yeni release adayı için yeniden al.

## 10. Bilinen açık riskler

- `DEEPSEEK_API_KEY` repository secret eksik; run `30747328540` secret kontrolünde durdu.
- Android Godot 4.6.3 editör responsive/klavye kanıtı için gerçek Android cihaz gerekir.
- Varsayılan dal ve branch protection otomatik değiştirilmedi.
- Açık lisans dosyası yoksa dağıtım hakkı otomatik varsayılmamalıdır.

## 11. Release kararı

Kod, 906 otomatik test ve gerçek masaüstü editör mutasyon kapısı üretim adayı seviyesindedir. Ancak gerçek sağlayıcı ve gerçek Android cihaz kanıtı olmadan sürüm dürüst biçimde `release-candidate` ve `merge_ready=false` kalır.
