@tool
class_name AIAgentCoordinationRuntimeTest
extends RefCounted

## Faz 11 — mailbox, event bus, scoped memory, resource lock ve bounded
## coordination runtime için 30 deterministik sözleşme testi.


static func run_all() -> Array:
	var results: Array = []
	results.append_array(_message_tests())
	results.append_array(_mailbox_tests())
	results.append_array(_event_bus_tests())
	results.append_array(_memory_tests())
	results.append_array(_lock_tests())
	results.append_array(_runtime_tests())
	return results


static func build_report() -> Dictionary:
	var results: Array = run_all()
	var passed: int = 0
	var failed: int = 0
	var lines := PackedStringArray(["=== Agent Coordination Runtime Test Sonuçları ==="])
	var batch: String = ""
	for result in results:
		if str(result["batch"]) != batch:
			batch = str(result["batch"])
			lines.append("--- %s ---" % batch)
		if bool(result["ok"]):
			passed += 1
			lines.append("  ✓ " + str(result["name"]))
		else:
			failed += 1
			lines.append("  ✗ %s — %s" % [result["name"], result["reason"]])
	lines.append("--- %d geçti, %d başarısız (toplam %d) ---" % [
		passed, failed, results.size()
	])
	var report: String = "\n".join(lines)
	print(report)
	return {"passed": passed, "failed": failed, "report": report}


static func _message_tests() -> Array:
	var chart := AIAgentOrgChart.new()
	var valid := _message(
		"m-1", "chief_orchestrator", "gameplay_engineer", "assignment"
	)
	var invalid_role := _message(
		"m-2", "unknown", "gameplay_engineer", "assignment"
	)
	var self_message := _message(
		"m-3", "gameplay_engineer", "gameplay_engineer", "status"
	)
	var ack_message := _message(
		"m-4", "chief_orchestrator", "gameplay_engineer", "assignment", true
	)
	var expired := _message(
		"m-5", "chief_orchestrator", "gameplay_engineer", "assignment"
	)
	expired.expires_at_ms = expired.created_at_ms
	return [
		_b("Mesaj", _check("Geçerli ajan mesajı", bool(valid.validate(chart)["ok"]))),
		_b("Mesaj", _check("Bilinmeyen rol reddedilir", not bool(invalid_role.validate(chart)["ok"]))),
		_b("Mesaj", _check("Self-send status reddedilir", not bool(self_message.validate(chart)["ok"]))),
		_b("Mesaj", _check("ACK yalnız bir kez kabul edilir", ack_message.acknowledge() and not ack_message.acknowledge())),
		_b("Mesaj", _check("Süresi dolan mesaj tespit edilir", expired.is_expired(expired.created_at_ms))),
	]


static func _mailbox_tests() -> Array:
	var box := AIAgentMailbox.new("gameplay_engineer", 3)
	var low := _message("mb-1", "chief_orchestrator", "gameplay_engineer", "status")
	low.priority = "low"
	var critical := _message("mb-2", "chief_orchestrator", "gameplay_engineer", "assignment")
	critical.priority = "critical"
	box.enqueue(low)
	box.enqueue(critical)
	var priority_ok: bool = box.peek() == critical
	var duplicate_ok: bool = not bool(box.enqueue(critical).get("ok", true))
	var wrong := _message("mb-3", "chief_orchestrator", "ui_ux_engineer", "status")
	var wrong_ok: bool = not bool(box.enqueue(wrong).get("ok", true))

	var capacity_box := AIAgentMailbox.new("gameplay_engineer", 2)
	var a := _message("mb-4", "chief_orchestrator", "gameplay_engineer", "status")
	a.priority = "low"
	var b := _message("mb-5", "chief_orchestrator", "gameplay_engineer", "status")
	b.priority = "normal"
	var c := _message("mb-6", "chief_orchestrator", "gameplay_engineer", "assignment")
	c.priority = "critical"
	capacity_box.enqueue(a)
	capacity_box.enqueue(b)
	var capacity_ok: bool = bool(capacity_box.enqueue(c).get("ok", false))
	var ids: Array = []
	while capacity_box.size() > 0:
		ids.append((capacity_box.dequeue() as AIAgentMessage).message_id)
	capacity_ok = capacity_ok and ids.has("mb-6") and not ids.has("mb-4")

	var expiry_box := AIAgentMailbox.new("gameplay_engineer")
	var old := _message("mb-7", "chief_orchestrator", "gameplay_engineer", "status")
	expiry_box.enqueue(old)
	var purged: int = expiry_box.purge_expired(old.expires_at_ms)
	return [
		_b("Mailbox", _check("Öncelik sırası critical önce", priority_ok)),
		_b("Mailbox", _check("Tekrarlı message_id reddedilir", duplicate_ok)),
		_b("Mailbox", _check("Yanlış alıcı mailbox'a giremez", wrong_ok)),
		_b("Mailbox", _check("Critical mesaj düşük önceliği tahliye eder", capacity_ok)),
		_b("Mailbox", _check("TTL purge mesajı temizler", purged == 1 and expiry_box.size() == 0)),
	]


static func _event_bus_tests() -> Array:
	var bus := AIAgentEventBus.new(8)
	bus.subscribe("quality", ["work.*"])
	bus.publish("message.status", "chief_orchestrator")
	bus.publish("work.started", "gameplay_engineer", {"task": "1"})
	var first: Array = bus.poll("quality")
	var wildcard_ok: bool = first.size() == 1 and str(first[0]["topic"]) == "work.started"
	var cursor_ok: bool = bus.poll("quality").is_empty()

	bus.subscribe("all", ["*"])
	for index in 3:
		bus.publish("work.event", "gameplay_engineer", {"index": index})
	var limited: Array = bus.poll("all", 1)
	var remainder: Array = bus.poll("all", 8)
	var limit_ok: bool = limited.size() == 1 and remainder.size() == 2

	var bounded := AIAgentEventBus.new(8)
	for index in 12:
		bounded.publish("audit.event", "security_reviewer", {"index": index})
	var stats: Dictionary = bounded.stats()
	var bounded_ok: bool = int(stats["retained_events"]) == 8 and int(stats["dropped"]) == 4
	return [
		_b("EventBus", _check("Wildcard topic subscription çalışır", wildcard_ok)),
		_b("EventBus", _check("Cursor aynı olayı ikinci kez döndürmez", cursor_ok)),
		_b("EventBus", _check("Poll limit kalan olayları korur", limit_ok)),
		_b("EventBus", _check("Event journal bounded kalır", bounded_ok)),
	]


static func _memory_tests() -> Array:
	var chart := AIAgentOrgChart.new()
	var memory := AIAgentScopedMemory.new(chart)
	memory.remember("gameplay_engineer", "özel combat kararı", "private", ["combat"])
	var private_owner: bool = memory.recall("gameplay_engineer", "combat").size() == 1
	var private_other: bool = memory.recall("ui_ux_engineer", "combat").is_empty()

	memory.remember("gameplay_engineer", "technical ortak karar", "department", ["shared"])
	var same_department: bool = memory.recall("ui_ux_engineer", "ortak").size() == 1
	var other_department: bool = memory.recall("code_reviewer", "ortak").is_empty()

	memory.remember("security_reviewer", "organizasyon güvenlik kuralı", "organization", ["security-policy"])
	var org_visible: bool = memory.recall("android_release_engineer", "güvenlik").size() == 1
	var tag_query: bool = memory.recall("android_release_engineer", "security-policy").size() == 1
	var forgotten: int = memory.forget_owner("security_reviewer")
	return [
		_b("Bellek", _check("Private bellek sahibine görünür", private_owner)),
		_b("Bellek", _check("Private bellek diğer ajana kapalı", private_other)),
		_b("Bellek", _check("Department bellek aynı departmana açık", same_department)),
		_b("Bellek", _check("Department bellek başka departmana kapalı", other_department)),
		_b("Bellek", _check("Organization/tag recall ve forget çalışır", org_visible and tag_query and forgotten == 1)),
	]


static func _lock_tests() -> Array:
	var locks := AIAgentResourceLockManager.new()
	var read_a: Dictionary = locks.acquire_read("res://game/player.gd", "gameplay_engineer")
	var read_b: Dictionary = locks.acquire_read("res://game/player.gd", "code_reviewer")
	var shared_ok: bool = bool(read_a["ok"]) and bool(read_b["ok"])
	var write_conflict: bool = not bool(locks.acquire_write(
		"res://game/player.gd", "gameplay_engineer"
	).get("ok", true))
	locks.release("res://game/player.gd", "code_reviewer")
	var upgrade_ok: bool = bool(locks.acquire_write(
		"res://game/player.gd", "gameplay_engineer"
	).get("ok", false))
	var read_blocked: bool = not bool(locks.acquire_read(
		"res://game/player.gd", "test_engineer"
	).get("ok", true))
	var renew_ok: bool = locks.renew("res://game/player.gd", "gameplay_engineer")
	var release_ok: bool = locks.release(
		"res://game/player.gd", "gameplay_engineer"
	) and not locks.owner_holds("res://game/player.gd", "gameplay_engineer")
	var unsafe_ok: bool = not bool(locks.acquire_write(
		"user://outside.gd", "gameplay_engineer"
	).get("ok", true))
	return [
		_b("Kilit", _check("Birden fazla read lock paylaşılır", shared_ok)),
		_b("Kilit", _check("Yabancı reader varken write reddedilir", write_conflict)),
		_b("Kilit", _check("Tek reader kendi write lock'una yükselir", upgrade_ok)),
		_b("Kilit", _check("Writer yabancı read lock'u engeller", read_blocked)),
		_b("Kilit", _check("Lease renew ve release çalışır", renew_ok and release_ok)),
		_b("Kilit", _check("res:// dışı resource reddedilir", unsafe_ok)),
	]


static func _runtime_tests() -> Array:
	var chart := AIAgentOrgChart.new()
	var router := AIAgentTaskRouter.new(chart)
	var runtime := AIAgentCoordinationRuntime.new(chart)
	var init_ok: bool = int(runtime.stats()["roles"]) == 25

	var order := router.route({
		"id": "runtime-1",
		"title": "Player inventory gameplay kodu",
		"target_file": "res://game/inventory.gd",
	})
	var dispatched: Dictionary = runtime.dispatch_work_order(order)
	var dispatch_ok: bool = (
		bool(dispatched.get("ok", false))
		and runtime.mailbox(order.primary_role_id).size() == 1
		and runtime.mailbox("code_reviewer").size() == 1
		and runtime.mailbox("test_engineer").size() == 1
	)

	runtime.set_department_limit("technical", 1)
	var reserve_one: bool = bool(runtime.reserve_work(
		order, "res://game/inventory.gd"
	).get("ok", false))
	var order_two := router.route({
		"id": "runtime-2",
		"title": "Combat gameplay kodu",
		"target_file": "res://game/combat.gd",
	})
	var bounded_ok: bool = not bool(runtime.reserve_work(
		order_two, "res://game/combat.gd"
	).get("ok", true))

	var lock_conflict := router.route({
		"id": "runtime-3",
		"title": "Player dosyasına scene node bağla",
		"target_file": "res://game/inventory.gd",
	})
	# Farklı departmanda olsa bile aynı resource write lock'ı çakışır.
	var resource_conflict: bool = not bool(runtime.reserve_work(
		lock_conflict, "res://game/inventory.gd"
	).get("ok", true))

	var complete_ok: bool = runtime.complete_work(order, "Inventory görevi tamamlandı")
	complete_ok = (
		complete_ok
		and not runtime.locks.owner_holds(
			"res://game/inventory.gd", order.primary_role_id
		)
		and runtime.memory.recall("ui_ux_engineer", "Inventory").size() == 1
	)
	return [
		_b("Runtime", _check("25 rol için mailbox oluşturulur", init_ok)),
		_b("Runtime", _check("WorkOrder assignment/review mesajları dağıtılır", dispatch_ok)),
		_b("Runtime", _check("Department concurrency sınırı uygulanır", reserve_one and bounded_ok)),
		_b("Runtime", _check("Aynı resource için çapraz ajan conflict engellenir", resource_conflict)),
		_b("Runtime", _check("Complete lock bırakır ve department memory yazar", complete_ok)),
	]


static func _message(
	id: String,
	sender: String,
	recipient: String,
	kind: String,
	ack_required: bool = false
) -> AIAgentMessage:
	return AIAgentMessage.create(
		id, sender, recipient, kind, "Konu", "Gövde", {},
		"normal", "corr", ack_required
	)


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _check(name: String, ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "name": name, "reason": reason if not ok else ""}
