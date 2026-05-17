@tool
class_name AIOfflineLLMCache
extends RefCounted

## LLMResponseCache — LLM cevap önbelleği (Madde 07 / Offline / cache).
##
## En pahalı kaynak: LLM çağrıları (para, zaman, ağ). Aynı isteği iki
## kez yapmak israf. Bu önbellek bir LLM cevabını saklar — aynı istek
## tekrar gelirse ağa çıkmadan, anında cevap verir.
##
## Offline değeri: internet gidince bile, daha önce sorulmuş şeyler
## önbellekten cevaplanır. Sistem daralarak ama çalışmaya devam eder.
##
## Anahtar üretimi kritik: aynı prompt + aynı model + aynı sıcaklık
## = aynı anahtar. Sıcaklık farkı bile ayrı anahtar (farklı sonuç).
##
## CacheBase'i sarmalar — LRU+TTL oradan gelir, bu sınıf sadece
## LLM'e özel anahtar üretir.
##
## Mock policy: önbellek gerçek LLM cevaplarından dolar.

## LLM cevapları için varsayılan TTL — uzun (cevaplar bayatlamaz).
const LLM_TTL_SECONDS: int = 86400  # 24 saat

## Maksimum önbellek girdisi.
const LLM_MAX_ENTRIES: int = 200


## Alttaki genel önbellek.
var _cache: AIOfflineCacheBase


func _init() -> void:
	_cache = AIOfflineCacheBase.new(LLM_MAX_ENTRIES, LLM_TTL_SECONDS)


# ============================================================
# ANAHTAR ÜRETİMİ
# ============================================================

## Bir LLM isteği için deterministik önbellek anahtarı üretir.
## prompt: istek metni. model: model adı. temperature: sıcaklık.
## Aynı üçlü her zaman aynı anahtarı verir.
func make_key(prompt: String, model: String, temperature: float) -> String:
	# Sıcaklığı sabit hassasiyete yuvarla — 0.70 ve 0.700 aynı olsun
	var temp_str: String = "%.2f" % temperature
	var raw: String = "%s|%s|%s" % [model, temp_str, prompt]
	# İçerik hash'i — uzun prompt'lar kısa anahtara iner
	return "llm_" + str(raw.hash())


# ============================================================
# YAZMA / OKUMA
# ============================================================

## Bir LLM cevabını önbelleğe yazar.
## prompt/model/temperature: istek tanımı. response: LLM cevabı.
func store(
	prompt: String, model: String, temperature: float, response: String
) -> void:
	var key: String = make_key(prompt, model, temperature)
	_cache.put(key, response)


## Bir LLM isteği için önbellekteki cevabı arar.
## Dönen: {hit: bool, response: String}
func lookup(
	prompt: String, model: String, temperature: float
) -> Dictionary:
	var key: String = make_key(prompt, model, temperature)
	var result: Dictionary = _cache.get_value(key)
	if result["hit"]:
		return {"hit": true, "response": str(result["value"])}
	return {"hit": false, "response": ""}


## Bir LLM isteği önbellekte var mı?
func is_cached(
	prompt: String, model: String, temperature: float
) -> bool:
	return _cache.has_valid(make_key(prompt, model, temperature))


# ============================================================
# YÖNETİM
# ============================================================

## Önbelleği temizler.
func clear() -> void:
	_cache.clear()


## Süresi dolmuş girdileri temizler.
func purge_expired() -> int:
	return _cache.purge_expired()


## Alttaki önbelleğe erişim — istatistik için.
func cache() -> AIOfflineCacheBase:
	return _cache


## Özet.
func summary() -> Dictionary:
	return _cache.summary()
