@tool
class_name AIReleaseReadinessAudit
extends RefCounted

## Faz 8 — release candidate doğrulayıcısı.
##
## Manifest yapısını, faz zincirini, plugin metadata'sını, otomatik ve
## manuel kapıların dürüstlüğünü denetler. Bu sınıf hiçbir GitHub işlemi
## yapmaz ve dosya yazmaz; CI veya editör saf sonuç sözlüğünü tüketir.

const REQUIRED_SCHEMA_VERSION: int = 1
const REQUIRED_PHASE_COUNT: int = 8
const REQUIRED_GODOT_VERSION: String = "4.6.3"
const REQUIRED_STRATEGY: String = "single_consolidation_pr"
const REQUIRED_MANUAL_GATE_IDS: Array = [
	"editor_undo_redo",
	"deepseek_v4_live",
	"android_editor",
]
const VALID_MANUAL_STATUSES: Array = ["pending", "passed", "failed"]


static func audit(
	manifest: Dictionary,
	plugin_text: String,
	phase1_document_present: bool,
	document_texts: Array = []
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var checks: Dictionary = {}

	_validate_schema(manifest, errors, checks)
	var release_data: Dictionary = manifest.get("release", {})
	var automatic: Dictionary = manifest.get("automatic", {})
	var phases: Array = manifest.get("phases", [])
	var manual_gates: Array = manifest.get("manual_gates", [])

	_validate_release(release_data, errors, checks)
	_validate_phases(phases, release_data, errors, checks)
	_validate_automatic(automatic, phases, errors, checks)
	_validate_manual_gates(manual_gates, errors, checks)
	_validate_plugin(plugin_text, release_data, errors, checks)
	_validate_documents(
		manifest,
		plugin_text,
		phase1_document_present,
		document_texts,
		errors,
		checks
	)

	var automatic_ready: bool = _automatic_ready(automatic, phases)
	var manuals_passed: bool = _manuals_passed(manual_gates)
	var declared_merge_ready: bool = bool(release_data.get("merge_ready", false))
	var computed_merge_ready: bool = (
		errors.is_empty() and automatic_ready and manuals_passed
	)

	checks["automatic_ready"] = automatic_ready
	checks["manuals_passed"] = manuals_passed
	checks["declared_merge_ready"] = declared_merge_ready
	checks["computed_merge_ready"] = computed_merge_ready

	if declared_merge_ready != computed_merge_ready:
		errors.append(
			"release.merge_ready dürüst değil: beyan=%s hesaplanan=%s" % [
				str(declared_merge_ready), str(computed_merge_ready)
			]
		)

	if not manuals_passed:
		warnings.append(
			"Üç gerçek kullanım kapısı tamamlanmadı; release candidate "
			+ "birleştirilmeye hazır değildir."
		)

	return {
		"ok": errors.is_empty(),
		"merge_ready": computed_merge_ready,
		"automatic_ready": automatic_ready,
		"manuals_passed": manuals_passed,
		"errors": errors,
		"warnings": warnings,
		"checks": checks,
	}


static func _validate_schema(
	manifest: Dictionary, errors: Array[String], checks: Dictionary
) -> void:
	checks["schema_version"] = (
		int(manifest.get("schema_version", -1)) == REQUIRED_SCHEMA_VERSION
	)
	if not bool(checks["schema_version"]):
		errors.append("readiness manifest schema_version=1 olmalı")
	for key in ["release", "automatic", "phases", "manual_gates"]:
		if not manifest.has(key):
			errors.append("manifest zorunlu alanı eksik: " + key)


static func _validate_release(
	release_data: Dictionary, errors: Array[String], checks: Dictionary
) -> void:
	checks["godot_version"] = (
		str(release_data.get("godot_version", "")) == REQUIRED_GODOT_VERSION
	)
	if not bool(checks["godot_version"]):
		errors.append("release godot_version 4.6.3 olmalı")

	checks["strategy"] = (
		str(release_data.get("strategy", "")) == REQUIRED_STRATEGY
	)
	if not bool(checks["strategy"]):
		errors.append("release strategy single_consolidation_pr olmalı")

	for key in [
		"name", "version", "channel", "default_branch",
		"consolidation_branch", "rollback_ref"
	]:
		if str(release_data.get(key, "")).strip_edges().is_empty():
			errors.append("release alanı boş olamaz: " + key)

	if str(release_data.get("channel", "")) != "release-candidate":
		errors.append("manuel kapılar açıkken channel release-candidate olmalı")


static func _validate_phases(
	phases: Array,
	release_data: Dictionary,
	errors: Array[String],
	checks: Dictionary
) -> void:
	checks["phase_count"] = phases.size() == REQUIRED_PHASE_COUNT
	if not bool(checks["phase_count"]):
		errors.append("manifest tam 8 faz içermeli")
		return

	var seen_branches: Dictionary = {}
	var seen_prs: Dictionary = {}
	var default_branch: String = str(release_data.get("default_branch", ""))
	for i in phases.size():
		if typeof(phases[i]) != TYPE_DICTIONARY:
			errors.append("faz kaydı Dictionary olmalı: indeks %d" % i)
			continue
		var phase: Dictionary = phases[i]
		var number: int = int(phase.get("number", -1))
		var branch: String = str(phase.get("branch", ""))
		var base: String = str(phase.get("base", ""))
		var pr_number: int = int(phase.get("pr", -1))

		if number != i + 1:
			errors.append("faz sırası kesintisiz 1..8 olmalı: indeks %d" % i)
		if branch.is_empty() or seen_branches.has(branch):
			errors.append("faz branch boş veya tekrarlı: " + branch)
		seen_branches[branch] = true
		if pr_number <= 0 or seen_prs.has(pr_number):
			errors.append("faz PR numarası geçersiz veya tekrarlı: %d" % pr_number)
		seen_prs[pr_number] = true
		if str(phase.get("name", "")).strip_edges().is_empty():
			errors.append("faz adı boş olamaz: %d" % number)

		if number <= 2:
			if base != default_branch:
				errors.append("Faz %d varsayılan dalı temel almalı" % number)
		else:
			var previous: Dictionary = phases[i - 1]
			var expected_base: String = str(previous.get("branch", ""))
			if base != expected_base:
				errors.append(
					"Faz %d base zinciri yanlış: %s != %s" % [
						number, base, expected_base
					]
				)

	checks["phase_order"] = not _has_error_prefix(errors, "faz sırası")
	checks["phase_dependencies"] = not _has_error_fragment(errors, "base")


static func _validate_automatic(
	automatic: Dictionary,
	phases: Array,
	errors: Array[String],
	checks: Dictionary
) -> void:
	var expected_tests: int = int(automatic.get("expected_test_count", 0))
	checks["test_count"] = expected_tests >= 886
	if not bool(checks["test_count"]):
		errors.append("expected_test_count Faz 7 tabanı olan 886'dan düşük olamaz")

	var gates: Dictionary = automatic.get("gates", {})
	var required_gates: Array = [
		"secret_leakage",
		"architecture_invariants",
		"plugin_parse_compile",
		"contract_suite",
		"runtime_hygiene",
		"android_repo_audit",
		"deepseek_v4_contracts",
	]
	for gate_id in required_gates:
		if not gates.has(gate_id) or not bool(gates[gate_id]):
			errors.append("otomatik gate geçmemiş veya eksik: " + str(gate_id))

	for phase_value in phases:
		if typeof(phase_value) != TYPE_DICTIONARY:
			continue
		var phase: Dictionary = phase_value
		if not bool(phase.get("automatic_complete", false)):
			errors.append(
				"faz automatic_complete değil: %d" % int(phase.get("number", -1))
			)
	checks["automatic_gates"] = not _has_error_fragment(errors, "otomatik gate")
	checks["phase_automatic_complete"] = not _has_error_fragment(
		errors, "automatic_complete"
	)


static func _validate_manual_gates(
	manual_gates: Array,
	errors: Array[String],
	checks: Dictionary
) -> void:
	if manual_gates.size() != REQUIRED_MANUAL_GATE_IDS.size():
		errors.append("tam 3 manuel gate tanımlanmalı")
		return
	var seen: Dictionary = {}
	for gate_value in manual_gates:
		if typeof(gate_value) != TYPE_DICTIONARY:
			errors.append("manuel gate Dictionary olmalı")
			continue
		var gate: Dictionary = gate_value
		var gate_id: String = str(gate.get("id", ""))
		var status: String = str(gate.get("status", ""))
		if not REQUIRED_MANUAL_GATE_IDS.has(gate_id) or seen.has(gate_id):
			errors.append("manuel gate eksik/bilinmeyen/tekrarlı: " + gate_id)
		seen[gate_id] = true
		if not VALID_MANUAL_STATUSES.has(status):
			errors.append("manuel gate status geçersiz: " + status)
		if int(gate.get("phase", 0)) <= 0:
			errors.append("manuel gate phase geçersiz: " + gate_id)
		if str(gate.get("evidence_marker", "")).strip_edges().is_empty():
			errors.append("manuel gate evidence_marker boş: " + gate_id)
		if str(gate.get("procedure", "")).strip_edges().is_empty():
			errors.append("manuel gate procedure boş: " + gate_id)
	checks["manual_gate_set"] = errors.filter(
		func(e: String) -> bool: return e.contains("manuel gate")
	).is_empty()


static func _validate_plugin(
	plugin_text: String,
	release_data: Dictionary,
	errors: Array[String],
	checks: Dictionary
) -> void:
	var version: String = _extract_cfg_value(plugin_text, "version")
	var description: String = _extract_cfg_value(plugin_text, "description")
	checks["plugin_version"] = version == str(release_data.get("version", ""))
	if not bool(checks["plugin_version"]):
		errors.append(
			"plugin.cfg version manifest ile eşleşmiyor: %s" % version
		)
	checks["plugin_description"] = (
		description.contains("Godot 4.6.3")
		and description.to_lower().contains("tam ekran")
		and not description.contains("sol dock")
	)
	if not bool(checks["plugin_description"]):
		errors.append("plugin description Godot 4.6.3/tam ekran mimarisini anlatmıyor")


static func _validate_documents(
	manifest: Dictionary,
	plugin_text: String,
	phase1_document_present: bool,
	document_texts: Array,
	errors: Array[String],
	checks: Dictionary
) -> void:
	checks["phase1_document"] = phase1_document_present
	if not phase1_document_present:
		errors.append("Faz 1 güvenlik denetimi konsolidasyon dalında yok")

	var combined: String = JSON.stringify(manifest) + "\n" + plugin_text
	for text_value in document_texts:
		combined += "\n" + str(text_value)
	checks["no_secret"] = not _contains_secret(combined)
	if not bool(checks["no_secret"]):
		errors.append("release manifesti veya belgelerde gizli anahtar değeri bulundu")


static func _automatic_ready(automatic: Dictionary, phases: Array) -> bool:
	var gates: Dictionary = automatic.get("gates", {})
	if gates.is_empty():
		return false
	for value in gates.values():
		if not bool(value):
			return false
	if phases.size() != REQUIRED_PHASE_COUNT:
		return false
	for phase_value in phases:
		if typeof(phase_value) != TYPE_DICTIONARY:
			return false
		if not bool((phase_value as Dictionary).get("automatic_complete", false)):
			return false
	return int(automatic.get("expected_test_count", 0)) >= 886


static func _manuals_passed(manual_gates: Array) -> bool:
	if manual_gates.size() != REQUIRED_MANUAL_GATE_IDS.size():
		return false
	for gate_value in manual_gates:
		if typeof(gate_value) != TYPE_DICTIONARY:
			return false
		if str((gate_value as Dictionary).get("status", "")) != "passed":
			return false
	return true


static func _extract_cfg_value(text: String, key: String) -> String:
	var regex := RegEx.new()
	if regex.compile("(?m)^" + key + "=\\\"([^\\\"]*)\\\"$") != OK:
		return ""
	var match_result: RegExMatch = regex.search(text)
	if match_result == null:
		return ""
	return match_result.get_string(1)


static func _contains_secret(text: String) -> bool:
	var secret_regex := RegEx.new()
	if secret_regex.compile("(?i)sk[-_][a-z0-9]{16,}") != OK:
		return true
	if secret_regex.search(text) != null:
		return true
	var auth_regex := RegEx.new()
	if auth_regex.compile(
		"(?i)authorization\\s*:\\s*bearer\\s+[a-z0-9._-]{16,}"
	) != OK:
		return true
	return auth_regex.search(text) != null


static func _has_error_prefix(errors: Array[String], prefix: String) -> bool:
	for error in errors:
		if error.begins_with(prefix):
			return true
	return false


static func _has_error_fragment(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false
