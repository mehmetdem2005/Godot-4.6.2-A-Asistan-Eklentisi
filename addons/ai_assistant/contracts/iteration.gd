@tool
class_name AIIteration
extends AIContractBase

## Iteration — artımlı geliştirme birimi.
##
## Bir kullanıcı isteği, tek seferde değil, küçük doğrulanabilir parçalara
## (iteration) bölünerek işlenir. Her iteration sonunda kullanıcıya sunulur,
## onay alınır, sonraki iteration başlar.
##
## Bu, "devasa oyunu şıp diye yapma" tuzağından kaçınmanın yolu: önce küçük,
## çalışan, doğrulanmış parça; sonra üstüne ekle.

## Iteration boyutları — task sayısına göre.
enum Size {
	MICRO,   ## 1 task — tek node, tek script
	SMALL,   ## 2-4 task — küçük feature slice
	MEDIUM,  ## 5-10 task — tam bir feature
	LARGE,   ## 10+ task — bölünmesi önerilir
}

const SIZE_NAMES: Dictionary = {
	Size.MICRO: "micro",
	Size.SMALL: "small",
	Size.MEDIUM: "medium",
	Size.LARGE: "large",
}

const SIZE_MAX_TASKS: Dictionary = {
	Size.MICRO: 1,
	Size.SMALL: 4,
	Size.MEDIUM: 10,
	Size.LARGE: 999,
}

## Iteration yaşam döngüsü durumları.
enum Phase {
	PLANNING,  ## ProductManager + Architect tasarlıyor
	ACTIVE,    ## Engineer + QA döngüsü çalışıyor
	REVIEW,    ## Kullanıcıya sunuldu, geri bildirim bekleniyor
	RETRO,     ## Episodic memory'ye kaydediliyor
	CLOSED,    ## Kapandı, bir sonraki başlayabilir
}

const PHASE_NAMES: Dictionary = {
	Phase.PLANNING: "planning",
	Phase.ACTIVE: "active",
	Phase.REVIEW: "review",
	Phase.RETRO: "retro",
	Phase.CLOSED: "closed",
}

# --- Kimlik ---
var id: String = ""
var number: int = 1                  ## Kaçıncı iteration (1, 2, 3...)
var goal: String = ""                ## Bu iteration'ın hedefi

# --- Sınıflandırma ---
var size: int = Size.SMALL
var genre_id: String = ""
var phase: int = Phase.PLANNING

# --- İçerik ---
var task_ids: PackedStringArray = PackedStringArray()  ## Bu iteration'a ait task'lar
var branch_name: String = ""         ## VCS branch (iteration/{id})

# --- Zaman ---
var started_at: String = ""
var ended_at: String = ""

# --- Sonuç ---
var retro_notes: String = ""         ## Ne işe yaradı, ne yaramadı (öğrenme)
var user_approved: bool = false      ## Kullanıcı bu iteration'ı onayladı mı
var commit_count: int = 0            ## Bu iteration'da kaç commit yapıldı


func contract_type() -> String:
	return "Iteration"


## Yeni bir iteration oluşturur (factory).
static func create(p_number: int, p_goal: String, p_size: int = Size.SMALL) -> AIIteration:
	var it := AIIteration.new()
	it.id = AIContractBase.generate_id("iter")
	it.number = p_number
	it.goal = p_goal
	it.size = p_size
	it.branch_name = "iteration/%s" % it.id
	it.started_at = AIContractBase.now_iso()
	it.phase = Phase.PLANNING
	return it


## Bu iteration'ın task kapasitesini aşıp aşmadığını kontrol eder.
func is_over_capacity() -> bool:
	var limit: int = SIZE_MAX_TASKS.get(size, 999)
	return task_ids.size() > limit


## Boyutun string adı.
func size_name() -> String:
	return SIZE_NAMES.get(size, "unknown")


## Fazın string adı.
func phase_name() -> String:
	return PHASE_NAMES.get(phase, "unknown")


## Iteration aktif mi (henüz kapanmadı)?
func is_open() -> bool:
	return phase != Phase.CLOSED


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"number": number,
		"goal": goal,
		"size": SIZE_NAMES.get(size, "small"),
		"genre_id": genre_id,
		"phase": PHASE_NAMES.get(phase, "planning"),
		"task_ids": task_ids,
		"branch_name": branch_name,
		"started_at": started_at,
		"ended_at": ended_at,
		"retro_notes": retro_notes,
		"user_approved": user_approved,
		"commit_count": commit_count,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	number = int(data.get("number", 1))
	goal = data.get("goal", "")
	size = _parse_size(data.get("size", "small"))
	genre_id = data.get("genre_id", "")
	phase = _parse_phase(data.get("phase", "planning"))
	task_ids = PackedStringArray(data.get("task_ids", []))
	branch_name = data.get("branch_name", "")
	started_at = data.get("started_at", "")
	ended_at = data.get("ended_at", "")
	retro_notes = data.get("retro_notes", "")
	user_approved = bool(data.get("user_approved", false))
	commit_count = int(data.get("commit_count", 0))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, goal, "goal")
	if number < 1:
		result.add_error("number en az 1 olmalı: %d" % number)
	if is_over_capacity():
		result.add_warning(
			"Iteration '%s' boyutu (%s) için fazla task içeriyor (%d) — bölünmesi önerilir"
			% [size_name(), size_name(), task_ids.size()]
		)


static func _parse_size(s: String) -> int:
	for key in SIZE_NAMES:
		if SIZE_NAMES[key] == s:
			return key
	return Size.SMALL


static func _parse_phase(s: String) -> int:
	for key in PHASE_NAMES:
		if PHASE_NAMES[key] == s:
			return key
	return Phase.PLANNING
