@tool
class_name AICostModel
extends RefCounted

## CostModel — Maliyet sekmesi modeli (Layer 11 / Workspace).
##
## Layer 6 maliyet kaydı tutar (her LLM çağrısının token + ücreti).
## Bu model o veriyi UI'da gösterilebilir biçime getirir: toplam
## harcama, sağlayıcı dağılımı, bütçeye göre durum.
##
## Mehmet'in bütçesi sınırlı — bu sekme "ne kadar harcadım, sınıra
## ne kadar var" sorusunun cevabıdır.
##
## Mock policy: maliyet kayıtları gerçek çağrılardan eklenir;
## model sayı uydurmaz.

## Bütçe durumu.
enum BudgetStatus { HEALTHY, WARNING, EXCEEDED }

const BUDGET_STATUS_NAMES: Dictionary = {
	BudgetStatus.HEALTHY: "İyi",
	BudgetStatus.WARNING: "Uyarı",
	BudgetStatus.EXCEEDED: "Aşıldı",
}

## Bütçenin bu oranına ulaşınca uyarı.
const WARNING_THRESHOLD: float = 0.8


## Tek bir maliyet kaydı.
class CostEntry extends RefCounted:
	var provider: String = ""
	var cost_usd: float = 0.0
	var input_tokens: int = 0
	var output_tokens: int = 0
	var from_cache: bool = false

	func to_dict() -> Dictionary:
		return {
			"provider": provider,
			"cost_usd": cost_usd,
			"tokens": input_tokens + output_tokens,
			"from_cache": from_cache,
		}


## Maliyet kayıtları.
var _entries: Array = []

## Bütçe limiti (USD). 0 = limitsiz.
var budget_limit_usd: float = 0.0


func _init(p_budget: float = 0.0) -> void:
	budget_limit_usd = maxf(p_budget, 0.0)


# ============================================================
# KAYIT
# ============================================================

## Bir maliyet kaydı ekler.
func record(
	provider: String, cost_usd: float, input_tokens: int,
	output_tokens: int, from_cache: bool = false
) -> void:
	var entry := CostEntry.new()
	entry.provider = provider
	entry.cost_usd = maxf(cost_usd, 0.0)
	entry.input_tokens = maxi(input_tokens, 0)
	entry.output_tokens = maxi(output_tokens, 0)
	entry.from_cache = from_cache
	_entries.append(entry)


# ============================================================
# TOPLAMLAR
# ============================================================

## Toplam harcama (USD).
func total_cost() -> float:
	var total: float = 0.0
	for entry in _entries:
		total += (entry as CostEntry).cost_usd
	return total


## Toplam token (girdi + çıktı).
func total_tokens() -> int:
	var total: int = 0
	for entry in _entries:
		var e: CostEntry = entry
		total += e.input_tokens + e.output_tokens
	return total


## Çağrı sayısı.
func call_count() -> int:
	return _entries.size()


## Cache'ten gelen çağrı oranı (0.0 - 1.0).
## Cache hit = ücretsiz çağrı, yüksek oran iyi.
func cache_hit_ratio() -> float:
	if _entries.is_empty():
		return 0.0
	var hits: int = 0
	for entry in _entries:
		if (entry as CostEntry).from_cache:
			hits += 1
	return float(hits) / float(_entries.size())


## Sağlayıcı bazında maliyet dağılımı.
## Dönen: {provider: toplam_maliyet}.
func cost_by_provider() -> Dictionary:
	var by_provider: Dictionary = {}
	for entry in _entries:
		var e: CostEntry = entry
		var current: float = by_provider.get(e.provider, 0.0)
		by_provider[e.provider] = current + e.cost_usd
	return by_provider


# ============================================================
# BÜTÇE
# ============================================================

## Bütçe kullanım oranı (0.0 - 1.0+). Limit yoksa 0.
func budget_ratio() -> float:
	if budget_limit_usd <= 0.0:
		return 0.0
	return total_cost() / budget_limit_usd


## Bütçe durumu — HEALTHY / WARNING / EXCEEDED.
func budget_status() -> int:
	if budget_limit_usd <= 0.0:
		return BudgetStatus.HEALTHY  # limitsiz
	var ratio: float = budget_ratio()
	if ratio >= 1.0:
		return BudgetStatus.EXCEEDED
	if ratio >= WARNING_THRESHOLD:
		return BudgetStatus.WARNING
	return BudgetStatus.HEALTHY


## Bütçe durum adı.
func budget_status_name() -> String:
	return BUDGET_STATUS_NAMES.get(budget_status(), "?")


## Bütçe aşıldı mı?
func is_over_budget() -> bool:
	return budget_status() == BudgetStatus.EXCEEDED


# ============================================================
# UI
# ============================================================

## UI'da gösterilecek özet kartları.
func summary_cards() -> Array:
	return [
		{"label": "Toplam", "value": "$%.4f" % total_cost()},
		{"label": "Çağrı", "value": str(call_count())},
		{"label": "Token", "value": str(total_tokens())},
		{"label": "Cache", "value": "%d%%" % int(
			cache_hit_ratio() * 100.0
		)},
		{"label": "Bütçe", "value": budget_status_name()},
	]


## Tam durum.
func to_dict() -> Dictionary:
	return {
		"total_cost": total_cost(),
		"total_tokens": total_tokens(),
		"call_count": call_count(),
		"cache_hit_ratio": cache_hit_ratio(),
		"budget_ratio": budget_ratio(),
		"budget_status": budget_status_name(),
	}


## Maliyet kayıtlarını temizler.
func clear() -> void:
	_entries.clear()
