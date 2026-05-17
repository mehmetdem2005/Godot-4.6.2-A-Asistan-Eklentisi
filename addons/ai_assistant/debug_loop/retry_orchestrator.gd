@tool
class_name AIDebugRetryOrchestrator
extends RefCounted

## RetryOrchestrator — yeniden deneme yöneticisi (Madde 02 / Debug Loop).
##
## Debug Loop'un kalbi: çalıştır -> hata -> düzelt -> TEKRAR DENE.
## Ama bu döngü sonsuz olamaz. İki koruma:
##
##   1. MAX RETRY — en fazla 3 deneme. 3 kez düzeltip hâlâ çözülmüyorsa
##      bir insan bakmalı (escalation).
##   2. CIRCUIT BREAKER — eğer düzeltmeler AYNI hatayı tekrar üretiyorsa
##      (döngüde takıldık), denemeyi bırak. Mehmet'in "sürekli başka
##      hata" değil, "sürekli AYNI hata" tuzağı.
##
## Circuit breaker mantığı: bir hata imzası iki kez görülürse, döngü
## ilerlemediği için devre açılır — daha fazla deneme israf.
##
## Mock policy: karar gerçek deneme geçmişinden; sahte ilerleme yok.

## En fazla deneme sayısı.
const MAX_RETRIES: int = 3

## Devre durumu.
enum CircuitState { CLOSED, OPEN }

const CIRCUIT_NAMES: Dictionary = {
	CircuitState.CLOSED: "closed",
	CircuitState.OPEN: "open",
}

## Bir denemenin sonucu.
enum AttemptOutcome { FIXED, STILL_FAILING, GAVE_UP }

const OUTCOME_NAMES: Dictionary = {
	AttemptOutcome.FIXED: "fixed",
	AttemptOutcome.STILL_FAILING: "still_failing",
	AttemptOutcome.GAVE_UP: "gave_up",
}


## Yapılan deneme sayısı.
var attempt_count: int = 0

## Devre durumu.
var circuit: int = CircuitState.CLOSED

## Görülen hata imzaları — circuit breaker için.
var _seen_signatures: Dictionary = {}

## Deneme geçmişi.
var _history: Array = []


# ============================================================
# DENEME DÖNGÜSÜ
# ============================================================

## Bir deneme sonucu bildirir ve sonraki adımı belirler.
## error_signature: bu denemedeki hatanın imzası (boş = hata yok,
## başarılı). Aynı imza tekrar gelirse circuit breaker tetiklenir.
## Dönen: {outcome: String, should_retry: bool, reason: String}
func report_attempt(error_signature: String) -> Dictionary:
	attempt_count += 1

	# --- Hata yok — düzeltme başarılı ---
	if error_signature.strip_edges().is_empty():
		_history.append({"attempt": attempt_count, "outcome": "fixed"})
		return {
			"outcome": OUTCOME_NAMES[AttemptOutcome.FIXED],
			"should_retry": false,
			"reason": "Hata çözüldü",
		}

	# --- Circuit breaker — aynı hata tekrar mı ---
	if _seen_signatures.has(error_signature):
		circuit = CircuitState.OPEN
		_history.append({
			"attempt": attempt_count, "outcome": "circuit_open"
		})
		return {
			"outcome": OUTCOME_NAMES[AttemptOutcome.GAVE_UP],
			"should_retry": false,
			"reason": "Devre kesici — aynı hata tekrarlanıyor, " \
				+ "döngü ilerlemiyor",
		}
	_seen_signatures[error_signature] = true

	# --- Max retry — deneme hakkı bitti mi ---
	if attempt_count >= MAX_RETRIES:
		_history.append({
			"attempt": attempt_count, "outcome": "max_retries"
		})
		return {
			"outcome": OUTCOME_NAMES[AttemptOutcome.GAVE_UP],
			"should_retry": false,
			"reason": "Maksimum deneme (%d) aşıldı" % MAX_RETRIES,
		}

	# --- Hâlâ hata var ama deneme hakkı kaldı ---
	_history.append({
		"attempt": attempt_count, "outcome": "retry"
	})
	return {
		"outcome": OUTCOME_NAMES[AttemptOutcome.STILL_FAILING],
		"should_retry": true,
		"reason": "Hata sürüyor — yeniden denenecek (%d/%d)" % [
			attempt_count, MAX_RETRIES
		],
	}


# ============================================================
# SORGULAMA
# ============================================================

## Devre açık mı (deneme durdu)?
func is_circuit_open() -> bool:
	return circuit == CircuitState.OPEN


## Daha fazla deneme yapılabilir mi?
func can_retry() -> bool:
	return circuit == CircuitState.CLOSED \
		and attempt_count < MAX_RETRIES


## Kalan deneme hakkı.
func retries_remaining() -> int:
	if circuit == CircuitState.OPEN:
		return 0
	return maxi(MAX_RETRIES - attempt_count, 0)


## Deneme geçmişi sayısı.
func history_count() -> int:
	return _history.size()


# ============================================================
# SIFIRLAMA
# ============================================================

## Yeni bir debug oturumu için durumu sıfırlar.
func reset() -> void:
	attempt_count = 0
	circuit = CircuitState.CLOSED
	_seen_signatures.clear()
	_history.clear()


## Durum özeti.
func summary() -> Dictionary:
	return {
		"attempt_count": attempt_count,
		"circuit": CIRCUIT_NAMES.get(circuit, "?"),
		"retries_remaining": retries_remaining(),
	}
