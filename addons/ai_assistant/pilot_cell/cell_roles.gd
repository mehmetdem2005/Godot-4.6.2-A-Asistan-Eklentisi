@tool
class_name AICellRoles
extends RefCounted

## CellRoles — 14 ajan rolü tanımı (Layer 9 / Pilot Cell).
##
## Pilot Cell, bir "yazılım şirketi" desenidir: 14 uzman rol, her biri
## bir aşamadan sorumlu. Bir oyun-geliştirme isteği bu rollerin
## arasından bir hat (pipeline) boyunca akar:
##
##   PM -> Architect -> DeliveryManager -> Engineers (4) ->
##   QA -> Debug -> Test -> Performance -> Reviewer -> Commit -> TechWriter
##
## Bu sınıf rollerin KİMLİĞİNİ tutar — kimlik, sorumluluk, pipeline
## sırası, hangi katmanları kullandığı. Rollerin asıl ZEKÂSI (LLM
## promptları) sonraki Pilot Cell oturumlarında her role tek tek
## yazılacak; bu sürüm iskeleti + orkestrasyonu kurar.
##
## Mock policy: roller gerçek pipeline'da çalışır — sahte ajan yok.

## 14 cell rolü.
enum Role {
	PRODUCT_MANAGER,    ## İsteği analiz eder, hedef belirler
	ARCHITECT,          ## Teknik tasarım, sistem mimarisi
	DELIVERY_MANAGER,   ## İşi parçalara böler, dağıtır
	CODE_ENGINEER,      ## GDScript kodu üretir
	SCENE_ENGINEER,     ## Godot sahnesi (.tscn) kurar
	SHADER_ENGINEER,    ## Shader / görsel efekt
	ASSET_ENGINEER,     ## Asset üretimi / entegrasyonu
	AUDIO_ENGINEER,     ## Ses sistemi
	QA_ENGINEER,        ## Kalite kontrol, kabul kriteri
	DEBUG_ENGINEER,     ## Hata teşhis ve düzeltme
	TEST_ENGINEER,      ## Test yazımı ve koşturma
	PERFORMANCE_ENGINEER,## Mobil performans optimizasyonu
	REVIEWER,           ## Kod incelemesi, son onay
	TECH_WRITER,        ## Dokümantasyon
}

const ROLE_NAMES: Dictionary = {
	Role.PRODUCT_MANAGER: "ProductManager",
	Role.ARCHITECT: "Architect",
	Role.DELIVERY_MANAGER: "DeliveryManager",
	Role.CODE_ENGINEER: "CodeEngineer",
	Role.SCENE_ENGINEER: "SceneEngineer",
	Role.SHADER_ENGINEER: "ShaderEngineer",
	Role.ASSET_ENGINEER: "AssetEngineer",
	Role.AUDIO_ENGINEER: "AudioEngineer",
	Role.QA_ENGINEER: "QAEngineer",
	Role.DEBUG_ENGINEER: "DebugEngineer",
	Role.TEST_ENGINEER: "TestEngineer",
	Role.PERFORMANCE_ENGINEER: "PerformanceEngineer",
	Role.REVIEWER: "Reviewer",
	Role.TECH_WRITER: "TechWriter",
}

## Her rolün insan-okunur sorumluluğu.
const ROLE_DUTIES: Dictionary = {
	Role.PRODUCT_MANAGER: "İsteği analiz eder, net hedef belirler",
	Role.ARCHITECT: "Teknik tasarımı ve sistem mimarisini kurar",
	Role.DELIVERY_MANAGER: "İşi task'lara böler ve mühendislere dağıtır",
	Role.CODE_ENGINEER: "GDScript kodu üretir",
	Role.SCENE_ENGINEER: "Godot sahnelerini (.tscn) kurar",
	Role.SHADER_ENGINEER: "Shader ve görsel efektleri yazar",
	Role.ASSET_ENGINEER: "Asset üretir ve entegre eder",
	Role.AUDIO_ENGINEER: "Ses sistemini kurar",
	Role.QA_ENGINEER: "Kalite kontrol yapar, kabul kriterlerini doğrular",
	Role.DEBUG_ENGINEER: "Hataları teşhis eder ve düzeltir",
	Role.TEST_ENGINEER: "Test yazar ve koşturur",
	Role.PERFORMANCE_ENGINEER: "Mobil performansı optimize eder",
	Role.REVIEWER: "Kodu inceler, son onayı verir",
	Role.TECH_WRITER: "Dokümantasyon yazar",
}

## Pipeline akış sırası — bir isteğin rollerden geçiş hattı.
## Engineers paralel çalışabilir; bu liste varsayılan sıralı akış.
const PIPELINE_ORDER: Array = [
	Role.PRODUCT_MANAGER,
	Role.ARCHITECT,
	Role.DELIVERY_MANAGER,
	Role.CODE_ENGINEER,
	Role.SCENE_ENGINEER,
	Role.SHADER_ENGINEER,
	Role.ASSET_ENGINEER,
	Role.AUDIO_ENGINEER,
	Role.QA_ENGINEER,
	Role.DEBUG_ENGINEER,
	Role.TEST_ENGINEER,
	Role.PERFORMANCE_ENGINEER,
	Role.REVIEWER,
	Role.TECH_WRITER,
]

## Kod üreten roller — Surgical Edit middleware bunlara uygulanır.
const CODE_GENERATING_ROLES: Array = [
	Role.CODE_ENGINEER,
	Role.SCENE_ENGINEER,
	Role.SHADER_ENGINEER,
	Role.ASSET_ENGINEER,
]

## "Engineer" grubu — paralel (concurrent) çalışabilen roller.
const ENGINEER_ROLES: Array = [
	Role.CODE_ENGINEER,
	Role.SCENE_ENGINEER,
	Role.SHADER_ENGINEER,
	Role.ASSET_ENGINEER,
	Role.AUDIO_ENGINEER,
]


# ============================================================
# ROL SORGULARI
# ============================================================

## Bir rolün adı.
static func role_name(role: int) -> String:
	return ROLE_NAMES.get(role, "?")


## Bir rolün sorumluluğu.
static func role_duty(role: int) -> String:
	return ROLE_DUTIES.get(role, "?")


## Bir rol enum değeri geçerli mi?
static func is_valid_role(role: int) -> bool:
	return ROLE_NAMES.has(role)


## Bir rol kod üretir mi (Surgical Edit gerektirir mi)?
static func is_code_generating(role: int) -> bool:
	return CODE_GENERATING_ROLES.has(role)


## Bir rol "Engineer" grubunda mı (paralel çalışabilir)?
static func is_engineer(role: int) -> bool:
	return ENGINEER_ROLES.has(role)


## Pipeline'da bir rolün indeksini döndürür. Yoksa -1.
static func pipeline_index(role: int) -> int:
	return PIPELINE_ORDER.find(role)


## Pipeline'da bir sonraki rolü döndürür. Son rolse -1.
static func next_in_pipeline(role: int) -> int:
	var idx: int = pipeline_index(role)
	if idx < 0 or idx + 1 >= PIPELINE_ORDER.size():
		return -1
	return PIPELINE_ORDER[idx + 1]


## Pipeline'da bir önceki rolü döndürür. İlk rolse -1.
## Reflection/feedback için — bir rol bir öncekine geri bildirim verir.
static func prev_in_pipeline(role: int) -> int:
	var idx: int = pipeline_index(role)
	if idx <= 0:
		return -1
	return PIPELINE_ORDER[idx - 1]


## Rol adından enum değeri bulur. Bulunamazsa -1.
static func role_from_name(name: String) -> int:
	for role in ROLE_NAMES:
		if ROLE_NAMES[role] == name:
			return role
	return -1


## Toplam rol sayısı.
static func role_count() -> int:
	return ROLE_NAMES.size()
