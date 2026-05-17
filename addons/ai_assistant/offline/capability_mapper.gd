@tool
class_name AIOfflineCapabilityMapper
extends RefCounted

## CapabilityMapper — yetenek haritalayıcı (Madde 07 / Offline / fallback).
##
## İnternet gidince sistem çökmez ama HER ŞEYİ yapamaz. Bu sınıf
## "şu an hangi yetenekler kullanılabilir" sorusunu cevaplar.
##
## Yetenekler üç sınıfa ayrılır:
##   ONLINE_ONLY   — sadece internetle (yeni LLM cevabı, model indir)
##   CACHE_BACKED  — önbellek varsa offline da çalışır (RAG arama)
##   ALWAYS        — her zaman çalışır (şablon kodu, statik analiz)
##
## Bağlantı durumuna göre her yeteneğin GERÇEK durumunu döndürür —
## UI buna bakarak "şu an şunu yapabilirsin" panelini çizer.
##
## Mock policy: yetenek durumu gerçek bağlantı + önbellek
## varlığından hesaplanır.

## Bir yeteneğin gereksinim sınıfı.
enum Requirement { ONLINE_ONLY, CACHE_BACKED, ALWAYS }

const REQUIREMENT_NAMES: Dictionary = {
	Requirement.ONLINE_ONLY: "online_only",
	Requirement.CACHE_BACKED: "cache_backed",
	Requirement.ALWAYS: "always",
}

## Bir yeteneğin anlık kullanılabilirlik durumu.
enum Availability { AVAILABLE, DEGRADED, UNAVAILABLE }

const AVAILABILITY_NAMES: Dictionary = {
	Availability.AVAILABLE: "available",
	Availability.DEGRADED: "degraded",
	Availability.UNAVAILABLE: "unavailable",
}

## Sistemin bilinen yetenekleri ve gereksinim sınıfları.
const CAPABILITIES: Dictionary = {
	"new_llm_response": Requirement.ONLINE_ONLY,
	"model_download": Requirement.ONLINE_ONLY,
	"cloud_sync": Requirement.ONLINE_ONLY,
	"rag_search": Requirement.CACHE_BACKED,
	"cached_llm_response": Requirement.CACHE_BACKED,
	"embedding_lookup": Requirement.CACHE_BACKED,
	"template_codegen": Requirement.ALWAYS,
	"static_analysis": Requirement.ALWAYS,
	"local_save": Requirement.ALWAYS,
	"surgical_edit": Requirement.ALWAYS,
}


# ============================================================
# YETENEK SORGULAMA
# ============================================================

## Bir yeteneğin gereksinim sınıfını döndürür.
## Bilinmeyen yetenek için ONLINE_ONLY (güvenli taraf).
func requirement_of(capability: String) -> int:
	return int(CAPABILITIES.get(capability, Requirement.ONLINE_ONLY))


## Bir yeteneğin anlık kullanılabilirliğini hesaplar.
## capability: yetenek adı. online: bağlantı kullanılabilir mi.
## has_cache: bu yetenek için önbellek var mı.
## Dönen: Availability.
func evaluate(
	capability: String, online: bool, has_cache: bool = false
) -> int:
	var req: int = requirement_of(capability)
	match req:
		Requirement.ALWAYS:
			# Her zaman çalışır — bağlantıdan bağımsız
			return Availability.AVAILABLE
		Requirement.CACHE_BACKED:
			if online:
				return Availability.AVAILABLE
			# Çevrimdışı — önbellek varsa daralarak çalışır
			if has_cache:
				return Availability.DEGRADED
			return Availability.UNAVAILABLE
		Requirement.ONLINE_ONLY:
			# Sadece bağlantıyla
			if online:
				return Availability.AVAILABLE
			return Availability.UNAVAILABLE
		_:
			return Availability.UNAVAILABLE


## Bir yetenek şu an kullanılabilir mi (available veya degraded)?
func is_usable(
	capability: String, online: bool, has_cache: bool = false
) -> bool:
	return evaluate(capability, online, has_cache) != \
		Availability.UNAVAILABLE


# ============================================================
# TOPLU DEĞERLENDİRME
# ============================================================

## Tüm yeteneklerin anlık durumunu döndürür — UI paneli için.
## online: bağlantı durumu. cached_capabilities: önbelleği olan
## yeteneklerin adları.
## Dönen: {capability: availability_name}
func evaluate_all(online: bool, cached_capabilities: Array) -> Dictionary:
	var cache_set: Dictionary = {}
	for cap in cached_capabilities:
		cache_set[cap] = true
	var result: Dictionary = {}
	for capability in CAPABILITIES:
		var has_cache: bool = cache_set.has(capability)
		var availability: int = evaluate(capability, online, has_cache)
		result[capability] = AVAILABILITY_NAMES[availability]
	return result


## Çevrimdışıyken kaç yetenek hâlâ kullanılabilir?
func offline_capability_count(cached_capabilities: Array) -> int:
	var count: int = 0
	var states: Dictionary = evaluate_all(false, cached_capabilities)
	for capability in states:
		if str(states[capability]) != AVAILABILITY_NAMES[
			Availability.UNAVAILABLE
		]:
			count += 1
	return count


## Toplam bilinen yetenek sayısı.
func total_capabilities() -> int:
	return CAPABILITIES.size()
