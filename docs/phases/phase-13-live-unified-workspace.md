# Faz 13 — Tek ekran canlı ajan akışı ve gerçek artefakt doğrulaması

## Gözlenen sorun

Android Godot 4.6.3 editöründeki mevcut ekran kullanıcıyı dört ayrı görünüm arasında dolaştırıyordu: Sohbet, Görevler, Ayarlar ve dokuz sekmeli Workspace. Üretim sırasında sohbet ekranına yalnız genel durum satırları geliyordu. Paralel ajanların gerçek rolü, katmanı, sonucu ve güveni görünmüyordu. Ayrıca `dosya yazıldı` sonucu, dosyanın Godot tarafından gerçekten yüklenebilir bir Script veya PackedScene olduğunu kanıtlamıyordu.

## Yeni çalışma yüzeyi

`AIStudioScreen` artık tek zaman çizelgesidir:

- kullanıcı ve asistan konuşması,
- görev ataması ve hedef dosya,
- aktif ajan sayısı,
- ajan başladı/ilerliyor/tamamlandı/başarısız olayları,
- ajan rolü, bilişsel katmanı ve güven skoru,
- oluşturulan artefakt yolu ve yükleme kanıtı,
- pipeline sonucu

aynı ekranda görünür.

Ayrı Görevler ve Workspace menüleri kullanıcı arayüzünden kaldırılmıştır. Ayarlar yalnız üstteki küçük `⚙ Ayarlar` düğmesiyle açılan gömülü paneldir. Eski `View` enum değerleri dış entegrasyonları kırmamak için korunur; SETTINGS dışındaki eski görünümler birleşik zaman çizelgesine yönlenir.

## Canlı ajan olay sözleşmesi

`AILiveAgentEvent` dört olay tipi taşır:

- `started`
- `progress`
- `completed`
- `failed`

Her olay şu alanları içerir:

- node kimliği,
- rol başlığı,
- bilişsel katman,
- çalışma başlığı,
- güven skoru,
- worker kimliği,
- sınırlı güvenli metin,
- güvenli metadata.

Metin 1200 karakterle sınırlandırılır. `sk-...` biçimli anahtarlar ve Authorization Bearer başlıkları redakte edilir. Anahtar, secret veya authorization isimli metadata alanları olaydan tamamen çıkarılır. UI bir çalışmada en fazla 180 ajan olayı gösterir; grafik arka planda çalışmaya devam eder.

## Gerçek artefakt kanıtı

`AIArtifactCommitVerifier`, Executor yazımından sonra şu kapıları uygular:

1. Yol `AIPathGuard` tarafından okunabilir olmalıdır.
2. Dosya fiziksel olarak bulunmalıdır.
3. Disk içeriği beklenen Executor çıktısıyla birebir eşleşmelidir.
4. `.gd` dosyası Godot motorunun `GDScript.reload()` çağrısından geçmeli ve `ResourceLoader` ile Script olarak yüklenmelidir.
5. `.tscn` dosyası PackedScene olarak yüklenmeli ve gerçek bir Node örneğine dönüştürülebilmelidir.
6. `.tres` ve `.res` dosyaları ResourceLoader tarafından yüklenebilmelidir.
7. Editörde dosya sistemi `update_file()` ve kontrollü `scan()` ile yenilenmelidir.

`AIIntegrityVerifier` bu kanıtı Executor'ın mevcut rollback hattına bağlar. Script veya sahne yüklenemezse görev başarı sayılmaz; yazım undo snapshot üzerinden geri alınır ve mevcut bounded repair akışına girer.

İlk doğrulanmış `.tscn`, Android editöründe otomatik olarak açılır. Böylece kullanıcı yalnız bir başarı metni değil, açılabilen gerçek sahneyi görür.

## Akış

```text
Kullanıcı isteği
  → alt görev ayrıştırma
  → görev/ajan ataması zaman çizelgesine yazılır
  → adaptif paralel graph
      → started/progress/completed/failed olayları
      → rol + katman + güven + sonuç görünür
  → Verifier
  → HITL gerektiğinde durdurma
  → Executor
  → bit bütünlüğü
  → Godot Script/PackedScene yükleme doğrulaması
  → başarısızsa rollback + repair
  → başarılıysa FileSystem yenileme + sahneyi açma
```

## Test kapsamı

Faz 13 on iki yeni contract testi ekler:

- geçerli ajan olayı,
- bilinmeyen olay reddi,
- confidence clamp,
- uzun metin kırpma,
- API anahtarı redaksiyonu,
- Authorization redaksiyonu,
- gizli metadata temizleme,
- olmayan dosya reddi,
- içerik uyuşmazlığı reddi,
- geçerli GDScript yükleme,
- parse hatalı GDScript reddi,
- PackedScene yükleme ve instantiate.

Yeni genel beklenen toplam: **1018 test**.

## Bilinen sınırlar

Bu fazdaki `canlı akış`, bağımsız ajanların yaşam döngüsü ve tamamlanan sonuçlarının anında ekrana akmasıdır. DeepSeek HTTP taşıyıcısı henüz SSE/token-chunk protokolü kullanmadığı için tek bir ajanın cevabı harf harf veya token token gösterilmez. Gerçek token streaming ayrı bir taşıyıcı fazı gerektirir.

Gerçek DeepSeek V4 Pro Max ağ çağrısı repository secret olmadan CI içinde doğrulanamaz. Gerçek Android dokunma, sanal klavye ve görsel yerleşim testi de fiziksel Android Godot editöründe manuel kapı olarak kalır.
