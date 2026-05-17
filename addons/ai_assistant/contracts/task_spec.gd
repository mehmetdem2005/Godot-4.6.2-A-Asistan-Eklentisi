@tool
class_name AITaskSpec
extends AIContractBase

## Görev (task) tanımı — sistemin en merkezi sözleşmesi.
##
## Bir TaskSpec, Pilot Cell pipeline'ında bir cell role'e atanan tek bir iş
## birimidir. Planner tarafından üretilir, DeliveryManager tarafından dağıtılır,
## bir Engineer tarafından işlenir, QA tarafından doğrulanır.
##
## Her task bir sahibe (owner_role), bir genre'ye ve bir iteration'a aittir.
## Yaşam döngüsü AITaskLifecycle.Status ile yönetilir.

# --- Kimlik ---
var id: String = ""                  ## Benzersiz task kimliği
var parent_id: String = ""           ## Üst task (alt görevler için); boş = kök
var iteration_id: String = ""        ## Ait olduğu iteration
var board_id: String = ""            ## Ait olduğu task board (Kanban)

# --- İçerik ---
var goal: String = ""                ## İnsan-okunabilir hedef (ne yapılacak)
var description: String = ""         ## Detaylı açıklama
var payload: Dictionary = {}         ## Cell role'e özel veri (serbest yapı)
var constraints: Dictionary = {}     ## Kısıtlar (deadline, budget, scope limitleri)
var acceptance_criteria: PackedStringArray = PackedStringArray()  ## Başarı koşulları

# --- Sahiplik ve atama ---
var owner_role: String = ""          ## Hangi cell role sorumlu (AICellRoles'tan)
var assigned_to: String = ""         ## Şu an işleyen instance (boş = atanmadı)
var created_by: String = "System"    ## Task'ı kim oluşturdu

# --- Sınıflandırma ---
var genre_id: String = ""            ## Oyun türü (genre profile referansı)
var tags: PackedStringArray = PackedStringArray()  ## Serbest etiketler

# --- Durum ---
var status: int = AITaskLifecycle.Status.QUEUED  ## Mevcut durum
var status_history: Array = []       ## [{from, to, at, reason}] geçiş kaydı

# --- Bağımlılık ---
var depends_on: PackedStringArray = PackedStringArray()  ## Bu task'ın beklediği task id'leri

# --- Zaman ---
var created_at: String = ""          ## Oluşturma zamanı (ISO 8601)
var started_at: String = ""          ## İşleme başlama zamanı
var completed_at: String = ""        ## Tamamlanma zamanı
var deadline: String = ""            ## Son tarih (opsiyonel)

# --- Çalıştırma metaları ---
var retry_count: int = 0             ## Kaç kez yeniden denendi
var max_retries: int = 3             ## İzin verilen maksimum retry
var priority: int = 1                ## 0=düşük, 1=normal, 2=yüksek, 3=kritik


func contract_type() -> String:
	return "TaskSpec"


## Yeni bir task oluşturur (factory).
static func create(p_goal: String, p_owner_role: String, p_iteration_id: String = "") -> AITaskSpec:
	var t := AITaskSpec.new()
	t.id = AIContractBase.generate_id("task")
	t.goal = p_goal
	t.owner_role = p_owner_role
	t.iteration_id = p_iteration_id
	t.created_at = AIContractBase.now_iso()
	t.status = AITaskLifecycle.Status.QUEUED
	return t


## Task durumunu değiştirir. Geçiş geçersizse false döner ve durum değişmez.
func transition_to(new_status: int, reason: String = "") -> bool:
	if not AITaskLifecycle.can_transition(status, new_status):
		push_warning(
			"Geçersiz task geçişi: %s -> %s (task: %s)"
			% [
				AITaskLifecycle.status_to_string(status),
				AITaskLifecycle.status_to_string(new_status),
				id,
			]
		)
		return false

	var transition := {
		"from": AITaskLifecycle.status_to_string(status),
		"to": AITaskLifecycle.status_to_string(new_status),
		"at": AIContractBase.now_iso(),
		"reason": reason,
	}
	status_history.append(transition)

	# Zaman damgalarını otomatik güncelle
	if new_status == AITaskLifecycle.Status.IN_PROGRESS and started_at.is_empty():
		started_at = AIContractBase.now_iso()
	if AITaskLifecycle.is_terminal(new_status):
		completed_at = AIContractBase.now_iso()

	status = new_status
	return true


## Task retry edilebilir mi?
func can_retry() -> bool:
	return retry_count < max_retries and status == AITaskLifecycle.Status.FAILED


## Retry sayacını artırır ve task'ı kuyruğa geri alır.
func mark_retry() -> bool:
	if not can_retry():
		return false
	retry_count += 1
	return transition_to(AITaskLifecycle.Status.QUEUED, "retry #%d" % retry_count)


## Task aktif mi (henüz bitmemiş)?
func is_active() -> bool:
	return AITaskLifecycle.is_active(status)


## Task başarıyla tamamlandı mı?
func is_complete() -> bool:
	return AITaskLifecycle.is_success(status)


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"parent_id": parent_id,
		"iteration_id": iteration_id,
		"board_id": board_id,
		"goal": goal,
		"description": description,
		"payload": payload,
		"constraints": constraints,
		"acceptance_criteria": acceptance_criteria,
		"owner_role": owner_role,
		"assigned_to": assigned_to,
		"created_by": created_by,
		"genre_id": genre_id,
		"tags": tags,
		"status": AITaskLifecycle.status_to_string(status),
		"status_history": status_history,
		"depends_on": depends_on,
		"created_at": created_at,
		"started_at": started_at,
		"completed_at": completed_at,
		"deadline": deadline,
		"retry_count": retry_count,
		"max_retries": max_retries,
		"priority": priority,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	parent_id = data.get("parent_id", "")
	iteration_id = data.get("iteration_id", "")
	board_id = data.get("board_id", "")
	goal = data.get("goal", "")
	description = data.get("description", "")
	payload = data.get("payload", {})
	constraints = data.get("constraints", {})
	acceptance_criteria = PackedStringArray(data.get("acceptance_criteria", []))
	owner_role = data.get("owner_role", "")
	assigned_to = data.get("assigned_to", "")
	created_by = data.get("created_by", "System")
	genre_id = data.get("genre_id", "")
	tags = PackedStringArray(data.get("tags", []))
	var status_str: String = data.get("status", "queued")
	var parsed_status: int = AITaskLifecycle.string_to_status(status_str)
	status = parsed_status if parsed_status >= 0 else AITaskLifecycle.Status.QUEUED
	status_history = data.get("status_history", [])
	depends_on = PackedStringArray(data.get("depends_on", []))
	created_at = data.get("created_at", "")
	started_at = data.get("started_at", "")
	completed_at = data.get("completed_at", "")
	deadline = data.get("deadline", "")
	retry_count = int(data.get("retry_count", 0))
	max_retries = int(data.get("max_retries", 3))
	priority = int(data.get("priority", 1))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, goal, "goal")
	require_non_empty_string(result, owner_role, "owner_role")
	require_in_range(result, priority, 0, 3, "priority")

	if max_retries < 0:
		result.add_error("max_retries negatif olamaz: %d" % max_retries)
	if retry_count < 0:
		result.add_error("retry_count negatif olamaz: %d" % retry_count)
	if retry_count > max_retries:
		result.add_warning(
			"retry_count (%d) max_retries'ı (%d) aşıyor" % [retry_count, max_retries]
		)

	if created_at.is_empty():
		result.add_warning("created_at boş — zaman takibi eksik olacak")

	# Kendine bağımlılık kontrolü
	if depends_on.has(id):
		result.add_error("Task kendine bağımlı olamaz (id: %s)" % id)
