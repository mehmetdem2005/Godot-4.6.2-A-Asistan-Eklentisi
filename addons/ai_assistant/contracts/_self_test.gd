@tool
class_name AIContractSelfTest
extends RefCounted

## Phase 0 / Layer 0 — Contract Self-Test (ZİNCİRLEME)
##
## Tüm batch'lerin testleri burada birikir. Yeni contract eklendikçe testi
## bu listeye eklenir — eski testler asla kaldırılmaz.
##
## Her test sonucu bir "batch" etiketi taşır; rapor bu etikete göre gruplanır.
## Mock policy: testler GERÇEK doğrulama yapar — sahte "passed" yok.


## Tüm testleri çalıştırır, sonuç özetini döndürür.
static func run_all() -> Dictionary:
	var results: Array = []

	# --- BATCH 1: Temel Görev Sistemi ---
	results.append(_b("Batch 1", _test_validation_result()))
	results.append(_b("Batch 1", _test_task_lifecycle()))
	results.append(_b("Batch 1", _test_task_spec_roundtrip()))
	results.append(_b("Batch 1", _test_task_spec_validation()))
	results.append(_b("Batch 1", _test_task_transition()))
	results.append(_b("Batch 1", _test_iteration_roundtrip()))
	results.append(_b("Batch 1", _test_iteration_capacity()))
	results.append(_b("Batch 1", _test_feed_event_roundtrip()))
	results.append(_b("Batch 1", _test_feed_event_format()))

	# --- BATCH 2: Board / Genre / Action / Snapshot / Tool ---
	results.append(_b("Batch 2", _test_task_board_roundtrip()))
	results.append(_b("Batch 2", _test_task_board_column_mapping()))
	results.append(_b("Batch 2", _test_genre_profile_roundtrip()))
	results.append(_b("Batch 2", _test_genre_profile_renderer_guard()))
	results.append(_b("Batch 2", _test_action_spec_roundtrip()))
	results.append(_b("Batch 2", _test_action_spec_destructive()))
	results.append(_b("Batch 2", _test_state_snapshot_diff()))
	results.append(_b("Batch 2", _test_state_snapshot_equals()))
	results.append(_b("Batch 2", _test_tool_call_roundtrip()))
	results.append(_b("Batch 2", _test_tool_call_cache_cost()))

	# --- BATCH 3a: VCS (Blob / Tree / Commit / Diff) ---
	results.append(_b("Batch 3a", _test_vcs_blob_content_address()))
	results.append(_b("Batch 3a", _test_vcs_blob_dedup()))
	results.append(_b("Batch 3a", _test_vcs_blob_roundtrip()))
	results.append(_b("Batch 3a", _test_vcs_tree_hash_deterministic()))
	results.append(_b("Batch 3a", _test_vcs_tree_find_entry()))
	results.append(_b("Batch 3a", _test_vcs_commit_id_compute()))
	results.append(_b("Batch 3a", _test_vcs_commit_root_merge()))
	results.append(_b("Batch 3a", _test_vcs_commit_roundtrip()))
	results.append(_b("Batch 3a", _test_vcs_diff_summary()))
	results.append(_b("Batch 3a", _test_vcs_diff_roundtrip()))

	# --- BATCH 3b: Memory / Plan / Verify / Provider / Cell / Error / Cost / Key / Edit ---
	results.append(_b("Batch 3b", _test_memory_record_roundtrip()))
	results.append(_b("Batch 3b", _test_memory_record_salience()))
	results.append(_b("Batch 3b", _test_plan_node_hierarchy()))
	results.append(_b("Batch 3b", _test_plan_node_dag_guard()))
	results.append(_b("Batch 3b", _test_verification_evidence_rule()))
	results.append(_b("Batch 3b", _test_verification_roundtrip()))
	results.append(_b("Batch 3b", _test_provider_request_cache_key()))
	results.append(_b("Batch 3b", _test_provider_request_roundtrip()))
	results.append(_b("Batch 3b", _test_cell_message_reflection()))
	results.append(_b("Batch 3b", _test_cell_message_roundtrip()))
	results.append(_b("Batch 3b", _test_error_report_classification()))
	results.append(_b("Batch 3b", _test_error_report_roundtrip()))
	results.append(_b("Batch 3b", _test_cost_record_compute()))
	results.append(_b("Batch 3b", _test_cost_record_roundtrip()))
	results.append(_b("Batch 3b", _test_encrypted_key_integrity()))
	results.append(_b("Batch 3b", _test_encrypted_key_roundtrip()))
	results.append(_b("Batch 3b", _test_edit_intent_protocol()))
	results.append(_b("Batch 3b", _test_edit_intent_surgical_limit()))

	# --- PHASE 1: Memory System (Layer 1) ---
	# Memory testleri ayrı dosyada (AIMemoryTest) — buradan zincirlenir.
	for mem_result in AIMemoryTest.run_all():
		results.append(mem_result)

	# --- PHASE 2: Knowledge & RAG (Layer 2) ---
	for kb_result in AIKnowledgeTest.run_all():
		results.append(kb_result)

	# --- PHASE 3: Planner (Layer 3) ---
	for plan_result in AIPlannerTest.run_all():
		results.append(plan_result)

	# --- PHASE 4: Executor & Sandbox (Layer 4) ---
	for exec_result in AIExecutorTest.run_all():
		results.append(exec_result)

	# --- PHASE 5: Verifier (Layer 5) ---
	for verify_result in AIVerifierTest.run_all():
		results.append(verify_result)

	# --- PHASE 6: Observability (Layer 6) ---
	for obs_result in AIObservabilityTest.run_all():
		results.append(obs_result)

	# --- PHASE 7: Multi-Provider Router (Layer 7) ---
	for router_result in AIRouterTest.run_all():
		results.append(router_result)

	# --- PHASE 7b: HTTP Transport ---
	for transport_result in AIHTTPTransportTest.run_all():
		results.append(transport_result)

	# --- PHASE 8: HITL (Layer 8) ---
	for hitl_result in AIHITLTest.run_all():
		results.append(hitl_result)

	# --- PHASE 10: Surgical Edit ---
	for surgical_result in AISurgicalEditTest.run_all():
		results.append(surgical_result)

	# --- PHASE 10b: Surgical Edit Protokolleri ---
	for protocol_result in AISurgicalProtocolsTest.run_all():
		results.append(protocol_result)

	# --- PHASE 10c: Surgical Edit Doğrulamaları ---
	for validation_result in AISurgicalValidationTest.run_all():
		results.append(validation_result)

	# --- PHASE 11: Workspace UI (Layer 11) ---
	for workspace_result in AIWorkspaceTest.run_all():
		results.append(workspace_result)

	# --- PHASE 11b: Workspace Kalan 6 Sekme ---
	for tabs_result in AIWorkspaceTabsTest.run_all():
		results.append(tabs_result)

	# --- PHASE 12: Pilot Cell (Layer 9) ---
	for pilot_result in AIPilotCellTest.run_all():
		results.append(pilot_result)

	# --- PHASE 12b: Pilot Cell Ajan Zekâsı ---
	for brain_result in AIPilotBrainTest.run_all():
		results.append(brain_result)

	# --- PHASE 12c: Pilot Cell Çıktı Ayrıştırma ---
	for parser_result in AIOutputParserTest.run_all():
		results.append(parser_result)

	# --- PHASE 12d: Pilot Cell Bağlam Aktarımı ---
	for relay_result in AIContextRelayTest.run_all():
		results.append(relay_result)

	# --- PHASE 13: Quality Gates (Layer 10) ---
	for quality_result in AIQualityGatesTest.run_all():
		results.append(quality_result)

	# --- PHASE 14: Save/Load (Madde 09) ---
	for save_result in AISaveLoadTest.run_all():
		results.append(save_result)

	# --- PHASE 15: Audio System (Madde 08) ---
	for audio_result in AIAudioTest.run_all():
		results.append(audio_result)

	# --- PHASE 16: App Lifecycle (Madde 10) ---
	for lifecycle_result in AILifecycleTest.run_all():
		results.append(lifecycle_result)

	# --- PHASE 17: Offline / Graceful Degradation (Madde 07) ---
	for offline_result in AIOfflineTest.run_all():
		results.append(offline_result)

	# --- PHASE 18: Debug Loop (Madde 02) ---
	for debug_result in AIDebugLoopTest.run_all():
		results.append(debug_result)

	# --- PHASE 19: Save/Load Mantık Tamamlama (Madde 09) ---
	for save_ext_result in AISaveLoadExtendedTest.run_all():
		results.append(save_ext_result)

	# --- PHASE 20: Genre Schemas + Cloud Stubs (Madde 09) ---
	for genre_cloud_result in AISaveGenreCloudTest.run_all():
		results.append(genre_cloud_result)

	# --- PHASE 21: Audio Sentez (Madde 08) ---
	for audio_synth_result in AIAudioSynthTest.run_all():
		results.append(audio_synth_result)

	# --- PHASE 22: Audio Tamamlama (Madde 08) ---
	for audio_comp_result in AIAudioCompletionTest.run_all():
		results.append(audio_comp_result)

	# --- PHASE 23: Lifecycle Tamamlama (Madde 10) ---
	for life_comp_result in AILifecycleCompletionTest.run_all():
		results.append(life_comp_result)

	# --- PHASE 24: Offline Tamamlama (Madde 07) ---
	for offline_comp_result in AIOfflineCompletionTest.run_all():
		results.append(offline_comp_result)

	# --- PHASE 25: UI Katmanı 7A — Offline+Audio UI ---
	for ui7a_result in AIUITur7ATest.run_all():
		results.append(ui7a_result)

	# --- PHASE 26: UI Katmanı 7B — Save/Load+Lifecycle UI ---
	for ui7b_result in AIUITur7BTest.run_all():
		results.append(ui7b_result)

	# --- PHASE 27: UI Katmanı 7C — Debug UI + Final Entegrasyon ---
	for ui7c_result in AIUITur7CTest.run_all():
		results.append(ui7c_result)

	# --- PHASE 28: Canlı API — Anahtar Deposu (Layer 7) ---
	for keystore_result in AIAPIKeyStoreTest.run_all():
		results.append(keystore_result)

	# --- PHASE 29: Pilot Cell Canlı Köprü (Aşama 4a) ---
	for live_bridge_result in AIAgentLiveBridgeTest.run_all():
		results.append(live_bridge_result)

	# --- PHASE 30: Hata ↔ Bellek Köprüsü (Aşama 4b) ---
	for dbg_mem_result in AIDebugMemoryBridgeTest.run_all():
		results.append(dbg_mem_result)

	return _build_report(results)


## Bir test sonucuna batch etiketi ekler.
static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


## Test sonuçlarından gruplu rapor üretir.
static func _build_report(results: Array) -> Dictionary:
	var passed: int = 0
	var failed: int = 0
	var report: PackedStringArray = PackedStringArray()
	report.append("=== Contract Self-Test Sonuçları ===")

	var current_batch: String = ""
	for r in results:
		if r["batch"] != current_batch:
			current_batch = r["batch"]
			report.append("--- %s ---" % current_batch)
		if r["ok"]:
			passed += 1
			report.append("  ✓ %s" % r["name"])
		else:
			failed += 1
			report.append("  ✗ %s — %s" % [r["name"], r["reason"]])

	report.append(
		"--- %d geçti, %d başarısız (toplam %d) ---" % [passed, failed, results.size()]
	)

	var summary: String = "\n".join(report)
	print(summary)
	return {"passed": passed, "failed": failed, "report": summary}


static func _ok(test_name: String) -> Dictionary:
	return {"ok": true, "name": test_name, "reason": ""}


static func _fail(test_name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": test_name, "reason": reason}


# ============================================================
# BATCH 1 TESTLERİ
# ============================================================

static func _test_validation_result() -> Dictionary:
	var name := "ValidationResult temel davranış"
	var v := AIValidationResult.new()
	if not v.ok:
		return _fail(name, "yeni result ok olmalı")
	v.add_warning("uyarı")
	if not v.ok:
		return _fail(name, "warning ok'u bozmamalı")
	v.add_error("hata")
	if v.ok:
		return _fail(name, "error sonrası ok false olmalı")
	if not v.has_errors() or not v.has_warnings():
		return _fail(name, "has_errors/has_warnings yanlış")
	return _ok(name)


static func _test_task_lifecycle() -> Dictionary:
	var name := "TaskLifecycle geçiş kuralları"
	if not AITaskLifecycle.can_transition(
		AITaskLifecycle.Status.QUEUED, AITaskLifecycle.Status.READY
	):
		return _fail(name, "QUEUED->READY geçerli olmalı")
	if AITaskLifecycle.can_transition(
		AITaskLifecycle.Status.DONE, AITaskLifecycle.Status.QUEUED
	):
		return _fail(name, "DONE->QUEUED geçersiz olmalı")
	if not AITaskLifecycle.is_terminal(AITaskLifecycle.Status.ARCHIVED):
		return _fail(name, "ARCHIVED terminal olmalı")
	if AITaskLifecycle.is_terminal(AITaskLifecycle.Status.IN_PROGRESS):
		return _fail(name, "IN_PROGRESS terminal olmamalı")
	return _ok(name)


static func _test_task_spec_roundtrip() -> Dictionary:
	var name := "TaskSpec serialize round-trip"
	var t := AITaskSpec.create("Mesh oluştur", "SceneEngineer", "iter_1")
	t.tags = PackedStringArray(["mesh", "3d"])
	t.priority = 2
	var dict: Dictionary = t.to_dict()
	var t2 := AITaskSpec.new()
	t2.from_dict(dict)
	if t2.goal != t.goal:
		return _fail(name, "goal kayboldu")
	if t2.owner_role != t.owner_role:
		return _fail(name, "owner_role kayboldu")
	if t2.priority != 2:
		return _fail(name, "priority kayboldu")
	if t2.tags.size() != 2:
		return _fail(name, "tags kayboldu")
	if dict.get("_contract_type") != "TaskSpec":
		return _fail(name, "_contract_type meta eksik")
	return _ok(name)


static func _test_task_spec_validation() -> Dictionary:
	var name := "TaskSpec doğrulama kuralları"
	var t := AITaskSpec.create("Geçerli hedef", "CodeEngineer")
	if not t.is_valid():
		return _fail(name, "geçerli task invalid çıktı")
	var bad := AITaskSpec.new()
	bad.id = "x"
	bad.owner_role = "CodeEngineer"
	bad.goal = ""
	if bad.is_valid():
		return _fail(name, "boş goal'lu task valid çıktı")
	return _ok(name)


static func _test_task_transition() -> Dictionary:
	var name := "TaskSpec durum geçişi + zaman damgası"
	var t := AITaskSpec.create("Test", "QAEngineer")
	if not t.transition_to(AITaskLifecycle.Status.READY):
		return _fail(name, "QUEUED->READY başarısız")
	if not t.transition_to(AITaskLifecycle.Status.IN_PROGRESS):
		return _fail(name, "READY->IN_PROGRESS başarısız")
	if t.started_at.is_empty():
		return _fail(name, "started_at IN_PROGRESS'te set edilmeli")
	var prev_status: int = t.status
	if t.transition_to(AITaskLifecycle.Status.ARCHIVED):
		return _fail(name, "IN_PROGRESS->ARCHIVED geçersiz olmalıydı")
	if t.status != prev_status:
		return _fail(name, "geçersiz geçiş durumu değiştirdi")
	if t.status_history.size() != 2:
		return _fail(name, "status_history yanlış")
	return _ok(name)


static func _test_iteration_roundtrip() -> Dictionary:
	var name := "Iteration serialize round-trip"
	var it := AIIteration.create(3, "Kamera sistemi", AIIteration.Size.MEDIUM)
	it.genre_id = "fps_3d"
	var dict: Dictionary = it.to_dict()
	var it2 := AIIteration.new()
	it2.from_dict(dict)
	if it2.number != 3:
		return _fail(name, "number kayboldu")
	if it2.size != AIIteration.Size.MEDIUM:
		return _fail(name, "size kayboldu")
	if it2.genre_id != "fps_3d":
		return _fail(name, "genre_id kayboldu")
	if not it2.branch_name.begins_with("iteration/"):
		return _fail(name, "branch_name yanlış")
	return _ok(name)


static func _test_iteration_capacity() -> Dictionary:
	var name := "Iteration kapasite kontrolü"
	var it := AIIteration.create(1, "Test", AIIteration.Size.MICRO)
	it.task_ids = PackedStringArray(["t1", "t2"])
	if not it.is_over_capacity():
		return _fail(name, "MICRO 2 task ile over-capacity olmalı")
	var v: AIValidationResult = it.validate()
	if not v.has_warnings():
		return _fail(name, "over-capacity uyarı üretmeli")
	return _ok(name)


static func _test_feed_event_roundtrip() -> Dictionary:
	var name := "FeedEvent serialize round-trip"
	var e := AIFeedEvent.create(
		"TASK_STARTED", "player.gd düzenleniyor", "CodeEngineer", AIFeedEvent.Severity.INFO
	)
	e.task_ref = "task_123"
	var dict: Dictionary = e.to_dict()
	var e2 := AIFeedEvent.new()
	e2.from_dict(dict)
	if e2.event_type != "TASK_STARTED":
		return _fail(name, "event_type kayboldu")
	if e2.task_ref != "task_123":
		return _fail(name, "task_ref kayboldu")
	if e2.severity != AIFeedEvent.Severity.INFO:
		return _fail(name, "severity kayboldu")
	return _ok(name)


static func _test_feed_event_format() -> Dictionary:
	var name := "FeedEvent format_line"
	var e := AIFeedEvent.create(
		"COMMIT_CREATED", "3 dosya commit edildi", "TechWriter", AIFeedEvent.Severity.SUCCESS
	)
	var line: String = e.format_line()
	if not line.contains("COMMIT_CREATED"):
		return _fail(name, "format_line event_type içermeli")
	if not line.contains("TechWriter"):
		return _fail(name, "format_line owner_role içermeli")
	if e.severity_color() != "#22C55E":
		return _fail(name, "SUCCESS rengi yanlış")
	return _ok(name)


# ============================================================
# BATCH 2 TESTLERİ
# ============================================================

static func _test_task_board_roundtrip() -> Dictionary:
	var name := "TaskBoard serialize round-trip"
	var b := AITaskBoard.create("Iteration 3 Board", "iteration")
	b.add_task("task_1")
	b.add_task("task_2")
	b.add_task("task_1")
	var dict: Dictionary = b.to_dict()
	var b2 := AITaskBoard.new()
	b2.from_dict(dict)
	if b2.name != "Iteration 3 Board":
		return _fail(name, "name kayboldu")
	if b2.task_ids.size() != 2:
		return _fail(name, "task_ids yanlış (tekrar engellenmedi)")
	if b2.columns.size() != 6:
		return _fail(name, "varsayılan 6 kolon kayboldu")
	return _ok(name)


static func _test_task_board_column_mapping() -> Dictionary:
	var name := "TaskBoard kolon-durum eşlemesi"
	if AITaskBoard.column_for_status(AITaskLifecycle.Status.IN_PROGRESS) != "active":
		return _fail(name, "IN_PROGRESS 'active' kolonuna düşmeli")
	if AITaskBoard.column_for_status(AITaskLifecycle.Status.DONE) != "done":
		return _fail(name, "DONE 'done' kolonuna düşmeli")
	var b := AITaskBoard.create("Test")
	b.add_task("x")
	b.remove_task("x")
	if b.task_ids.size() != 0:
		return _fail(name, "remove_task çalışmadı")
	return _ok(name)


static func _test_genre_profile_roundtrip() -> Dictionary:
	var name := "GenreProfile serialize round-trip"
	var g := AIGenreProfile.create("fps_3d", "Birinci Şahıs Nişancı")
	g.core_systems = PackedStringArray(["first_person_camera", "weapon_system"])
	g.performance_emphasis = "frame_rate_priority"
	var dict: Dictionary = g.to_dict()
	var g2 := AIGenreProfile.new()
	g2.from_dict(dict)
	if g2.genre_id != "fps_3d":
		return _fail(name, "genre_id kayboldu")
	if g2.core_systems.size() != 2:
		return _fail(name, "core_systems kayboldu")
	if not g2.has_system("weapon_system"):
		return _fail(name, "has_system yanlış")
	if g2.performance_emphasis != "frame_rate_priority":
		return _fail(name, "performance_emphasis kayboldu")
	return _ok(name)


static func _test_genre_profile_renderer_guard() -> Dictionary:
	var name := "GenreProfile Forward+ koruması"
	var g := AIGenreProfile.create("test_genre", "Test")
	if not g.is_valid():
		return _fail(name, "Forward Mobile geçerli olmalı")
	g.default_renderer = "Forward Plus"
	if g.is_valid():
		return _fail(name, "Forward+ Android'de reddedilmeli")
	return _ok(name)


static func _test_action_spec_roundtrip() -> Dictionary:
	var name := "ActionSpec serialize round-trip"
	var a := AIActionSpec.create(
		AIActionSpec.ActionType.FILE_WRITE, "res://player.gd", "CodeEngineer"
	)
	a.sequence = 5
	a.expected_outcome = "player.gd oluşturuldu"
	var dict: Dictionary = a.to_dict()
	var a2 := AIActionSpec.new()
	a2.from_dict(dict)
	if a2.action_type != AIActionSpec.ActionType.FILE_WRITE:
		return _fail(name, "action_type kayboldu")
	if a2.target_path != "res://player.gd":
		return _fail(name, "target_path kayboldu")
	if a2.sequence != 5:
		return _fail(name, "sequence kayboldu")
	if a2.action_type_name() != "file_write":
		return _fail(name, "action_type_name yanlış")
	return _ok(name)


static func _test_action_spec_destructive() -> Dictionary:
	var name := "ActionSpec yıkıcı işlem tespiti"
	var del := AIActionSpec.create(
		AIActionSpec.ActionType.FILE_DELETE, "res://old.gd", "CodeEngineer"
	)
	if not del.is_destructive():
		return _fail(name, "FILE_DELETE yıkıcı olmalı")
	var write := AIActionSpec.create(
		AIActionSpec.ActionType.FILE_WRITE, "res://new.gd", "CodeEngineer"
	)
	if write.is_destructive():
		return _fail(name, "FILE_WRITE yıkıcı olmamalı")
	return _ok(name)


static func _test_state_snapshot_diff() -> Dictionary:
	var name := "StateSnapshot diff hesaplama"
	var old_snap := AIStateSnapshot.create("eski")
	old_snap.file_hashes = {"a.gd": "hash1", "b.gd": "hash2"}
	var new_snap := AIStateSnapshot.create("yeni")
	new_snap.file_hashes = {"a.gd": "hash1", "b.gd": "DEGISTI", "c.gd": "hash3"}
	var d: Dictionary = new_snap.diff_against(old_snap)
	var added: PackedStringArray = d.get("files_added", PackedStringArray())
	var changed: PackedStringArray = d.get("files_changed", PackedStringArray())
	if not added.has("c.gd"):
		return _fail(name, "c.gd eklenen olarak tespit edilmeli")
	if not changed.has("b.gd"):
		return _fail(name, "b.gd değişen olarak tespit edilmeli")
	if added.size() != 1:
		return _fail(name, "fazladan eklenen tespit edildi")
	return _ok(name)


static func _test_state_snapshot_equals() -> Dictionary:
	var name := "StateSnapshot eşitlik kontrolü"
	var s1 := AIStateSnapshot.create("a")
	s1.file_hashes = {"x.gd": "h1"}
	var s2 := AIStateSnapshot.create("b")
	s2.file_hashes = {"x.gd": "h1"}
	if not s1.equals(s2):
		return _fail(name, "aynı içerikli snapshot'lar eşit olmalı")
	s2.file_hashes = {"x.gd": "h2"}
	if s1.equals(s2):
		return _fail(name, "farklı içerikli snapshot'lar eşit olmamalı")
	return _ok(name)


static func _test_tool_call_roundtrip() -> Dictionary:
	var name := "ToolCall serialize round-trip"
	var tc := AIToolCall.create("generate_texture", "AssetEngineer")
	tc.cost_estimate = 0.04
	tc.params = {"size": 1024, "type": "perlin"}
	var dict: Dictionary = tc.to_dict()
	var tc2 := AIToolCall.new()
	tc2.from_dict(dict)
	if tc2.tool_name != "generate_texture":
		return _fail(name, "tool_name kayboldu")
	if abs(tc2.cost_estimate - 0.04) > 0.0001:
		return _fail(name, "cost_estimate kayboldu")
	if tc2.params.get("size") != 1024:
		return _fail(name, "params kayboldu")
	return _ok(name)


static func _test_tool_call_cache_cost() -> Dictionary:
	var name := "ToolCall cache hit maliyeti"
	var tc := AIToolCall.create("expensive_tool", "CodeEngineer")
	tc.cost_estimate = 0.10
	if abs(tc.effective_cost() - 0.10) > 0.0001:
		return _fail(name, "cache miss'te tam maliyet dönmeli")
	tc.was_cache_hit = true
	if tc.effective_cost() != 0.0:
		return _fail(name, "cache hit'te maliyet 0 olmalı")
	return _ok(name)


# ============================================================
# BATCH 3a TESTLERİ — VCS
# ============================================================

static func _test_vcs_blob_content_address() -> Dictionary:
	var name := "VCSBlob içerik-adresleme"
	var blob := AIVCSBlob.create_from_text("merhaba dünya")
	# Hash SHA-256 formatında olmalı (64 hex karakter)
	if blob.hash.length() != 64:
		return _fail(name, "hash 64 hex değil: %d" % blob.hash.length())
	# Boyut doğru mu
	if blob.size_bytes != "merhaba dünya".to_utf8_buffer().size():
		return _fail(name, "size_bytes yanlış")
	# Storage path hash'ten türetilmeli
	if not blob.storage_path.contains(blob.hash.substr(0, 2)):
		return _fail(name, "storage_path hash'ten türetilmemiş")
	return _ok(name)


static func _test_vcs_blob_dedup() -> Dictionary:
	var name := "VCSBlob deduplication (aynı içerik = aynı hash)"
	var b1 := AIVCSBlob.create_from_text("aynı içerik")
	var b2 := AIVCSBlob.create_from_text("aynı içerik")
	var b3 := AIVCSBlob.create_from_text("farklı içerik")
	if b1.hash != b2.hash:
		return _fail(name, "aynı içerik farklı hash üretti")
	if b1.hash == b3.hash:
		return _fail(name, "farklı içerik aynı hash üretti")
	return _ok(name)


static func _test_vcs_blob_roundtrip() -> Dictionary:
	var name := "VCSBlob serialize round-trip"
	var b := AIVCSBlob.create_from_text("test")
	var dict: Dictionary = b.to_dict()
	var b2 := AIVCSBlob.new()
	b2.from_dict(dict)
	if b2.hash != b.hash:
		return _fail(name, "hash kayboldu")
	if b2.size_bytes != b.size_bytes:
		return _fail(name, "size_bytes kayboldu")
	if not b2.is_valid():
		return _fail(name, "round-trip sonrası invalid")
	return _ok(name)


static func _test_vcs_tree_hash_deterministic() -> Dictionary:
	var name := "VCSTree deterministik hash (sıra bağımsız)"
	# Aynı girdiler farklı sırada eklendiğinde aynı hash üretmeli
	var t1 := AIVCSTree.create()
	t1.add_blob("b.gd", "hashB")
	t1.add_blob("a.gd", "hashA")
	var h1: String = t1.compute_hash()

	var t2 := AIVCSTree.create()
	t2.add_blob("a.gd", "hashA")
	t2.add_blob("b.gd", "hashB")
	var h2: String = t2.compute_hash()

	if h1 != h2:
		return _fail(name, "sıra farkı hash'i değiştirdi: %s != %s" % [h1, h2])
	if h1.length() != 64:
		return _fail(name, "tree hash SHA-256 değil")
	return _ok(name)


static func _test_vcs_tree_find_entry() -> Dictionary:
	var name := "VCSTree find_entry"
	var t := AIVCSTree.create()
	t.add_blob("player.gd", "h1")
	t.add_subtree("scripts", "h2")
	var found: Dictionary = t.find_entry("player.gd")
	if found.is_empty() or found["type"] != "blob":
		return _fail(name, "player.gd blob bulunamadı")
	var sub: Dictionary = t.find_entry("scripts")
	if sub.is_empty() or sub["type"] != "tree":
		return _fail(name, "scripts subtree bulunamadı")
	if not t.find_entry("yok.gd").is_empty():
		return _fail(name, "olmayan girdi boş dönmeli")
	if t.entry_count() != 2:
		return _fail(name, "entry_count yanlış")
	return _ok(name)


static func _test_vcs_commit_id_compute() -> Dictionary:
	var name := "VCSCommit ID hesaplama (içerik-adresli)"
	var c := AIVCSCommit.create("treehash123", "İlk commit", "DeliveryManager")
	if c.id.length() != 64:
		return _fail(name, "commit id SHA-256 değil: %d" % c.id.length())
	# Aynı içerik aynı ID üretmeli (timestamp hariç sabit tutulursa)
	var c2 := AIVCSCommit.new()
	c2.tree_hash = c.tree_hash
	c2.message = c.message
	c2.author_role = c.author_role
	c2.timestamp = c.timestamp
	c2.compute_id()
	if c2.id != c.id:
		return _fail(name, "aynı içerik farklı ID üretti")
	return _ok(name)


static func _test_vcs_commit_root_merge() -> Dictionary:
	var name := "VCSCommit root/merge tespiti"
	var root := AIVCSCommit.create("t1", "kök", "DeliveryManager")
	if not root.is_root():
		return _fail(name, "parent'sız commit root olmalı")
	if root.is_merge():
		return _fail(name, "tek parent'sız commit merge olmamalı")
	var merge := AIVCSCommit.create("t2", "birleştirme", "DeliveryManager")
	merge.parent_ids = PackedStringArray(["p1", "p2"])
	if not merge.is_merge():
		return _fail(name, "çift parent commit merge olmalı")
	return _ok(name)


static func _test_vcs_commit_roundtrip() -> Dictionary:
	var name := "VCSCommit serialize round-trip"
	var c := AIVCSCommit.create("treehash", "Mesh eklendi", "SceneEngineer")
	c.iteration_id = "iter_3"
	c.edit_type = "surgical"
	var dict: Dictionary = c.to_dict()
	var c2 := AIVCSCommit.new()
	c2.from_dict(dict)
	if c2.id != c.id:
		return _fail(name, "id kayboldu")
	if c2.message != "Mesh eklendi":
		return _fail(name, "message kayboldu")
	if c2.iteration_id != "iter_3":
		return _fail(name, "iteration_id kayboldu")
	if c2.edit_type != "surgical":
		return _fail(name, "edit_type kayboldu")
	return _ok(name)


static func _test_vcs_diff_summary() -> Dictionary:
	var name := "VCSDiff özet üretimi"
	var d := AIVCSDiff.create("file", "commit_a", "commit_b")
	if not d.is_empty():
		return _fail(name, "yeni diff boş olmalı")
	d.files_added = PackedStringArray(["yeni.gd"])
	d.files_changed = PackedStringArray(["mevcut.gd"])
	d.lines_added_count = 20
	d.lines_removed_count = 5
	if d.is_empty():
		return _fail(name, "değişiklikli diff boş görünüyor")
	if d.total_files_affected() != 2:
		return _fail(name, "total_files_affected yanlış")
	if not d.summary().contains("20"):
		return _fail(name, "summary satır sayısı içermeli")
	return _ok(name)


static func _test_vcs_diff_roundtrip() -> Dictionary:
	var name := "VCSDiff serialize round-trip"
	var d := AIVCSDiff.create("scene", "snap_1", "snap_2")
	d.nodes_added = PackedStringArray(["Player/Camera3D"])
	d.nodes_modified = PackedStringArray(["Player"])
	var dict: Dictionary = d.to_dict()
	var d2 := AIVCSDiff.new()
	d2.from_dict(dict)
	if d2.diff_type != "scene":
		return _fail(name, "diff_type kayboldu")
	if d2.nodes_added.size() != 1:
		return _fail(name, "nodes_added kayboldu")
	if d2.total_nodes_affected() != 2:
		return _fail(name, "total_nodes_affected yanlış")
	return _ok(name)


# ============================================================
# BATCH 3b TESTLERİ
# ============================================================

static func _test_memory_record_roundtrip() -> Dictionary:
	var name := "MemoryRecord serialize round-trip"
	var m := AIMemoryRecord.create(AIMemoryRecord.Layer.EPISODIC, "Mesh hatası çözüldü")
	m.tags = PackedStringArray(["debug", "mesh"])
	m.salience = 0.8
	var dict: Dictionary = m.to_dict()
	var m2 := AIMemoryRecord.new()
	m2.from_dict(dict)
	if m2.layer != AIMemoryRecord.Layer.EPISODIC:
		return _fail(name, "layer kayboldu")
	if m2.content != "Mesh hatası çözüldü":
		return _fail(name, "content kayboldu")
	if abs(m2.salience - 0.8) > 0.0001:
		return _fail(name, "salience kayboldu")
	if m2.tags.size() != 2:
		return _fail(name, "tags kayboldu")
	return _ok(name)


static func _test_memory_record_salience() -> Dictionary:
	var name := "MemoryRecord erişim ve decay"
	var m := AIMemoryRecord.create(AIMemoryRecord.Layer.SEMANTIC, "Godot API bilgisi")
	var before: float = m.salience
	m.mark_accessed()
	if m.salience <= before:
		return _fail(name, "mark_accessed önemi artırmalı")
	if m.access_count != 1:
		return _fail(name, "access_count artmalı")
	# Decay: uzun süre erişilmeyen bellek zayıflar
	var fresh: float = m.effective_salience(0.0)
	var old: float = m.effective_salience(100.0)
	if old >= fresh:
		return _fail(name, "zaman geçince effective_salience düşmeli")
	return _ok(name)


static func _test_plan_node_hierarchy() -> Dictionary:
	var name := "PlanNode hiyerarşi seviyeleri"
	var goal := AIPlanNode.create(AIPlanNode.Level.GOAL, "Oyun yap")
	if not goal.is_root():
		return _fail(name, "GOAL kök olmalı")
	if goal.expected_child_level() != AIPlanNode.Level.MILESTONE:
		return _fail(name, "GOAL'un çocuğu MILESTONE olmalı")
	var action := AIPlanNode.create(AIPlanNode.Level.ACTION, "Dosya yaz")
	if action.expected_child_level() != -1:
		return _fail(name, "ACTION'ın çocuğu olmamalı")
	goal.add_child("milestone_1")
	goal.add_child("milestone_1")  # tekrar
	if goal.children_ids.size() != 1:
		return _fail(name, "add_child tekrar engellemeli")
	return _ok(name)


static func _test_plan_node_dag_guard() -> Dictionary:
	var name := "PlanNode DAG koruması"
	var n := AIPlanNode.create(AIPlanNode.Level.TASK, "Test görevi")
	n.assigned_role = "CodeEngineer"
	if not n.is_valid():
		return _fail(name, "geçerli TASK invalid çıktı")
	# Kendine bağımlılık = DAG ihlali
	n.depends_on = PackedStringArray([n.id])
	if n.is_valid():
		return _fail(name, "kendine bağımlılık reddedilmeli")
	return _ok(name)


static func _test_verification_evidence_rule() -> Dictionary:
	var name := "VerificationResult evidence-based kuralı"
	var v := AIVerificationResult.create(
		AIVerificationResult.VerifyLevel.SYNTACTIC, "task_1"
	)
	# Kanıtsız PASS -> WARNING'e düşmeli (mock policy)
	v.mark_pass({}, "")
	if v.outcome == AIVerificationResult.Outcome.PASS:
		return _fail(name, "kanıtsız PASS engellenmedi")
	# Kanıtlı PASS -> gerçekten PASS
	var v2 := AIVerificationResult.create(
		AIVerificationResult.VerifyLevel.SYNTACTIC, "task_1"
	)
	v2.mark_pass({"ast": "ok"}, "ast_parse")
	if v2.outcome != AIVerificationResult.Outcome.PASS:
		return _fail(name, "kanıtlı PASS reddedildi")
	if not v2.has_evidence():
		return _fail(name, "has_evidence yanlış")
	return _ok(name)


static func _test_verification_roundtrip() -> Dictionary:
	var name := "VerificationResult serialize round-trip"
	var v := AIVerificationResult.create(
		AIVerificationResult.VerifyLevel.RUNTIME, "task_5"
	)
	v.mark_fail("Sahne çökmesi", PackedStringArray(["null reference"]))
	var dict: Dictionary = v.to_dict()
	var v2 := AIVerificationResult.new()
	v2.from_dict(dict)
	if v2.level != AIVerificationResult.VerifyLevel.RUNTIME:
		return _fail(name, "level kayboldu")
	if v2.outcome != AIVerificationResult.Outcome.FAIL:
		return _fail(name, "outcome kayboldu")
	if v2.errors.size() != 1:
		return _fail(name, "errors kayboldu")
	return _ok(name)


static func _test_provider_request_cache_key() -> Dictionary:
	var name := "ProviderRequest deterministik cache key"
	var r1 := AIProviderRequest.create(
		AIProviderRequest.Purpose.CODE, "CodeEngineer"
	)
	r1.system_prompt = "Sen bir kod uzmanısın"
	r1.add_message("user", "for döngüsü yaz")
	var k1: String = r1.compute_cache_key()

	var r2 := AIProviderRequest.create(
		AIProviderRequest.Purpose.CODE, "CodeEngineer"
	)
	r2.system_prompt = "Sen bir kod uzmanısın"
	r2.add_message("user", "for döngüsü yaz")
	var k2: String = r2.compute_cache_key()

	if k1 != k2:
		return _fail(name, "aynı istek farklı cache key üretti")
	# Farklı içerik farklı key
	r2.add_message("user", "ekstra mesaj")
	if r2.compute_cache_key() == k1:
		return _fail(name, "farklı içerik aynı key üretti")
	return _ok(name)


static func _test_provider_request_roundtrip() -> Dictionary:
	var name := "ProviderRequest serialize round-trip"
	var r := AIProviderRequest.create(
		AIProviderRequest.Purpose.REASONING, "Architect"
	)
	r.temperature = 0.3
	r.max_tokens = 4096
	r.add_message("user", "plan yap")
	var dict: Dictionary = r.to_dict()
	var r2 := AIProviderRequest.new()
	r2.from_dict(dict)
	if r2.purpose != AIProviderRequest.Purpose.REASONING:
		return _fail(name, "purpose kayboldu")
	if abs(r2.temperature - 0.3) > 0.0001:
		return _fail(name, "temperature kayboldu")
	if r2.max_tokens != 4096:
		return _fail(name, "max_tokens kayboldu")
	if r2.messages.size() != 1:
		return _fail(name, "messages kayboldu")
	return _ok(name)


static func _test_cell_message_reflection() -> Dictionary:
	var name := "CellMessage reflection loop"
	var m := AICellMessage.create(
		"QAEngineer", "CodeEngineer", AICellMessage.MessageType.FEEDBACK
	)
	if not m.is_feedback():
		return _fail(name, "FEEDBACK tipi is_feedback true olmalı")
	m.iteration_round = 2
	if not m.is_valid():
		return _fail(name, "round 2 geçerli olmalı")
	# Round 4 = reflection limiti aşımı (uyarı)
	m.iteration_round = 4
	var v: AIValidationResult = m.validate()
	if not v.has_warnings():
		return _fail(name, "round 4 uyarı üretmeli")
	return _ok(name)


static func _test_cell_message_roundtrip() -> Dictionary:
	var name := "CellMessage serialize round-trip"
	var m := AICellMessage.create(
		"Architect", "DeliveryManager", AICellMessage.MessageType.HANDOFF
	)
	m.subject = "TechDesign hazır"
	m.task_ref = "task_9"
	var dict: Dictionary = m.to_dict()
	var m2 := AICellMessage.new()
	m2.from_dict(dict)
	if m2.from_role != "Architect":
		return _fail(name, "from_role kayboldu")
	if m2.message_type != AICellMessage.MessageType.HANDOFF:
		return _fail(name, "message_type kayboldu")
	if m2.subject != "TechDesign hazır":
		return _fail(name, "subject kayboldu")
	return _ok(name)


static func _test_error_report_classification() -> Dictionary:
	var name := "ErrorReport sınıflandırma"
	var e := AIErrorReport.create(
		AIErrorReport.Category.MISSING_METHOD, "Invalid call to method 'foo'"
	)
	# MISSING_METHOD deterministik çözülebilir
	if not e.is_deterministic_fixable():
		return _fail(name, "MISSING_METHOD deterministik fixable olmalı")
	var e2 := AIErrorReport.create(
		AIErrorReport.Category.RUNTIME_LOGIC, "Yanlış sonuç"
	)
	if e2.is_deterministic_fixable():
		return _fail(name, "RUNTIME_LOGIC deterministik fixable olmamalı")
	# Retry limiti
	e.retry_count = 3
	if e.can_retry():
		return _fail(name, "retry 3'te can_retry false olmalı")
	return _ok(name)


static func _test_error_report_roundtrip() -> Dictionary:
	var name := "ErrorReport serialize round-trip"
	var e := AIErrorReport.create(
		AIErrorReport.Category.SHADER_ERROR, "Shader compile failed"
	)
	e.severity = AIErrorReport.Severity.HIGH
	e.file_path = "res://water.gdshader"
	e.line_number = 42
	var dict: Dictionary = e.to_dict()
	var e2 := AIErrorReport.new()
	e2.from_dict(dict)
	if e2.category != AIErrorReport.Category.SHADER_ERROR:
		return _fail(name, "category kayboldu")
	if e2.severity != AIErrorReport.Severity.HIGH:
		return _fail(name, "severity kayboldu")
	if e2.line_number != 42:
		return _fail(name, "line_number kayboldu")
	return _ok(name)


static func _test_cost_record_compute() -> Dictionary:
	var name := "CostRecord maliyet hesaplama"
	var c := AICostRecord.create("deepseek", "CodeEngineer")
	c.input_cost_usd = 0.02
	c.output_cost_usd = 0.03
	var total: float = c.compute_total()
	if abs(total - 0.05) > 0.0001:
		return _fail(name, "toplam maliyet yanlış: %s" % str(total))
	# Cache hit -> maliyet 0
	c.was_cache_hit = true
	if c.compute_total() != 0.0:
		return _fail(name, "cache hit'te maliyet 0 olmalı")
	return _ok(name)


static func _test_cost_record_roundtrip() -> Dictionary:
	var name := "CostRecord serialize round-trip"
	var c := AICostRecord.create("openai", "Architect")
	c.input_tokens = 500
	c.output_tokens = 800
	c.input_cost_usd = 0.01
	c.output_cost_usd = 0.02
	c.compute_total()
	var dict: Dictionary = c.to_dict()
	var c2 := AICostRecord.new()
	c2.from_dict(dict)
	if c2.provider != "openai":
		return _fail(name, "provider kayboldu")
	if c2.total_tokens() != 1300:
		return _fail(name, "token toplamı yanlış")
	if abs(c2.total_cost_usd - 0.03) > 0.0001:
		return _fail(name, "total_cost_usd kayboldu")
	return _ok(name)


static func _test_encrypted_key_integrity() -> Dictionary:
	var name := "EncryptedKeyEntry bütünlük kuralı"
	var e := AIEncryptedKeyEntry.create("deepseek")
	# Boş payload geçerli (henüz set edilmedi)
	if not e.is_valid():
		return _fail(name, "boş key entry geçerli olmalı")
	# Eksik iv/hmac = bütünlük ihlali
	e.ciphertext = "sifreli_veri"
	if e.is_valid():
		return _fail(name, "ciphertext var ama iv/hmac yok — reddedilmeli")
	# Tam payload geçerli
	e.set_encrypted_payload("sifreli", "iv_data", "hmac_data")
	if not e.is_valid():
		return _fail(name, "tam payload geçerli olmalı")
	if not e.has_payload():
		return _fail(name, "has_payload yanlış")
	return _ok(name)


static func _test_encrypted_key_roundtrip() -> Dictionary:
	var name := "EncryptedKeyEntry serialize round-trip"
	var e := AIEncryptedKeyEntry.create("anthropic")
	e.set_encrypted_payload("ct", "iv", "hm")
	e.mark_validated(true)
	var dict: Dictionary = e.to_dict()
	# Düz metin anahtar ASLA serialize edilmemeli
	if dict.has("api_key") or dict.has("plaintext"):
		return _fail(name, "düz metin anahtar serialize edildi — GÜVENLİK İHLALİ")
	var e2 := AIEncryptedKeyEntry.new()
	e2.from_dict(dict)
	if e2.provider != "anthropic":
		return _fail(name, "provider kayboldu")
	if e2.validation_status != "valid":
		return _fail(name, "validation_status kayboldu")
	if e2.ciphertext != "ct":
		return _fail(name, "ciphertext kayboldu")
	return _ok(name)


static func _test_edit_intent_protocol() -> Dictionary:
	var name := "EditIntent protokol eşlemesi"
	var fn_edit := AIEditIntent.create(
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION, "res://player.gd", "CodeEngineer"
	)
	if fn_edit.protocol() != "search_replace_block":
		return _fail(name, "MODIFY_FUNCTION protokolü yanlış")
	var replace := AIEditIntent.create(
		AIEditIntent.IntentType.REPLACE_FILE, "res://old.gd", "CodeEngineer"
	)
	# REPLACE_FILE HITL onayı gerektirir
	if not replace.requires_approval():
		return _fail(name, "REPLACE_FILE onay gerektirmeli")
	var add_new := AIEditIntent.create(
		AIEditIntent.IntentType.ADD_NEW_FILE, "res://new.gd", "CodeEngineer"
	)
	if add_new.requires_approval():
		return _fail(name, "ADD_NEW_FILE onay gerektirmemeli")
	if add_new.modifies_existing():
		return _fail(name, "ADD_NEW_FILE mevcut dosyayı değiştirmemeli")
	return _ok(name)


static func _test_edit_intent_surgical_limit() -> Dictionary:
	var name := "EditIntent cerrahi sınır kontrolü"
	var e := AIEditIntent.create(
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION, "res://big.gd", "CodeEngineer"
	)
	e.target_symbol = "process_data"
	e.expected_change_size = 10
	if e.exceeds_surgical_limit():
		return _fail(name, "10 satır sınırı aşmamalı")
	# 60 satır = cerrahi sınır aşımı (50)
	e.expected_change_size = 60
	if not e.exceeds_surgical_limit():
		return _fail(name, "60 satır sınırı aşmalı")
	var v: AIValidationResult = e.validate()
	if not v.has_warnings():
		return _fail(name, "sınır aşımı uyarı üretmeli")
	return _ok(name)
