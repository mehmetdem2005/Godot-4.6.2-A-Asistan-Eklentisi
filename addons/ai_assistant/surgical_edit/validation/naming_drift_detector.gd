@tool
class_name AINamingDriftDetector
extends RefCounted

## NamingDriftDetector — isim kayması dedektörü (Surgical Edit / doğrulama).
##
## Madde 19'un asıl korkularından biri: LLM bir düzenleme yaparken
## değişken/fonksiyon adlarını "iyileştirir". "hp" görür, "health_points"
## yapar. Sonuç: başka dosyalardaki referanslar kırılır, kod çöker.
##
## Bu dedektör düzenleme öncesi ve sonrasındaki TANIMLANMIŞ SEMBOLLERİ
## (var, const, func, signal adları) karşılaştırır. İstenmeden değişmiş
## ya da kaybolmuş sembol = naming drift.
##
## Önemli ayrım: yeni sembol EKLENMESI normaldir (düzenleme yeni kod
## getirebilir). Mevcut bir sembolün KAYBOLMASI veya DEĞİŞMESİ
## şüphelidir — çünkü dışarıda referansı olabilir.
##
## Mock policy: drift gerçek sembol çıkarımından tespit edilir.


## İsim kayması analiz sonucu.
class NamingDriftReport extends RefCounted:
	var has_drift: bool = false
	var removed_symbols: PackedStringArray = PackedStringArray()  ## Kaybolan
	var added_symbols: PackedStringArray = PackedStringArray()     ## Eklenen
	var before_symbols: PackedStringArray = PackedStringArray()
	var after_symbols: PackedStringArray = PackedStringArray()

	## Kaybolan sembol var mı — asıl tehlike bu.
	func has_removed() -> bool:
		return removed_symbols.size() > 0

	func to_dict() -> Dictionary:
		return {
			"has_drift": has_drift,
			"removed": removed_symbols,
			"added": added_symbols,
			"before_count": before_symbols.size(),
			"after_count": after_symbols.size(),
		}


## Sembol bildirimi anahtar kelimeleri.
const DECLARATION_KEYWORDS: Array = ["var", "const", "func", "signal", "enum"]


# ============================================================
# TESPİT
# ============================================================

## Öncesi ve sonrası içeriği karşılaştırır, isim kaymasını bulur.
## before / after: düzenleme öncesi ve sonrası.
## Dönen: NamingDriftReport.
func detect(before: String, after: String) -> NamingDriftReport:
	var report := NamingDriftReport.new()

	report.before_symbols = _extract_symbols(before)
	report.after_symbols = _extract_symbols(after)

	# Sonrası sembollerini küme yap
	var after_set: Dictionary = {}
	for sym in report.after_symbols:
		after_set[sym] = true
	var before_set: Dictionary = {}
	for sym in report.before_symbols:
		before_set[sym] = true

	# Öncesinde olup sonrasında olmayan = kaybolan
	for sym in report.before_symbols:
		if not after_set.has(sym):
			report.removed_symbols.append(sym)
	# Sonrasında olup öncesinde olmayan = eklenen
	for sym in report.after_symbols:
		if not before_set.has(sym):
			report.added_symbols.append(sym)

	# Drift = kaybolan VEYA eklenen sembol var
	# (kaybolan tehlikeli, eklenen genelde normal ama yine raporlanır)
	report.has_drift = report.has_removed() or report.added_symbols.size() > 0
	return report


# ============================================================
# DAHİLİ — sembol çıkarımı
# ============================================================

## Bir GDScript içeriğinden tanımlanmış sembolleri çıkarır.
## var/const/func/signal/enum bildirimlerinin adlarını toplar.
func _extract_symbols(content: String) -> PackedStringArray:
	var symbols: PackedStringArray = PackedStringArray()
	for line in content.split("\n"):
		var stripped: String = line.strip_edges()
		# "static func" -> "func"
		if stripped.begins_with("static "):
			stripped = stripped.substr(7).strip_edges()
		# "@export var" gibi anotasyonları atla
		if stripped.begins_with("@"):
			var space: int = stripped.find(" ")
			if space > 0:
				stripped = stripped.substr(space + 1).strip_edges()
		for keyword in DECLARATION_KEYWORDS:
			if stripped.begins_with(keyword + " "):
				var name: String = _extract_name_after(
					stripped, keyword.length() + 1
				)
				if not name.is_empty():
					symbols.append(keyword + ":" + name)
				break
	return symbols


## Bir bildirim satırından sembol adını çıkarır.
## start_index: anahtar kelimeden sonraki konum.
func _extract_name_after(line: String, start_index: int) -> String:
	if start_index >= line.length():
		return ""
	var rest: String = line.substr(start_index).strip_edges()
	# Adın bittiği yer: boşluk, (, :, =
	var name: String = ""
	for ch in rest:
		if ch == " " or ch == "(" or ch == ":" or ch == "=":
			break
		name += ch
	return name


# ============================================================
# DEĞERLENDİRME
# ============================================================

## Bir isim kaymasının kabul edilebilir olup olmadığı.
## Sembol KAYBI kabul edilemez (dış referans kırılabilir).
## Sembol EKLENMESI kabul edilebilir (düzenleme yeni kod getirebilir).
func is_drift_acceptable(report: NamingDriftReport) -> bool:
	return not report.has_removed()


## Kayma için insan-okunur özet.
func summary(report: NamingDriftReport) -> String:
	if not report.has_drift:
		return "İsim kayması yok — semboller korundu"
	var parts: PackedStringArray = PackedStringArray()
	if report.has_removed():
		parts.append("%d sembol kayboldu (TEHLİKE)" % report.removed_symbols.size())
	if report.added_symbols.size() > 0:
		parts.append("%d yeni sembol" % report.added_symbols.size())
	return ", ".join(parts)
