@tool
class_name AIPathGuard
extends RefCounted

## PathGuard — sandbox yol güvenliği (Layer 4).
##
## Executor'ın yazdığı/sildiği HER yol bu sınıftan geçer. Tek bir açık
## tüm sandbox'ı çökertir — bu yüzden kurallar agresif ve "deny by default".
##
## Güvenlik kuralları (hepsi zorunlu):
##   1. Sadece res:// (proje) ve user:// (AI veri) altına yazılır
##   2. Path traversal (..) yasak — res://../../etc gibi kaçış engellenir
##   3. addons/ai_assistant/ KENDİNİ değiştiremez (kendi kodunu bozmasın)
##   4. .godot/ ve .import/ dokunulmaz (motor iç dosyaları)
##   5. project.godot yalnız okuma — yanlışlıkla bozulması felakettir
##   6. Mutlak sistem yolları (/etc, C:\) tamamen reddedilir
##
## Mock policy: şüpheli yol GÜVENLİ kabul edilmez — açıkça reddedilir.

## Yazmaya izin verilen kök önekler.
const ALLOWED_WRITE_ROOTS: Array = ["res://", "user://"]

## Hiçbir koşulda yazılamayacak yol parçaları (alt-dize eşleşmesi).
const FORBIDDEN_WRITE_FRAGMENTS: Array = [
	".godot/",          # motor cache
	".import/",         # import cache
	"addons/ai_assistant/",  # sistemin kendi kodu — kendini bozamaz
]

## Yalnızca-okuma yolları — yazma/silme reddedilir.
const READ_ONLY_PATHS: Array = [
	"res://project.godot",
	"res://export_presets.cfg",
]

## Path traversal işareti.
const TRAVERSAL_TOKEN: String = ".."

## AI'ın ÜRETTİĞİ kodun yazılabileceği TEK kök (AAA izole yerleşim).
## Üretilen dosyalar yalnız buraya — elle yazılan kod / addons /
## project.godot bu daha-dar kapıyla ek olarak korunur.
const GENERATED_ROOT: String = "res://game/"


## Bir yola YAZMA (oluştur/değiştir/sil/taşı) izni var mı kontrol eder.
## Dönen: {allowed: bool, reason: String}
## reason, reddedilmişse insan-okunur gerekçe içerir.
static func check_write(path: String) -> Dictionary:
	# Boş yol
	if path.strip_edges().is_empty():
		return _deny("Yol boş")

	var p: String = path.strip_edges()

	# Path traversal — herhangi bir yerde ".." varsa reddet
	if p.contains(TRAVERSAL_TOKEN):
		return _deny("Path traversal yasak (.. içeriyor): %s" % p)

	# İzinli kök kontrolü — res:// veya user:// ile başlamalı
	var has_allowed_root: bool = false
	for root in ALLOWED_WRITE_ROOTS:
		if p.begins_with(root):
			has_allowed_root = true
			break
	if not has_allowed_root:
		return _deny("Yazma sadece res:// veya user:// altında: %s" % p)

	# Mutlak sistem yolu izi — res://'den sonra / veya sürücü harfi
	# (res:// soyulduktan sonra kalan kısımda kök / olmamalı)
	var rel: String = _strip_root(p)
	if rel.begins_with("/") or _looks_like_drive(rel):
		return _deny("Mutlak sistem yolu reddedildi: %s" % p)

	# Yasaklı parça kontrolü
	for fragment in FORBIDDEN_WRITE_FRAGMENTS:
		if p.contains(fragment):
			return _deny("Korunan konum (yazılamaz): %s" % fragment)

	# Yalnızca-okuma yolu
	for ro in READ_ONLY_PATHS:
		if p == ro:
			return _deny("Yalnızca-okuma dosyası: %s" % ro)

	return {"allowed": true, "reason": ""}


## AI'ın ÜRETTİĞİ kod için DAHA DAR yazma kapısı: önce tüm genel
## check_write kuralları (traversal, addons, project.godot, sistem
## yolu), SONRA "yalnız res://game/ altı" kısıtı. Orkestratör üretilen
## dosyayı diske vermeden bunu uygular — model uydurma yol üretse bile
## elle yazılan kodu / motoru bozamaz.
## Dönen: {allowed: bool, reason: String}
static func check_generated_write(path: String) -> Dictionary:
	var base: Dictionary = check_write(path)
	if not bool(base["allowed"]):
		return base
	var p: String = path.strip_edges()
	if not p.begins_with(GENERATED_ROOT):
		return _deny(
			"Üretilen kod yalnız %s altına yazılır: %s" % [
				GENERATED_ROOT, p
			]
		)
	return {"allowed": true, "reason": ""}


## Üretilen kod için kısa kontrol (bool).
static func can_generate_write(path: String) -> bool:
	return check_generated_write(path)["allowed"]


## Bir yoldan OKUMA izni var mı kontrol eder.
## Okuma yazmadan gevşek — ama yine traversal ve sistem yolu engellenir.
## Dönen: {allowed: bool, reason: String}
static func check_read(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return _deny("Yol boş")

	var p: String = path.strip_edges()

	if p.contains(TRAVERSAL_TOKEN):
		return _deny("Path traversal yasak (.. içeriyor): %s" % p)

	# Okuma için res:// veya user:// şart (proje dışı okuma yok)
	var has_allowed_root: bool = false
	for root in ALLOWED_WRITE_ROOTS:
		if p.begins_with(root):
			has_allowed_root = true
			break
	if not has_allowed_root:
		return _deny("Okuma sadece res:// veya user:// altında: %s" % p)

	var rel: String = _strip_root(p)
	if rel.begins_with("/") or _looks_like_drive(rel):
		return _deny("Mutlak sistem yolu reddedildi: %s" % p)

	return {"allowed": true, "reason": ""}


## Bir yolun yazılabilir olup olmadığını kısa kontrol (bool).
static func can_write(path: String) -> bool:
	return check_write(path)["allowed"]


## Bir yolun okunabilir olup olmadığını kısa kontrol (bool).
static func can_read(path: String) -> bool:
	return check_read(path)["allowed"]


## Bir yolu güvenli biçime normalize eder — fazla slash temizler.
## NOT: normalize traversal'ı ÇÖZMEZ; traversal zaten reddedilir.
static func normalize_path(path: String) -> String:
	var p: String = path.strip_edges()
	# Çoklu slash'ı tekile indir (res:////a -> res://a), ama res:// korunur
	while p.contains("///"):
		p = p.replace("///", "//")
	return p


# ============================================================
# DAHİLİ YARDIMCILAR
# ============================================================

## Yoldan res:// / user:// kökünü soyar — kalan göreli kısmı döndürür.
static func _strip_root(path: String) -> String:
	for root in ALLOWED_WRITE_ROOTS:
		if path.begins_with(root):
			return path.substr(root.length())
	return path


## Bir göreli yolun Windows sürücü harfi gibi görünüp görünmediği (C:, D:).
static func _looks_like_drive(rel: String) -> bool:
	if rel.length() < 2:
		return false
	# X: deseni — ilk karakter harf, ikinci ':'
	var first: String = rel.substr(0, 1)
	var second: String = rel.substr(1, 1)
	var is_letter: bool = first.to_lower() != first.to_upper()
	return is_letter and second == ":"


## Red sonucu üretir.
static func _deny(reason: String) -> Dictionary:
	return {"allowed": false, "reason": reason}
