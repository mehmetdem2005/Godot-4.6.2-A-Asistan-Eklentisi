@tool
class_name AISaveAnomalyDetector
extends RefCounted

## AnomalyDetector — anomali dedektörü (Madde 09 / Save-Load / anti-cheat).
##
## İmza doğrulama (HMAC) kurcalamayı yakalar — AMA oyuncu oyunun
## kendi içinden hile yaptıysa (bellek düzenleyici, vb.) imza yine
## geçerli olur. Bu sınıf DEĞER ANOMALİLERİNİ yakalar: "bu oyuncu
## 1. dakikada 9 milyon altın mı kazanmış?"
##
## Bu OPSIYONEL bir katmandır — tek oyunculu oyunda hile oyuncunun
## kendi tercihidir. Ama lider tablosu / çok oyunculu için gerekir.
##
## Dedektör KESIN HÜKÜM VERMEZ — sadece "şüpheli" işaretler. Yanlış
## pozitif olabilir (gerçekten iyi oyuncu), o yüzden insan/sunucu
## kararı verir.
##
## Mock policy: anomali gerçek değer sınırlarından tespit edilir;
## kesin "hile" iddiası yok — sadece şüphe işareti.

## Şüphe seviyesi.
enum SuspicionLevel { CLEAN, LOW, MEDIUM, HIGH }

const SUSPICION_NAMES: Dictionary = {
	SuspicionLevel.CLEAN: "temiz",
	SuspicionLevel.LOW: "düşük",
	SuspicionLevel.MEDIUM: "orta",
	SuspicionLevel.HIGH: "yüksek",
}


## Bir alan için anomali kuralı.
class FieldRule extends RefCounted:
	var field_name: String = ""
	var min_value: float = 0.0
	var max_value: float = 0.0
	var has_max: bool = true

	func _init(p_field: String, p_min: float, p_max: float) -> void:
		field_name = p_field
		min_value = p_min
		max_value = p_max


## Bir anomali analizi sonucu.
class AnomalyReport extends RefCounted:
	var level: int = AISaveAnomalyDetector.SuspicionLevel.CLEAN
	var flagged_fields: Array = []     ## [{field, value, reason}]

	func is_suspicious() -> bool:
		return level != AISaveAnomalyDetector.SuspicionLevel.CLEAN

	func to_dict() -> Dictionary:
		return {
			"level": AISaveAnomalyDetector.SUSPICION_NAMES.get(level, "?"),
			"flagged_count": flagged_fields.size(),
			"is_suspicious": is_suspicious(),
		}


## Tanımlı alan kuralları — field_name -> FieldRule.
var _rules: Dictionary = {}


# ============================================================
# KURAL TANIMLAMA
# ============================================================

## Bir sayısal alan için makul aralık kuralı ekler.
## field: alan adı. min_val / max_val: makul aralık.
func add_rule(field: String, min_val: float, max_val: float) -> void:
	if field.is_empty():
		return
	_rules[field] = FieldRule.new(field, min_val, max_val)


## Tanımlı kural sayısı.
func rule_count() -> int:
	return _rules.size()


# ============================================================
# ANOMALİ TESPİTİ
# ============================================================

## Bir oyun durumunu anomali açısından denetler.
## game_data: kayıttaki oyun verisi (Dictionary).
## Dönen: AnomalyReport.
func detect(game_data: Dictionary) -> AnomalyReport:
	var report := AnomalyReport.new()

	for field in _rules:
		if not game_data.has(field):
			continue  # alan yoksa denetlenmez
		var value: Variant = game_data[field]
		# Sadece sayısal alanlar denetlenir
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue
		var num_value: float = float(value)
		var rule: FieldRule = _rules[field]

		var violation: String = ""
		if num_value < rule.min_value:
			violation = "değer minimumun altında (%s < %s)" % [
				num_value, rule.min_value
			]
		elif rule.has_max and num_value > rule.max_value:
			violation = "değer maksimumun üstünde (%s > %s)" % [
				num_value, rule.max_value
			]

		if not violation.is_empty():
			report.flagged_fields.append({
				"field": field,
				"value": num_value,
				"reason": violation,
			})

	# Şüphe seviyesi — kaç alan işaretlendi
	var flagged: int = report.flagged_fields.size()
	if flagged == 0:
		report.level = SuspicionLevel.CLEAN
	elif flagged == 1:
		report.level = SuspicionLevel.LOW
	elif flagged <= 3:
		report.level = SuspicionLevel.MEDIUM
	else:
		report.level = SuspicionLevel.HIGH
	return report


## İlerleme hızı anomalisi — iki kayıt arası değişim makul mu.
## before / after: iki kayıttaki bir alanın değeri.
## elapsed_seconds: iki kayıt arası geçen süre.
## max_per_second: saniyede makul artış.
## Dönen: true = şüpheli (çok hızlı artmış).
func is_progress_anomalous(
	before: float, after: float, elapsed_seconds: float,
	max_per_second: float
) -> bool:
	if elapsed_seconds <= 0.0:
		return false  # zaman bilgisi yoksa karar verilemez
	var gain: float = after - before
	if gain <= 0.0:
		return false  # azalma/sabit — anomali değil
	var rate: float = gain / elapsed_seconds
	return rate > max_per_second
