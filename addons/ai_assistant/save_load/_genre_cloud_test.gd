@tool
class_name AISaveGenreCloudTest
extends RefCounted

## Madde 09 — Genre Schemas + Cloud Stubs Self-Test
##
## Sıkı testler: genre_schemas (schema_base doğrulama, 9 tür şeması,
## schema_registry), cloud_stubs (cloud_sync_iface, platform stub'lar,
## conflict_resolver).


static func run_all() -> Array:
	var results: Array = []

	# Schema base + doğrulama
	results.append(_b("Genre: Schema", _test_schema_skeleton()))
	results.append(_b("Genre: Schema", _test_schema_validate_valid()))
	results.append(_b("Genre: Schema", _test_schema_missing_field()))
	results.append(_b("Genre: Schema", _test_schema_type_error()))
	results.append(_b("Genre: Schema", _test_schema_int_float_flex()))
	results.append(_b("Genre: Schema", _test_schema_fill_defaults()))

	# Somut şemalar
	results.append(_b("Genre: Schemas", _test_all_9_schemas()))
	results.append(_b("Genre: Schemas", _test_rpg_schema_fields()))

	# Schema registry
	results.append(_b("Genre: Registry", _test_registry_count()))
	results.append(_b("Genre: Registry", _test_registry_detect()))
	results.append(_b("Genre: Registry", _test_registry_validate()))

	# Cloud sync interface + stubs
	results.append(_b("Cloud: Stub", _test_cloud_stub_unavailable()))
	results.append(_b("Cloud: Stub", _test_cloud_stub_upload()))
	results.append(_b("Cloud: Stub", _test_cloud_three_providers()))

	# Conflict resolver
	results.append(_b("Cloud: Conflict", _test_conflict_identical()))
	results.append(_b("Cloud: Conflict", _test_conflict_local_newer()))
	results.append(_b("Cloud: Conflict", _test_conflict_cloud_newer()))
	results.append(_b("Cloud: Conflict", _test_conflict_ask_user()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# SCHEMA BASE
# ============================================================

static func _test_schema_skeleton() -> Dictionary:
	var name := "Schema iskelet üretimi"
	var schema := AISaveRPGTopdownSchema.new()
	var skeleton: Dictionary = schema.make_skeleton()
	if str(skeleton.get("__genre__", "")) != "rpg_topdown":
		return _fail(name, "iskelet __genre__ alanı içermeli")
	if not skeleton.has("level"):
		return _fail(name, "iskelet tanımlı alanları içermeli")
	return _ok(name)


static func _test_schema_validate_valid() -> Dictionary:
	var name := "Schema geçerli kayıt"
	var schema := AISavePuzzleSchema.new()
	var skeleton: Dictionary = schema.make_skeleton()
	var result: Dictionary = schema.validate(skeleton)
	if not bool(result["valid"]):
		return _fail(name, "kendi iskeletini doğrulamalı")
	return _ok(name)


static func _test_schema_missing_field() -> Dictionary:
	var name := "Schema eksik zorunlu alan"
	var schema := AISaveFPS3DSchema.new()
	# Boş kayıt — zorunlu alanlar eksik
	var result: Dictionary = schema.validate({})
	var missing: PackedStringArray = result["missing"]
	if missing.is_empty():
		return _fail(name, "boş kayıtta eksik alanlar tespit edilmeli")
	if bool(result["valid"]):
		return _fail(name, "eksik alanlı kayıt geçersiz olmalı")
	return _ok(name)


static func _test_schema_type_error() -> Dictionary:
	var name := "Schema tip hatası"
	var schema := AISavePlatformer2DSchema.new()
	var skeleton: Dictionary = schema.make_skeleton()
	# lives int olmalı — string ver
	skeleton["lives"] = "üç"
	var result: Dictionary = schema.validate(skeleton)
	var errors: PackedStringArray = result["errors"]
	if errors.is_empty():
		return _fail(name, "tip hatası yakalanmalı")
	return _ok(name)


static func _test_schema_int_float_flex() -> Dictionary:
	var name := "Schema int/float esnekliği"
	var schema := AISaveRacing3DSchema.new()
	var skeleton: Dictionary = schema.make_skeleton()
	# credits int alanı — float değer JSON esnekliğiyle kabul edilmeli
	skeleton["credits"] = 100.0
	var result: Dictionary = schema.validate(skeleton)
	if not bool(result["valid"]):
		return _fail(name, "int alana float değer esnek kabul edilmeli")
	return _ok(name)


static func _test_schema_fill_defaults() -> Dictionary:
	var name := "Schema eksik tamamlama"
	var schema := AISaveSurvival3DSchema.new()
	# Kısmi kayıt
	var partial: Dictionary = {"health": 50.0}
	var filled: Dictionary = schema.fill_defaults(partial)
	# Verilen değer korunmalı
	if not is_equal_approx(float(filled["health"]), 50.0):
		return _fail(name, "verilen değer korunmalı")
	# Eksik alan varsayılanla tamamlanmalı
	if not filled.has("hunger"):
		return _fail(name, "eksik alan varsayılanla tamamlanmalı")
	return _ok(name)


# ============================================================
# SOMUT ŞEMALAR
# ============================================================

static func _test_all_9_schemas() -> Dictionary:
	var name := "9 tür şeması tutarlılığı"
	var schemas: Array = [
		AISaveFPS3DSchema.new(), AISavePlatformer2DSchema.new(),
		AISaveRPGTopdownSchema.new(), AISavePuzzleSchema.new(),
		AISaveRacing3DSchema.new(), AISaveSurvival3DSchema.new(),
		AISaveVisualNovelSchema.new(),
		AISaveStrategyIsometricSchema.new(), AISaveHorror3DSchema.new(),
	]
	for schema_obj in schemas:
		var schema: AISaveGenreSchemaBase = schema_obj
		# Her şema en az 1 alan tanımlamalı
		if schema.field_count() == 0:
			return _fail(name, "%s alan tanımlamamış" % schema.genre_name)
		# Her şema kendi iskeletini doğrulamalı
		var skeleton: Dictionary = schema.make_skeleton()
		if not bool(schema.validate(skeleton)["valid"]):
			return _fail(name, "%s iskeleti doğrulanamadı" % \
				schema.genre_name)
	return _ok(name)


static func _test_rpg_schema_fields() -> Dictionary:
	var name := "RPG şeması zengin alanlar"
	var schema := AISaveRPGTopdownSchema.new()
	# RPG en zengin şema — kritik alanlar olmalı
	for required_field in ["level", "gold", "inventory", "active_quests"]:
		if not schema.has_field(required_field):
			return _fail(name, "RPG şemasında '%s' olmalı" % required_field)
	return _ok(name)


# ============================================================
# SCHEMA REGISTRY
# ============================================================

static func _test_registry_count() -> Dictionary:
	var name := "Registry 9 şema"
	var registry := AISaveSchemaRegistry.new()
	if registry.schema_count() != 9:
		return _fail(name, "9 yerleşik şema kayıtlı olmalı")
	return _ok(name)


static func _test_registry_detect() -> Dictionary:
	var name := "Registry tür tespiti"
	var registry := AISaveSchemaRegistry.new()
	# Bilinen tür
	var horror: Dictionary = {"__genre__": "horror_3d"}
	if registry.detect_genre(horror) != "horror_3d":
		return _fail(name, "bilinen tür tespit edilmeli")
	# Bilinmeyen tür
	if registry.detect_genre({"__genre__": "olmayan_tur"}) != "":
		return _fail(name, "bilinmeyen tür boş dönmeli")
	return _ok(name)


static func _test_registry_validate() -> Dictionary:
	var name := "Registry kayıt doğrulama"
	var registry := AISaveSchemaRegistry.new()
	# Geçerli RPG iskeleti
	var rpg_skeleton: Dictionary = registry.make_skeleton("rpg_topdown")
	var result: Dictionary = registry.validate_save(rpg_skeleton)
	if not bool(result["ok"]):
		return _fail(name, "geçerli RPG kaydı doğrulanmalı")
	# Türsüz kayıt
	var no_genre: Dictionary = registry.validate_save({"data": "x"})
	if bool(no_genre["ok"]):
		return _fail(name, "türsüz kayıt doğrulanamamalı")
	return _ok(name)


# ============================================================
# CLOUD SYNC STUBS
# ============================================================

static func _test_cloud_stub_unavailable() -> Dictionary:
	var name := "Cloud stub kullanılamaz"
	var stub := AISaveGooglePlayCloudStub.new()
	# Phase 1 — stub kullanılamaz olmalı
	if stub.is_available():
		return _fail(name, "Phase 1 stub kullanılamaz olmalı")
	# Bağlanma denemesi başarısız
	if stub.attempt_connect():
		return _fail(name, "Phase 1 bağlanma başarısız olmalı")
	return _ok(name)


static func _test_cloud_stub_upload() -> Dictionary:
	var name := "Cloud stub upload NOT_AVAILABLE"
	var stub := AISaveSteamCloudStub.new()
	var result: AISaveCloudSyncInterface.SyncResult = stub.upload(
		{"data": "x"}, "slot_1"
	)
	# Sahte başarı yok — NOT_AVAILABLE dönmeli
	if result.is_success():
		return _fail(name, "stub upload sahte başarı vermemeli")
	if result.status != AISaveCloudSyncInterface.SyncStatus.NOT_AVAILABLE:
		return _fail(name, "stub upload NOT_AVAILABLE dönmeli")
	return _ok(name)


static func _test_cloud_three_providers() -> Dictionary:
	var name := "Cloud 3 sağlayıcı tanımlı"
	var google := AISaveGooglePlayCloudStub.new()
	var steam := AISaveSteamCloudStub.new()
	var icloud := AISaveICloudStub.new()
	# Her sağlayıcının benzersiz adı olmalı
	var names: Array = [
		google.provider_name(), steam.provider_name(),
		icloud.provider_name(),
	]
	if names[0] == names[1] or names[1] == names[2]:
		return _fail(name, "sağlayıcı adları benzersiz olmalı")
	return _ok(name)


# ============================================================
# CONFLICT RESOLVER
# ============================================================

static func _test_conflict_identical() -> Dictionary:
	var name := "Conflict aynı kayıt"
	var resolver := AISaveConflictResolver.new()
	var meta: Dictionary = {"timestamp": 1000, "progress": 0.5}
	var result: AISaveConflictResolver.ResolutionResult = resolver.resolve(
		meta, meta.duplicate()
	)
	if result.resolution != AISaveConflictResolver.Resolution.IDENTICAL:
		return _fail(name, "aynı kayıt IDENTICAL olmalı")
	return _ok(name)


static func _test_conflict_local_newer() -> Dictionary:
	var name := "Conflict yerel daha yeni"
	var resolver := AISaveConflictResolver.new()
	var local: Dictionary = {"timestamp": 5000, "progress": 0.5}
	var cloud: Dictionary = {"timestamp": 1000, "progress": 0.5}
	var result: AISaveConflictResolver.ResolutionResult = resolver.resolve(
		local, cloud
	)
	if result.resolution != AISaveConflictResolver.Resolution.USE_LOCAL:
		return _fail(name, "yerel belirgin yeniyse USE_LOCAL olmalı")
	return _ok(name)


static func _test_conflict_cloud_newer() -> Dictionary:
	var name := "Conflict bulut daha yeni"
	var resolver := AISaveConflictResolver.new()
	var local: Dictionary = {"timestamp": 1000, "progress": 0.5}
	var cloud: Dictionary = {"timestamp": 5000, "progress": 0.5}
	var result: AISaveConflictResolver.ResolutionResult = resolver.resolve(
		local, cloud
	)
	if result.resolution != AISaveConflictResolver.Resolution.USE_CLOUD:
		return _fail(name, "bulut belirgin yeniyse USE_CLOUD olmalı")
	return _ok(name)


static func _test_conflict_ask_user() -> Dictionary:
	var name := "Conflict belirsiz -> kullanıcıya sor"
	var resolver := AISaveConflictResolver.new()
	# Zaman çok yakın, ilerleme de yakın — net karar yok
	var local: Dictionary = {"timestamp": 1010, "progress": 0.51}
	var cloud: Dictionary = {"timestamp": 1000, "progress": 0.50}
	var result: AISaveConflictResolver.ResolutionResult = resolver.resolve(
		local, cloud
	)
	if not result.needs_user_decision():
		return _fail(name, "belirsiz çakışma kullanıcıya sorulmalı")
	return _ok(name)
