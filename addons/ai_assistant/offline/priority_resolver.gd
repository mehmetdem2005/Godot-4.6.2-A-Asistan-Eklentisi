@tool
class_name AIOfflinePriorityResolver
extends RefCounted

## PriorityResolver — öncelik çözücü (Madde 07 / Offline / queue).
##
## Çevrimdışıyken işlemler kuyruğa girer (sync_queue). Bağlantı
## gelince hepsi birden işlenemez — bir SIRA gerekir. Bu sınıf her
## işleme bir öncelik puanı verir; kuyruk bu puana göre işler.
##
## Öncelik birden fazla faktörden hesaplanır:
##   - işlem türü   (kayıt senkronu > analitik > önbellek tazeleme)
##   - bekleme süresi (uzun bekleyen öne çıkar — açlık önleme)
##   - yeniden deneme (çok denenmiş işlem geriye düşer)
##
## Tek faktör yeterli değil: sadece türe bakılırsa düşük öncelikli
## işlem sonsuza dek bekler (starvation). Bekleme süresi bunu önler.
##
## Mock policy: öncelik gerçek faktör puanlarından hesaplanır.

## İşlem türleri ve temel öncelik puanları (yüksek = önce).
const TYPE_PRIORITY: Dictionary = {
	"save_sync": 100,        # oyuncu ilerlemesi — en kritik
	"purchase": 95,          # satın alma — kritik
	"leaderboard": 60,       # skor tablosu
	"achievement": 55,       # başarım
	"analytics": 30,         # analitik — düşük
	"cache_refresh": 20,     # önbellek tazeleme — en düşük
}

## Bekleme süresinin öncelik katkısı — saniye başına puan.
const WAIT_BONUS_PER_MINUTE: float = 2.0

## Bekleme bonusunun üst sınırı — sınırsız büyümesin.
const MAX_WAIT_BONUS: float = 80.0

## Her yeniden deneme öncelikten ne kadar düşürür.
const RETRY_PENALTY: float = 15.0


# ============================================================
# ÖNCELİK HESABI
# ============================================================

## Bir kuyruk işleminin öncelik puanını hesaplar.
## operation_type: işlem türü.
## wait_seconds: işlemin kuyrukta bekleme süresi.
## retry_count: kaç kez denendi (başarısız oldu).
## Dönen: öncelik puanı (yüksek = önce işlenmeli).
func compute_priority(
	operation_type: String, wait_seconds: float, retry_count: int
) -> float:
	# Temel öncelik — işlem türünden
	var base: float = float(
		TYPE_PRIORITY.get(operation_type, 10)
	)

	# Bekleme bonusu — uzun bekleyen öne çıkar (açlık önleme)
	var wait_minutes: float = wait_seconds / 60.0
	var wait_bonus: float = minf(
		wait_minutes * WAIT_BONUS_PER_MINUTE, MAX_WAIT_BONUS
	)

	# Yeniden deneme cezası — sürekli başarısız işlem geriye düşer
	var retry_penalty: float = float(maxi(retry_count, 0)) \
		* RETRY_PENALTY

	return maxf(base + wait_bonus - retry_penalty, 0.0)


# ============================================================
# SIRALAMA
# ============================================================

## Bir işlem listesini önceliğe göre sıralar (yüksek öncelik önce).
## operations: her biri {type, wait_seconds, retry_count, id} sözlüğü.
## Dönen: öncelik sırasına dizilmiş kopya.
func sort_by_priority(operations: Array) -> Array:
	var scored: Array = []
	for op in operations:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = op
		var priority: float = compute_priority(
			str(dict.get("type", "")),
			float(dict.get("wait_seconds", 0.0)),
			int(dict.get("retry_count", 0))
		)
		scored.append({"op": dict, "priority": priority})

	# Yüksek öncelik önce
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["priority"]) > float(b["priority"]))

	# Sadece işlemleri döndür
	var sorted_ops: Array = []
	for entry in scored:
		sorted_ops.append(entry["op"])
	return sorted_ops


## Bir işlem listesinden en yüksek öncelikli olanı seçer.
## operations: işlem listesi.
## Dönen: en öncelikli işlem; liste boşsa boş sözlük.
func pick_highest(operations: Array) -> Dictionary:
	var sorted_ops: Array = sort_by_priority(operations)
	if sorted_ops.is_empty():
		return {}
	return sorted_ops[0]


# ============================================================
# SORGULAMA
# ============================================================

## Bir işlem türünün temel önceliğini döndürür.
func base_priority_of(operation_type: String) -> int:
	return int(TYPE_PRIORITY.get(operation_type, 10))


## Bir işlem türü bilinen bir tür mü?
func is_known_type(operation_type: String) -> bool:
	return TYPE_PRIORITY.has(operation_type)
