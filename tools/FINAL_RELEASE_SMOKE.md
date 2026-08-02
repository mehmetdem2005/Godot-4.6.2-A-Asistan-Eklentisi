# Final release smoke — AI Asistan 1.1.0-rc.1

Bu kontrol listesi yalnız Faz 4, Faz 6 ve Faz 7 manuel kanıtları alındıktan sonra uygulanır. Otomatik merge yapmaz.

## 1. Çalışma ağacı ve sürüm

- [ ] Dal: `agent/phase-08-release-consolidation`
- [ ] Godot: `4.6.3.stable`
- [ ] `addons/ai_assistant/plugin.cfg` sürümü: `1.1.0-rc.1`
- [ ] `release/readiness_manifest.json` schema: `1`
- [ ] Üç manuel gate: `passed`
- [ ] Manifest `merge_ready=true`

## 2. Otomatik final kalite kapısı

```bash
godot --headless --path . --script res://tools/ci_contract_runner.gd
```

Beklenen:

- [ ] `CI_ENGINE_OK: 4.6.3-stable`
- [ ] Contract toplamı manifestteki `expected_test_count` ile eşleşir
- [ ] Release Readiness paketinde 0 başarısız
- [ ] `Runtime hygiene gate passed`
- [ ] ObjectDB/Resource leak yok
- [ ] Secret leakage gate geçti
- [ ] Architecture invariant gate geçti

## 3. Masaüstü editör

- [ ] AI Asistan üst ana ekranı açılıyor
- [ ] Sohbet ve build niyetleri doğru ayrılıyor
- [ ] Ayarlar/API anahtarı akışı çalışıyor
- [ ] Node/property/script Undo/Redo sonucu: `SMOKE_OK: 3/3 smoke testi geçti`
- [ ] Üretilen `res://game/` dosyaları editör dosya sisteminde görünüyor
- [ ] Eklenti kapatılıp açıldığında Timer/leak uyarısı oluşmuyor

## 4. DeepSeek V4 canlı çağrı

- [ ] Güvenli ortam değişkeniyle runner çalıştırıldı
- [ ] Model: `deepseek-v4-pro`
- [ ] HTTP 2xx
- [ ] Pozitif input/output token
- [ ] Finish reason mevcut
- [ ] API anahtarı logda/sonuçta yok
- [ ] Sonuç: `V4_LIVE_OK`

## 5. Android editör

- [ ] Godot Android `4.6.3.stable`
- [ ] Portre ayarlar tek kolon
- [ ] Android klavyesi açıkken Gönder erişilebilir
- [ ] Landscape profil canlı uygulanıyor
- [ ] Workspace sekmeleri yatay kaydırılıyor
- [ ] API anahtarı Output/Debugger ve proje dosyalarında görünmüyor
- [ ] Sonuç: `ANDROID_SMOKE_OK: 6/6`

## 6. Güvenlik ve diff incelemesi

- [ ] `project.godot` veya export preset içinde anahtar yok
- [ ] HTTP sağlayıcı endpointi yok
- [ ] `res://game/` sandbox sınırı genişletilmemiş
- [ ] `project.godot`, eklenti veya araç dosyalarında beklenmeyen silme yok
- [ ] Release belgelerinde gerçek API anahtarı veya Authorization değeri yok
- [ ] Varsayılan dal diff'i incelendi

## 7. Birleşme kararı

- [ ] PR #28 varsayılan dala retarget edildi
- [ ] Final CI retarget sonrası tekrar geçti
- [ ] Kullanıcı açıkça merge kararı verdi
- [ ] Birleşme biçimi: tek squash merge
- [ ] Release tag/notu oluşturuldu
- [ ] Eski stacked PR'lar yalnız release merge'inden sonra superseded olarak kapatıldı

## 8. Rollback hazırlığı

- [ ] Squash release commit SHA kaydedildi
- [ ] Phase 7 doğrulanmış referans: `d9565c48f756420f2fd93e2aad773cf23d530d81`
- [ ] Kritik regresyonda tek revert PR açma prosedürü hazır
- [ ] Secret olayı için sağlayıcı anahtar iptal prosedürü biliniyor

## Başarı işareti

Tüm maddeler gerçek kanıtla tamamlandıktan sonra PR'a şu not eklenebilir:

```text
FINAL_RELEASE_SMOKE_OK
```

Bu işaret kullanıcı birleşme kararının yerine geçmez.
