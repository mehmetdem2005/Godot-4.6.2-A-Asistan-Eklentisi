@tool
class_name AIVCSTree
extends AIContractBase

## VCSTree — dosya ağacı düğümü (Git'in tree mantığı).
##
## Bir commit anındaki tüm dosya yapısını temsil eder. Her girdi ya bir blob
## (dosya) ya da başka bir tree'dir (alt klasör). Tree'nin kendisi de hash'lenir.

## Bir tree girdisi — dosya veya alt klasör.
## entry yapısı: {path: String, type: "blob"|"tree", hash: String}

# --- Kimlik ---
var hash: String = ""                ## Tree'nin SHA-256 hash'i
var entries: Array = []              ## Girdi listesi (her biri Dictionary)


func contract_type() -> String:
	return "VCSTree"


## Boş bir tree oluşturur (factory).
static func create() -> AIVCSTree:
	return AIVCSTree.new()


## Tree'ye bir dosya (blob) girdisi ekler.
func add_blob(path: String, blob_hash: String) -> void:
	entries.append({"path": path, "type": "blob", "hash": blob_hash})


## Tree'ye bir alt klasör (tree) girdisi ekler.
func add_subtree(path: String, tree_hash: String) -> void:
	entries.append({"path": path, "type": "tree", "hash": tree_hash})


## Tüm girdilerin içeriğinden tree hash'ini hesaplar.
## Girdiler path'e göre sıralanır — deterministik hash garantisi.
func compute_hash() -> String:
	var sorted_entries: Array = entries.duplicate()
	sorted_entries.sort_custom(func(a, b): return a["path"] < b["path"])

	var canonical: String = ""
	for e in sorted_entries:
		canonical += "%s %s %s\n" % [e["type"], e["hash"], e["path"]]

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	hash = ctx.finish().hex_encode()
	return hash


## Belirli bir yoldaki girdiyi bulur. Yoksa boş Dictionary döner.
func find_entry(path: String) -> Dictionary:
	for e in entries:
		if e["path"] == path:
			return e
	return {}


## Tree'deki toplam girdi sayısı.
func entry_count() -> int:
	return entries.size()


func _to_dict_impl() -> Dictionary:
	return {
		"hash": hash,
		"entries": entries,
	}


func _from_dict_impl(data: Dictionary) -> void:
	hash = data.get("hash", "")
	entries = data.get("entries", [])


func _validate_impl(result: AIValidationResult) -> void:
	# Her girdi geçerli yapıda mı
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		if not e.has("path") or not e.has("type") or not e.has("hash"):
			result.add_error("Tree girdisi #%d eksik alan içeriyor" % i)
			continue
		require_in_set(result, e["type"], ["blob", "tree"], "entry[%d].type" % i)
	# Hash hesaplandıysa SHA-256 formatında olmalı
	if not hash.is_empty() and hash.length() != 64:
		result.add_error("tree hash SHA-256 formatında değil")
