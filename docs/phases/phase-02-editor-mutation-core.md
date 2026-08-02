# Faz 2 — Editör Mutasyon Çekirdeği

## Amaç

Godot editöründe node, property, script ve proje ayarı değiştiren hattın yanlış sahneyi değiştirmesini, Undo/Redo dışı kalmasını ve geniş kapsamlı yıkıcı yetki kullanmasını engellemek.

## Düzeltilen kök sorunlar

1. `EditorInterface`, `Engine.has_singleton()` üzerinden çözülmeye çalışılıyordu. Godot 4.6 editör API'sinde doğrudan global singleton olarak kullanılır.
2. Node/property/script işlemleri `EditorUndoRedoManager` kullanmadan doğrudan nesneleri değiştiriyordu.
3. `ActionSpec.target_path` uygulanacak sahneyle karşılaştırılmıyordu; o anda açık farklı bir sahne değiştirilebilirdi.
4. `allow_high_risk = true`, birden çok yıkıcı işleme açık uçlu izin verebiliyordu.
5. Yazım bütünlük kontrolü başarısız olduğunda dosya otomatik geri alınmıyordu.
6. NodePath traversal, property subname ve güvenlik-kritik ProjectSettings anahtarları yeterince sınırlandırılmıyordu.

## Yeni davranış

- Editör erişimi doğrudan `EditorInterface` üzerinden çözülür.
- Sahne mutasyonları Godot'un `EditorUndoRedoManager` geçmişine kaydolur.
- Açık sahne, `ActionSpec.target_path` ile eşleşmiyorsa işlem reddedilir.
- Yıkıcı işlemler action id + idempotency key'e bağlı tek kullanımlık izin gerektirir.
- Eski `allow_high_risk` uyumluluğu yalnız sıradaki tek işlemle sınırlandırılmıştır.
- Bütünlük doğrulaması başarısız dosya yazımı rollback edilir.
- Güvenlik-kritik ayarlar model üzerinden değiştirilemez.

## Değişen dosyalar

- `executor/editor_action_applier.gd`
- `executor/executor_engine.gd`
- `executor/scene_action_planner.gd`
- `executor/_scene_action_planner_test.gd`

## Doğrulama sınırı

Bu değişiklikler resmî Godot 4.6 editör API sözleşmesine göre hazırlanmıştır. Bu çalışma ortamında Godot 4.6.3 çalıştırılabilir dosyası olmadığı için gerçek parse, headless self-test ve canlı editör smoke testi burada çalıştırılamadı. PR bu nedenle taslak kalmalıdır.
