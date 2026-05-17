@tool
class_name AIWorkingMemory
extends AIMemoryStoreBase

## Working Memory — anlık çalışma belleği (Layer 1).
##
## Görev işlenirken kullanılan kısa ömürlü bellek. İnsan zihnindeki
## "çalışma belleği" gibi: sınırlı kapasiteli, hızlı zayıflayan, diske yazılmaz.
##
## Karakter:
##   - Kalıcı DEĞİL (uygulama kapanınca kaybolur — bilinçli tasarım)
##   - Sınırlı kapasite (varsayılan 20 kayıt) — dolunca eviction
##   - Hızlı decay — birkaç saat içinde unutulur

## Working memory varsayılan kapasitesi.
const DEFAULT_CAPACITY: int = 20


func _init() -> void:
	# Working memory: kalıcı değil, kapasiteli
	_setup(
		AIMemoryRecord.Layer.WORKING,
		"",  # storage_path boş — diske yazılmaz
		false,  # persistent = false
		DEFAULT_CAPACITY
	)


## Working memory'ye eklenen kayıtlar hızlı zayıflar — decay_rate yüksek.
func add(record: AIMemoryRecord) -> bool:
	if record != null and record.layer == AIMemoryRecord.Layer.WORKING:
		# Working memory hızlı decay — varsayılanın 10 katı
		record.decay_rate = 0.1
	return super.add(record)


## Mevcut görev bağlamını döndürür — en önemli kayıtlar.
## Bu, bir cell role'e "şu an aklında ne var" bilgisini verir.
func current_context(max_items: int = 10) -> Array:
	return top_by_salience(max_items)


## Yeni bir göreve geçerken çağrılır — working memory temizlenir.
## (İnsan da yeni işe geçince önceki işin detaylarını unutur.)
func reset_for_new_task() -> void:
	clear()
