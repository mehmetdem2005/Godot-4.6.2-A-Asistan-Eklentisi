@tool
class_name AIWorkspaceTabsTest
extends RefCounted

## Workspace — Kalan 6 Sekme Self-Test
##
## Sıkı testler: Overview, Plan Tree, Cost, Verifier, Checkpoints,
## Settings sekme modelleri. Her model salt-veridir; testler veri
## kayıt, sorgulama ve doğrulama mantığını denetler.


static func run_all() -> Array:
	var results: Array = []

	# Overview
	results.append(_b("Tabs: Overview", _test_overview_completion()))
	results.append(_b("Tabs: Overview", _test_overview_active()))
	results.append(_b("Tabs: Overview", _test_overview_problems()))
	results.append(_b("Tabs: Overview", _test_overview_clamp()))

	# Plan Tree
	results.append(_b("Tabs: PlanTree", _test_tree_add_root()))
	results.append(_b("Tabs: PlanTree", _test_tree_single_root()))
	results.append(_b("Tabs: PlanTree", _test_tree_orphan_rejected()))
	results.append(_b("Tabs: PlanTree", _test_tree_collapse()))
	results.append(_b("Tabs: PlanTree", _test_tree_progress()))

	# Cost
	results.append(_b("Tabs: Cost", _test_cost_totals()))
	results.append(_b("Tabs: Cost", _test_cost_cache_ratio()))
	results.append(_b("Tabs: Cost", _test_cost_budget_status()))
	results.append(_b("Tabs: Cost", _test_cost_unlimited()))
	results.append(_b("Tabs: Cost", _test_cost_by_provider()))

	# Verifier
	results.append(_b("Tabs: Verifier", _test_verifier_counts()))
	results.append(_b("Tabs: Verifier", _test_verifier_all_passing()))
	results.append(_b("Tabs: Verifier", _test_verifier_failure_details()))

	# Checkpoints
	results.append(_b("Tabs: Checkpoints", _test_checkpoint_add()))
	results.append(_b("Tabs: Checkpoints", _test_checkpoint_duplicate()))
	results.append(_b("Tabs: Checkpoints", _test_checkpoint_restore()))
	results.append(_b("Tabs: Checkpoints", _test_checkpoint_no_selection()))

	# Settings
	results.append(_b("Tabs: Settings", _test_settings_valid_change()))
	results.append(_b("Tabs: Settings", _test_settings_invalid_rejected()))
	results.append(_b("Tabs: Settings", _test_settings_live_safety()))
	results.append(_b("Tabs: Settings", _test_settings_roundtrip()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# OVERVIEW
# ============================================================

static func _test_overview_completion() -> Dictionary:
	var name := "Overview tamamlanma oranı"
	var m := AIOverviewModel.new()
	m.update_task_counts(10, 4, 1)
	if absf(m.completion_ratio() - 0.4) > 0.001:
		return _fail(name, "10'da 4 tamamlanan %40 olmalı")
	# Sıfır görev — sıfır oran
	var empty := AIOverviewModel.new()
	if empty.completion_ratio() != 0.0:
		return _fail(name, "sıfır görevde oran 0 olmalı")
	return _ok(name)


static func _test_overview_active() -> Dictionary:
	var name := "Overview aktiflik durumu"
	var m := AIOverviewModel.new()
	# IDLE — aktif değil
	m.set_status(AIOverviewModel.SystemStatus.IDLE)
	if m.is_active():
		return _fail(name, "IDLE aktif olmamalı")
	# EXECUTING — aktif
	m.set_status(AIOverviewModel.SystemStatus.EXECUTING)
	if not m.is_active():
		return _fail(name, "EXECUTING aktif olmalı")
	return _ok(name)


static func _test_overview_problems() -> Dictionary:
	var name := "Overview sorun tespiti"
	var m := AIOverviewModel.new()
	# Başarısız task — sorun var
	m.update_task_counts(5, 2, 1)
	if not m.has_problems():
		return _fail(name, "başarısız task sorun sayılmalı")
	# Temiz — sorun yok
	var clean := AIOverviewModel.new()
	clean.update_task_counts(5, 3, 0)
	clean.set_status(AIOverviewModel.SystemStatus.EXECUTING)
	if clean.has_problems():
		return _fail(name, "temiz durumda sorun olmamalı")
	return _ok(name)


static func _test_overview_clamp() -> Dictionary:
	var name := "Overview sayaç sınırlama"
	var m := AIOverviewModel.new()
	# completed > total — clamp edilmeli
	m.update_task_counts(10, 15, 3)
	if m.completed_tasks > m.total_tasks:
		return _fail(name, "completed total'ı aşmamalı (clamp)")
	return _ok(name)


# ============================================================
# PLAN TREE
# ============================================================

static func _test_tree_add_root() -> Dictionary:
	var name := "PlanTree kök + çocuk ekleme"
	var m := AIPlanTreeModel.new()
	var root := m.add_node("goal", "", "Hedef", AIPlanTreeModel.NodeLevel.GOAL)
	if root == null:
		return _fail(name, "kök eklenemedi")
	var child := m.add_node(
		"epic", "goal", "Epik", AIPlanTreeModel.NodeLevel.EPIC
	)
	if child == null:
		return _fail(name, "çocuk eklenemedi")
	if child.depth != 1:
		return _fail(name, "çocuk derinliği 1 olmalı")
	return _ok(name)


static func _test_tree_single_root() -> Dictionary:
	var name := "PlanTree tek kök kuralı"
	var m := AIPlanTreeModel.new()
	m.add_node("root1", "", "İlk", AIPlanTreeModel.NodeLevel.GOAL)
	# İkinci kök reddedilmeli
	var second := m.add_node(
		"root2", "", "İkinci", AIPlanTreeModel.NodeLevel.GOAL
	)
	if second != null:
		return _fail(name, "ikinci kök reddedilmeli")
	return _ok(name)


static func _test_tree_orphan_rejected() -> Dictionary:
	var name := "PlanTree öksüz düğüm reddi"
	var m := AIPlanTreeModel.new()
	m.add_node("goal", "", "Hedef", AIPlanTreeModel.NodeLevel.GOAL)
	# Var olmayan parent
	var orphan := m.add_node(
		"task", "olmayan_parent", "Görev", AIPlanTreeModel.NodeLevel.TASK
	)
	if orphan != null:
		return _fail(name, "olmayan parent'lı düğüm reddedilmeli")
	return _ok(name)


static func _test_tree_collapse() -> Dictionary:
	var name := "PlanTree katlama"
	var m := AIPlanTreeModel.new()
	m.add_node("goal", "", "Hedef", AIPlanTreeModel.NodeLevel.GOAL)
	m.add_node("epic", "goal", "Epik", AIPlanTreeModel.NodeLevel.EPIC)
	m.add_node("task", "epic", "Görev", AIPlanTreeModel.NodeLevel.TASK)
	# Açıkken 3 görünür
	if m.visible_nodes().size() != 3:
		return _fail(name, "açık ağaçta 3 düğüm görünmeli")
	# Epic kapat — task gizlenir
	m.toggle_node("epic")
	if m.visible_nodes().size() != 2:
		return _fail(name, "kapalı düğüm çocuğunu gizlemeli")
	# Tekrar aç
	m.toggle_node("epic")
	if m.visible_nodes().size() != 3:
		return _fail(name, "açılınca tekrar görünmeli")
	return _ok(name)


static func _test_tree_progress() -> Dictionary:
	var name := "PlanTree ilerleme"
	var m := AIPlanTreeModel.new()
	m.add_node("goal", "", "Hedef", AIPlanTreeModel.NodeLevel.GOAL)
	m.add_node("t1", "goal", "G1", AIPlanTreeModel.NodeLevel.TASK)
	m.add_node("t2", "goal", "G2", AIPlanTreeModel.NodeLevel.TASK)
	# 3 düğümden 0 done — ilerleme 0
	if m.progress() != 0.0:
		return _fail(name, "hiçbiri done değilken ilerleme 0")
	m.set_node_status("t1", "done")
	# 3 düğümden 1 done
	if absf(m.progress() - (1.0 / 3.0)) > 0.001:
		return _fail(name, "1/3 done ilerleme yanlış")
	return _ok(name)


# ============================================================
# COST
# ============================================================

static func _test_cost_totals() -> Dictionary:
	var name := "Cost toplamlar"
	var m := AICostModel.new(1.0)
	m.record("deepseek", 0.3, 100, 50)
	m.record("openai", 0.2, 80, 40)
	if absf(m.total_cost() - 0.5) > 0.001:
		return _fail(name, "toplam maliyet 0.5 olmalı")
	if m.total_tokens() != 270:
		return _fail(name, "toplam token 270 olmalı")
	if m.call_count() != 2:
		return _fail(name, "çağrı sayısı 2 olmalı")
	return _ok(name)


static func _test_cost_cache_ratio() -> Dictionary:
	var name := "Cost cache oranı"
	var m := AICostModel.new()
	m.record("x", 0.1, 10, 5, false)
	m.record("x", 0.0, 10, 5, true)
	if absf(m.cache_hit_ratio() - 0.5) > 0.001:
		return _fail(name, "2 çağrıdan 1 cache %50 olmalı")
	return _ok(name)


static func _test_cost_budget_status() -> Dictionary:
	var name := "Cost bütçe durumu"
	var m := AICostModel.new(1.0)
	m.record("x", 0.5, 1, 1)
	# %50 — healthy
	if m.budget_status() != AICostModel.BudgetStatus.HEALTHY:
		return _fail(name, "%50 kullanım HEALTHY olmalı")
	m.record("x", 0.4, 1, 1)
	# %90 — warning
	if m.budget_status() != AICostModel.BudgetStatus.WARNING:
		return _fail(name, "%90 kullanım WARNING olmalı")
	m.record("x", 0.3, 1, 1)
	# %120 — exceeded
	if not m.is_over_budget():
		return _fail(name, "%120 kullanım bütçe aşımı olmalı")
	return _ok(name)


static func _test_cost_unlimited() -> Dictionary:
	var name := "Cost limitsiz bütçe"
	var m := AICostModel.new(0.0)
	m.record("x", 999.0, 1, 1)
	# Limitsiz — her zaman healthy
	if m.budget_status() != AICostModel.BudgetStatus.HEALTHY:
		return _fail(name, "limitsiz bütçe hep HEALTHY olmalı")
	return _ok(name)


static func _test_cost_by_provider() -> Dictionary:
	var name := "Cost sağlayıcı dağılımı"
	var m := AICostModel.new()
	m.record("deepseek", 0.3, 1, 1)
	m.record("deepseek", 0.2, 1, 1)
	m.record("openai", 0.4, 1, 1)
	var by_provider: Dictionary = m.cost_by_provider()
	if absf(float(by_provider.get("deepseek", 0.0)) - 0.5) > 0.001:
		return _fail(name, "deepseek toplamı 0.5 olmalı")
	return _ok(name)


# ============================================================
# VERIFIER
# ============================================================

static func _test_verifier_counts() -> Dictionary:
	var name := "Verifier sayaçlar"
	var m := AIVerifierModel.new()
	m.record("a.gd", AIVerifierModel.VerifyOutcome.PASSED, PackedStringArray())
	m.record("b.gd", AIVerifierModel.VerifyOutcome.FAILED,
		PackedStringArray(["hata1", "hata2"]))
	if m.passed_count() != 1:
		return _fail(name, "1 geçen olmalı")
	if m.failed_count() != 1:
		return _fail(name, "1 başarısız olmalı")
	if m.total_issues() != 2:
		return _fail(name, "toplam 2 sorun olmalı")
	return _ok(name)


static func _test_verifier_all_passing() -> Dictionary:
	var name := "Verifier hepsi geçti"
	var m := AIVerifierModel.new()
	m.record("a.gd", AIVerifierModel.VerifyOutcome.PASSED, PackedStringArray())
	m.record("b.gd", AIVerifierModel.VerifyOutcome.PASSED, PackedStringArray())
	if not m.all_passing():
		return _fail(name, "hepsi geçince all_passing true olmalı")
	# Boş model — all_passing false
	var empty := AIVerifierModel.new()
	if empty.all_passing():
		return _fail(name, "boş modelde all_passing false olmalı")
	return _ok(name)


static func _test_verifier_failure_details() -> Dictionary:
	var name := "Verifier başarısızlık detayı"
	var m := AIVerifierModel.new()
	m.record("bad.gd", AIVerifierModel.VerifyOutcome.FAILED,
		PackedStringArray(["sözdizimi hatası"]))
	var details: Array = m.failure_details()
	if details.size() != 1:
		return _fail(name, "1 başarısızlık detayı olmalı")
	if str(details[0]["file"]) != "bad.gd":
		return _fail(name, "başarısız dosya adı yanlış")
	return _ok(name)


# ============================================================
# CHECKPOINTS
# ============================================================

static func _test_checkpoint_add() -> Dictionary:
	var name := "Checkpoint ekleme"
	var m := AICheckpointsModel.new()
	var cp := m.add_checkpoint(
		"cp1", "Başlangıç", AICheckpointsModel.CheckpointKind.AUTO
	)
	if cp == null:
		return _fail(name, "checkpoint eklenemedi")
	if cp.sequence != 1:
		return _fail(name, "ilk checkpoint sıra 1 olmalı")
	if m.count() != 1:
		return _fail(name, "count 1 olmalı")
	return _ok(name)


static func _test_checkpoint_duplicate() -> Dictionary:
	var name := "Checkpoint çift id reddi"
	var m := AICheckpointsModel.new()
	m.add_checkpoint("cp1", "İlk", AICheckpointsModel.CheckpointKind.AUTO)
	var dup := m.add_checkpoint(
		"cp1", "Tekrar", AICheckpointsModel.CheckpointKind.MANUAL
	)
	if dup != null:
		return _fail(name, "çift id reddedilmeli")
	return _ok(name)


static func _test_checkpoint_restore() -> Dictionary:
	var name := "Checkpoint geri yükleme"
	var m := AICheckpointsModel.new()
	m.add_checkpoint("cp1", "Nokta", AICheckpointsModel.CheckpointKind.MANUAL)
	if not m.select("cp1"):
		return _fail(name, "checkpoint seçilemedi")
	var restore: Dictionary = m.request_restore()
	if not restore["ok"]:
		return _fail(name, "geçerli seçim geri yüklenebilmeli")
	if str(restore["checkpoint_id"]) != "cp1":
		return _fail(name, "geri yükleme id'si yanlış")
	return _ok(name)


static func _test_checkpoint_no_selection() -> Dictionary:
	var name := "Checkpoint seçimsiz geri yükleme"
	var m := AICheckpointsModel.new()
	m.add_checkpoint("cp1", "Nokta", AICheckpointsModel.CheckpointKind.AUTO)
	# Seçim yapılmadan geri yükleme — reddedilmeli
	var restore: Dictionary = m.request_restore()
	if restore["ok"]:
		return _fail(name, "seçimsiz geri yükleme reddedilmeli")
	return _ok(name)


# ============================================================
# SETTINGS
# ============================================================

static func _test_settings_valid_change() -> Dictionary:
	var name := "Settings geçerli değişiklik"
	var m := AISettingsModel.new()
	if not m.set_llm_mode(AISettingsModel.LLMMode.PROFESSIONAL):
		return _fail(name, "geçerli LLM modu kabul edilmeli")
	if not m.set_budget_limit(10.0):
		return _fail(name, "geçerli bütçe kabul edilmeli")
	if not m.set_mobile_tier(2):
		return _fail(name, "geçerli tier kabul edilmeli")
	return _ok(name)


static func _test_settings_invalid_rejected() -> Dictionary:
	var name := "Settings geçersiz değer reddi"
	var m := AISettingsModel.new()
	# Geçersiz LLM modu
	if m.set_llm_mode(999):
		return _fail(name, "geçersiz LLM modu reddedilmeli")
	# Negatif bütçe
	if m.set_budget_limit(-5.0):
		return _fail(name, "negatif bütçe reddedilmeli")
	# Aralık dışı tier
	if m.set_mobile_tier(7):
		return _fail(name, "aralık dışı tier reddedilmeli")
	return _ok(name)


static func _test_settings_live_safety() -> Dictionary:
	var name := "Settings canlı mod güvenliği"
	var m := AISettingsModel.new()
	# Otonom + canlı + auto_checkpoint kapalı — güvensiz
	m.set_automation_level(AISettingsModel.AutomationLevel.AUTONOMOUS)
	m.set_live_mode(true)
	m.set_auto_checkpoint(false)
	if m.is_live_safe():
		return _fail(name, "otonom+canlı+checkpoint kapalı güvensiz olmalı")
	# auto_checkpoint açılınca güvenli
	m.set_auto_checkpoint(true)
	if not m.is_live_safe():
		return _fail(name, "otomatik checkpoint güvenliği sağlamalı")
	return _ok(name)


static func _test_settings_roundtrip() -> Dictionary:
	var name := "Settings sözlük round-trip"
	var m := AISettingsModel.new()
	m.set_llm_mode(AISettingsModel.LLMMode.QUALITY)
	m.set_budget_limit(7.5)
	m.set_mobile_tier(0)
	var data: Dictionary = m.to_dict()
	# Yeni modele yükle
	var loaded := AISettingsModel.new()
	loaded.from_dict(data)
	if loaded.llm_mode != AISettingsModel.LLMMode.QUALITY:
		return _fail(name, "LLM modu round-trip'te korunmadı")
	if absf(loaded.budget_limit_usd - 7.5) > 0.001:
		return _fail(name, "bütçe round-trip'te korunmadı")
	if loaded.mobile_tier != 0:
		return _fail(name, "tier round-trip'te korunmadı")
	return _ok(name)
