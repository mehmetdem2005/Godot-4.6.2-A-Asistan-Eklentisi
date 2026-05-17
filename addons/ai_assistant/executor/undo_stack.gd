@tool
class_name AIUndoStack
extends RefCounted

## UndoStack — geri-alma yığını (Layer 4).
##
## Executor bir dosyayı değiştirmeden/silmeden ÖNCE, dosyanın o anki hâlini
## buraya snapshot'lar. Her snapshot bir "undo token" üretir. İşlem geri
## alınmak istenirse, token ile eski hâl geri yazılır.
##
## Snapshot tipleri:
##   - FILE_CONTENT: dosyanın eski içeriği (değiştirme/silme öncesi)
##   - FILE_ABSENT : dosya yoktu (oluşturma öncesi — geri-al = sil)
##
## İçerik MD5 ile adreslenir — aynı içerik iki kez saklanmaz (Layer 0
## vcs_blob mantığı). Bellek dostu.

## Snapshot tipleri.
enum SnapshotKind { FILE_CONTENT, FILE_ABSENT }


## Tek bir geri-alma snapshot'u.
class UndoEntry extends RefCounted:
	var token: String = ""
	var kind: int = SnapshotKind.FILE_CONTENT
	var path: String = ""
	var content_hash: String = ""    ## FILE_CONTENT için içerik MD5
	var created_at: String = ""

	func to_dict() -> Dictionary:
		return {
			"token": token,
			"kind": kind,
			"path": path,
			"content_hash": content_hash,
			"created_at": created_at,
		}


## Snapshot girdileri — token -> UndoEntry
var _entries: Dictionary = {}

## İçerik havuzu — content_hash -> içerik metni (deduplike depolama)
var _content_pool: Dictionary = {}

## Geri-alma sırası — LIFO (son işlem ilk geri alınır)
var _stack: PackedStringArray = PackedStringArray()


## Yığındaki snapshot sayısı.
func count() -> int:
	return _stack.size()


## Yığın boş mu?
func is_empty() -> bool:
	return _stack.is_empty()


# ============================================================
# SNAPSHOT ALMA
# ============================================================

## Bir dosyanın değiştirme/silme ÖNCESİ hâlini snapshot'lar.
## old_content: dosyanın mevcut içeriği (executor okuyup verir).
## Dönen: undo token.
func snapshot_existing(path: String, old_content: String) -> String:
	var entry := UndoEntry.new()
	entry.token = AIContractBase.generate_id("undo")
	entry.kind = SnapshotKind.FILE_CONTENT
	entry.path = path
	entry.content_hash = old_content.md5_text()
	entry.created_at = AIContractBase.now_iso()

	# İçeriği havuza koy — aynı hash zaten varsa tekrar saklama
	if not _content_pool.has(entry.content_hash):
		_content_pool[entry.content_hash] = old_content

	_entries[entry.token] = entry
	_stack.append(entry.token)
	return entry.token


## Bir dosyanın OLUŞTURULMADAN önceki "yokluğunu" snapshot'lar.
## Geri-al = dosyayı sil. Dönen: undo token.
func snapshot_absent(path: String) -> String:
	var entry := UndoEntry.new()
	entry.token = AIContractBase.generate_id("undo")
	entry.kind = SnapshotKind.FILE_ABSENT
	entry.path = path
	entry.created_at = AIContractBase.now_iso()

	_entries[entry.token] = entry
	_stack.append(entry.token)
	return entry.token


# ============================================================
# GERİ-ALMA VERİSİ
# ============================================================

## Bir token'ın geri-alma talimatını döndürür.
## Dönen: {found, kind, path, restore_content}
##   kind FILE_CONTENT  -> restore_content'i path'e geri yaz
##   kind FILE_ABSENT   -> path'i sil
func get_undo_instruction(token: String) -> Dictionary:
	if not _entries.has(token):
		return {"found": false}

	var entry: UndoEntry = _entries[token]
	if entry.kind == SnapshotKind.FILE_ABSENT:
		return {
			"found": true,
			"kind": SnapshotKind.FILE_ABSENT,
			"path": entry.path,
			"restore_content": "",
		}
	# FILE_CONTENT — havuzdan içeriği al
	var content: String = _content_pool.get(entry.content_hash, "")
	return {
		"found": true,
		"kind": SnapshotKind.FILE_CONTENT,
		"path": entry.path,
		"restore_content": content,
	}


## En son snapshot'ın token'ını döndürür (LIFO tepe). Yoksa boş string.
func peek_last() -> String:
	if _stack.is_empty():
		return ""
	return _stack[_stack.size() - 1]


## En son snapshot'ı yığından çıkarır ve token'ını döndürür.
## Geri-alma uygulandıktan sonra çağrılır.
func pop_last() -> String:
	if _stack.is_empty():
		return ""
	var token: String = _stack[_stack.size() - 1]
	_stack.remove_at(_stack.size() - 1)
	return token


## Bir token'ın hâlâ yığında olup olmadığı.
func has_token(token: String) -> bool:
	return _entries.has(token)


# ============================================================
# YÖNETİM
# ============================================================

## Yığını tamamen temizler — içerik havuzu da boşalır.
func clear() -> void:
	_entries.clear()
	_content_pool.clear()
	_stack.clear()


## İçerik havuzunda kaç benzersiz içerik var (deduplike sayısı).
func pool_size() -> int:
	return _content_pool.size()


## Yığın istatistikleri.
func stats() -> Dictionary:
	return {
		"snapshots": _stack.size(),
		"unique_contents": _content_pool.size(),
		"total_entries": _entries.size(),
	}
