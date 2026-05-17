@tool
class_name AIVCSCommit
extends AIContractBase

## VCSCommit — logical commit kaydı (Git'in commit mantığı).
##
## Belirli bir andaki proje durumunun kalıcı kaydı. Her commit bir tree'ye
## (dosya yapısı) işaret eder ve bir veya daha çok parent commit'i vardır.
##
## Logical Commit System (LCS) — saf GDScript, Android uyumlu, internet gerektirmez.

# --- Kimlik ---
var id: String = ""                  ## Commit SHA-256 hash'i (içerikten hesaplanır)
var parent_ids: PackedStringArray = PackedStringArray()  ## Üst commit'ler (merge için çoklu)

# --- İçerik ---
var tree_hash: String = ""           ## Bu commit'in dosya yapısı (VCSTree hash'i)
var message: String = ""             ## İnsan-okunabilir commit mesajı (Türkçe)

# --- Sahiplik ---
var author_role: String = ""         ## Hangi cell role bu commit'i üretti
var iteration_id: String = ""        ## Hangi iteration'a ait
var branch: String = "main"          ## Hangi branch'te

# --- Zaman ---
var timestamp: String = ""           ## Commit zamanı (ISO 8601)

# --- Meta ---
var user_approved: bool = false      ## Kullanıcı bu commit'i onayladı mı
var edit_type: String = ""           ## "surgical" | "new_file" | "replace" (Madde 19)
var metadata: Dictionary = {}        ## Ek etiketler


func contract_type() -> String:
	return "VCSCommit"


## Yeni bir commit oluşturur (factory). ID, içerikten compute_id() ile hesaplanır.
static func create(p_tree_hash: String, p_message: String, p_author_role: String) -> AIVCSCommit:
	var c := AIVCSCommit.new()
	c.tree_hash = p_tree_hash
	c.message = p_message
	c.author_role = p_author_role
	c.timestamp = AIContractBase.now_iso()
	c.compute_id()
	return c


## Commit içeriğinden ID (hash) hesaplar — içerik-adresleme.
## tree_hash + parent_ids + message + author + timestamp birleşiminden.
func compute_id() -> String:
	var canonical: String = "tree:%s\n" % tree_hash
	for p in parent_ids:
		canonical += "parent:%s\n" % p
	canonical += "author:%s\n" % author_role
	canonical += "time:%s\n" % timestamp
	canonical += "message:%s\n" % message

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	id = ctx.finish().hex_encode()
	return id


## Bu commit kök commit mi (parent'ı yok)?
func is_root() -> bool:
	return parent_ids.is_empty()


## Bu commit bir merge commit'i mi (birden çok parent)?
func is_merge() -> bool:
	return parent_ids.size() > 1


## Kısa commit kimliği (ilk 8 karakter — UI için).
func short_id() -> String:
	if id.length() >= 8:
		return id.substr(0, 8)
	return id


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"parent_ids": parent_ids,
		"tree_hash": tree_hash,
		"message": message,
		"author_role": author_role,
		"iteration_id": iteration_id,
		"branch": branch,
		"timestamp": timestamp,
		"user_approved": user_approved,
		"edit_type": edit_type,
		"metadata": metadata,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	parent_ids = PackedStringArray(data.get("parent_ids", []))
	tree_hash = data.get("tree_hash", "")
	message = data.get("message", "")
	author_role = data.get("author_role", "")
	iteration_id = data.get("iteration_id", "")
	branch = data.get("branch", "main")
	timestamp = data.get("timestamp", "")
	user_approved = bool(data.get("user_approved", false))
	edit_type = data.get("edit_type", "")
	metadata = data.get("metadata", {})


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, tree_hash, "tree_hash")
	require_non_empty_string(result, message, "message")
	require_non_empty_string(result, author_role, "author_role")
	require_non_empty_string(result, branch, "branch")
	if id.length() != 64:
		result.add_error("commit id SHA-256 formatında değil")
	# Kendine parent olamaz
	if parent_ids.has(id):
		result.add_error("Commit kendine parent olamaz")
