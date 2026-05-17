@tool
class_name AIAudioEnvelope
extends RefCounted

## Envelope — ADSR zarfı (Madde 08 / procedural_synth).
##
## Bir oscillator sürekli aynı yükseklikte çalar — bu yapay duyulur.
## Gerçek sesler ZAMANLA değişir: piyano tuşu basınca ani başlar,
## yavaş söner. Bu "zarf"tır.
##
## ADSR — sesin yükseklik zarfının 4 evresi:
##   Attack  (atak)   — 0'dan tepeye yükseliş (notanın başlaması)
##   Decay   (düşüş)  — tepeden sustain seviyesine iniş
##   Sustain (tutuş)  — tuş basılı kaldığı sürece sabit seviye
##   Release (bırakış)— tuş bırakılınca 0'a sönüş
##
## Bu zarf bir oscillator örneğiyle çarpılır — sesi canlı yapar.
##
## Bu sınıf saf matematiktir — Godot gerektirmez.
##
## Mock policy: zarf değeri gerçek ADSR hesabından.

## ADSR evreleri.
enum Phase { ATTACK, DECAY, SUSTAIN, RELEASE, IDLE }

const PHASE_NAMES: Dictionary = {
	Phase.ATTACK: "attack",
	Phase.DECAY: "decay",
	Phase.SUSTAIN: "sustain",
	Phase.RELEASE: "release",
	Phase.IDLE: "idle",
}


## Atak süresi (saniye) — 0'dan tepeye.
var attack: float = 0.01

## Düşüş süresi (saniye) — tepeden sustain'e.
var decay: float = 0.1

## Tutuş seviyesi (0-1) — basılı kaldığı sürece.
var sustain: float = 0.7

## Bırakış süresi (saniye) — sustain'den 0'a.
var release: float = 0.2


func _init(
	p_attack: float = 0.01, p_decay: float = 0.1,
	p_sustain: float = 0.7, p_release: float = 0.2
) -> void:
	attack = maxf(p_attack, 0.0)
	decay = maxf(p_decay, 0.0)
	sustain = clampf(p_sustain, 0.0, 1.0)
	release = maxf(p_release, 0.0)


# ============================================================
# ZARF DEĞERİ
# ============================================================

## Bir zaman anında zarf çarpanını hesaplar.
## time_seconds: notanın başından bu yana geçen süre.
## note_held: nota hâlâ basılı mı (release'i tetikler).
## release_start: nota bırakıldığı an (note_held false ise gerekli).
## Dönen: zarf çarpanı (0-1).
func value_at(
	time_seconds: float, note_held: bool,
	release_start: float = -1.0
) -> float:
	if time_seconds < 0.0:
		return 0.0

	# --- Nota bırakıldı — release evresi ---
	if not note_held and release_start >= 0.0:
		var time_in_release: float = time_seconds - release_start
		if time_in_release >= release:
			return 0.0  # tamamen sönmüş
		# release_start anındaki seviyeden 0'a doğrusal iniş
		var level_at_release: float = _level_during_hold(release_start)
		if release <= 0.0:
			return 0.0
		var fade: float = 1.0 - (time_in_release / release)
		return level_at_release * fade

	# --- Nota basılı — attack/decay/sustain ---
	return _level_during_hold(time_seconds)


## Nota basılıyken (release öncesi) zarf seviyesini hesaplar.
func _level_during_hold(time_seconds: float) -> float:
	# Attack evresi — 0'dan 1'e
	if time_seconds < attack:
		if attack <= 0.0:
			return 1.0
		return time_seconds / attack

	# Decay evresi — 1'den sustain'e
	var time_after_attack: float = time_seconds - attack
	if time_after_attack < decay:
		if decay <= 0.0:
			return sustain
		var decay_progress: float = time_after_attack / decay
		return 1.0 - decay_progress * (1.0 - sustain)

	# Sustain evresi — sabit
	return sustain


## Bir zaman anının hangi ADSR evresinde olduğunu söyler.
func phase_at(
	time_seconds: float, note_held: bool, release_start: float = -1.0
) -> int:
	if time_seconds < 0.0:
		return Phase.IDLE
	if not note_held and release_start >= 0.0:
		var time_in_release: float = time_seconds - release_start
		if time_in_release >= release:
			return Phase.IDLE
		return Phase.RELEASE
	if time_seconds < attack:
		return Phase.ATTACK
	if time_seconds < attack + decay:
		return Phase.DECAY
	return Phase.SUSTAIN


# ============================================================
# SORGULAMA
# ============================================================

## Bir evrenin adı.
func phase_name(phase: int) -> String:
	return PHASE_NAMES.get(phase, "?")


## Atak + düşüş toplam süresi — sesin "kurulma" süresi.
func onset_duration() -> float:
	return attack + decay


## Bir notanın bırakıldıktan sonra tamamen sönme süresi.
func total_release_time() -> float:
	return release
