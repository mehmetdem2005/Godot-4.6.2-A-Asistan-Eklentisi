@tool
class_name AIKnowledgeBase
extends RefCounted

## KnowledgeBase — bilgi tabanı ana yöneticisi (Layer 2).
##
## RAG retrieval'i, disk kalıcılığını ve Layer 1 bellek entegrasyonunu birleştirir.
## Sistemin geri kalanı bilgiye bu sınıf üzerinden erişir.
##
## Akış: belge ekle -> indeksle -> sorgula -> en alakalı sonuçları al.
## Bütçe: TF-IDF retriever ile sıfır maliyetli çalışır.

## RAG retrieval motoru (TF-IDF — bütçesiz).
var retriever: AITFIDFRetriever

## Disk kalıcılık yolu.
const STORAGE_PATH: String = "user://ai_assistant/knowledge/knowledge_base.json"

## Belge içerik hash'leri — incremental indeksleme için (path -> hash)
var _content_hashes: Dictionary = {}


func _init() -> void:
	retriever = AITFIDFRetriever.new()


## İndeksteki belge sayısı.
func doc_count() -> int:
	return retriever.doc_count()


# ============================================================
# BELGE EKLEME
# ============================================================

## Bir belgeyi bilgi tabanına ekler.
func add_doc(doc: AIKnowledgeDoc) -> bool:
	if doc == null:
		return false
	var ok: bool = retriever.index_doc(doc)
	if ok and not doc.source_path.is_empty():
		_content_hashes[doc.source_path] = doc.content_hash
	return ok


## Metin içerikten hızlı belge ekler (kolaylık).
func add_text(
	content: String, source_type: int, title: String = "", tags: PackedStringArray = PackedStringArray()
) -> AIKnowledgeDoc:
	var doc := AIKnowledgeDoc.create(source_type, content, title)
	doc.tags = tags
	if add_doc(doc):
		return doc
	return null


## Bir kaynak yolu için belge zaten güncel mi kontrol eder.
## Incremental indeksleme: içerik değişmemişse yeniden indekslemeye gerek yok.
func is_up_to_date(source_path: String, content: String) -> bool:
	if not _content_hashes.has(source_path):
		return false
	return _content_hashes[source_path] == content.md5_text()


## Layer 1 bellek kaydından bir bilgi belgesi türetir ve ekler.
## Bu, belleği RAG'e besler — sistem kendi anılarını arayabilir hale gelir.
func ingest_memory_record(record: AIMemoryRecord) -> AIKnowledgeDoc:
	if record == null:
		return null
	var doc := AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.MEMORY,
		record.content,
		record.content.left(40)
	)
	doc.source_path = record.id
	doc.tags = record.tags
	doc.genre_id = record.genre_id
	if add_doc(doc):
		return doc
	return null


## Bir Memory Manager'ın tüm kalıcı belleğini RAG'e besler.
## Dönen: indekslenen belge sayısı.
func ingest_memory_manager(manager: AIMemoryManager) -> int:
	if manager == null:
		return 0
	var count: int = 0
	for record in manager.episodic.all():
		if ingest_memory_record(record) != null:
			count += 1
	for record in manager.semantic.all():
		if ingest_memory_record(record) != null:
			count += 1
	for record in manager.procedural.all():
		if ingest_memory_record(record) != null:
			count += 1
	return count


# ============================================================
# ARAMA
# ============================================================

## Bilgi tabanında arama yapar — en alakalı belgeleri döndürür.
## Dönen: [{doc, score}] azalan skor sıralı.
func search(query: String, max_results: int = 5) -> Array:
	return retriever.search(query, max_results)


## Sadece kod dosyalarında arama.
func search_code(query: String, max_results: int = 5) -> Array:
	return retriever.search_by_source_type(
		query, AIKnowledgeDoc.SourceType.CODE_FILE, max_results
	)


## Sadece bellekten türetilen belgelerde arama.
func search_memory(query: String, max_results: int = 5) -> Array:
	return retriever.search_by_source_type(
		query, AIKnowledgeDoc.SourceType.MEMORY, max_results
	)


## Belirli bir genre için arama.
func search_genre(query: String, genre_id: String, max_results: int = 5) -> Array:
	return retriever.search_by_genre(query, genre_id, max_results)


## En alakalı belgeleri birleştirilmiş bağlam metni olarak döndürür.
## Bu, bir LLM çağrısına "ilgili bilgi" enjekte etmek için kullanılır (RAG).
func build_context(query: String, max_docs: int = 3) -> String:
	var results: Array = search(query, max_docs)
	if results.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for r in results:
		var doc: AIKnowledgeDoc = r["doc"]
		parts.append("[%s] %s" % [doc.source_type_name(), doc.content])
	return "\n---\n".join(parts)


# ============================================================
# DİSK KALICILIĞI (atomic write)
# ============================================================

## Bilgi tabanını diske yazar (atomik).
func save_to_disk() -> bool:
	var data: Dictionary = {
		"saved_at": AIContractBase.now_iso(),
		"docs": [],
	}
	# Tüm belgeleri retriever'dan topla
	for doc in _all_docs():
		(data["docs"] as Array).append(doc.to_dict())

	var json_text: String = JSON.stringify(data, "  ")
	var dir_path: String = STORAGE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp_path: String = STORAGE_PATH + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("KnowledgeBase.save: dosya açılamadı")
		return false
	f.store_string(json_text)
	f.close()

	var rename_err: int = DirAccess.rename_absolute(tmp_path, STORAGE_PATH)
	if rename_err != OK:
		push_error("KnowledgeBase.save: rename başarısız")
		return false
	return true


## Bilgi tabanını diskten yükler.
func load_from_disk() -> bool:
	if not FileAccess.file_exists(STORAGE_PATH):
		return true  # İlk çalıştırma — normal

	var f: FileAccess = FileAccess.open(STORAGE_PATH, FileAccess.READ)
	if f == null:
		return false
	var json_text: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		push_error("KnowledgeBase.load: bozuk JSON")
		return false

	retriever.clear()
	_content_hashes.clear()
	for doc_dict in (parsed as Dictionary).get("docs", []):
		var doc := AIKnowledgeDoc.new()
		doc.from_dict(doc_dict)
		if doc.is_valid():
			add_doc(doc)
		else:
			push_warning("KnowledgeBase.load: bozuk belge atlandı")
	return true


## Retriever'daki tüm belgeleri döndürür (dahili yardımcı).
func _all_docs() -> Array:
	return retriever.all_docs()


## Bilgi tabanı istatistikleri.
func stats() -> Dictionary:
	return {
		"doc_count": doc_count(),
		"unique_terms": retriever.unique_term_count(),
		"tracked_paths": _content_hashes.size(),
	}
