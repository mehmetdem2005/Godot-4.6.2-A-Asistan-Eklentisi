@tool
class_name AISettingsModel
extends RefCounted

## SettingsModel — Ayarlar sekmesi modeli (Layer 11 / Workspace).
##
## Kullanıcının eklentiyi yapılandırdığı sekme. Hangi LLM modu,
## bütçe limiti, otomasyon seviyesi, mobil performans profili.
##
## Bu model ayarları tutar ve DOĞRULAR — geçersiz değer kabul
## edilmez. Ayarlar diğer katmanlara (Router, QualityGate, HITL)
## aktarılabilir biçimde sunulur.
##
## Mock policy: ayarlar kullanıcıdan gelir; geçersiz değer
## reddedilir, sessizce düzeltilmez.

## LLM çalışma modu — Layer 7 Router ile uyumlu.
enum LLMMode { ECO, SINGLE, QUALITY, PROFESSIONAL }

const LLM_MODE_NAMES: Dictionary = {
	LLMMode.ECO: "Ekonomik",
	LLMMode.SINGLE: "Tek Sağlayıcı",
	LLMMode.QUALITY: "Kalite",
	LLMMode.PROFESSIONAL: "Profesyonel",
}

## Otomasyon seviyesi — sistem ne kadar kendi başına çalışsın.
enum AutomationLevel { MANUAL, ASSISTED, AUTONOMOUS }

const AUTOMATION_NAMES: Dictionary = {
	AutomationLevel.MANUAL: "Manuel",
	AutomationLevel.ASSISTED: "Yardımlı",
	AutomationLevel.AUTONOMOUS: "Otonom",
}


## Ayar alanları.
var llm_mode: int = LLMMode.SINGLE
var automation_level: int = AutomationLevel.ASSISTED
var budget_limit_usd: float = 5.0           ## Maliyet sınırı
var mobile_tier: int = 1                     ## QualityGate Tier (0/1/2)
var live_mode: bool = false                  ## Gerçek LLM çağrısı açık mı
var auto_checkpoint: bool = true             ## Otomatik kontrol noktası


# ============================================================
# AYAR DEĞİŞTİRME — doğrulamalı
# ============================================================

## LLM modunu ayarlar. Geçersizse değişmez, false döner.
func set_llm_mode(mode: int) -> bool:
	if not LLM_MODE_NAMES.has(mode):
		push_warning("SettingsModel: geçersiz LLM modu")
		return false
	llm_mode = mode
	return true


## Otomasyon seviyesini ayarlar.
func set_automation_level(level: int) -> bool:
	if not AUTOMATION_NAMES.has(level):
		push_warning("SettingsModel: geçersiz otomasyon seviyesi")
		return false
	automation_level = level
	return true


## Bütçe limitini ayarlar. Negatif değer reddedilir.
func set_budget_limit(limit: float) -> bool:
	if limit < 0.0:
		push_warning("SettingsModel: bütçe limiti negatif olamaz")
		return false
	budget_limit_usd = limit
	return true


## Mobil performans profilini ayarlar (0=düşük, 1=orta, 2=yüksek).
func set_mobile_tier(tier: int) -> bool:
	if tier < 0 or tier > 2:
		push_warning("SettingsModel: mobil tier 0-2 aralığında olmalı")
		return false
	mobile_tier = tier
	return true


## Canlı modu ayarlar.
func set_live_mode(value: bool) -> void:
	live_mode = value


## Otomatik kontrol noktasını ayarlar.
func set_auto_checkpoint(value: bool) -> void:
	auto_checkpoint = value


# ============================================================
# SORGULAMA
# ============================================================

## Otonom modda mı çalışıyor?
func is_autonomous() -> bool:
	return automation_level == AutomationLevel.AUTONOMOUS


## Canlı mod güvenli mi — otonom + canlı tehlikeli kombinasyon.
## Otonom + canlı: sistem onaysız gerçek değişiklik yapabilir.
func is_live_safe() -> bool:
	# Otonom + canlı mod birlikteyse, en azından otomatik checkpoint açık olmalı
	if is_autonomous() and live_mode:
		return auto_checkpoint
	return true


## LLM modu adı.
func llm_mode_name() -> String:
	return LLM_MODE_NAMES.get(llm_mode, "?")


## Otomasyon seviyesi adı.
func automation_name() -> String:
	return AUTOMATION_NAMES.get(automation_level, "?")


# ============================================================
# DIŞA AKTARMA
# ============================================================

## Ayarları sözlük olarak — diğer katmanlara aktarım için.
func to_dict() -> Dictionary:
	return {
		"llm_mode": llm_mode,
		"llm_mode_name": llm_mode_name(),
		"automation_level": automation_level,
		"automation_name": automation_name(),
		"budget_limit_usd": budget_limit_usd,
		"mobile_tier": mobile_tier,
		"live_mode": live_mode,
		"auto_checkpoint": auto_checkpoint,
		"is_live_safe": is_live_safe(),
	}


## Bir sözlükten ayarları yükler — doğrulamadan geçirir.
func from_dict(data: Dictionary) -> void:
	if data.has("llm_mode"):
		set_llm_mode(int(data["llm_mode"]))
	if data.has("automation_level"):
		set_automation_level(int(data["automation_level"]))
	if data.has("budget_limit_usd"):
		set_budget_limit(float(data["budget_limit_usd"]))
	if data.has("mobile_tier"):
		set_mobile_tier(int(data["mobile_tier"]))
	if data.has("live_mode"):
		set_live_mode(bool(data["live_mode"]))
	if data.has("auto_checkpoint"):
		set_auto_checkpoint(bool(data["auto_checkpoint"]))


## Ayarları varsayılana sıfırlar.
func reset() -> void:
	llm_mode = LLMMode.SINGLE
	automation_level = AutomationLevel.ASSISTED
	budget_limit_usd = 5.0
	mobile_tier = 1
	live_mode = false
	auto_checkpoint = true
