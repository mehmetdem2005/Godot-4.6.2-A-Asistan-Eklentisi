@tool
class_name AITFIDFRetriever
extends RefCounted

## TF-IDF Retriever — bütçesiz lokal anlamsal arama (Layer 2).
##
## TF-IDF (Term Frequency - Inverse Document Frequency): bir kelimenin
## bir belgede ne sıklıkta geçtiğini (TF), ama tüm belgelerde ne kadar
## yaygın olduğunu (IDF) hesaba katar. Yaygın kelimeler az puan,
## ayırt edici kelimeler çok puan alır.
##
## Bütçe: bu retriever SIFIR maliyetlidir — internet/LLM gerektirmez.
## OpenAI embedding (Phase 2+) bunun yerine geçebilir ama bu her zaman çalışır.

## İndekslenmiş belgeler — id -> AIKnowledgeDoc
var _docs: Dictionary = {}

## Document frequency cache — token -> kaç belgede geçiyor
## (IDF hesaplaması için; belge eklenince/çıkınca güncellenir)
var _doc_frequency: Dictionary = {}


## İndeksteki belge sayısı.
func doc_count() -> int:
	return _docs.size()


## İndeks boş mu?
func is_empty() -> bool:
	return _docs.is_empty()


## İndeksteki tüm belgeleri döndürür.
func all_docs() -> Array:
	return _docs.values()


## Benzersiz token (terim) sayısı — istatistik için.
func unique_term_count() -> int:
	return _doc_frequency.size()


# ============================================================
# İNDEKSLEME
# ============================================================

## Bir belgeyi indekse ekler. Geçersiz belge eklenmez.
func index_doc(doc: AIKnowledgeDoc) -> bool:
	if doc == null:
		return false
	if not doc.is_valid():
		push_warning("TFIDFRetriever: geçersiz belge indekslenmedi")
		return false

	# Belge zaten varsa önce eski document frequency katkısını çıkar
	if _docs.has(doc.id):
		_remove_from_doc_frequency(_docs[doc.id])

	_docs[doc.id] = doc
	_add_to_doc_frequency(doc)
	return true


## Bir belgeyi indeksten çıkarır.
func remove_doc(doc_id: String) -> bool:
	if not _docs.has(doc_id):
		return false
	_remove_from_doc_frequency(_docs[doc_id])
	_docs.erase(doc_id)
	return true


## Tüm indeksi temizler.
func clear() -> void:
	_docs.clear()
	_doc_frequency.clear()


## Bir belgenin token'larını document frequency'ye ekler.
func _add_to_doc_frequency(doc: AIKnowledgeDoc) -> void:
	# Her benzersiz token için "1 belgede daha geçiyor"
	for token in doc.term_freq:
		_doc_frequency[token] = int(_doc_frequency.get(token, 0)) + 1


## Bir belgenin token'larını document frequency'den çıkarır.
func _remove_from_doc_frequency(doc: AIKnowledgeDoc) -> void:
	for token in doc.term_freq:
		var current: int = int(_doc_frequency.get(token, 0))
		if current <= 1:
			_doc_frequency.erase(token)
		else:
			_doc_frequency[token] = current - 1


# ============================================================
# TF-IDF SKORLAMA
# ============================================================

## Bir token için IDF (Inverse Document Frequency) hesaplar.
## Formül: log(1 + toplam_belge / (1 + token_içeren_belge))
## "1 +" sarması IDF'i ASLA negatife düşürmez — bir terim tüm belgelerde
## geçse bile pozitif kalır (yaygın terim düşük ama sıfır-üstü puan alır).
## Yaygın token = düşük IDF, nadir token = yüksek IDF.
func _idf(token: String) -> float:
	var total: int = _docs.size()
	if total == 0:
		return 0.0
	var df: int = int(_doc_frequency.get(token, 0))
	# 1 + (...) sarması: log argümanı her zaman > 1, sonuç her zaman > 0
	return log(1.0 + float(total) / float(1 + df))


## Bir belgenin bir sorguya karşı TF-IDF skorunu hesaplar.
## Skor = sorgu token'larının belgedeki TF-IDF değerlerinin toplamı.
##
## Tam eşleşme + prefix (önek) eşleşme: Türkçe sondan eklemeli bir dildir
## ("kamera/kamerayı/kamerasıdır" aynı kök). Tam eşleşme tam puan alır;
## prefix eşleşme (en az 4 karakter ortak önek) yarım puan alır.
func _score_doc(doc: AIKnowledgeDoc, query_tokens: PackedStringArray) -> float:
	if doc.token_count == 0:
		return 0.0

	var score: float = 0.0
	for token in query_tokens:
		# Adım 1 - Tam eşleşme: tam puan
		var tf_raw: int = doc.frequency_of(token)
		if tf_raw > 0:
			var tf: float = float(tf_raw) / float(doc.token_count)
			score += tf * _idf(token)
			continue

		# Adım 2 - Tam eşleşme yok: prefix eşleşme ara, yarım ağırlık
		var prefix_tf: int = _prefix_frequency(doc, token)
		if prefix_tf > 0:
			var tf2: float = float(prefix_tf) / float(doc.token_count)
			# 0.5 ağırlık: prefix eşleşme tam eşleşmeden zayıftır
			score += 0.5 * tf2 * _idf(token)
	return score


## Minimum prefix eşleşme uzunluğu.
## Token'lar zaten Tokenizer.normalize() ile köke indirilmiş gelir; bu prefix
## eşleşme, kökleri biraz farklı uzunlukta kalan TR+EN kelimeler için ek
## güvenlik katmanıdır (örn. "anim" ~ "anima"). 3 karakter — kökler kısa olur.
const MIN_PREFIX_MATCH: int = 3


## Bir belgede, verilen token ile prefix-eşleşen kelimelerin toplam frekansı.
## "kamera" sorgusu "kamerasıdır" belgesinde eşleşir (ortak önek "kamera").
## Eşleşme çift yönlü: sorgu belge token'ının öneki VEYA belge token'ı
## sorgunun öneki olabilir — ikisi de en az MIN_PREFIX_MATCH karakter.
func _prefix_frequency(doc: AIKnowledgeDoc, query_token: String) -> int:
	if query_token.length() < MIN_PREFIX_MATCH:
		return 0
	var total: int = 0
	for doc_token in doc.term_freq:
		var dt: String = doc_token
		if dt == query_token:
			continue  # tam eşleşme zaten ele alındı
		# Çift yönlü prefix kontrolü
		var matched: bool = false
		if dt.length() >= MIN_PREFIX_MATCH and dt.begins_with(query_token):
			matched = true
		elif query_token.begins_with(dt) and dt.length() >= MIN_PREFIX_MATCH:
			matched = true
		if matched:
			total += int(doc.term_freq[doc_token])
	return total


# ============================================================
# ARAMA
# ============================================================

## Bir sorgu için en alakalı belgeleri döndürür.
## Dönen: [{doc: AIKnowledgeDoc, score: float}] — skora göre azalan sıralı.
## max_results: kaç sonuç döndürülecek (0 = hepsi).
func search(query: String, max_results: int = 5) -> Array:
	var query_tokens: PackedStringArray = AITokenizer.tokenize(query)
	if query_tokens.is_empty():
		return []

	var scored: Array = []
	for doc_id in _docs:
		var doc: AIKnowledgeDoc = _docs[doc_id]
		var score: float = _score_doc(doc, query_tokens)
		if score > 0.0:  # sadece alakalı belgeler
			scored.append({"doc": doc, "score": score})

	# Skora göre azalan sırala
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	if max_results <= 0 or max_results >= scored.size():
		return scored
	return scored.slice(0, max_results)


## Belirli bir kaynak tipinde arama yapar.
func search_by_source_type(query: String, source_type: int, max_results: int = 5) -> Array:
	var all_results: Array = search(query, 0)  # önce hepsini al
	var filtered: Array = []
	for r in all_results:
		if (r["doc"] as AIKnowledgeDoc).source_type == source_type:
			filtered.append(r)
	if max_results <= 0 or max_results >= filtered.size():
		return filtered
	return filtered.slice(0, max_results)


## Belirli bir genre'ye ait belgelerde arama yapar.
func search_by_genre(query: String, genre_id: String, max_results: int = 5) -> Array:
	var all_results: Array = search(query, 0)
	var filtered: Array = []
	for r in all_results:
		if (r["doc"] as AIKnowledgeDoc).genre_id == genre_id:
			filtered.append(r)
	if max_results <= 0 or max_results >= filtered.size():
		return filtered
	return filtered.slice(0, max_results)
