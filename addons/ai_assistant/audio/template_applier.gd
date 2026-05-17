@tool
class_name AIAudioTemplateApplier
extends RefCounted

## TemplateApplier — şablon uygulayıcı (Madde 08 / templates).
##
## genre_audio_registry bir tür için ses şablonu verir (soyut tarif).
## Bu sınıf o şablonu SOMUT KURULUM ADIMLARINA çevirir: hangi bus
## kurulacak, hangi EQ uygulanacak, hangi sesler önceden üretilecek.
##
## "Uygulama" gerçek bus oluşturmayı değil, oluşturma PLANINI üretir
## — gerçek kurulum bus_architect + AudioServer'ın işi. Bu sınıf
## planı çıkarır, test edilebilir.
##
## Mock policy: kurulum planı gerçek şablon içeriğinden.

## Bir uygulama planı.
class ApplyPlan extends RefCounted:
	var genre: String = ""
	var eq_profile: String = ""
	var reverb: String = ""
	var sfx_to_generate: PackedStringArray = PackedStringArray()
	var intensity_bias: float = 0.5
	var steps: Array = []            ## İnsan-okunur kurulum adımları

	func to_dict() -> Dictionary:
		return {
			"genre": genre,
			"eq_profile": eq_profile,
			"reverb": reverb,
			"sfx_count": sfx_to_generate.size(),
			"step_count": steps.size(),
		}


## Tür ses kayıt defteri.
var _registry: AIAudioGenreRegistry


func _init(registry: AIAudioGenreRegistry = null) -> void:
	if registry != null:
		_registry = registry
	else:
		_registry = AIAudioGenreRegistry.new()


# ============================================================
# ŞABLON UYGULAMA
# ============================================================

## Bir tür için ses kurulum planı üretir.
## genre_name: oyun türü.
## Dönen: {ok: bool, plan: ApplyPlan, reason: String}
func build_plan(genre_name: String) -> Dictionary:
	if not _registry.has_genre(genre_name):
		return {
			"ok": false, "plan": null,
			"reason": "Tür için ses şablonu yok: " + genre_name,
		}

	var template: Dictionary = _registry.get_template(genre_name)
	var plan := ApplyPlan.new()
	plan.genre = genre_name
	plan.eq_profile = str(template["eq_profile"])
	plan.reverb = str(template["reverb"])
	plan.sfx_to_generate = _registry.default_sfx_for(genre_name)
	plan.intensity_bias = _registry.intensity_bias(genre_name)

	# Somut kurulum adımları
	plan.steps = _build_steps(plan)

	return {
		"ok": true,
		"plan": plan,
		"reason": "%s için ses planı hazır" % genre_name,
	}


## Bir plandan kurulum adımlarını üretir.
func _build_steps(plan: ApplyPlan) -> Array:
	var steps: Array = []
	# 1. Bus yapısı
	steps.append({
		"order": 1, "action": "setup_buses",
		"detail": "Standart bus ağacı kur (Master/Music/SFX/UI)",
	})
	# 2. EQ profili
	steps.append({
		"order": 2, "action": "apply_eq",
		"detail": "Master bus'a '%s' EQ profili uygula" % \
			plan.eq_profile,
	})
	# 3. Reverb (varsa)
	if plan.reverb != "none":
		steps.append({
			"order": 3, "action": "add_reverb",
			"detail": "SFX bus'a '%s' reverb ekle" % plan.reverb,
		})
	# 4. Sfx üretimi
	if not plan.sfx_to_generate.is_empty():
		steps.append({
			"order": 4, "action": "generate_sfx",
			"detail": "%d varsayılan ses efekti üret" % \
				plan.sfx_to_generate.size(),
		})
	# 5. Müzik yoğunluğu
	steps.append({
		"order": 5, "action": "set_intensity_bias",
		"detail": "Müzik yoğunluk eğilimini %.2f ayarla" % \
			plan.intensity_bias,
	})
	return steps


# ============================================================
# SORGULAMA
# ============================================================

## Bir tür için plan üretilebilir mi?
func can_apply(genre_name: String) -> bool:
	return _registry.has_genre(genre_name)


## Bir tür için kaç kurulum adımı gerekir?
func step_count_for(genre_name: String) -> int:
	var result: Dictionary = build_plan(genre_name)
	if not bool(result["ok"]):
		return 0
	return (result["plan"] as ApplyPlan).steps.size()
