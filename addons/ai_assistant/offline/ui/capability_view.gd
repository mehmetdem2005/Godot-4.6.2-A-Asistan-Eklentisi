@tool
class_name AIOfflineCapabilityView
extends RefCounted

## CapabilityView — yetenek paneli (Madde 07 / offline / ui).
##
## Çevrimdışıyken bazı özellikler çalışmaz (LLM çağrısı), bazıları
## çalışır (önbellekten okuma, prosedürel üretim). Kullanıcı "şu an
## ne yapabilirim" diye merak eder.
##
## Bu view-model "şu anki bağlantı durumunda her özelliğin durumu
## nedir" listesini üretir: yeşil (çalışır), sarı (sınırlı), kırmızı
## (çalışmaz). UI bu listeyi bir panelde gösterir.
##
## capability_mapper (mantık katmanı) ile beslenir; bu sınıf onu
## görsel sunuma çevirir.
##
## Mock policy: yetenek listesi gerçek bağlantı durumundan.

## Bir yeteneğin görsel durumu.
enum CapabilityState { AVAILABLE, LIMITED, UNAVAILABLE }

const STATE_NAMES: Dictionary = {
	CapabilityState.AVAILABLE: "available",
	CapabilityState.LIMITED: "limited",
	CapabilityState.UNAVAILABLE: "unavailable",
}

const STATE_COLOR: Dictionary = {
	CapabilityState.AVAILABLE: "#4caf50",
	CapabilityState.LIMITED: "#ff9800",
	CapabilityState.UNAVAILABLE: "#f44336",
}

## İzlenen özellikler ve çevrimdışı davranışları.
## offline_state: çevrimdışıyken bu özellik ne durumda.
const FEATURES: Dictionary = {
	"llm_generation": {
		"label": "AI Kod Üretimi",
		"offline_state": CapabilityState.UNAVAILABLE,
	},
	"cached_results": {
		"label": "Önbellek Sonuçları",
		"offline_state": CapabilityState.AVAILABLE,
	},
	"procedural_synth": {
		"label": "Prosedürel Ses",
		"offline_state": CapabilityState.AVAILABLE,
	},
	"rag_search": {
		"label": "Bilgi Araması",
		"offline_state": CapabilityState.LIMITED,
	},
	"file_operations": {
		"label": "Dosya İşlemleri",
		"offline_state": CapabilityState.AVAILABLE,
	},
	"cloud_sync": {
		"label": "Bulut Senkronizasyonu",
		"offline_state": CapabilityState.UNAVAILABLE,
	},
}


## Mevcut bağlantı durumu — çevrimiçi mi.
var is_online: bool = true


# ============================================================
# DURUM GÜNCELLEME
# ============================================================

## Bağlantı durumunu günceller.
func set_online(online: bool) -> void:
	is_online = online


# ============================================================
# YETENEK LİSTESİ
# ============================================================

## Bir özelliğin mevcut bağlantı durumundaki halini döndürür.
func capability_state(feature_id: String) -> int:
	if not FEATURES.has(feature_id):
		return CapabilityState.UNAVAILABLE
	# Çevrimiçiyken her özellik kullanılabilir
	if is_online:
		return CapabilityState.AVAILABLE
	# Çevrimdışı — özelliğin çevrimdışı durumu
	return int(FEATURES[feature_id]["offline_state"])


## Tüm özelliklerin görsel listesini üretir — UI panelin gösterdiği.
## Dönen: her biri {id, label, state, state_name, color} dizi.
func build_list() -> Array:
	var list: Array = []
	for feature_id in FEATURES:
		var feature_state: int = capability_state(feature_id)
		list.append({
			"id": feature_id,
			"label": str(FEATURES[feature_id]["label"]),
			"state": feature_state,
			"state_name": STATE_NAMES.get(feature_state, "?"),
			"color": STATE_COLOR.get(feature_state, "#9e9e9e"),
		})
	return list


# ============================================================
# SORGULAMA
# ============================================================

## Bir özellik şu an kullanılabilir mi?
func is_available(feature_id: String) -> bool:
	return capability_state(feature_id) == CapabilityState.AVAILABLE


## Şu an kaç özellik tam kullanılabilir?
func available_count() -> int:
	var count: int = 0
	for feature_id in FEATURES:
		if capability_state(feature_id) == CapabilityState.AVAILABLE:
			count += 1
	return count


## Şu an kaç özellik tamamen kullanılamaz?
func unavailable_count() -> int:
	var count: int = 0
	for feature_id in FEATURES:
		if capability_state(feature_id) == CapabilityState.UNAVAILABLE:
			count += 1
	return count


## İzlenen toplam özellik sayısı.
func feature_count() -> int:
	return FEATURES.size()
