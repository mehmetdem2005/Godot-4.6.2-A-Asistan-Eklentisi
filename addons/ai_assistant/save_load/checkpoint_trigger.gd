@tool
class_name AISaveCheckpointTrigger
extends RefCounted

## CheckpointTrigger — kontrol noktası tetikleyici (Madde 09 / autosave).
##
## Zaman tabanlı otomatik kayıt yeterli değil — bazı ANLAR kayıt için
## kritiktir, beklemeden kaydedilmeli: bölüm bitti, boss yenildi,
## önemli eşya alındı, ayar değişti.
##
## Bu sınıf OLAY tabanlı tetikler: oyun "level_complete olayı oldu"
## der, trigger "bu olay kayıt gerektiriyor mu" cevabını verir.
##
## Olaylar önem derecesine göre sınıflanır — kritik olaylar her
## zaman kaydeder, küçük olaylar debounce'a tabidir (üst üste çok
## olay tek kayda toplanır).
##
## Mock policy: tetik kararı gerçek olaydan.

## Bir olayın kayıt önceliği.
enum TriggerPriority { CRITICAL, NORMAL, LOW }

const PRIORITY_NAMES: Dictionary = {
	TriggerPriority.CRITICAL: "critical",
	TriggerPriority.NORMAL: "normal",
	TriggerPriority.LOW: "low",
}

## Bilinen kontrol noktası olayları ve öncelikleri.
const TRIGGER_EVENTS: Dictionary = {
	"level_complete": TriggerPriority.CRITICAL,
	"boss_defeated": TriggerPriority.CRITICAL,
	"chapter_end": TriggerPriority.CRITICAL,
	"item_acquired": TriggerPriority.NORMAL,
	"quest_updated": TriggerPriority.NORMAL,
	"settings_changed": TriggerPriority.NORMAL,
	"area_entered": TriggerPriority.LOW,
	"checkpoint_touched": TriggerPriority.LOW,
}


## LOW öncelikli olaylar için debounce sayacı.
var _low_event_count: int = 0

## LOW olayların kaç tanesi birikince kayıt tetiklenir.
var low_debounce_threshold: int = 3

## Toplam tetiklenen kontrol noktası sayısı.
var _checkpoint_count: int = 0


# ============================================================
# OLAY İŞLEME
# ============================================================

## Bir oyun olayı bildirir ve kayıt gerekip gerekmediğini söyler.
## event_name: olay adı (TRIGGER_EVENTS'ten biri).
## Dönen: {should_save: bool, priority: String, reason: String}
func notify_event(event_name: String) -> Dictionary:
	# Bilinmeyen olay — kayıt tetiklemez
	if not TRIGGER_EVENTS.has(event_name):
		return {
			"should_save": false,
			"priority": "",
			"reason": "Bilinmeyen olay — tetik yok: " + event_name,
		}

	var priority: int = TRIGGER_EVENTS[event_name]

	match priority:
		TriggerPriority.CRITICAL:
			# Kritik olay — her zaman kaydet, debounce sıfırla
			_low_event_count = 0
			_checkpoint_count += 1
			return {
				"should_save": true,
				"priority": PRIORITY_NAMES[priority],
				"reason": "Kritik olay — hemen kayıt",
			}

		TriggerPriority.NORMAL:
			# Normal olay — kaydet
			_checkpoint_count += 1
			return {
				"should_save": true,
				"priority": PRIORITY_NAMES[priority],
				"reason": "Önemli olay — kayıt tetiklendi",
			}

		TriggerPriority.LOW:
			# Düşük öncelik — debounce: eşiğe ulaşınca kaydet
			_low_event_count += 1
			if _low_event_count >= low_debounce_threshold:
				_low_event_count = 0
				_checkpoint_count += 1
				return {
					"should_save": true,
					"priority": PRIORITY_NAMES[priority],
					"reason": "Birikmiş küçük olaylar — kayıt",
				}
			return {
				"should_save": false,
				"priority": PRIORITY_NAMES[priority],
				"reason": "Küçük olay — biriktiriliyor (%d/%d)" % [
					_low_event_count, low_debounce_threshold
				],
			}

		_:
			return {
				"should_save": false, "priority": "",
				"reason": "Bilinmeyen öncelik",
			}


# ============================================================
# SORGULAMA
# ============================================================

## Bir olay bilinen bir tetikleyici mi?
func is_trigger_event(event_name: String) -> bool:
	return TRIGGER_EVENTS.has(event_name)


## Bir olayın önceliğini döndürür. Bilinmiyorsa -1.
func event_priority(event_name: String) -> int:
	return int(TRIGGER_EVENTS.get(event_name, -1))


## Toplam tetiklenen kontrol noktası sayısı.
func checkpoint_count() -> int:
	return _checkpoint_count


## Bekleyen (henüz kaydedilmemiş) düşük öncelikli olay sayısı.
func pending_low_events() -> int:
	return _low_event_count
