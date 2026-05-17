@tool
class_name AIAudioCompletionTest
extends RefCounted

## Madde 08 — Audio Tamamlama Self-Test
##
## Sıkı testler: templates (genre_audio_registry, template_applier),
## budget (memory_estimator, audio_budget_enforcer), lifecycle
## (audio_focus_handler, scene_audio_cleanup), ai_generation_stubs
## (ai_audio_gen_provider, elevenlabs, stable_audio).


static func run_all() -> Array:
	var results: Array = []

	# Templates
	results.append(_b("AudioExt: Template", _test_genre_registry()))
	results.append(_b("AudioExt: Template", _test_template_plan()))
	results.append(_b("AudioExt: Template", _test_template_unknown()))

	# Budget
	results.append(_b("AudioExt: Memory", _test_memory_estimate()))
	results.append(_b("AudioExt: Memory", _test_memory_ogg()))
	results.append(_b("AudioExt: Budget", _test_budget_fits()))
	results.append(_b("AudioExt: Budget", _test_budget_overflow()))
	results.append(_b("AudioExt: Budget", _test_budget_load_unload()))

	# Lifecycle
	results.append(_b("AudioExt: Focus", _test_focus_lost_gained()))
	results.append(_b("AudioExt: Focus", _test_focus_duck()))
	results.append(_b("AudioExt: Cleanup", _test_cleanup_actions()))
	results.append(_b("AudioExt: Cleanup", _test_cleanup_plan()))

	# AI generation stubs
	results.append(_b("AudioExt: AIGen", _test_aigen_unavailable()))
	results.append(_b("AudioExt: AIGen", _test_aigen_invalid_prompt()))
	results.append(_b("AudioExt: AIGen", _test_aigen_fallback()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# TEMPLATES
# ============================================================

static func _test_genre_registry() -> Dictionary:
	var name := "GenreRegistry 9 tür"
	var registry := AIAudioGenreRegistry.new()
	if registry.genre_count() != 9:
		return _fail(name, "9 tür ses şablonu olmalı")
	# Bilinen tür
	if not registry.has_genre("horror_3d"):
		return _fail(name, "horror_3d şablonu olmalı")
	# Tür için varsayılan sfx
	var sfx: PackedStringArray = registry.default_sfx_for("fps_3d")
	if sfx.is_empty():
		return _fail(name, "FPS için varsayılan sfx olmalı")
	return _ok(name)


static func _test_template_plan() -> Dictionary:
	var name := "TemplateApplier plan üretimi"
	var applier := AIAudioTemplateApplier.new()
	var result: Dictionary = applier.build_plan("horror_3d")
	if not bool(result["ok"]):
		return _fail(name, "geçerli tür plan üretmeli")
	var plan: AIAudioTemplateApplier.ApplyPlan = result["plan"]
	if plan.steps.is_empty():
		return _fail(name, "plan kurulum adımları içermeli")
	return _ok(name)


static func _test_template_unknown() -> Dictionary:
	var name := "TemplateApplier bilinmeyen tür"
	var applier := AIAudioTemplateApplier.new()
	var result: Dictionary = applier.build_plan("olmayan_tur")
	if bool(result["ok"]):
		return _fail(name, "bilinmeyen tür plan üretmemeli")
	return _ok(name)


# ============================================================
# BUDGET
# ============================================================

static func _test_memory_estimate() -> Dictionary:
	var name := "MemoryEstimator tahmin"
	var estimator := AIAudioMemoryEstimator.new()
	# 1 saniye mono PCM ~88KB
	var one_sec: int = estimator.estimate_stream(1.0, 1)
	if one_sec < 80000 or one_sec > 96000:
		return _fail(name, "1sn mono PCM ~88KB olmalı")
	# Stereo iki kat
	var stereo: int = estimator.estimate_stream(1.0, 2)
	if stereo != one_sec * 2:
		return _fail(name, "stereo mono'nun iki katı olmalı")
	return _ok(name)


static func _test_memory_ogg() -> Dictionary:
	var name := "MemoryEstimator OGG sıkıştırma"
	var estimator := AIAudioMemoryEstimator.new()
	var pcm: int = estimator.estimate_stream(
		10.0, 1, AIAudioMemoryEstimator.StorageType.PCM_UNCOMPRESSED
	)
	var ogg: int = estimator.estimate_stream(
		10.0, 1, AIAudioMemoryEstimator.StorageType.OGG_COMPRESSED
	)
	if ogg >= pcm:
		return _fail(name, "OGG PCM'den küçük olmalı")
	return _ok(name)


static func _test_budget_fits() -> Dictionary:
	var name := "Budget sığma kontrolü"
	var budget := AIAudioBudgetEnforcer.new(1)  # 32 MB
	var check: Dictionary = budget.check_load("sound_1", 1024 * 1024)
	if not bool(check["allowed"]):
		return _fail(name, "küçük ses bütçeye sığmalı")
	return _ok(name)


static func _test_budget_overflow() -> Dictionary:
	var name := "Budget aşım reddi"
	var budget := AIAudioBudgetEnforcer.new(0)  # 16 MB
	# 40 MB ses — 16 MB bütçeye sığmaz
	var check: Dictionary = budget.check_load("huge", 40 * 1024 * 1024)
	if bool(check["allowed"]):
		return _fail(name, "bütçe aşımı reddedilmeli")
	if int(check["free_needed"]) <= 0:
		return _fail(name, "ne kadar yer gerektiği bildirilmeli")
	return _ok(name)


static func _test_budget_load_unload() -> Dictionary:
	var name := "Budget yükle/boşalt"
	var budget := AIAudioBudgetEnforcer.new(1)
	# Yükle
	if not budget.register_load("snd", 5 * 1024 * 1024):
		return _fail(name, "geçerli ses yüklenebilmeli")
	if budget.used_bytes != 5 * 1024 * 1024:
		return _fail(name, "yükleme kullanımı artırmalı")
	# Boşalt
	if not budget.register_unload("snd"):
		return _fail(name, "yüklü ses boşaltılabilmeli")
	if budget.used_bytes != 0:
		return _fail(name, "boşaltma kullanımı azaltmalı")
	return _ok(name)


# ============================================================
# LIFECYCLE
# ============================================================

static func _test_focus_lost_gained() -> Dictionary:
	var name := "Focus kayıp ve geri kazanım"
	var handler := AIAudioFocusHandler.new()
	# Odak kaybı — ses durmalı
	var lost: Dictionary = handler.on_focus_lost()
	if not is_zero_approx(float(lost["volume"])):
		return _fail(name, "odak kaybında ses 0 olmalı")
	if handler.can_play_audio():
		return _fail(name, "odak kayıpken ses çalınamamalı")
	# Odak geri — ses restore
	var gained: Dictionary = handler.on_focus_gained()
	if not bool(gained["should_resume"]):
		return _fail(name, "odak geri gelince devam etmeli")
	return _ok(name)


static func _test_focus_duck() -> Dictionary:
	var name := "Focus ducking"
	var handler := AIAudioFocusHandler.new()
	var ducked: Dictionary = handler.on_duck_requested()
	# Ducking — ses kısılır ama durmaz
	if bool(ducked["should_pause"]):
		return _fail(name, "ducking sesi durdurmamalı, kısmalı")
	if not handler.is_ducked():
		return _fail(name, "ducking durumu işaretlenmeli")
	if handler.current_volume() >= 1.0:
		return _fail(name, "ducking ses seviyesini düşürmeli")
	return _ok(name)


static func _test_cleanup_actions() -> Dictionary:
	var name := "Cleanup kategori eylemleri"
	var cleanup := AIAudioSceneCleanup.new()
	# sfx -> stop
	if cleanup.action_for_category("sfx") != \
			AIAudioSceneCleanup.CleanupAction.STOP:
		return _fail(name, "sfx STOP olmalı")
	# music -> keep
	if cleanup.action_for_category("music") != \
			AIAudioSceneCleanup.CleanupAction.KEEP:
		return _fail(name, "music KEEP olmalı")
	# bilinmeyen -> stop (güvenli)
	if cleanup.action_for_category("bilinmeyen") != \
			AIAudioSceneCleanup.CleanupAction.STOP:
		return _fail(name, "bilinmeyen kategori STOP olmalı")
	return _ok(name)


static func _test_cleanup_plan() -> Dictionary:
	var name := "Cleanup geçiş planı"
	var cleanup := AIAudioSceneCleanup.new()
	cleanup.register_sound("explosion", "sfx")
	cleanup.register_sound("bg_music", "music")
	cleanup.register_sound("wind", "ambient")
	var plan: Dictionary = cleanup.build_cleanup_plan()
	var to_stop: PackedStringArray = plan["stop"]
	var to_keep: PackedStringArray = plan["keep"]
	# sfx durdurulmalı, music tutulmalı
	if not to_stop.has("explosion"):
		return _fail(name, "sfx durdurulmalı")
	if not to_keep.has("bg_music"):
		return _fail(name, "music tutulmalı")
	return _ok(name)


# ============================================================
# AI GENERATION STUBS
# ============================================================

static func _test_aigen_unavailable() -> Dictionary:
	var name := "AIGen Phase 1 kullanılamaz"
	var elevenlabs := AIAudioElevenLabsProvider.new()
	# Phase 1 — kullanılamaz olmalı
	if elevenlabs.is_available():
		return _fail(name, "Phase 1 AI üretim kullanılamaz olmalı")
	# Üretim NOT_AVAILABLE dönmeli
	var result: AIAudioGenProviderBase.GenResult = elevenlabs.generate(
		"cam kırılması sesi"
	)
	if result.is_generated():
		return _fail(name, "Phase 1 sahte ses üretmemeli")
	return _ok(name)


static func _test_aigen_invalid_prompt() -> Dictionary:
	var name := "AIGen geçersiz tarif"
	var stable := AIAudioStableAudioProvider.new()
	# Boş tarif — geçersiz
	var result: AIAudioGenProviderBase.GenResult = stable.generate("   ")
	if result.status != AIAudioGenProviderBase.GenStatus.INVALID_PROMPT:
		return _fail(name, "boş tarif INVALID_PROMPT olmalı")
	return _ok(name)


static func _test_aigen_fallback() -> Dictionary:
	var name := "AIGen fallback önerisi"
	var elevenlabs := AIAudioElevenLabsProvider.new()
	var result: AIAudioGenProviderBase.GenResult = elevenlabs.generate(
		"ejderha kükremesi"
	)
	# Kullanılamadığında procedural alternatif önerilmeli
	if result.fallback_suggestion.is_empty():
		return _fail(name, "AI yokken fallback önerisi olmalı")
	return _ok(name)
