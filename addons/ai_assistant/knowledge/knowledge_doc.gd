@tool
class_name AIKnowledgeDoc
extends AIContractBase

## KnowledgeDoc — RAG'de indekslenen belge birimi (Layer 2).
##
## Bir belge: bir kod dosyası parçası, bir bellek kaydı, bir Godot API notu,
## bir genre bilgisi olabilir. RAG bu belgeleri indeksler ve arar.
##
## Her belge bir "kaynak" tipine sahiptir — sonuç sıralamasında bağlam verir.

## Belge kaynak tipleri.
enum SourceType {
	CODE_FILE,    ## Proje kod dosyası parçası
	MEMORY,       ## Layer 1 bellek kaydından türetildi
	API_DOC,      ## Godot API dokümantasyonu
	GENRE_KB,     ## Genre bilgi tabanı
	USER_NOTE,    ## Kullanıcı notu
}

const SOURCE_TYPE_NAMES: Dictionary = {
	SourceType.CODE_FILE: "code_file",
	SourceType.MEMORY: "memory",
	SourceType.API_DOC: "api_doc",
	SourceType.GENRE_KB: "genre_kb",
	SourceType.USER_NOTE: "user_note",
}

# --- Kimlik ---
var id: String = ""
var source_type: int = SourceType.CODE_FILE
var source_path: String = ""         ## Dosya yolu / kayıt id (kaynak referansı)

# --- İçerik ---
var content: String = ""             ## Belgenin metni
var title: String = ""               ## Kısa başlık (sonuç gösteriminde)

# --- İndeksleme verisi ---
var term_freq: Dictionary = {}        ## token -> frekans (tokenize sonucu)
var token_count: int = 0              ## Toplam token sayısı

# --- Bağlam ---
var tags: PackedStringArray = PackedStringArray()
var genre_id: String = ""

# --- Değişiklik takibi ---
var content_hash: String = ""         ## İçerik MD5 — incremental indeksleme için
var indexed_at: String = ""


func contract_type() -> String:
	return "KnowledgeDoc"


## Yeni bir belge oluşturur (factory). term_freq otomatik hesaplanır.
static func create(p_source_type: int, p_content: String, p_title: String = "") -> AIKnowledgeDoc:
	var d := AIKnowledgeDoc.new()
	d.id = AIContractBase.generate_id("doc")
	d.source_type = p_source_type
	d.content = p_content
	d.title = p_title if not p_title.is_empty() else p_content.left(40)
	d.indexed_at = AIContractBase.now_iso()
	d._reindex()
	return d


## İçerik değiştiğinde çağrılır — term frequency yeniden hesaplanır.
func _reindex() -> void:
	term_freq = AITokenizer.term_frequency(content)
	var total: int = 0
	for token in term_freq:
		total += int(term_freq[token])
	token_count = total
	content_hash = content.md5_text()


## Belge içeriğini günceller ve yeniden indeksler.
func update_content(new_content: String) -> void:
	content = new_content
	indexed_at = AIContractBase.now_iso()
	_reindex()


## Kaynak tipinin string adı.
func source_type_name() -> String:
	return SOURCE_TYPE_NAMES.get(source_type, "code_file")


## Bir token'ın bu belgedeki frekansını döndürür.
func frequency_of(token: String) -> int:
	return int(term_freq.get(token, 0))


## Bu belge belirli bir token'ı içeriyor mu?
func contains_token(token: String) -> bool:
	return term_freq.has(token)


func _to_dict_impl() -> Dictionary:
	return {
		"id": id,
		"source_type": SOURCE_TYPE_NAMES.get(source_type, "code_file"),
		"source_path": source_path,
		"content": content,
		"title": title,
		"term_freq": term_freq,
		"token_count": token_count,
		"tags": tags,
		"genre_id": genre_id,
		"content_hash": content_hash,
		"indexed_at": indexed_at,
	}


func _from_dict_impl(data: Dictionary) -> void:
	id = data.get("id", "")
	source_type = _parse_source_type(data.get("source_type", "code_file"))
	source_path = data.get("source_path", "")
	content = data.get("content", "")
	title = data.get("title", "")
	term_freq = data.get("term_freq", {})
	token_count = int(data.get("token_count", 0))
	tags = PackedStringArray(data.get("tags", []))
	genre_id = data.get("genre_id", "")
	content_hash = data.get("content_hash", "")
	indexed_at = data.get("indexed_at", "")


func _validate_impl(result: AIValidationResult) -> void:
	require_non_empty_string(result, id, "id")
	require_non_empty_string(result, content, "content")
	if token_count < 0:
		result.add_error("token_count negatif olamaz")


static func _parse_source_type(s: String) -> int:
	for key in SOURCE_TYPE_NAMES:
		if SOURCE_TYPE_NAMES[key] == s:
			return key
	return SourceType.CODE_FILE
