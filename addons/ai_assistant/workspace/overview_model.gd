@tool
class_name AIOverviewModel
extends RefCounted

## OverviewModel — Genel Bakış sekmesi modeli (Layer 11 / Workspace).
##
## Workspace'in ilk sekmesi: tüm sistemin tek bakışta durumu.
## Pilot çalışıyor mu, kaç task var, ne aşamada, son aktivite ne.
##
## Bu model SALT-VERİdir — başka katmanlardan toplanan özet bilgiyi
## UI'a sunulabilir biçimde tutar. Hesaplama yapmaz, sunar.
##
## Mock policy: tüm değerler gerçek sisteme bağlandığında dolar;
## bağlanmadan önce sıfır/boş — sahte istatistik yok.

## Sistemin genel çalışma durumu.
enum SystemStatus { IDLE, PLANNING, EXECUTING, VERIFYING, BLOCKED, DONE }

const STATUS_NAMES: Dictionary = {
	SystemStatus.IDLE: "Boşta",
	SystemStatus.PLANNING: "Planlıyor",
	SystemStatus.EXECUTING: "Yürütüyor",
	SystemStatus.VERIFYING: "Doğruluyor",
	SystemStatus.BLOCKED: "Engellendi",
	SystemStatus.DONE: "Tamamlandı",
}


## Genel durum alanları.
var status: int = SystemStatus.IDLE
var current_task: String = ""              ## Aktif görev tanımı
var total_tasks: int = 0
var completed_tasks: int = 0
var failed_tasks: int = 0
var active_iteration: int = 0               ## Kaçıncı iterasyon
var total_cost_usd: float = 0.0             ## Şu ana kadar maliyet
var last_activity: String = ""              ## Son olay özeti
var pilot_live_mode: bool = false           ## Pilot Cell canlı mı


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Sistem durumunu ayarlar.
func set_status(p_status: int) -> void:
	if STATUS_NAMES.has(p_status):
		status = p_status


## Görev sayaçlarını günceller.
func update_task_counts(total: int, completed: int, failed: int) -> void:
	total_tasks = maxi(total, 0)
	completed_tasks = clampi(completed, 0, total_tasks)
	failed_tasks = clampi(failed, 0, total_tasks)


## Bir aktivite kaydeder — son olay.
func record_activity(activity: String) -> void:
	last_activity = activity


# ============================================================
# SORGULAMA
# ============================================================

## Görev tamamlanma oranı (0.0 - 1.0).
func completion_ratio() -> float:
	if total_tasks == 0:
		return 0.0
	return float(completed_tasks) / float(total_tasks)


## Sistem aktif mi (boşta veya bitmiş değil)?
func is_active() -> bool:
	return status != SystemStatus.IDLE and status != SystemStatus.DONE


## Sistemde sorun var mı (başarısız task veya engel)?
func has_problems() -> bool:
	return failed_tasks > 0 or status == SystemStatus.BLOCKED


## Aktif durumun adı.
func status_name() -> String:
	return STATUS_NAMES.get(status, "?")


## UI'da gösterilecek özet kartları.
## Her kart: {label, value}.
func summary_cards() -> Array:
	return [
		{"label": "Durum", "value": status_name()},
		{"label": "Görevler", "value": "%d / %d" % [
			completed_tasks, total_tasks
		]},
		{"label": "İlerleme", "value": "%d%%" % int(
			completion_ratio() * 100.0
		)},
		{"label": "Iterasyon", "value": str(active_iteration)},
		{"label": "Maliyet", "value": "$%.4f" % total_cost_usd},
		{"label": "Pilot", "value": "Canlı" if pilot_live_mode else "Hazır"},
	]


## Tam durum sözlüğü.
func to_dict() -> Dictionary:
	return {
		"status": status_name(),
		"current_task": current_task,
		"total_tasks": total_tasks,
		"completed_tasks": completed_tasks,
		"failed_tasks": failed_tasks,
		"completion_ratio": completion_ratio(),
		"active_iteration": active_iteration,
		"total_cost_usd": total_cost_usd,
		"is_active": is_active(),
		"has_problems": has_problems(),
	}


## Modeli başlangıç durumuna sıfırlar.
func reset() -> void:
	status = SystemStatus.IDLE
	current_task = ""
	total_tasks = 0
	completed_tasks = 0
	failed_tasks = 0
	active_iteration = 0
	total_cost_usd = 0.0
	last_activity = ""
