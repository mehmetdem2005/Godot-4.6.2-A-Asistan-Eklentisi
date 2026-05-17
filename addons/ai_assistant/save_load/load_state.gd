@tool
class_name AISaveLoadState
extends RefCounted

## LoadState — yükleme durumu (Madde 09 / persistence_helpers).
##
## Bir kaydı yüklemek tek adım değil, bir SÜREÇTİR ve her adım
## başarısız olabilir:
##   1. dosyayı oku
##   2. bütünlüğü doğrula (imza)
##   3. JSON ayrıştır
##   4. sürüm uyumluluğu kontrol et
##   5. gerekirse geçiş (migration) yap
##   6. veriyi oyuna uygula
##
## Bu sınıf yükleme sürecinin HANGİ AŞAMADA olduğunu izler ve bir
## aşama başarısız olduğunda nerede/neden durduğunu raporlar.
## Yarım yüklenmiş bir oyun tehlikelidir — süreç ya tamamlanır
## ya temiz başarısız olur.
##
## Mock policy: aşama durumu gerçek yükleme adımlarından.

## Yükleme aşamaları.
enum LoadPhase { IDLE, READING, VERIFYING, PARSING, CHECKING_VERSION, MIGRATING, APPLYING, COMPLETE, FAILED }

const PHASE_NAMES: Dictionary = {
	LoadPhase.IDLE: "idle",
	LoadPhase.READING: "reading",
	LoadPhase.VERIFYING: "verifying",
	LoadPhase.PARSING: "parsing",
	LoadPhase.CHECKING_VERSION: "checking_version",
	LoadPhase.MIGRATING: "migrating",
	LoadPhase.APPLYING: "applying",
	LoadPhase.COMPLETE: "complete",
	LoadPhase.FAILED: "failed",
}

## Aşamaların normal sırası — ilerleme bu sırayı izler.
const PHASE_ORDER: Array = [
	LoadPhase.READING, LoadPhase.VERIFYING, LoadPhase.PARSING,
	LoadPhase.CHECKING_VERSION, LoadPhase.MIGRATING,
	LoadPhase.APPLYING, LoadPhase.COMPLETE,
]


## Mevcut aşama.
var phase: int = LoadPhase.IDLE

## Başarısızlık durumunda — hangi aşamada, neden.
var failed_phase: int = -1
var failure_reason: String = ""


# ============================================================
# AŞAMA İLERLETME
# ============================================================

## Yükleme sürecini başlatır.
func begin() -> void:
	phase = LoadPhase.READING
	failed_phase = -1
	failure_reason = ""


## Bir aşamayı başarıyla tamamlar ve bir sonrakine geçer.
## expected_phase: tamamlanan aşama (tutarlılık kontrolü).
## Dönen: {ok: bool, next_phase: String, reason: String}
func advance(expected_phase: int) -> Dictionary:
	# Başarısız durumdayken ilerleme yok
	if phase == LoadPhase.FAILED:
		return {
			"ok": false, "next_phase": phase_name(),
			"reason": "Süreç zaten başarısız",
		}

	# Beklenen aşamada mıyız
	if phase != expected_phase:
		return {
			"ok": false, "next_phase": phase_name(),
			"reason": "Aşama uyuşmazlığı — sıra dışı ilerleme",
		}

	# Sıradaki aşamaya geç
	var current_idx: int = PHASE_ORDER.find(phase)
	if current_idx == -1 or current_idx >= PHASE_ORDER.size() - 1:
		phase = LoadPhase.COMPLETE
		return {
			"ok": true, "next_phase": phase_name(),
			"reason": "Yükleme tamamlandı",
		}
	phase = PHASE_ORDER[current_idx + 1]
	return {
		"ok": true, "next_phase": phase_name(),
		"reason": "Sonraki aşamaya geçildi",
	}


## Geçiş (migration) aşamasını atlar — kayıt güncel sürümdeyse.
## CHECKING_VERSION'dan doğrudan APPLYING'e.
func skip_migration() -> Dictionary:
	if phase != LoadPhase.CHECKING_VERSION:
		return {
			"ok": false,
			"reason": "Geçiş atlama sadece sürüm kontrolünden sonra",
		}
	phase = LoadPhase.APPLYING
	return {"ok": true, "reason": "Geçiş atlandı — kayıt güncel"}


## Mevcut aşamada süreci başarısız olarak işaretler.
## reason: başarısızlık sebebi.
func fail(reason: String) -> void:
	failed_phase = phase
	failure_reason = reason
	phase = LoadPhase.FAILED


# ============================================================
# SORGULAMA
# ============================================================

## Mevcut aşama adı.
func phase_name() -> String:
	return PHASE_NAMES.get(phase, "?")


## Yükleme tamamlandı mı?
func is_complete() -> bool:
	return phase == LoadPhase.COMPLETE


## Yükleme başarısız mı?
func is_failed() -> bool:
	return phase == LoadPhase.FAILED


## Yükleme hâlâ devam ediyor mu?
func is_in_progress() -> bool:
	return phase != LoadPhase.IDLE \
		and phase != LoadPhase.COMPLETE \
		and phase != LoadPhase.FAILED


## İlerleme oranı (0.0 - 1.0).
func progress() -> float:
	if phase == LoadPhase.COMPLETE:
		return 1.0
	if phase == LoadPhase.IDLE or phase == LoadPhase.FAILED:
		return 0.0
	var idx: int = PHASE_ORDER.find(phase)
	if idx == -1:
		return 0.0
	return float(idx) / float(PHASE_ORDER.size() - 1)


## Başarısızlık aşamasının adı. Başarısız değilse boş.
func failed_phase_name() -> String:
	if failed_phase == -1:
		return ""
	return PHASE_NAMES.get(failed_phase, "?")


## Durum özeti.
func summary() -> Dictionary:
	return {
		"phase": phase_name(),
		"is_complete": is_complete(),
		"is_failed": is_failed(),
		"progress": progress(),
		"failed_phase": failed_phase_name(),
		"failure_reason": failure_reason,
	}
