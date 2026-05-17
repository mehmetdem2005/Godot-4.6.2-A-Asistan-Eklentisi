@tool
class_name AICostTracker
extends RefCounted

## CostTracker — maliyet takipçisi (Layer 6).
##
## Sistem LLM sağlayıcıları kullanacak (Layer 7) — her çağrı para demek.
## Bütçe sınırlı bir projede maliyet GÖRÜNÜR ve SINIRLI olmalı.
##
## Bu sınıf:
##   - Her AICostRecord'u (Layer 0 contract) biriktirir
##   - Toplam maliyeti, sağlayıcı/rol bazında dağılımı hesaplar
##   - Bütçe sınırı tanımlanabilir — aşımda uyarı/blok
##   - Cache hit'leri ve tahminleri ayrı izler
##
## Mock policy: maliyet gerçek kayıttan toplanır — uydurma rakam yok.

## Toplam bütçe sınırı (USD). 0 = sınırsız.
var budget_limit_usd: float = 0.0

## Bütçenin bu oranı aşılınca UYARI verilir (0.8 = %80).
var warn_threshold: float = 0.8

## Tüm maliyet kayıtları (AICostRecord listesi).
var _records: Array = []


## Kayıt sayısı.
func record_count() -> int:
	return _records.size()


# ============================================================
# MALİYET KAYDI
# ============================================================

## Bir maliyet kaydı ekler.
## record: AICostRecord (Layer 0 contract).
## Dönen: bütçe durumu — {within_budget, warn, total_after}
func add_cost(record: AICostRecord) -> Dictionary:
	if record == null:
		push_warning("CostTracker.add_cost: null kayıt")
		return {"within_budget": true, "warn": false, "total_after": total_cost()}

	_records.append(record)
	var total: float = total_cost()

	var within: bool = true
	var warn: bool = false
	if budget_limit_usd > 0.0:
		within = total <= budget_limit_usd
		warn = total >= (budget_limit_usd * warn_threshold)

	return {
		"within_budget": within,
		"warn": warn,
		"total_after": total,
	}


## Bir sonraki çağrıya bütçe açısından izin var mı kontrol eder.
## estimated_cost: tahmini ek maliyet.
## Dönen: {allowed: bool, reason: String, projected_total: float}
func check_budget(estimated_cost: float) -> Dictionary:
	var projected: float = total_cost() + estimated_cost
	if budget_limit_usd <= 0.0:
		# Sınırsız bütçe
		return {"allowed": true, "reason": "", "projected_total": projected}
	if projected > budget_limit_usd:
		return {
			"allowed": false,
			"reason": "Bütçe aşımı: $%.4f > $%.4f sınır" % [
				projected, budget_limit_usd
			],
			"projected_total": projected,
		}
	return {"allowed": true, "reason": "", "projected_total": projected}


# ============================================================
# TOPLAM VE DAĞILIM
# ============================================================

## Tüm kayıtların toplam maliyeti (USD).
func total_cost() -> float:
	var sum: float = 0.0
	for r in _records:
		sum += (r as AICostRecord).total_cost_usd
	return sum


## Toplam token sayısı (input + output).
func total_tokens() -> int:
	var sum: int = 0
	for r in _records:
		sum += (r as AICostRecord).total_tokens()
	return sum


## Sağlayıcı bazında maliyet dağılımı — {provider: cost}.
func cost_by_provider() -> Dictionary:
	var dist: Dictionary = {}
	for r in _records:
		var rec: AICostRecord = r
		dist[rec.provider] = float(dist.get(rec.provider, 0.0)) + rec.total_cost_usd
	return dist


## Cell rolü bazında maliyet dağılımı — {role: cost}.
func cost_by_role() -> Dictionary:
	var dist: Dictionary = {}
	for r in _records:
		var rec: AICostRecord = r
		dist[rec.cell_role] = float(dist.get(rec.cell_role, 0.0)) + rec.total_cost_usd
	return dist


## Cache hit sayısı — cache'lenmiş (maliyetsiz) çağrılar.
func cache_hit_count() -> int:
	var n: int = 0
	for r in _records:
		if (r as AICostRecord).was_cache_hit:
			n += 1
	return n


## Cache hit oranı (0.0 - 1.0) — yüksek = iyi, para tasarrufu.
func cache_hit_rate() -> float:
	if _records.is_empty():
		return 0.0
	return float(cache_hit_count()) / float(_records.size())


# ============================================================
# BÜTÇE DURUMU
# ============================================================

## Bütçe durumu özeti.
func budget_status() -> Dictionary:
	var total: float = total_cost()
	var remaining: float = 0.0
	var used_ratio: float = 0.0
	if budget_limit_usd > 0.0:
		remaining = maxf(0.0, budget_limit_usd - total)
		used_ratio = total / budget_limit_usd
	return {
		"total_spent": total,
		"budget_limit": budget_limit_usd,
		"remaining": remaining,
		"used_ratio": used_ratio,
		"is_unlimited": budget_limit_usd <= 0.0,
		"over_budget": budget_limit_usd > 0.0 and total > budget_limit_usd,
		"in_warn_zone": (
			budget_limit_usd > 0.0
			and total >= budget_limit_usd * warn_threshold
		),
	}


## Tam özet — maliyet, token, dağılım, cache, bütçe.
func summary() -> Dictionary:
	return {
		"record_count": _records.size(),
		"total_cost_usd": total_cost(),
		"total_tokens": total_tokens(),
		"by_provider": cost_by_provider(),
		"by_role": cost_by_role(),
		"cache_hit_rate": cache_hit_rate(),
		"budget": budget_status(),
	}


## Tüm kayıtları temizler.
func reset() -> void:
	_records.clear()
