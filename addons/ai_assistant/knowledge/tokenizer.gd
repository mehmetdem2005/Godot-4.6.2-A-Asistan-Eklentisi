@tool
class_name AITokenizer
extends RefCounted

## Tokenizer — metni arama için kelime parçalarına ayırır (Layer 2).
##
## RAG'in temel taşı: metni anlamlı kelimelere böler, gürültüyü (noktalama,
## çok kısa kelimeler, durdurma kelimeleri) temizler.
##
## TR + EN bilinçli: hem Türkçe hem İngilizce durdurma kelimelerini tanır.
## Kod-bilinçli: GDScript anahtar kelimelerini de işleyebilir.

## Türkçe durdurma kelimeleri (anlamsal değeri düşük, aramada gürültü).
## NOT: GDScript'te const PackedStringArray atanamaz — düz Array literal kullanılır.
const STOPWORDS_TR: Array = [
	"ve", "veya", "ile", "için", "bir", "bu", "şu", "o", "da", "de",
	"ki", "mi", "mı", "mu", "mü", "ama", "fakat", "çünkü", "ise", "gibi",
	"daha", "çok", "az", "her", "hiç", "ne", "nasıl", "neden", "kadar",
	"sonra", "önce", "şimdi", "olarak", "olan", "olur", "var", "yok",
]

## İngilizce durdurma kelimeleri.
const STOPWORDS_EN: Array = [
	"the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
	"of", "with", "is", "are", "was", "were", "be", "been", "this", "that",
	"it", "as", "by", "from", "has", "have", "had", "not", "no", "can",
	"will", "would", "should", "could", "if", "then", "else", "so",
]

## Minimum token uzunluğu — bundan kısa kelimeler atlanır.
const MIN_TOKEN_LENGTH: int = 2

## Normalize sonrası kökün en az kalması gereken uzunluk.
## Bundan kısa kalacaksa sonek kırpılmaz (aşırı kırpma önleme).
const MIN_STEM_LENGTH: int = 3

## Fixed-point normalize için maksimum tur sayısı (sonsuz döngü koruması).
const MAX_NORMALIZE_PASSES: int = 5

## İngilizce yaygın sonekler — en uzundan kısaya doğru denenir.
## Tam stemmer değil; yaygın çekim/türetme eklerini kırpan hafif normalize.
const SUFFIXES_EN: Array = [
	"ization", "ations", "ation", "izing", "ings", "tion", "sion",
	"ness", "ment", "ions", "ies", "ied", "ous", "ing", "ers", "er",
	"ed", "es", "ly", "al", "s",
]

## Türkçe yaygın sonekler — Türkçe sondan eklemeli, çok sayıda ek alır.
## NOT: Tek harfli ekler (-e -a -i) bilinçli olarak HARİÇ — "gölge" gibi
## kelimeleri "gölg"e kırparlardı (aşırı kırpma). Tek harf ekli kelimeler
## (örn. "meshi") TF-IDF prefix eşleşmesi ile yakalanır — bkz. tfidf_retriever.
const SUFFIXES_TR: Array = [
	"landırılması", "landırma", "sıdır", "sidir", "sudur", "südür",
	"ması", "mesi", "ları", "leri", "lar", "ler", "dan", "den", "tan",
	"ten", "nin", "nın", "nun", "nün", "yor", "sı", "si", "su", "sü",
	"ya", "ye", "da", "de", "ta", "te", "la", "le",
]

## Korunan kökler — bunlar ASLA kırpılmaz. Godot/oyun teknik terimleri
## ve sık kullanılan kelimeler. "render" kelimesi "-er" eki sanılıp "rend"e
## kırpılmamalı; bu liste yanlış kırpmayı engeller.
const PROTECTED_STEMS: Array = [
	"render", "shader", "node", "mesh", "scene", "script", "godot",
	"camera", "light", "audio", "video", "sound", "music", "input",
	"output", "signal", "vector", "color", "material", "texture",
	"model", "anim", "frame", "layer", "tile", "grid", "timer",
	"sahne", "ışık", "ses", "oyun", "veri", "mesaj", "hata", "kod",
]


## Bir kelimede TEK sonek kırpar. Dönen: [yeni_kelime, değişti_mi].
## Fixed-point normalize'in iç adımı.
static func _strip_one_suffix(w: String) -> Array:
	if w.length() < MIN_STEM_LENGTH + 1:
		return [w, false]
	var all_suffixes: Array = SUFFIXES_TR + SUFFIXES_EN
	all_suffixes.sort_custom(func(a, b): return a.length() > b.length())
	for suffix in all_suffixes:
		var s: String = suffix
		if w.ends_with(s) and (w.length() - s.length()) >= MIN_STEM_LENGTH:
			return [w.substr(0, w.length() - s.length()), true]
	return [w, false]


## Bir kelimeyi köküne normalize eder — yaygın TR+EN soneklerini kırpar.
## İndeksleme ve arama AYNI normalize'i kullanır; bu sayede "render" araması
## "rendering" içeren belgeyi, "kamera" araması "kamerasıdır"ı bulur.
##
## Tasarım garantileri:
##   - IDEMPOTENT: normalize(normalize(x)) == normalize(x). Fixed-point
##     döngü ile çok katmanlı ekler tek seferde soyulur ("renderings" -> "render").
##   - KORUMA: PROTECTED_STEMS listesindeki teknik terimler asla kırpılmaz.
##   - AŞIRI KIRPMA YOK: kök her zaman >= MIN_STEM_LENGTH karakter.
##
## Tam stemmer değil — hafif, deterministik, mobil-dostu.
static func normalize(word: String) -> String:
	var w: String = word.to_lower()
	# Korunan kök — hiç kırpma
	if PROTECTED_STEMS.has(w):
		return w
	# Fixed-point: sonek kalmayana kadar tekrarla (idempotency garantisi)
	for _pass in range(MAX_NORMALIZE_PASSES):
		if PROTECTED_STEMS.has(w):
			return w
		var result: Array = _strip_one_suffix(w)
		var next_w: String = result[0]
		var changed: bool = result[1]
		if not changed:
			break
		w = next_w
	return w


## Bir metni token listesine çevirir.
## Küçük harfe çevirir, noktalama temizler, durdurma kelimelerini ve
## çok kısa kelimeleri eler.
static func tokenize(text: String) -> PackedStringArray:
	if text.is_empty():
		return PackedStringArray()

	var lower: String = text.to_lower()
	var tokens: PackedStringArray = PackedStringArray()
	var current: String = ""

	for i in range(lower.length()):
		var ch: String = lower[i]
		if _is_word_char(ch):
			current += ch
		else:
			if not current.is_empty():
				_maybe_add_token(tokens, current)
				current = ""

	# Son kelime
	if not current.is_empty():
		_maybe_add_token(tokens, current)

	return tokens


## Bir karakterin kelime karakteri olup olmadığını kontrol eder.
## Harf, rakam, alt çizgi ve Türkçe karakterler kelime karakteridir.
static func _is_word_char(ch: String) -> bool:
	if ch.is_empty():
		return false
	# ASCII harf/rakam
	var code: int = ch.unicode_at(0)
	if (code >= 48 and code <= 57):   # 0-9
		return true
	if (code >= 97 and code <= 122):  # a-z
		return true
	if ch == "_":
		return true
	# Türkçe küçük harfler: ç ğ ı ö ş ü
	if ch in ["ç", "ğ", "ı", "ö", "ş", "ü", "â", "î", "û"]:
		return true
	return false


## Bir kelimeyi token listesine ekler — eğer geçerliyse.
## Kelime önce stopword/uzunluk kontrolünden geçer, sonra normalize edilip
## kök haline indirilir. Böylece "rendering" ve "render" aynı token olur.
static func _maybe_add_token(tokens: PackedStringArray, word: String) -> void:
	if word.length() < MIN_TOKEN_LENGTH:
		return
	# Stopword kontrolü ham kelime üzerinde — normalize öncesi
	if is_stopword(word):
		return
	# Sadece rakamdan oluşan token'ları atla (anlamsal değeri düşük)
	if word.is_valid_int():
		return
	# Normalize: TR+EN soneklerini kırp, kök token'ı ekle
	var stem: String = normalize(word)
	if stem.length() < MIN_TOKEN_LENGTH:
		stem = word  # aşırı kırpma — ham kelimeye dön
	tokens.append(stem)


## Bir kelimenin durdurma kelimesi olup olmadığını kontrol eder (TR + EN).
static func is_stopword(word: String) -> bool:
	return STOPWORDS_TR.has(word) or STOPWORDS_EN.has(word)


## Bir token listesindeki benzersiz token'ları döndürür.
static func unique_tokens(tokens: PackedStringArray) -> PackedStringArray:
	var seen: Dictionary = {}
	var result: PackedStringArray = PackedStringArray()
	for t in tokens:
		if not seen.has(t):
			seen[t] = true
			result.append(t)
	return result


## Bir metindeki her token'ın kaç kez geçtiğini sayar.
## Dönen: token -> count
static func term_frequency(text: String) -> Dictionary:
	var tokens: PackedStringArray = tokenize(text)
	var tf: Dictionary = {}
	for t in tokens:
		tf[t] = int(tf.get(t, 0)) + 1
	return tf
