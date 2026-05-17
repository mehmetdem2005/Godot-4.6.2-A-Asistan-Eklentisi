@tool
class_name AIDebugMemoryBridge
extends RefCounted

## DebugMemoryBridge — Hata ↔ Bellek köprüsü (Aşama 4b / devir ADIM 2b).
##
## SORUN (denetim bulgusu): debug_loop bir hatayı çözünce çözüm hiçbir
## yere yazılmıyordu; aynı hata tekrar gelince sıfırdan uğraşılıyordu.
## memory/ Episodic + Procedural API'leri "neyin işe yaradığını hatırla"
## için hazırdı ama debug_loop bunları HİÇ çağırmıyordu.
##
## ÇÖZÜM: Mevcut hiçbir dosyayı değiştirmeyen ince köprü. İki yön:
##   1. remember_resolution() — çözülen hatayı Episodic'e (anı) yazar;
##      BAŞARILI çözümü Procedural'a (tekrarlanabilir reçete) kaydeder.
##   2. recall_similar() — yeni hata gelince ÖNCE bellekte arar; daha
##      önce çözülmüşse eski çözümü güven skoruyla önerir.
##
## Mock policy: yalnızca GERÇEKTEN başarılı çözüm tekrarlanabilir
## prosedür olur; bellekte yoksa found=false dürüstçe döner — uydurma
## çözüm önerilmez.

var _episodic: AIEpisodicMemory = null
var _procedural: AIProceduralMemory = null
var _classifier: AIDebugErrorClassifier = null


func _init(
	episodic: AIEpisodicMemory,
	procedural: AIProceduralMemory,
	classifier: AIDebugErrorClassifier = null
) -> void:
	_episodic = episodic
	_procedural = procedural
	if classifier != null:
		_classifier = classifier
	else:
		_classifier = AIDebugErrorClassifier.new()


## Hata metnini satır no / yol / sayı bağımsız kararlı bir imzaya
## indirger — "res://player.gd:42" ile "res://x.gd:9" aynı hatayı
## gösteriyorsa eşleşebilsinler.
func _signature(error_text: String) -> String:
	var lowered: String = error_text.to_lower()
	var out: String = ""
	for i in range(lowered.length()):
		var c: String = lowered[i]
		if (c >= "a" and c <= "z") or c == " ":
			out += c
		else:
			out += " "
	var words: PackedStringArray = out.split(" ", false)
	var kept: PackedStringArray = PackedStringArray()
	for w in words:
		if w.length() >= 4 and kept.size() < 8:
			kept.append(w)
	return " ".join(kept)


## Çözülen bir hatayı belleğe yazar.
## succeeded=true ve fix doluysa Procedural'a tekrarlanabilir reçete olur.
## Dönen: {stored, category, reusable, procedure_id}
func remember_resolution(
	error_text: String, fix_description: String, succeeded: bool
) -> Dictionary:
	var ec: AIDebugErrorClassifier.ErrorClass = _classifier.classify(
		error_text
	)
	var cat: String = ec.category_name()

	_episodic.record_debug_outcome(
		error_text.left(120), succeeded, fix_description
	)

	var reusable: bool = succeeded \
		and not fix_description.strip_edges().is_empty()
	if not reusable:
		return {
			"stored": true,
			"category": cat,
			"reusable": false,
			"procedure_id": "",
		}

	var sig: String = _signature(error_text)
	var rec: AIMemoryRecord = _procedural.record_procedure(
		"fix::%s::%s" % [cat, sig],
		PackedStringArray([fix_description]),
		error_text.left(200)
	)
	rec.structured_data["error_category"] = cat
	rec.structured_data["error_signature"] = sig
	return {
		"stored": true,
		"category": cat,
		"reusable": true,
		"procedure_id": rec.id,
	}


## Yeni bir hata için bellekte daha önce çözüm var mı arar.
## Önce Procedural (kanıtlı reçete), sonra Episodic (geçmiş anı).
## Dönen: {found, source, suggestion, confidence, category}
func recall_similar(error_text: String) -> Dictionary:
	var ec: AIDebugErrorClassifier.ErrorClass = _classifier.classify(
		error_text
	)
	var cat: String = ec.category_name()
	var sig: String = _signature(error_text)

	# --- 1. Procedural: kanıtlı, tekrarlanabilir reçete ---
	for rec in _procedural.find_by_tag("procedure"):
		if str(rec.structured_data.get("error_category", "")) != cat:
			continue
		if str(rec.structured_data.get("error_signature", "")) != sig:
			continue
		var steps: PackedStringArray = PackedStringArray(
			rec.structured_data.get("steps", [])
		)
		var rate: float = _procedural.success_rate(rec.id)
		var conf: float = 0.7 if rate < 0.0 else maxf(0.5, rate)
		return {
			"found": true,
			"source": "procedural",
			"suggestion": " ".join(steps),
			"confidence": conf,
			"category": cat,
		}

	# --- 2. Episodic: çözülmüş geçmiş anılar ---
	for rec in _episodic.find_by_tag("resolved"):
		var sig_match: bool = _shares_enough(
			_signature(rec.content), sig
		)
		if sig_match:
			return {
				"found": true,
				"source": "episodic",
				"suggestion": rec.content,
				"confidence": 0.4,
				"category": cat,
			}

	return {
		"found": false,
		"source": "",
		"suggestion": "",
		"confidence": 0.0,
		"category": cat,
	}


## İki imza yeterince ortak anlamlı kelime paylaşıyor mu (>=2).
func _shares_enough(sig_a: String, sig_b: String) -> bool:
	var a_words: PackedStringArray = sig_a.split(" ", false)
	var b_words: PackedStringArray = sig_b.split(" ", false)
	var shared: int = 0
	for w in a_words:
		if w in b_words:
			shared += 1
	return shared >= 2


## Köprü istatistikleri — UI / test için.
func bridge_stats() -> Dictionary:
	return {
		"episodic_count": _episodic.count(),
		"procedural_count": _procedural.count(),
	}
