@tool
class_name AISaveProgressIndicator
extends RefCounted

## SaveProgressIndicator — kayıt ilerleme göstergesi (Madde 09 / ui).
##
## Kayıt yapılırken ekranın köşesinde küçük bir 💾 ikonu belirir,
## kayıt bitince kaybolur. Otomatik kayıtta da çalışır — oyuncu
## "kaydedildi" geri bildirimini görür.
##
## Bu view-model göstergenin görünürlük durumunu yönetir: gösteriliyor
## mu, hangi aşamada (kaydediliyor / tamam / hata), ne kadar süre
## daha görünür kalacak.
##
## save_manager olayları (mantık katmanı) ile beslenir.
##
## Mock policy: gösterge gerçek kayıt olaylarından.

## Gösterge görsel durumu.
enum IndicatorPhase { HIDDEN, SAVING, SUCCESS, ERROR }

const PHASE_NAMES: Dictionary = {
	IndicatorPhase.HIDDEN: "hidden",
	IndicatorPhase.SAVING: "saving",
	IndicatorPhase.SUCCESS: "success",
	IndicatorPhase.ERROR: "error",
}

const PHASE_ICON: Dictionary = {
	IndicatorPhase.SAVING: "save_progress",
	IndicatorPhase.SUCCESS: "save_done",
	IndicatorPhase.ERROR: "save_failed",
}

## "Tamam"/"hata" göstergesinin ekranda kalma süresi (saniye).
const RESULT_DISPLAY_SECONDS: float = 2.0


## Mevcut aşama.
var phase: int = IndicatorPhase.HIDDEN

## Sonuç gösteriminde kalan süre.
var _remaining_time: float = 0.0


# ============================================================
# KAYIT OLAYLARI
# ============================================================

## Kayıt başladı — gösterge "kaydediliyor" durumuna geçer.
func on_save_started() -> void:
	phase = IndicatorPhase.SAVING
	_remaining_time = 0.0


## Kayıt başarıyla bitti — "tamam" gösterilir, sonra kaybolur.
func on_save_succeeded() -> void:
	phase = IndicatorPhase.SUCCESS
	_remaining_time = RESULT_DISPLAY_SECONDS


## Kayıt başarısız — "hata" gösterilir, sonra kaybolur.
func on_save_failed() -> void:
	phase = IndicatorPhase.ERROR
	_remaining_time = RESULT_DISPLAY_SECONDS


# ============================================================
# ZAMANLAMA
# ============================================================

## Zamanı ilerletir — sonuç göstergesinin süresini azaltır.
## delta_seconds: geçen süre.
## Dönen: {visible: bool, changed: bool}
func tick(delta_seconds: float) -> Dictionary:
	var changed: bool = false

	# Sonuç gösteriminde — süreyi azalt
	if phase == IndicatorPhase.SUCCESS or phase == IndicatorPhase.ERROR:
		_remaining_time -= delta_seconds
		if _remaining_time <= 0.0:
			phase = IndicatorPhase.HIDDEN
			changed = true

	return {
		"visible": phase != IndicatorPhase.HIDDEN,
		"changed": changed,
	}


# ============================================================
# SUNUM
# ============================================================

## Göstergenin görsel verisini üretir.
## Dönen: {visible, phase, icon, animated}
func presentation() -> Dictionary:
	return {
		"visible": phase != IndicatorPhase.HIDDEN,
		"phase": PHASE_NAMES.get(phase, "?"),
		"icon": PHASE_ICON.get(phase, ""),
		# "Kaydediliyor" aşamasında ikon animasyonlu döner
		"animated": phase == IndicatorPhase.SAVING,
	}


# ============================================================
# SORGULAMA
# ============================================================

## Gösterge şu an görünür mü?
func is_visible() -> bool:
	return phase != IndicatorPhase.HIDDEN


## Şu an kayıt sürüyor mu?
func is_saving() -> bool:
	return phase == IndicatorPhase.SAVING


## Son kayıt başarısız mı sonuçlandı?
func shows_error() -> bool:
	return phase == IndicatorPhase.ERROR
