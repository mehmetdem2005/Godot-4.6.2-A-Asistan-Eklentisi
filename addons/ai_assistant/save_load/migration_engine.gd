@tool
class_name AISaveMigrationEngine
extends RefCounted

## MigrationEngine — geçiş motoru (Madde 09 / Save/Load / versioning).
##
## Eski bir kaydı güncel şemaya taşıyan motor. Registry'deki geçiş
## zincirini sırayla uygular: v1 kaydı -> v1->v2 dönüşümü -> v2->v3
## -> ... -> güncel.
##
## Her adım izlenir: hangi sürümden hangisine geçildi, dönüşüm
## başarılı oldu mu. Bir adım çökerse motor DURUR — yarım dönüşmüş
## veri tehlikelidir, tüm geçiş başarısız sayılır (atomik).
##
## "Mock yasak": dönüşüm başarısızsa "tamamlandı" demez. Kısmi
## sonuç dönmez — ya tam geçiş ya açık başarısızlık.
##
## Mock policy: sonuç gerçek dönüşüm zincirinden.

## Bir geçiş sonucu.
class MigrationResult extends RefCounted:
	var success: bool = false
	var from_version: int = 0
	var final_version: int = 0       ## Ulaşılan sürüm
	var steps_applied: int = 0
	var migrated_data: Dictionary = {}
	var reason: String = ""

	func to_dict() -> Dictionary:
		return {
			"success": success,
			"from_version": from_version,
			"final_version": final_version,
			"steps_applied": steps_applied,
		}


## Geçiş kayıt defteri.
var _registry: AISaveMigrationRegistry


func _init(registry: AISaveMigrationRegistry = null) -> void:
	if registry != null:
		_registry = registry
	else:
		_registry = AISaveMigrationRegistry.new()


## Kayıt defterine erişim.
func registry() -> AISaveMigrationRegistry:
	return _registry


# ============================================================
# GEÇİŞ ÇALIŞTIRMA
# ============================================================

## Bir kaydı kaynak sürümden hedef sürüme taşır.
## data: kayıt verisi (Dictionary).
## from_version: kaydın mevcut şema sürümü.
## to_version: ulaşılmak istenen sürüm.
## Dönen: MigrationResult.
func migrate(
	data: Dictionary, from_version: int, to_version: int
) -> MigrationResult:
	var result := MigrationResult.new()
	result.from_version = from_version
	result.final_version = from_version

	# Geçiş gerekmiyor — zaten hedefte
	if from_version >= to_version:
		result.success = true
		result.migrated_data = data.duplicate(true)
		result.reason = "Geçiş gerekmiyor — kayıt zaten güncel"
		return result

	# Zincir eksik mi
	if not _registry.has_complete_chain(from_version, to_version):
		var missing: int = _registry.first_missing_step(
			from_version, to_version
		)
		result.success = false
		result.reason = "Geçiş zinciri eksik — v%d adımı yok" % missing
		return result

	# Zinciri sırayla uygula
	var working: Dictionary = data.duplicate(true)
	var chain: Array = _registry.build_chain(from_version, to_version)

	for step_obj in chain:
		var step: AISaveMigrationRegistry.MigrationStep = step_obj
		# Dönüşümü çalıştır
		if not step.transformer.is_valid():
			result.success = false
			result.reason = "v%d dönüştürücüsü geçersiz" % \
				step.from_version
			return result

		var transformed: Variant = step.transformer.call(working)
		# Dönüşüm Dictionary döndürmeli — değilse başarısız
		if typeof(transformed) != TYPE_DICTIONARY:
			result.success = false
			result.reason = "v%d dönüşümü geçersiz sonuç verdi" % \
				step.from_version
			return result

		working = transformed
		result.steps_applied += 1
		result.final_version = step.to_version

	# Tüm zincir başarıyla tamamlandı
	result.success = true
	result.migrated_data = working
	result.reason = "Geçiş tamam: v%d -> v%d (%d adım)" % [
		from_version, to_version, result.steps_applied
	]
	return result


# ============================================================
# SORGULAMA
# ============================================================

## Bir geçiş çalıştırılabilir mi (zincir tam mı)?
func can_migrate(from_version: int, to_version: int) -> bool:
	return _registry.has_complete_chain(from_version, to_version)
