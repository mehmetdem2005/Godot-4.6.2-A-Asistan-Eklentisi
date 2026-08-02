@tool
class_name AIAgentResourceLockManager
extends RefCounted

## Aynı dosya/resource üzerinde ajan çakışmasını önleyen lease tabanlı
## read/write lock yöneticisi. Gerçek dosya yazmaz; yalnız rezervasyon yapar.

const DEFAULT_LEASE_MS: int = 5 * 60 * 1000
const MAX_LEASE_MS: int = 30 * 60 * 1000

var _locks: Dictionary = {}
var _acquired_count: int = 0
var _conflict_count: int = 0
var _expired_count: int = 0


func acquire_read(
	resource_path: String,
	owner_role_id: String,
	lease_ms: int = DEFAULT_LEASE_MS
) -> Dictionary:
	return _acquire(resource_path, owner_role_id, "read", lease_ms)


func acquire_write(
	resource_path: String,
	owner_role_id: String,
	lease_ms: int = DEFAULT_LEASE_MS
) -> Dictionary:
	return _acquire(resource_path, owner_role_id, "write", lease_ms)


func release(resource_path: String, owner_role_id: String) -> bool:
	var path: String = _normalize_path(resource_path)
	if path.is_empty() or not _locks.has(path):
		return false
	var state: Dictionary = _locks[path]
	var changed: bool = false
	if str(state.get("writer", "")) == owner_role_id:
		state["writer"] = ""
		state["writer_expires_at_ms"] = 0
		changed = true
	var readers: Dictionary = state.get("readers", {})
	if readers.erase(owner_role_id):
		changed = true
	if str(state.get("writer", "")).is_empty() and readers.is_empty():
		_locks.erase(path)
	else:
		state["readers"] = readers
		_locks[path] = state
	return changed


func renew(
	resource_path: String,
	owner_role_id: String,
	lease_ms: int = DEFAULT_LEASE_MS
) -> bool:
	_cleanup_expired()
	var path: String = _normalize_path(resource_path)
	if path.is_empty() or not _locks.has(path):
		return false
	var expires: int = Time.get_ticks_msec() + _lease(lease_ms)
	var state: Dictionary = _locks[path]
	if str(state.get("writer", "")) == owner_role_id:
		state["writer_expires_at_ms"] = expires
		_locks[path] = state
		return true
	var readers: Dictionary = state.get("readers", {})
	if readers.has(owner_role_id):
		readers[owner_role_id] = expires
		state["readers"] = readers
		_locks[path] = state
		return true
	return false


func owner_holds(resource_path: String, owner_role_id: String) -> bool:
	_cleanup_expired()
	var path: String = _normalize_path(resource_path)
	if path.is_empty() or not _locks.has(path):
		return false
	var state: Dictionary = _locks[path]
	return (
		str(state.get("writer", "")) == owner_role_id
		or (state.get("readers", {}) as Dictionary).has(owner_role_id)
	)


func snapshot() -> Array:
	_cleanup_expired()
	var out: Array = []
	for path_value in _locks.keys():
		var path: String = str(path_value)
		var state: Dictionary = _locks[path]
		out.append({
			"resource_path": path,
			"writer": str(state.get("writer", "")),
			"writer_expires_at_ms": int(state.get("writer_expires_at_ms", 0)),
			"readers": (state.get("readers", {}) as Dictionary).duplicate(),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["resource_path"]) < str(b["resource_path"])
	)
	return out


func stats() -> Dictionary:
	_cleanup_expired()
	return {
		"resources": _locks.size(),
		"acquired": _acquired_count,
		"conflicts": _conflict_count,
		"expired": _expired_count,
	}


func _acquire(
	resource_path: String,
	owner_role_id: String,
	mode: String,
	lease_ms: int
) -> Dictionary:
	_cleanup_expired()
	var path: String = _normalize_path(resource_path)
	var owner: String = owner_role_id.strip_edges()
	if path.is_empty():
		return {"ok": false, "reason": "güvensiz veya boş resource path"}
	if owner.is_empty():
		return {"ok": false, "reason": "owner boş"}
	var expires: int = Time.get_ticks_msec() + _lease(lease_ms)
	var state: Dictionary = _locks.get(path, {
		"writer": "",
		"writer_expires_at_ms": 0,
		"readers": {},
	})
	var writer: String = str(state.get("writer", ""))
	var readers: Dictionary = state.get("readers", {})
	if mode == "read":
		if not writer.is_empty() and writer != owner:
			_conflict_count += 1
			return {"ok": false, "reason": "write lock başka ajanda", "holder": writer}
		readers[owner] = expires
		state["readers"] = readers
	else:
		if not writer.is_empty() and writer != owner:
			_conflict_count += 1
			return {"ok": false, "reason": "write lock başka ajanda", "holder": writer}
		var foreign_readers: Array = []
		for reader_value in readers.keys():
			var reader: String = str(reader_value)
			if reader != owner:
				foreign_readers.append(reader)
		if not foreign_readers.is_empty():
			_conflict_count += 1
			return {
				"ok": false,
				"reason": "read lock başka ajanlarda",
				"holders": foreign_readers,
			}
		readers.erase(owner)
		state["readers"] = readers
		state["writer"] = owner
		state["writer_expires_at_ms"] = expires
	_locks[path] = state
	_acquired_count += 1
	return {"ok": true, "reason": "", "resource_path": path, "mode": mode}


func _cleanup_expired(now_ms: int = -1) -> int:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	var removed: int = 0
	for path_value in _locks.keys().duplicate():
		var path: String = str(path_value)
		var state: Dictionary = _locks[path]
		if (
			not str(state.get("writer", "")).is_empty()
			and int(state.get("writer_expires_at_ms", 0)) <= now
		):
			state["writer"] = ""
			state["writer_expires_at_ms"] = 0
			removed += 1
		var readers: Dictionary = state.get("readers", {})
		for reader_value in readers.keys().duplicate():
			if int(readers[reader_value]) <= now:
				readers.erase(reader_value)
				removed += 1
		state["readers"] = readers
		if str(state.get("writer", "")).is_empty() and readers.is_empty():
			_locks.erase(path)
		else:
			_locks[path] = state
	_expired_count += removed
	return removed


func _normalize_path(resource_path: String) -> String:
	var path: String = resource_path.strip_edges().replace("\\", "/").simplify_path()
	if not path.begins_with("res://"):
		return ""
	if path.contains("..") or path.contains(":") and not path.begins_with("res://"):
		return ""
	return path


func _lease(lease_ms: int) -> int:
	return clampi(lease_ms, 1000, MAX_LEASE_MS)
