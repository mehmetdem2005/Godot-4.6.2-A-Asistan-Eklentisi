@tool
class_name AIKnowledgeTest
extends RefCounted

## Phase 2 / Layer 2 — Knowledge & RAG Self-Test
##
## Sıkı testler: tokenizer doğruluğu, TF-IDF skorlama, arama isabeti,
## incremental indeksleme, disk persistence, bellek entegrasyonu.
##
## Mock policy: testler GERÇEK doğrulama yapar.

const TEST_DIR: String = "user://ai_assistant/knowledge/test"


## Tüm knowledge testlerini çalıştırır.
static func run_all() -> Array:
	var results: Array = []

	# Tokenizer
	results.append(_b("RAG: Tokenizer", _test_tokenize_basic()))
	results.append(_b("RAG: Tokenizer", _test_tokenize_stopwords()))
	results.append(_b("RAG: Tokenizer", _test_tokenize_turkish()))
	results.append(_b("RAG: Tokenizer", _test_tokenize_term_freq()))
	results.append(_b("RAG: Tokenizer", _test_tokenize_empty()))
	results.append(_b("RAG: Tokenizer", _test_normalize_tr()))
	results.append(_b("RAG: Tokenizer", _test_normalize_en()))
	results.append(_b("RAG: Tokenizer", _test_normalize_idempotent()))
	results.append(_b("RAG: Tokenizer", _test_normalize_protected()))

	# KnowledgeDoc
	results.append(_b("RAG: Doc", _test_doc_auto_index()))
	results.append(_b("RAG: Doc", _test_doc_update_reindex()))
	results.append(_b("RAG: Doc", _test_doc_roundtrip()))

	# TF-IDF Retriever
	results.append(_b("RAG: TF-IDF", _test_retriever_basic_search()))
	results.append(_b("RAG: TF-IDF", _test_retriever_relevance_ranking()))
	results.append(_b("RAG: TF-IDF", _test_retriever_rare_term_wins()))
	results.append(_b("RAG: TF-IDF", _test_retriever_remove_doc()))
	results.append(_b("RAG: TF-IDF", _test_retriever_no_match()))
	results.append(_b("RAG: TF-IDF", _test_retriever_source_filter()))
	results.append(_b("RAG: TF-IDF", _test_retriever_prefix_match()))

	# KnowledgeBase
	results.append(_b("RAG: Base", _test_kb_add_search()))
	results.append(_b("RAG: Base", _test_kb_incremental()))
	results.append(_b("RAG: Base", _test_kb_build_context()))
	results.append(_b("RAG: Base", _test_kb_memory_ingest()))
	results.append(_b("RAG: Base", _test_kb_disk_roundtrip()))
	results.append(_b("RAG: Base", _test_kb_stats()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(test_name: String) -> Dictionary:
	return {"ok": true, "name": test_name, "reason": ""}


static func _fail(test_name: String, reason: String) -> Dictionary:
	return {"ok": false, "name": test_name, "reason": reason}


# ============================================================
# TOKENIZER
# ============================================================

static func _test_tokenize_basic() -> Dictionary:
	var name := "Tokenizer temel parçalama"
	var tokens: PackedStringArray = AITokenizer.tokenize("Mesh oluştur ve sahneye ekle")
	# "ve" stopword — atlanmalı. Diğer kelimeler kök haline iner (normalize).
	if tokens.has("ve"):
		return _fail(name, "stopword 've' atlanmamış")
	# "mesh" sonek almaz — değişmeden kalır
	if not tokens.has("mesh"):
		return _fail(name, "'mesh' token'ı yok")
	# "oluştur" sonek almaz — değişmeden kalır
	if not tokens.has("oluştur"):
		return _fail(name, "'oluştur' token'ı yok")
	# En az 4 anlamlı token üretilmeli (mesh, oluştur, sahne kökü, ekle)
	if tokens.size() < 4:
		return _fail(name, "beklenen en az 4 token, %d bulundu" % tokens.size())
	return _ok(name)


static func _test_tokenize_stopwords() -> Dictionary:
	var name := "Tokenizer durdurma kelimeleri"
	if not AITokenizer.is_stopword("ve"):
		return _fail(name, "'ve' stopword olmalı (TR)")
	if not AITokenizer.is_stopword("the"):
		return _fail(name, "'the' stopword olmalı (EN)")
	if AITokenizer.is_stopword("shader"):
		return _fail(name, "'shader' stopword olmamalı")
	return _ok(name)


static func _test_tokenize_turkish() -> Dictionary:
	var name := "Tokenizer Türkçe karakter"
	var tokens: PackedStringArray = AITokenizer.tokenize("ışık gölge çözünürlük")
	# Türkçe karakterli kelimeler bölünmeden kalmalı
	if not tokens.has("ışık"):
		return _fail(name, "'ışık' bölündü/kayboldu")
	if not tokens.has("gölge"):
		return _fail(name, "'gölge' bölündü/kayboldu")
	if not tokens.has("çözünürlük"):
		return _fail(name, "'çözünürlük' bölündü/kayboldu")
	return _ok(name)


static func _test_tokenize_term_freq() -> Dictionary:
	var name := "Tokenizer frekans sayımı"
	var tf: Dictionary = AITokenizer.term_frequency("mesh mesh mesh sahne")
	if tf.get("mesh") != 3:
		return _fail(name, "'mesh' 3 kez sayılmalı: %s" % str(tf.get("mesh")))
	if tf.get("sahne") != 1:
		return _fail(name, "'sahne' 1 kez sayılmalı")
	return _ok(name)


static func _test_tokenize_empty() -> Dictionary:
	var name := "Tokenizer boş/gürültü girdi"
	if AITokenizer.tokenize("").size() != 0:
		return _fail(name, "boş metin boş token vermeli")
	# Sadece noktalama ve stopword
	if AITokenizer.tokenize("... ve the !!!").size() != 0:
		return _fail(name, "sadece gürültü boş token vermeli")
	return _ok(name)


static func _test_normalize_tr() -> Dictionary:
	var name := "Tokenizer Türkçe kök normalize"
	# Çok-harfli sonekli kelimeler aynı köke inmeli
	var k1: String = AITokenizer.normalize("kamerasıdır")
	var k2: String = AITokenizer.normalize("kamera")
	if not (k1 == k2 or k1.begins_with(k2) or k2.begins_with(k1)):
		return _fail(name, "'kamera/kamerasıdır' aynı köke inmeli: '%s' vs '%s'" % [k1, k2])
	# "ışıklandırma" -> "ışık" (çok-harfli "landırma" eki kırpılır)
	if AITokenizer.normalize("ışıklandırma") != "ışık":
		return _fail(name, "'ışıklandırma' -> 'ışık' olmalı: '%s'" % AITokenizer.normalize("ışıklandırma"))
	# Tek-harf veya kısa ek alan kelimeler ("meshi", "oluşturma") normalize ile
	# tam köke inmeyebilir — ama TF-IDF prefix eşleşmesi yine bulur.
	# Burada ortak önek paylaştıklarını doğrula (retriever'ın eşleşme şartı).
	var pairs: Array = [["meshi", "mesh"], ["oluşturma", "oluştur"]]
	for pair in pairs:
		var a: String = AITokenizer.normalize(pair[0])
		var b: String = AITokenizer.normalize(pair[1])
		if not (a.begins_with(b) or b.begins_with(a)):
			return _fail(name, "'%s/%s' ortak önek paylaşmalı: '%s' vs '%s'" % [pair[0], pair[1], a, b])
	return _ok(name)


static func _test_normalize_en() -> Dictionary:
	var name := "Tokenizer İngilizce kök normalize"
	# "rendering" ve "render" aynı köke inmeli
	var doc_tokens: PackedStringArray = AITokenizer.tokenize("GPU rendering pipeline")
	var query_tokens: PackedStringArray = AITokenizer.tokenize("render")
	if query_tokens.is_empty():
		return _fail(name, "'render' tokenize boş")
	# "render" kökü doc token'larından biriyle eşleşmeli (tam veya prefix)
	var query_stem: String = query_tokens[0]
	var found: bool = false
	for dt in doc_tokens:
		if dt == query_stem or dt.begins_with(query_stem) or query_stem.begins_with(dt):
			found = true
			break
	if not found:
		return _fail(name, "'render' ~ 'rendering' kök eşleşmedi: %s" % str(doc_tokens))
	# "collision" -> "collide" ile aynı köke yakın inmeli
	var c1: String = AITokenizer.normalize("collision")
	var c2: String = AITokenizer.normalize("collide")
	if not (c1 == c2 or c1.begins_with(c2) or c2.begins_with(c1)):
		return _fail(name, "'collide/collision' kök ayrıştı: '%s' vs '%s'" % [c1, c2])
	return _ok(name)


static func _test_normalize_idempotent() -> Dictionary:
	var name := "Tokenizer normalize idempotent"
	# KRİTİK: normalize(normalize(x)) == normalize(x).
	# İndeksleme ve arama farklı kod yollarından geçebilir; iki kez normalize
	# edilen bir kelime farklı sonuç verirse arama sessizce başarısız olur.
	var words: PackedStringArray = PackedStringArray([
		"rendering", "kamerasıdır", "collision", "meshes",
		"ışıklandırma", "optimization", "textures", "createds",
	])
	for w in words:
		var n1: String = AITokenizer.normalize(w)
		var n2: String = AITokenizer.normalize(n1)
		var n3: String = AITokenizer.normalize(n2)
		if not (n1 == n2 and n2 == n3):
			return _fail(name, "'%s' idempotent değil: '%s' -> '%s' -> '%s'" % [w, n1, n2, n3])
	return _ok(name)


static func _test_normalize_protected() -> Dictionary:
	var name := "Tokenizer korunan kökler kırpılmaz"
	# Teknik terimler sonek sanılıp kırpılmamalı (örn. "render" -> "rend").
	var protected: PackedStringArray = PackedStringArray([
		"render", "shader", "node", "mesh", "scene", "camera",
		"texture", "material", "sahne", "ışık",
	])
	for w in protected:
		var n: String = AITokenizer.normalize(w)
		if n != w:
			return _fail(name, "korunan kök '%s' kırpıldı -> '%s'" % [w, n])
	return _ok(name)


# ============================================================
# KNOWLEDGE DOC
# ============================================================

static func _test_doc_auto_index() -> Dictionary:
	var name := "KnowledgeDoc otomatik indeksleme"
	var doc := AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "AudioStreamPlayer3D ses çalar"
	)
	# create() term_freq'i otomatik hesaplamalı
	if doc.term_freq.is_empty():
		return _fail(name, "term_freq otomatik hesaplanmadı")
	if doc.token_count <= 0:
		return _fail(name, "token_count hesaplanmadı")
	if doc.content_hash.is_empty():
		return _fail(name, "content_hash hesaplanmadı")
	return _ok(name)


static func _test_doc_update_reindex() -> Dictionary:
	var name := "KnowledgeDoc içerik güncelleme yeniden indeksler"
	var doc := AIKnowledgeDoc.create(AIKnowledgeDoc.SourceType.USER_NOTE, "ilk içerik")
	var old_hash: String = doc.content_hash
	doc.update_content("tamamen yeni farklı içerik metni")
	if doc.content_hash == old_hash:
		return _fail(name, "içerik değişti ama hash aynı kaldı")
	if not doc.contains_token("yeni"):
		return _fail(name, "yeni içeriğin token'ı indekslenmemiş")
	return _ok(name)


static func _test_doc_roundtrip() -> Dictionary:
	var name := "KnowledgeDoc serialize round-trip"
	var doc := AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.CODE_FILE, "func _ready(): pass", "ready fonksiyonu"
	)
	doc.genre_id = "fps_3d"
	var dict: Dictionary = doc.to_dict()
	var doc2 := AIKnowledgeDoc.new()
	doc2.from_dict(dict)
	if doc2.content != doc.content:
		return _fail(name, "content kayboldu")
	if doc2.source_type != AIKnowledgeDoc.SourceType.CODE_FILE:
		return _fail(name, "source_type kayboldu")
	if doc2.genre_id != "fps_3d":
		return _fail(name, "genre_id kayboldu")
	if doc2.token_count != doc.token_count:
		return _fail(name, "token_count kayboldu")
	return _ok(name)


# ============================================================
# TF-IDF RETRIEVER
# ============================================================

static func _test_retriever_basic_search() -> Dictionary:
	var name := "TF-IDF temel arama"
	var r := AITFIDFRetriever.new()
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "mesh oluşturma rehberi"
	))
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "ses sistemi kurulumu"
	))
	var results: Array = r.search("mesh", 5)
	if results.is_empty():
		return _fail(name, "'mesh' araması sonuç vermedi")
	# İlk sonuç mesh içermeli
	var top_doc: AIKnowledgeDoc = results[0]["doc"]
	if not top_doc.content.contains("mesh"):
		return _fail(name, "en alakalı sonuç 'mesh' içermeli")
	return _ok(name)


static func _test_retriever_relevance_ranking() -> Dictionary:
	var name := "TF-IDF alaka sıralaması"
	var r := AITFIDFRetriever.new()
	# Bu belge sorgu kelimesini çok geçiriyor
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "shader shader shader kodu"
	))
	# Bu belge bir kez geçiriyor
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "shader hakkında kısa not buraya"
	))
	var results: Array = r.search("shader", 5)
	if results.size() < 2:
		return _fail(name, "2 sonuç beklenir")
	# İlk sonuç daha yüksek skorlu olmalı
	if results[0]["score"] < results[1]["score"]:
		return _fail(name, "sonuçlar skora göre sıralı değil")
	return _ok(name)


static func _test_retriever_rare_term_wins() -> Dictionary:
	var name := "TF-IDF nadir terim daha değerli (IDF)"
	var r := AITFIDFRetriever.new()
	# "godot" 3 belgede geçiyor (yaygın), "raycast" 1 belgede (nadir)
	r.index_doc(AIKnowledgeDoc.create(AIKnowledgeDoc.SourceType.API_DOC, "godot sahne"))
	r.index_doc(AIKnowledgeDoc.create(AIKnowledgeDoc.SourceType.API_DOC, "godot node"))
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "godot raycast çarpışma"
	))
	# "godot raycast" araması — raycast içeren belge öne çıkmalı
	var results: Array = r.search("godot raycast", 5)
	if results.is_empty():
		return _fail(name, "sonuç yok")
	var top: AIKnowledgeDoc = results[0]["doc"]
	if not top.content.contains("raycast"):
		return _fail(name, "nadir terim 'raycast' içeren belge öne çıkmalı")
	return _ok(name)


static func _test_retriever_remove_doc() -> Dictionary:
	var name := "TF-IDF belge çıkarma"
	var r := AITFIDFRetriever.new()
	var doc := AIKnowledgeDoc.create(AIKnowledgeDoc.SourceType.API_DOC, "silinecek belge")
	r.index_doc(doc)
	if r.doc_count() != 1:
		return _fail(name, "belge eklenmedi")
	r.remove_doc(doc.id)
	if r.doc_count() != 0:
		return _fail(name, "belge çıkarılmadı")
	# Çıkarılan belge aramada görünmemeli
	if r.search("silinecek", 5).size() != 0:
		return _fail(name, "çıkarılan belge hâlâ aranıyor")
	return _ok(name)


static func _test_retriever_no_match() -> Dictionary:
	var name := "TF-IDF eşleşmeyen sorgu"
	var r := AITFIDFRetriever.new()
	r.index_doc(AIKnowledgeDoc.create(AIKnowledgeDoc.SourceType.API_DOC, "mesh node"))
	# Alakasız sorgu boş sonuç vermeli
	var results: Array = r.search("xyzzy bambaşka", 5)
	if results.size() != 0:
		return _fail(name, "eşleşmeyen sorgu boş dönmeli")
	return _ok(name)


static func _test_retriever_source_filter() -> Dictionary:
	var name := "TF-IDF kaynak tipi filtresi"
	var r := AITFIDFRetriever.new()
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.CODE_FILE, "kamera kodu"
	))
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "kamera dokümantasyonu"
	))
	var code_only: Array = r.search_by_source_type(
		"kamera", AIKnowledgeDoc.SourceType.CODE_FILE, 5
	)
	if code_only.size() != 1:
		return _fail(name, "kaynak filtresi 1 sonuç vermeli")
	if (code_only[0]["doc"] as AIKnowledgeDoc).source_type != AIKnowledgeDoc.SourceType.CODE_FILE:
		return _fail(name, "filtre yanlış tip döndürdü")
	return _ok(name)


static func _test_retriever_prefix_match() -> Dictionary:
	var name := "TF-IDF Türkçe prefix eşleşme"
	var r := AITFIDFRetriever.new()
	# "Camera3D kamerasıdır" — "kamera" araması bunu bulmalı (prefix)
	r.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "Camera3D sahne kamerasıdır"
	))
	var results: Array = r.search("kamera", 5)
	if results.is_empty():
		return _fail(name, "'kamera' -> 'kamerasıdır' prefix eşleşmeli")
	# "meshi" çekimli kelime — "mesh" araması bunu bulmalı
	var r2 := AITFIDFRetriever.new()
	r2.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "meshi sahneye ekledim"
	))
	if r2.search("mesh", 5).is_empty():
		return _fail(name, "'mesh' -> 'meshi' prefix eşleşmeli")
	# Kısa sorgu (2 harf) prefix yapmamalı — gürültü önleme
	var r3 := AITFIDFRetriever.new()
	r3.index_doc(AIKnowledgeDoc.create(
		AIKnowledgeDoc.SourceType.API_DOC, "eleman element"
	))
	# "el" 2 harf — prefix eşleşme tetiklenmemeli; sadece tam eşleşme yoksa boş
	var short_results: Array = r3.search("el", 5)
	# "el" stopword değil ama 2 harf — prefix yapmaz, tam eşleşme de yok
	if not short_results.is_empty():
		return _fail(name, "kısa sorgu (2 harf) prefix yapmamalı")
	return _ok(name)


# ============================================================
# KNOWLEDGE BASE
# ============================================================

static func _test_kb_add_search() -> Dictionary:
	var name := "KnowledgeBase ekle ve ara"
	var kb := AIKnowledgeBase.new()
	kb.add_text(
		"CharacterBody2D platform oyunları için", AIKnowledgeDoc.SourceType.API_DOC
	)
	var results: Array = kb.search("platform", 5)
	if results.is_empty():
		return _fail(name, "arama sonuç vermedi")
	if kb.doc_count() != 1:
		return _fail(name, "doc_count yanlış")
	return _ok(name)


static func _test_kb_incremental() -> Dictionary:
	var name := "KnowledgeBase incremental indeksleme"
	var kb := AIKnowledgeBase.new()
	var doc := AIKnowledgeDoc.create(AIKnowledgeDoc.SourceType.CODE_FILE, "test içeriği")
	doc.source_path = "res://test.gd"
	kb.add_doc(doc)
	# Aynı içerik — güncel olmalı
	if not kb.is_up_to_date("res://test.gd", "test içeriği"):
		return _fail(name, "değişmemiş içerik güncel sayılmalı")
	# Farklı içerik — güncel değil
	if kb.is_up_to_date("res://test.gd", "farklı içerik"):
		return _fail(name, "değişmiş içerik güncel sayılmamalı")
	# Hiç görülmemiş yol — güncel değil
	if kb.is_up_to_date("res://yok.gd", "x"):
		return _fail(name, "bilinmeyen yol güncel sayılmamalı")
	return _ok(name)


static func _test_kb_build_context() -> Dictionary:
	var name := "KnowledgeBase RAG bağlam üretimi"
	var kb := AIKnowledgeBase.new()
	kb.add_text("shader derleme adımları", AIKnowledgeDoc.SourceType.API_DOC)
	kb.add_text("shader hata ayıklama ipuçları", AIKnowledgeDoc.SourceType.API_DOC)
	var context: String = kb.build_context("shader", 2)
	if context.is_empty():
		return _fail(name, "bağlam boş")
	if not context.contains("shader"):
		return _fail(name, "bağlam alakalı içerik içermeli")
	return _ok(name)


static func _test_kb_memory_ingest() -> Dictionary:
	var name := "KnowledgeBase bellek entegrasyonu"
	var kb := AIKnowledgeBase.new()
	var mgr := AIMemoryManager.new()
	mgr.semantic.record_api_fact("Camera3D sahne kamerasıdır")
	mgr.episodic.add_content("iteration 1 tamamlandı")
	var count: int = kb.ingest_memory_manager(mgr)
	if count != 2:
		return _fail(name, "2 bellek kaydı indekslenmeli, %d oldu" % count)
	# Belleğe yazılan bilgi artık aranabilir
	var results: Array = kb.search("kamera", 5)
	if results.is_empty():
		return _fail(name, "bellekten gelen bilgi aranabilir olmalı")
	return _ok(name)


static func _test_kb_disk_roundtrip() -> Dictionary:
	var name := "KnowledgeBase disk save/load round-trip"
	var kb := AIKnowledgeBase.new()
	kb.add_text("kalıcı bilgi birinci", AIKnowledgeDoc.SourceType.API_DOC)
	kb.add_text("kalıcı bilgi ikinci", AIKnowledgeDoc.SourceType.API_DOC)
	var count_before: int = kb.doc_count()
	if not kb.save_to_disk():
		return _fail(name, "save_to_disk başarısız")

	var kb2 := AIKnowledgeBase.new()
	if not kb2.load_from_disk():
		return _fail(name, "load_from_disk başarısız")
	if kb2.doc_count() != count_before:
		return _fail(name, "yüklenen belge sayısı uyuşmuyor")
	# Yüklenen belge aranabilir olmalı
	if kb2.search("kalıcı", 5).is_empty():
		return _fail(name, "yüklenen belgeler aranamıyor")

	# Temizlik
	DirAccess.remove_absolute(AIKnowledgeBase.STORAGE_PATH)
	return _ok(name)


static func _test_kb_stats() -> Dictionary:
	var name := "KnowledgeBase istatistik"
	var kb := AIKnowledgeBase.new()
	kb.add_text("birinci belge", AIKnowledgeDoc.SourceType.API_DOC)
	kb.add_text("ikinci belge", AIKnowledgeDoc.SourceType.API_DOC)
	var stats: Dictionary = kb.stats()
	if stats["doc_count"] != 2:
		return _fail(name, "doc_count yanlış")
	if int(stats["unique_terms"]) <= 0:
		return _fail(name, "unique_terms hesaplanmadı")
	return _ok(name)
