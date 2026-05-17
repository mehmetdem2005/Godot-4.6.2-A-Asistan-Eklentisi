@tool
class_name AIVCSBlob
extends AIContractBase

## VCSBlob — içerik-adresli depolama birimi (Git'in blob mantığı).
##
## Bir dosyanın içeriği SHA-256 hash'iyle adreslenir. Aynı içerik = aynı hash =
## tek kez saklanır (deduplication). Logical Commit System'in temel taşı.

# --- Kimlik ---
var hash: String = ""                ## İçerik SHA-256 hash'i (adres)
var size_bytes: int = 0              ## Orijinal içerik boyutu

# --- Depolama ---
var compressed: bool = false         ## İçerik sıkıştırılmış mı (büyük dosyalar)
var storage_path: String = ""        ## user://vcs/objects/ altındaki dosya yolu
var is_binary: bool = false          ## Metin mi binary mi


func contract_type() -> String:
	return "VCSBlob"


## İçerikten yeni bir blob oluşturur (factory).
## Hash, içerikten otomatik hesaplanır — içerik-adresleme garantisi.
static func create_from_content(content: PackedByteArray) -> AIVCSBlob:
	var b := AIVCSBlob.new()
	b.hash = _compute_hash(content)
	b.size_bytes = content.size()
	b.storage_path = "user://vcs/objects/%s/%s" % [b.hash.substr(0, 2), b.hash.substr(2)]
	return b


## Metin içerikten blob oluşturur (kolaylık).
static func create_from_text(text: String) -> AIVCSBlob:
	var b := create_from_content(text.to_utf8_buffer())
	b.is_binary = false
	return b


## İçeriğin SHA-256 hash'ini hesaplar.
static func _compute_hash(content: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(content)
	return ctx.finish().hex_encode()


func _to_dict_impl() -> Dictionary:
	return {
		"hash": hash,
		"size_bytes": size_bytes,
		"compressed": compressed,
		"storage_path": storage_path,
		"is_binary": is_binary,
	}


func _from_dict_impl(data: Dictionary) -> void:
	hash = data.get("hash", "")
	size_bytes = int(data.get("size_bytes", 0))
	compressed = bool(data.get("compressed", false))
	storage_path = data.get("storage_path", "")
	is_binary = bool(data.get("is_binary", false))


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, hash, "hash")
	# SHA-256 hash 64 hex karakter olmalı
	if hash.length() != 64:
		result.add_error("hash SHA-256 formatında değil (64 hex bekleniyor): %d" % hash.length())
	if size_bytes < 0:
		result.add_error("size_bytes negatif olamaz: %d" % size_bytes)
