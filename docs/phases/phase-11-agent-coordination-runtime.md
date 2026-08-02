# Faz 11 — Ajan koordinasyon runtime'ı

## Amaç

Canlı görevlere atanmış ajanların birbirinden ayrılmış iletişim, bellek ve çalışma rezervasyonu altyapısını kurmak. Bu faz gerçek paralel Executor mutasyonu açmaz; yalnız güvenli koordinasyon çekirdeği sağlar.

## Bileşenler

### AIAgentMessage

- typed mesaj türleri
- priority
- correlation id
- bounded payload
- TTL
- isteğe bağlı ACK
- rol doğrulaması
- self-message kısıtı

### AIAgentMailbox

- her 25 rol için ayrı mailbox
- kapasite sınırı
- message-id dedupe
- critical/high/normal/low önceliği
- süresi dolan mesaj temizliği
- kritik mesaj için düşük öncelikli tahliye

### AIAgentEventBus

- callback yerine cursor/poll modeli
- wildcard topic aboneliği
- bounded event journal
- correlation id
- subscriber cursor ve limitli tüketim

### AIAgentScopedMemory

- `private`: yalnız owner
- `department`: aynı departmandaki roller
- `organization`: bütün roller
- tag/query recall
- confidence ve provenance
- owner başına bounded kayıt

### AIAgentResourceLockManager

- paylaşımlı read lock
- exclusive write lock
- yabancı reader/writer conflict
- tek owner read → write upgrade
- lease renew/release
- yalnız `res://` kaynakları
- süresi dolan lock temizliği

### AIAgentCoordinationRuntime

- 25 mailbox oluşturur
- WorkOrder assignment ve review mesajlarını dağıtır
- departman başına bounded active-work limiti uygular
- resource write lock rezervasyonu yapar
- görev tamamlanınca lock bırakır
- department memory'ye sonuç özeti yazar
- `work.started` / `work.completed` olayları yayınlar

## Güvenlik sınırı

- Runtime dosya veya editör mutasyonu yapmaz.
- Lock rezervasyonu Executor yetkisi değildir.
- Paralel Executor çağrısı bu fazda kapalıdır.
- Yalnız doğrulanmış WorkOrder kabul edilir.
- Yüksek risk reviewer kuralları Faz 9/10 sözleşmesinden korunur.
- Mailbox ve event journal bounded kalır; sınırsız bellek büyümesi yoktur.

## Testler

30 yeni test:

- mesaj: 5
- mailbox: 5
- event bus: 4
- scoped memory: 5
- resource lock: 6
- coordination runtime: 5

Beklenen genel toplam: **966 test**.

## Sonraki aşama

Faz 12'de bu runtime gerçek `AIPipelineOrchestrator` yaşam döngüsüne bağlanacak:

- WorkOrder dispatch
- uzman mailbox tüketimi
- reviewer sonuç mesajları
- task başlamadan lock rezervasyonu
- görev sonunda release ve memory sonucu
- çakışmada bekleme/escalation

Gerçek paralellik ancak bu entegrasyon ve ilave conflict/regression testlerinden sonra açılabilir.
