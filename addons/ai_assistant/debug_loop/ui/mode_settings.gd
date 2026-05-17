@tool
class_name AIDebugModeSettings
extends RefCounted

## ModeSettings — debug mod ayarları (Madde 02 / debug_loop / ui).
##
## Settings ekranındaki debug mod seçicisi. AI'ın hata yakalandığında
## nasıl davranacağını belirler: otomatik düzeltsin mi, sadece önersin
## mi, hiç karışmasın mı.
##
## Bu view-model seçili modu ve mod seçeneklerini yönetir. Görsel
## dropdown bunu okur.
##
## debug_loop davranışını yönlendirir.
##
## Mock policy: ayar gerçek kullanıcı tercihinden.

## Debug çalışma modları.
enum DebugMode { OFF, OBSERVE, SUGGEST, AUTO_FIX }

const MODE_NAMES: Dictionary = {
	DebugMode.OFF: "off",
	DebugMode.OBSERVE: "observe",
	DebugMode.SUGGEST: "suggest",
	DebugMode.AUTO_FIX: "auto_fix",
}

## Her modun kullanıcı-dostu açıklaması.
const MODE_INFO: Dictionary = {
	DebugMode.OFF: {
		"label": "Kapalı",
		"description": "Hata yakalama devre dışı.",
	},
	DebugMode.OBSERVE: {
		"label": "Gözlem",
		"description": "Hatalar yakalanır ve listelenir, müdahale yok.",
	},
	DebugMode.SUGGEST: {
		"label": "Öneri",
		"description": "Hatalar yakalanır, AI düzeltme önerir — "
			+ "uygulamak için onay gerekir.",
	},
	DebugMode.AUTO_FIX: {
		"label": "Otomatik Düzeltme",
		"description": "AI güvenli düzeltmeleri otomatik uygular, "
			+ "riskli olanlar için onay ister.",
	},
}


## Şu an seçili mod.
var current_mode: int = DebugMode.SUGGEST


# ============================================================
# MOD SEÇİMİ
# ============================================================

## Debug modunu ayarlar.
## mode: DebugMode değeri.
## Dönen: {applied: bool, reason: String}
func set_mode(mode: int) -> Dictionary:
	if not MODE_NAMES.has(mode):
		return {"applied": false, "reason": "Geçersiz debug modu"}
	current_mode = mode
	return {
		"applied": true,
		"reason": "Debug modu: " + str(MODE_INFO[mode]["label"]),
	}


# ============================================================
# SUNUM
# ============================================================

## Dropdown seçeneklerinin listesini üretir.
## Dönen: her biri {mode, name, label, description, selected} dizi.
func build_options() -> Array:
	var options: Array = []
	for mode in MODE_INFO:
		options.append({
			"mode": mode,
			"name": MODE_NAMES[mode],
			"label": str(MODE_INFO[mode]["label"]),
			"description": str(MODE_INFO[mode]["description"]),
			"selected": mode == current_mode,
		})
	return options


## Seçili modun etiketi.
func current_label() -> String:
	return str(MODE_INFO.get(current_mode, {}).get("label", "?"))


## Seçili modun adı.
func current_mode_name() -> String:
	return MODE_NAMES.get(current_mode, "?")


## Seçili modun açıklaması.
func current_description() -> String:
	return str(MODE_INFO.get(current_mode, {}).get("description", ""))


# ============================================================
# DAVRANIŞ SORGULARI — debug_loop bunları okur
# ============================================================

## Hata yakalama aktif mi?
func is_capture_enabled() -> bool:
	return current_mode != DebugMode.OFF


## AI düzeltme önerisi üretmeli mi?
func should_suggest_fixes() -> bool:
	return current_mode == DebugMode.SUGGEST \
		or current_mode == DebugMode.AUTO_FIX


## AI güvenli düzeltmeleri otomatik uygulamalı mı?
func should_auto_apply() -> bool:
	return current_mode == DebugMode.AUTO_FIX


# ============================================================
# KALICILIK
# ============================================================

## Ayarı kaydetmek için sözlüğe çevirir.
func to_dict() -> Dictionary:
	return {"debug_mode": current_mode}


## Kaydedilmiş ayarı yükler.
func from_dict(data: Dictionary) -> void:
	var mode: int = int(data.get("debug_mode", DebugMode.SUGGEST))
	if MODE_NAMES.has(mode):
		current_mode = mode


## Toplam mod sayısı.
func mode_count() -> int:
	return MODE_INFO.size()
