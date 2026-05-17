@tool
class_name AIModeController
extends RefCounted

## ModeController — çalışma modu kontrolcüsü (Layer 7).
##
## Sistem farklı "modlar"da çalışabilir — kalite/maliyet dengesi:
##
## OperationMode (kalite-maliyet ekseni):
##   ECO       — en ucuz model, düşük token, agresif cache. Bütçe önce.
##   BALANCED  — orta. Varsayılan.
##   QUALITY   — en güçlü model, yüksek token. Sonuç önce.
##
## AccessMode (sağlayıcı erişim ekseni):
##   SINGLE       — sadece DeepSeek (master plan başlangıcı, bütçe dostu)
##   PROFESSIONAL — tüm sağlayıcılar açık, router en iyisini seçer
##
## Bu sınıf modlara göre somut parametreler üretir: hangi sağlayıcı,
## kaç token, hangi sıcaklık, cache ne kadar agresif.

## Kalite-maliyet modu.
enum OperationMode { ECO, BALANCED, QUALITY }

const OPERATION_MODE_NAMES: Dictionary = {
	OperationMode.ECO: "eco",
	OperationMode.BALANCED: "balanced",
	OperationMode.QUALITY: "quality",
}

## Sağlayıcı erişim modu.
enum AccessMode { SINGLE, PROFESSIONAL }

const ACCESS_MODE_NAMES: Dictionary = {
	AccessMode.SINGLE: "single",
	AccessMode.PROFESSIONAL: "professional",
}

## Aktif modlar — varsayılan: BALANCED + SINGLE (master plan başlangıcı).
var operation_mode: int = OperationMode.BALANCED
var access_mode: int = AccessMode.SINGLE


# ============================================================
# MOD AYARLAMA
# ============================================================

## Kalite-maliyet modunu ayarlar.
func set_operation_mode(mode: int) -> void:
	if OPERATION_MODE_NAMES.has(mode):
		operation_mode = mode
	else:
		push_warning("ModeController: geçersiz operation mode %d" % mode)


## Sağlayıcı erişim modunu ayarlar.
func set_access_mode(mode: int) -> void:
	if ACCESS_MODE_NAMES.has(mode):
		access_mode = mode
	else:
		push_warning("ModeController: geçersiz access mode %d" % mode)


## Operation modunun adı.
func operation_mode_name() -> String:
	return OPERATION_MODE_NAMES.get(operation_mode, "balanced")


## Access modunun adı.
func access_mode_name() -> String:
	return ACCESS_MODE_NAMES.get(access_mode, "single")


# ============================================================
# MODA GÖRE PARAMETRELER
# ============================================================

## Mevcut moda göre max_tokens değeri üretir.
## ECO az token (ucuz), QUALITY çok token (zengin yanıt).
func resolve_max_tokens(base_max_tokens: int) -> int:
	match operation_mode:
		OperationMode.ECO:
			# Ucuz: token'ı kırp (en az 256)
			return maxi(256, base_max_tokens / 2)
		OperationMode.QUALITY:
			# Zengin: token'ı artır
			return base_max_tokens * 2
		_:
			return base_max_tokens


## Mevcut moda göre temperature üretir.
## ECO/QUALITY arası fark küçük — ama QUALITY biraz daha yaratıcı olabilir.
func resolve_temperature(base_temperature: float) -> float:
	match operation_mode:
		OperationMode.ECO:
			# Deterministik = daha az "deneme", daha öngörülebilir
			return clampf(base_temperature - 0.2, 0.0, 2.0)
		OperationMode.QUALITY:
			return base_temperature
		_:
			return base_temperature


## Cache'in ne kadar agresif kullanılacağı.
## ECO modda cache her zaman kullanılır (tasarruf önce).
## QUALITY modda da kullanılır ama Eco kadar "ısrarcı" değil.
## Şu an ikisi de cache kullanır — ayrım gelecekteki TTL/benzerlik içindir.
func should_use_cache() -> bool:
	# Tüm modlarda cache açık — para tasarrufu her zaman değerli.
	return true


## SINGLE modda mı — yani sadece DeepSeek mi kullanılmalı?
func is_single_provider() -> bool:
	return access_mode == AccessMode.SINGLE


# ============================================================
# SAĞLAYICI SEÇİM POLİTİKASI
# ============================================================

## Bu moda göre KULLANILABİLİR sağlayıcı listesini döndürür.
## SINGLE: sadece DeepSeek. PROFESSIONAL: hepsi.
## Dönen: AIProviderRequest.Provider enum değerleri.
func allowed_providers() -> Array:
	if access_mode == AccessMode.SINGLE:
		return [AIProviderRequest.Provider.DEEPSEEK]
	# PROFESSIONAL — hepsi açık
	return [
		AIProviderRequest.Provider.DEEPSEEK,
		AIProviderRequest.Provider.OPENAI,
		AIProviderRequest.Provider.ANTHROPIC,
		AIProviderRequest.Provider.GEMINI,
	]


## Bu mod + amaç için TERCİH EDİLEN sağlayıcıyı döndürür.
## QUALITY modda güçlü sağlayıcı, ECO modda ucuz olan tercih edilir.
## SINGLE modda her zaman DeepSeek.
## purpose: AIProviderRequest.Purpose enum değeri.
func preferred_provider(purpose: int) -> int:
	# SINGLE — seçim yok
	if access_mode == AccessMode.SINGLE:
		return AIProviderRequest.Provider.DEEPSEEK

	# PROFESSIONAL — mod + amaca göre
	match operation_mode:
		OperationMode.ECO:
			# Ucuz: DeepSeek veya Gemini Flash
			return AIProviderRequest.Provider.DEEPSEEK
		OperationMode.QUALITY:
			# Güçlü: kod için Anthropic, akıl yürütme için de Anthropic
			if purpose == AIProviderRequest.Purpose.CODE:
				return AIProviderRequest.Provider.ANTHROPIC
			return AIProviderRequest.Provider.ANTHROPIC
		_:
			# BALANCED — OpenAI orta nokta
			return AIProviderRequest.Provider.OPENAI


## Mevcut mod durumunun özeti.
func status() -> Dictionary:
	return {
		"operation_mode": operation_mode_name(),
		"access_mode": access_mode_name(),
		"allowed_providers": allowed_providers(),
		"cache_enabled": should_use_cache(),
	}
