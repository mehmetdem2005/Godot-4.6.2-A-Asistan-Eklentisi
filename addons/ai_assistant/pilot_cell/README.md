# Layer 9 — Pilot Cell (14-rollü çok-ajanlı sistem)

Sistemin asıl "ajan beyni". Pilot Cell bir yazılım şirketi desenidir:
14 uzman rol, bir oyun-geliştirme isteğini pipeline boyunca işler.

## Dosyalar

- cell_roles.gd — 14 rol tanımı, sorumluluklar, pipeline sırası.
- cell_agent.gd — Tek ajan temel sınıfı: kimlik, gelen kutusu,
  görev işleme, reflection kararı.
- message_bus.gd — Ajanlar arası mesaj veri yolu (gevşek bağlama).
- reflection_loop.gd — Öz-eleştiri döngüsü (max 3 tur).
- cell_orchestrator.gd — Layer 9 ana motoru, pipeline'ı yürütür.
- _pilot_cell_test.gd — 20 sıkı test.

## 14 rol (pipeline sırası)

ProductManager -> Architect -> DeliveryManager ->
CodeEngineer -> SceneEngineer -> ShaderEngineer -> AssetEngineer ->
AudioEngineer -> QAEngineer -> DebugEngineer -> TestEngineer ->
PerformanceEngineer -> Reviewer -> TechWriter

## Desen: Hierarchical + Reflection + Concurrent

- Hierarchical: istek pipeline boyunca rolden role akar
- Reflection: kod üreten rollerin çıktısı öz-eleştiri turundan geçer
- Concurrent: Engineer grubu (Code/Scene/Shader/Asset/Audio) paralel
  çalışabilir (sonraki sürümde tam paralel yürütme)

## ÖNEMLİ — bu iskelet sürümün kapsamı

Bu sürüm ORKESTRASYON İSKELETİNİ kurar: roller, pipeline akışı,
mesajlaşma, reflection tur yönetimi — hepsi tam çalışır ve test
edilir. AMA ajanların gerçek ZEKÂSI henüz yok: her ajan NEEDS_LLM
döndürür (sahte "oyun üretildi" YOK).

Sonraki Pilot Cell oturumlarında her 14 role özel LLM promptu
(Layer 7 Router üzerinden) eklenecek. O zaman ajanlar gerçekten
kod/sahne/shader üretecek. Master plan bunu 5-6 oturum olarak
işaretlemiş — bu 1. oturum, iskelet.

## Eski agents/ klasörü

Bu modül, orijinal projedeki eski 'agents/' klasörünün yerini
alır. Layer 9 tam olunca eski agents/ silinebilir.

## Kalite

gdlint.py R01-R13 + stress test (pilot cell logic 33/33).


## GÜNCELLEME — Ajan Zekâsı (bu sürüm)

İskeletin üstüne ajan zekâsı eklendi:

- role_prompts.gd — 14 rolün LLM sistem promptları + görev
  şablonları. Gerçek prompt mühendisliği, kullanıma hazır.
- agent_brain.gd — Ajanın düşünme mekanizması. Prompt'u alır,
  AIProviderRequest kurar, Layer 7 Router'a gönderir.

cell_agent.process_task artık brain kullanır. cell_orchestrator
tüm ajanlara Router bağlayabilir (attach_router) ve canlı modu
yayar (set_live_mode).

### Canlı mod (live_mode)

Layer 7'deki desenle aynı. Container'da/anahtarsız gerçek LLM
çağrısı yapılamaz:
- live_mode=false (varsayılan): istek hazırlanır, çağrılmaz,
  NEEDS_LLM döner. SAHTE CEVAP ÜRETİLMEZ.
- live_mode=true + Router + API anahtarı: ajan gerçekten düşünür,
  process_task DONE döndürür.

14 rolün hepsinin promptu yazıldı. Sonraki oturumlarda her rolün
çıktısı rol-özel olarak parse edilip yapılandırılacak (şu an ham
LLM metni output'a konuyor).

## GÜNCELLEME — Çıktı Ayrıştırma (bu sürüm)

output_parser.gd eklendi. Ajan beyni LLM'den ham metin döndürür;
bu parser onu rol-özel yapılandırılmış veriye çevirir:
- Plan rolleri (PM, Architect) -> madde listesi
- DeliveryManager -> numaralı task listesi
- Kod rolleri -> SEARCH/REPLACE bloğu veya kod bloğu
- Denetim rolleri (QA, Reviewer) -> PASS/FAIL kararı + bulgular

cell_agent.process_task başarılı LLM cevabını artık parser'dan
geçirir; yapılandırılmış sonuç artifacts'a konur (parsed_kind,
items, verdict, structured).

### Savunmacı ayrıştırma

LLM her zaman temiz format döndürmez. Parser çıkarabildiğini
çıkarır; çıkaramazsa ham metni KORUR ve structured=false der.
ASLA veri uydurmaz.

## GÜNCELLEME — Bağlam Aktarımı (bu sürüm)

context_relay.gd eklendi. Pipeline'da bir ajanın çıktısı bir
sonraki ajana artık YAPILANDIRILMIŞ aktarılır.

Önceki sürüm sadece kısa özet geçiriyordu — DeliveryManager'ın
task listesi CodeEngineer'a "3 task çıkarıldı" gibi bir özet
olarak ulaşıyordu, gerçek task'lar kayboluyordu.

ContextRelay her rolün ParsedOutput'unu saklar; bir sonraki
role:
- Tüm önceki rollerin özetleri
- İlgili (key) öncülün yapılandırılmış maddeleri (_key_input_items)
verir. Kod rolleri DeliveryManager'ın task'larını, QA kod
rolünün çıktısını gerçek veri olarak alır.

cell_orchestrator.run_pipeline artık ContextRelay kullanır;
PipelineRun.relay ile çıktılara erişilebilir.

Pilot Cell artık fonksiyonel olarak TAM: 14 rol -> prompt ->
beyin -> LLM -> yapılandırılmış çıktı -> yapılandırılmış bağlam
-> sonraki rol. Pipeline uçtan uca bağlı.