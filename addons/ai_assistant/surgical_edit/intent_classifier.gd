@tool
class_name AIIntentClassifier
extends RefCounted

## IntentClassifier — düzenleme niyeti sınıflandırıcı (Surgical Edit).
##
## Surgical Edit'in temel fikri: "şu dosyayı düzelt" demek YETERSİZ.
## Önce NE TÜR bir düzenleme olduğunu bilmek gerek — her tip farklı
## protokol ister:
##   - Yeni dosya?         -> doğrudan yazım, diff yok
##   - Fonksiyon değişimi? -> SEARCH/REPLACE, sadece o fonksiyon
##   - Sembol yeniden ad?  -> proje-geneli, dikkatli
##   - Tam dosya değişimi? -> HITL onayı ZORUNLU (tehlikeli)
##
## Bu sınıf bir görev metnini AIEditIntent.IntentType'a sınıflandırır.
## Yöntem: deterministik anahtar-kelime eşleşmesi (hızlı, ücretsiz) +
## belirsizlikte LLM'e devredilebilir bir "güven skoru".
##
## Master plan: "deterministic keyword + LLM fallback hybrid".
## Bu sürüm deterministik kısmı uygular; LLM fallback için güven
## skoru düşükse 'needs_llm' işaretler.
##
## Mock policy: sınıflandırma gerçek metin analizinden gelir.

## Sınıflandırma sonucu.
class IntentResult extends RefCounted:
	var intent_type: int = AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION
	var confidence: float = 0.0       ## 0.0-1.0 güven
	var needs_llm: bool = false       ## Güven düşük — LLM'e sor
	var matched_keywords: PackedStringArray = PackedStringArray()
	var reasoning: String = ""

	func to_dict() -> Dictionary:
		return {
			"intent_type": intent_type,
			"confidence": confidence,
			"needs_llm": needs_llm,
			"matched_keywords": matched_keywords,
			"reasoning": reasoning,
		}


## Güven bu eşiğin altındaysa LLM fallback önerilir.
const LLM_FALLBACK_THRESHOLD: float = 0.5

## Her intent tipi için tetikleyici anahtar kelimeler (TR + EN).
## Düzen: intent -> kelime listesi.
const INTENT_KEYWORDS: Dictionary = {
	AIEditIntent.IntentType.ADD_NEW_FILE: [
		"yeni dosya", "oluştur", "new file", "create file", "sıfırdan",
	],
	AIEditIntent.IntentType.ADD_TO_EXISTING: [
		"ekle", "ilave", "add", "yeni fonksiyon ekle", "append",
	],
	AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION: [
		"değiştir", "düzenle", "güncelle", "modify", "update", "change",
	],
	AIEditIntent.IntentType.MODIFY_FUNCTION_SIGNATURE: [
		"imza", "parametre", "signature", "argüman", "parameter",
	],
	AIEditIntent.IntentType.DELETE_CODE: [
		"sil", "kaldır", "delete", "remove", "temizle",
	],
	AIEditIntent.IntentType.RENAME_SYMBOL: [
		"yeniden adlandır", "ismini değiştir", "rename", "ad değiştir",
	],
	AIEditIntent.IntentType.REFACTOR: [
		"refactor", "yeniden yapılandır", "yapısal", "düzenle ve böl",
	],
	AIEditIntent.IntentType.FIX_BUG_AT_LINE: [
		"düzelt", "hata", "bug", "fix", "çöz", "hatayı",
	],
	AIEditIntent.IntentType.REPLACE_FILE: [
		"tamamen değiştir", "baştan yaz", "rewrite", "replace file",
		"hepsini yeniden",
	],
}


# ============================================================
# SINIFLANDIRMA
# ============================================================

## Bir görev metnini intent tipine sınıflandırır.
## task_text: kullanıcının/planlayıcının verdiği görev tanımı.
## has_line_hint: görevde belirli bir satır numarası geçiyor mu.
## Dönen: IntentResult.
func classify(task_text: String, has_line_hint: bool = false) -> IntentResult:
	var result := IntentResult.new()
	var lowered: String = task_text.to_lower()

	if lowered.strip_edges().is_empty():
		result.needs_llm = true
		result.confidence = 0.0
		result.reasoning = "Boş görev metni — sınıflandırılamaz"
		return result

	# Her intent için eşleşen kelimeleri puanla.
	# Puan = eşleşen kelimelerin UZUNLUK toplamı (sayı değil).
	# Gerekçe: uzun/spesifik kelime ("tamamen değiştir") kısa/genel
	# kelimeden ("değiştir") daha güçlü niyet sinyalidir. Sadece adet
	# saymak, genel kelimenin spesifik olanı bastırmasına yol açar.
	var scores: Dictionary = {}
	var all_matched: Dictionary = {}
	for intent_type in INTENT_KEYWORDS:
		var matched: PackedStringArray = PackedStringArray()
		var weight: int = 0
		for keyword in INTENT_KEYWORDS[intent_type]:
			if lowered.contains(keyword):
				matched.append(keyword)
				weight += keyword.length()
		if matched.size() > 0:
			scores[intent_type] = weight
			all_matched[intent_type] = matched

	# Satır ipucu varsa FIX_BUG_AT_LINE puanını güçlendir.
	# Puanlama uzunluk-tabanlı olduğu için, ipucu da anlamlı bir
	# ağırlık almalı — güçlü bir sinyaldir (ortalama kelime uzunluğu kadar).
	if has_line_hint:
		var fix_bug: int = AIEditIntent.IntentType.FIX_BUG_AT_LINE
		scores[fix_bug] = int(scores.get(fix_bug, 0)) + 12
		if not all_matched.has(fix_bug):
			all_matched[fix_bug] = PackedStringArray(["(satır ipucu)"])
		else:
			(all_matched[fix_bug] as PackedStringArray).append("(satır ipucu)")

	# Hiç eşleşme yok — LLM'e devret
	if scores.is_empty():
		result.needs_llm = true
		result.confidence = 0.0
		result.intent_type = AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION
		result.reasoning = "Anahtar kelime eşleşmedi — LLM sınıflandırması gerekli"
		return result

	# En yüksek puanlı intent
	var best_intent: int = -1
	var best_score: int = 0
	var total_score: int = 0
	for intent_type in scores:
		total_score += scores[intent_type]
		if scores[intent_type] > best_score:
			best_score = scores[intent_type]
			best_intent = intent_type

	result.intent_type = best_intent
	result.matched_keywords = all_matched[best_intent]
	# Güven = en iyi skorun toplam içindeki payı
	result.confidence = float(best_score) / float(total_score)
	result.needs_llm = result.confidence < LLM_FALLBACK_THRESHOLD

	if result.needs_llm:
		result.reasoning = (
			"Birden çok intent benzer puanlı (güven %.2f) — LLM doğrulaması önerilir"
			% result.confidence
		)
	else:
		result.reasoning = "Anahtar kelime eşleşmesi net (güven %.2f)" % result.confidence
	return result


# ============================================================
# RİSK / ÖZELLİK SORGULARI
# ============================================================

## Bir intent tipinin TEHLİKELİ olup olmadığı.
## REPLACE_FILE en tehlikelisi — full rewrite, HITL onayı şart.
static func is_dangerous(intent_type: int) -> bool:
	return intent_type == AIEditIntent.IntentType.REPLACE_FILE


## Bir intent tipinin proje-geneli etki yapıp yapmadığı.
## RENAME_SYMBOL diğer dosyalardaki referansları etkiler.
static func is_project_wide(intent_type: int) -> bool:
	return intent_type == AIEditIntent.IntentType.RENAME_SYMBOL


## Bir intent tipinin yeni dosya mı oluşturduğu (diff/scope gerekmez).
static func creates_new_file(intent_type: int) -> bool:
	return intent_type == AIEditIntent.IntentType.ADD_NEW_FILE


## Intent tipinin adı (AIEditIntent üzerinden — tek kaynak).
static func intent_name(intent_type: int) -> String:
	var names: Dictionary = {
		AIEditIntent.IntentType.ADD_NEW_FILE: "add_new_file",
		AIEditIntent.IntentType.ADD_TO_EXISTING: "add_to_existing",
		AIEditIntent.IntentType.MODIFY_EXISTING_FUNCTION: "modify_function",
		AIEditIntent.IntentType.MODIFY_FUNCTION_SIGNATURE: "modify_signature",
		AIEditIntent.IntentType.DELETE_CODE: "delete_code",
		AIEditIntent.IntentType.RENAME_SYMBOL: "rename_symbol",
		AIEditIntent.IntentType.REFACTOR: "refactor",
		AIEditIntent.IntentType.FIX_BUG_AT_LINE: "fix_bug_at_line",
		AIEditIntent.IntentType.REPLACE_FILE: "replace_file",
	}
	return names.get(intent_type, "unknown")
