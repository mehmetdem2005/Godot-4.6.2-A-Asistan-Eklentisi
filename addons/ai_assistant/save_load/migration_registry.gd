@tool
class_name AISaveMigrationRegistry
extends RefCounted

## MigrationRegistry — geçiş kayıt defteri (Madde 09 / versioning).
##
## Şema değiştikçe her sürüm geçişi (v1->v2, v2->v3...) için bir
## DÖNÜŞTÜRÜCÜ gerekir: eski biçimdeki kaydı yeni biçime çevirir.
## Bu sınıf o dönüştürücüleri kaydeder ve sırayla erişim sağlar.
##
## Geçişler ADIMLIDIR: v1'den v4'e gitmek için v1->v2->v3->v4
## zinciri çalışır. Her adım küçük ve test edilebilir; büyük tek
## sıçrama yerine kademeli dönüşüm.
##
## Bir geçiş adımı bir Callable'dır: eski Dictionary alır, yeni
## Dictionary döndürür.
##
## Mock policy: kayıt gerçek dönüştürücülerden; eksik adım açıkça
## raporlanır.

## Bir geçiş adımı.
class MigrationStep extends RefCounted:
	var from_version: int = 0
	var to_version: int = 0
	var transformer: Callable
	var description: String = ""

	func _init(
		p_from: int, p_to: int, p_transformer: Callable,
		p_desc: String
	) -> void:
		from_version = p_from
		to_version = p_to
		transformer = p_transformer
		description = p_desc


## Kayıtlı geçiş adımları — from_version -> MigrationStep.
var _steps: Dictionary = {}


# ============================================================
# KAYIT
# ============================================================

## Bir geçiş adımı kaydeder.
## from_version'dan bir sonraki sürüme (from+1) dönüşüm.
## transformer: Dictionary alıp Dictionary döndüren Callable.
## Dönen: true = kayıt başarılı.
func register(
	from_version: int, transformer: Callable, description: String = ""
) -> bool:
	if from_version < 1:
		push_warning("MigrationRegistry: geçersiz sürüm")
		return false
	if not transformer.is_valid():
		push_warning("MigrationRegistry: geçersiz dönüştürücü")
		return false
	var step := MigrationStep.new(
		from_version, from_version + 1, transformer, description
	)
	_steps[from_version] = step
	return true


## Bir sürümden bir sonrakine geçiş adımı kayıtlı mı?
func has_step(from_version: int) -> bool:
	return _steps.has(from_version)


## Bir geçiş adımını döndürür. Yoksa null.
func get_step(from_version: int) -> MigrationStep:
	return _steps.get(from_version, null)


# ============================================================
# ZİNCİR DOĞRULAMA
# ============================================================

## from_version'dan to_version'a kesintisiz geçiş zinciri var mı?
## Her ara adım kayıtlı olmalı.
func has_complete_chain(from_version: int, to_version: int) -> bool:
	if from_version >= to_version:
		return true  # geçiş gerekmez
	for v in range(from_version, to_version):
		if not has_step(v):
			return false
	return true


## from_version'dan to_version'a geçiş adımlarını sırayla döndürür.
## Dönen: MigrationStep dizisi. Zincir eksikse boş dizi.
func build_chain(from_version: int, to_version: int) -> Array:
	if not has_complete_chain(from_version, to_version):
		return []
	var chain: Array = []
	for v in range(from_version, to_version):
		chain.append(_steps[v])
	return chain


## Zincirde eksik olan ilk adımı bulur. Zincir tamsa -1.
func first_missing_step(from_version: int, to_version: int) -> int:
	for v in range(from_version, to_version):
		if not has_step(v):
			return v
	return -1


# ============================================================
# DURUM
# ============================================================

## Kayıtlı geçiş adımı sayısı.
func step_count() -> int:
	return _steps.size()


## Kayıtlı tüm kaynak sürümler.
func registered_versions() -> Array:
	var versions: Array = _steps.keys()
	versions.sort()
	return versions
