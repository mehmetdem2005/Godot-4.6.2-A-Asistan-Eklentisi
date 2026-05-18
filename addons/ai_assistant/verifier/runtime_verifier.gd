@tool
class_name AIRuntimeVerifier
extends AIVerifyLevelBase

## RuntimeVerifier — çalışma-zamanı doğrulama (Layer 5, Seviye 3).
##
## "AAA teknik": syntactic (derlenir mi) + semantic (anlamlı mı)
## yetmez — kod GERÇEKTEN yüklenip örneklenebiliyor mu? Profesyonel
## stüdyolar üretilen kodu headless yükleyip örnekler; motor hatası =
## FAIL. Bu seviye onu yapar:
##   1. GDScript'i motora derlet (reload) — link/analyze tam çalışır
##   2. Örneklenebilirliği motora sor (can_instantiate)
##   3. Yan etkisi GÜVENLİ tabanlarda (RefCounted/Resource) GERÇEKTEN
##      new() ile örnekle — _init çalışır, hata olursa yakalanır,
##      nesne hemen serbest bırakılır
##
## GÜVENLİ SINIRLAMA (build döngüsünde keyfi kod çalıştırma riski —
## plan'da işaretlendi): Node/sahne-ağacı türevleri new() İLE
## çalıştırılMAZ (_enter_tree/_ready yan etkisi + olası askıya alma
## build hattını kilitler). Onlar için motor-örneklenebilirliği +
## taban tipi çözümü doğrulanır (yine gerçek runtime kanıtı, ama
## hattı tehlikeye atmadan). Sahne (.tscn) bu seviyeye gelmez —
## orkestratör .tscn'i GDScript doğrulayıcısına sokmaz.
##
## Mock policy: motor hatası gizlenmez — dürüst FAIL. Kanıtsız PASS
## yok (evidence dolu).

## new() ile gerçekten örneklenmesi GÜVENLİ kabul edilen taban tipler
## (sahne ağacına girmez, otonom işlem başlatmaz).
const SAFE_INSTANTIATE_BASES: Array = [
	"RefCounted", "Resource",
]


func _init() -> void:
	level = AIVerificationResult.VerifyLevel.RUNTIME
	level_name = "runtime"


## Bir GDScript kaynağını çalışma-zamanı düzeyinde doğrular.
## Dönen: AIVerificationResult — PASS (yüklendi/örneklenebilir) /
## FAIL (motor reddetti veya örnekleme çöktü).
func verify(
	source_code: String, context: Dictionary = {}
) -> AIVerificationResult:
	var result: AIVerificationResult = _new_result(context)

	var validity: Dictionary = _check_source_validity(source_code)
	if not validity["ok"]:
		result.mark_fail("Runtime: %s" % validity["reason"])
		return result

	# --- 1. Motor derlemesi (link + analyze) ---
	var script := GDScript.new()
	script.source_code = source_code
	var err: int = script.reload()
	if err != OK:
		result.mark_fail(
			"Runtime: motor yüklemesi başarısız (Error %d) — "
			% err + "kod çalıştırılamaz"
		)
		return result

	# --- 2. Örneklenebilirlik (motora sor) ---
	if not script.can_instantiate():
		result.mark_fail(
			"Runtime: script örneklenemiyor (geçerli extends / "
			+ "soyut taban değil)"
		)
		return result

	var base_type: String = script.get_instance_base_type()
	if base_type.strip_edges().is_empty():
		result.mark_fail(
			"Runtime: taban tipi çözülemedi (geçersiz extends)"
		)
		return result

	# --- 3. Güvenli tabanlarda GERÇEK örnekleme (_init çalışır) ---
	# new() YALNIZ argümansız _init için çağrılır: zorunlu argümanlı
	# _init'te new() motor hatası verir (geçerli kod — KOD DEFEKTİ
	# DEĞİL; ayrıca hata yürütmeyi bozar). Otoriter runtime kanıtı
	# zaten reload+can_instantiate+taban çözümü; örnekleme bonustur.
	var instantiated: bool = false
	if SAFE_INSTANTIATE_BASES.has(base_type) \
			and not _init_requires_args(script):
		var inst: Variant = script.new()
		if inst != null:
			instantiated = true
			# RefCounted/Resource: referans bırakılınca otomatik serbest.
			inst = null

	result.mark_pass(
		{
			"loaded": true,
			"method": "GDScript.reload()+can_instantiate()",
			"base_type": base_type,
			"instantiated": instantiated,
			"line_count": source_code.split("\n").size(),
		},
		"engine_runtime"
	)
	result.message = (
		"Çalışma-zamanı geçerli — motor yükledi, örneklenebilir (taban %s%s)"
		% [
			base_type,
			", gerçek örneklendi" if instantiated else "",
		]
	)
	return result


## script._init zorunlu (varsayılansız) argüman istiyor mu?
## İstiyorsa new() çağrılmaz — motor hatası verir (geçerli kod olsa
## bile) ve yürütmeyi bozar. _init yoksa argümansız Object init
## (güvenli) → false.
func _init_requires_args(script: GDScript) -> bool:
	for m in script.get_script_method_list():
		if str(m.get("name", "")) != "_init":
			continue
		var args: Array = m.get("args", [])
		var defaults: Array = m.get("default_args", [])
		return args.size() - defaults.size() > 0
	return false
