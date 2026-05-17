@tool
class_name AITaskLifecycle
extends RefCounted

## Görev (task) yaşam döngüsü — durum makinesi.
##
## Bir task'ın hangi durumlarda olabileceğini, hangi geçişlerin geçerli olduğunu
## ve her durumun anlamını tanımlar. TaskSpec bu sınıfı kullanır.
##
## Tasarım: Geçersiz durum geçişleri engellenir (örn: 'done' bir task tekrar
## 'in_progress' olamaz; ama 'failed' bir task 'queued'a dönebilir — retry).

## Task durumları.
enum Status {
	QUEUED,       ## Kuyrukta, henüz başlamadı
	READY,        ## Bağımlılıkları çözüldü, başlamaya hazır
	IN_PROGRESS,  ## Bir cell role tarafından işleniyor
	BLOCKED,      ## Bir engele takıldı (bağımlılık, kaynak, onay bekliyor)
	IN_REVIEW,    ## İş bitti, doğrulama/inceleme aşamasında
	DONE,         ## Başarıyla tamamlandı + kanıtlandı
	FAILED,       ## Başarısız oldu (retry mümkün olabilir)
	CANCELLED,    ## Kullanıcı veya sistem tarafından iptal edildi
	ARCHIVED,     ## Tamamlandı ve arşivlendi (artık aktif değil)
}

## Durum -> string isim eşlemesi (serileştirme ve UI için).
const STATUS_NAMES: Dictionary = {
	Status.QUEUED: "queued",
	Status.READY: "ready",
	Status.IN_PROGRESS: "in_progress",
	Status.BLOCKED: "blocked",
	Status.IN_REVIEW: "in_review",
	Status.DONE: "done",
	Status.FAILED: "failed",
	Status.CANCELLED: "cancelled",
	Status.ARCHIVED: "archived",
}

## Durum -> Kanban kolon başlığı (Türkçe UI için).
const STATUS_DISPLAY_TR: Dictionary = {
	Status.QUEUED: "Kuyrukta",
	Status.READY: "Hazır",
	Status.IN_PROGRESS: "İşleniyor",
	Status.BLOCKED: "Engellendi",
	Status.IN_REVIEW: "İncelemede",
	Status.DONE: "Tamamlandı",
	Status.FAILED: "Başarısız",
	Status.CANCELLED: "İptal",
	Status.ARCHIVED: "Arşiv",
}

## Geçerli durum geçişleri. Anahtar: kaynak durum, değer: izin verilen hedef durumlar.
const VALID_TRANSITIONS: Dictionary = {
	Status.QUEUED: [Status.READY, Status.CANCELLED, Status.BLOCKED],
	Status.READY: [Status.IN_PROGRESS, Status.BLOCKED, Status.CANCELLED],
	Status.IN_PROGRESS: [Status.IN_REVIEW, Status.BLOCKED, Status.FAILED, Status.CANCELLED],
	Status.BLOCKED: [Status.QUEUED, Status.READY, Status.CANCELLED, Status.FAILED],
	Status.IN_REVIEW: [Status.DONE, Status.IN_PROGRESS, Status.FAILED],
	Status.DONE: [Status.ARCHIVED, Status.IN_PROGRESS],  ## IN_PROGRESS: regression/reopen
	Status.FAILED: [Status.QUEUED, Status.CANCELLED, Status.ARCHIVED],  ## QUEUED: retry
	Status.CANCELLED: [Status.ARCHIVED],
	Status.ARCHIVED: [],  ## Terminal — geçiş yok
}

## Aktif (henüz bitmemiş) durumlar.
const ACTIVE_STATES: Array = [
	Status.QUEUED, Status.READY, Status.IN_PROGRESS, Status.BLOCKED, Status.IN_REVIEW
]

## Terminal (bitmiş) durumlar.
const TERMINAL_STATES: Array = [Status.DONE, Status.CANCELLED, Status.ARCHIVED]


## Bir geçişin geçerli olup olmadığını kontrol eder.
static func can_transition(from: Status, to: Status) -> bool:
	if not VALID_TRANSITIONS.has(from):
		return false
	return (VALID_TRANSITIONS[from] as Array).has(to)


## Status enum -> string. Geçersizse "unknown" döner.
static func status_to_string(s: Status) -> String:
	return STATUS_NAMES.get(s, "unknown")


## String -> Status enum. Geçersizse -1 döner.
static func string_to_status(name: String) -> int:
	for key in STATUS_NAMES:
		if STATUS_NAMES[key] == name:
			return key
	return -1


## Status'un Türkçe görünen adını döndürür.
static func status_display_tr(s: Status) -> String:
	return STATUS_DISPLAY_TR.get(s, "Bilinmiyor")


## Durum aktif mi (henüz bitmemiş)?
static func is_active(s: Status) -> bool:
	return ACTIVE_STATES.has(s)


## Durum terminal mi (bitmiş)?
static func is_terminal(s: Status) -> bool:
	return TERMINAL_STATES.has(s)


## Durum başarılı bir tamamlanma mı?
static func is_success(s: Status) -> bool:
	return s == Status.DONE or s == Status.ARCHIVED


## Bir durumdan çıkılabilecek tüm geçerli hedefleri döndürür.
static func allowed_targets(from: Status) -> Array:
	return VALID_TRANSITIONS.get(from, [])
