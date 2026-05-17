@tool
class_name AIAudioBudgetGauge
extends RefCounted

## AudioBudgetGauge — ses bütçe göstergesi (Madde 08 / audio / ui).
##
## audio_budget_enforcer verisini görsel bir göstergeye çevirir:
## dolu bir çubuk, renk (yeşil/sarı/kırmızı), yüklü ses listesi.
##
## Geliştirici bir bakışta "ses belleğinin ne kadarı dolu, hangi
## sesler yer kaplıyor" görür.
##
## audio_budget_enforcer + memory_estimator (mantık katmanı) ile
## beslenir; bu sınıf onu görsel göstergeye çevirir.
##
## Mock policy: gösterge gerçek bütçe verisinden.

## Gösterge durumu.
enum GaugeState { HEALTHY, WARNING, CRITICAL }

const STATE_NAMES: Dictionary = {
	GaugeState.HEALTHY: "healthy",
	GaugeState.WARNING: "warning",
	GaugeState.CRITICAL: "critical",
}

const STATE_COLOR: Dictionary = {
	GaugeState.HEALTHY: "#4caf50",
	GaugeState.WARNING: "#ff9800",
	GaugeState.CRITICAL: "#f44336",
}

## Uyarı bölgesi eşiği.
const WARNING_RATIO: float = 0.80


# ============================================================
# GÖSTERGE
# ============================================================

## Bütçe verisinden gösterge durumunu hesaplar.
## used_bytes: kullanılan bellek. budget_bytes: bütçe.
## Dönen: {state, state_name, color, ratio, label}
func build_gauge(used_bytes: int, budget_bytes: int) -> Dictionary:
	var ratio: float = 0.0
	if budget_bytes > 0:
		ratio = clampf(
			float(used_bytes) / float(budget_bytes), 0.0, 1.0
		)

	var state: int
	if used_bytes >= budget_bytes and budget_bytes > 0:
		state = GaugeState.CRITICAL
	elif ratio >= WARNING_RATIO:
		state = GaugeState.WARNING
	else:
		state = GaugeState.HEALTHY

	var used_mb: float = float(used_bytes) / (1024.0 * 1024.0)
	var budget_mb: float = float(budget_bytes) / (1024.0 * 1024.0)

	return {
		"state": state,
		"state_name": STATE_NAMES.get(state, "?"),
		"color": STATE_COLOR.get(state, "#9e9e9e"),
		"ratio": ratio,
		"label": "%.1f / %.1f MB" % [used_mb, budget_mb],
	}


# ============================================================
# YÜKLÜ SES LİSTESİ
# ============================================================

## Yüklü seslerin görsel listesini üretir — büyükten küçüğe.
## loaded_sounds: sound_id -> bayt sözlüğü.
## Dönen: her biri {id, bytes, mb, percent} dizi.
func build_sound_list(loaded_sounds: Dictionary) -> Array:
	var total: int = 0
	for sound_id in loaded_sounds:
		total += int(loaded_sounds[sound_id])

	var list: Array = []
	for sound_id in loaded_sounds:
		var bytes: int = int(loaded_sounds[sound_id])
		var percent: float = 0.0
		if total > 0:
			percent = (float(bytes) / float(total)) * 100.0
		list.append({
			"id": sound_id,
			"bytes": bytes,
			"mb": float(bytes) / (1024.0 * 1024.0),
			"percent": percent,
		})
	# Büyükten küçüğe — en çok yer kaplayan üstte
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["bytes"]) > int(b["bytes"]))
	return list


## En çok yer kaplayan sesi döndürür. Liste boşsa boş string.
func largest_sound(loaded_sounds: Dictionary) -> String:
	var largest_id: String = ""
	var largest_bytes: int = -1
	for sound_id in loaded_sounds:
		var bytes: int = int(loaded_sounds[sound_id])
		if bytes > largest_bytes:
			largest_bytes = bytes
			largest_id = sound_id
	return largest_id


# ============================================================
# SORGULAMA
# ============================================================

## Gösterge uyarı veriyor mu?
func shows_warning(used_bytes: int, budget_bytes: int) -> bool:
	var gauge: Dictionary = build_gauge(used_bytes, budget_bytes)
	return int(gauge["state"]) != GaugeState.HEALTHY
