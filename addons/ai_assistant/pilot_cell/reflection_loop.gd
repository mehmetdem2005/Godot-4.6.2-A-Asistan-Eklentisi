@tool
class_name AIReflectionLoop
extends RefCounted

## ReflectionLoop — öz-eleştiri döngüsü (Layer 9 / Pilot Cell).
##
## Master plan: Pilot Cell deseni "Hierarchical + Reflection + Concurrent".
## Reflection kısmı bu sınıf.
##
## Fikir: bir ajan çıktı üretir; o çıktı doğrudan kabul edilmez —
## önce GÖZDEN GEÇİRİLİR. Eleştiri varsa ajan tekrar dener (yeni turda).
## Bu, tek-seferde-mükemmel beklemeden, iteratif kalite sağlar.
##
## Akış:
##   tur 0: ajan üretir -> eleştir -> sorun varsa tur 1
##   tur 1: ajan düzeltir -> eleştir -> sorun varsa tur 2
##   ...   max tur'a kadar (AICellMessage iteration_round 0-3)
##
## Eleştiri kaynağı: QA/Reviewer ajanı, ya da Verifier (Layer 5).
## Bu iskelet sürümde tur yönetimi + karar mantığı tam çalışır;
## eleştirinin LLM-tarafı sonraki sürümde derinleşir.
##
## Mock policy: reflection sahte "düzeldi" demez — gerçek eleştiri
## sonucuna göre devam/dur kararı verir.

## Reflection için azami tur sayısı (AICellMessage.iteration_round 0-3).
const MAX_ROUNDS: int = 3


## Bir reflection oturumunun durumu.
class ReflectionSession extends RefCounted:
	var round: int = 0
	var converged: bool = false       ## Eleştiri kalmadı mı (kabul)
	var exhausted: bool = false       ## Max tur aşıldı mı (zorla dur)
	var critiques: Array = []         ## Her turun eleştiri kaydı
	var final_output: String = ""

	## Oturum bitti mi (kabul edildi VEYA tur bitti)?
	func is_complete() -> bool:
		return converged or exhausted

	func to_dict() -> Dictionary:
		return {
			"round": round,
			"converged": converged,
			"exhausted": exhausted,
			"critique_count": critiques.size(),
			"complete": is_complete(),
		}


## Tek bir tur eleştiri sonucu.
class Critique extends RefCounted:
	var round: int = 0
	var has_issues: bool = false
	var issues: PackedStringArray = PackedStringArray()
	var reviewer_role: int = AICellRoles.Role.QA_ENGINEER

	func to_dict() -> Dictionary:
		return {
			"round": round,
			"has_issues": has_issues,
			"issues": issues,
			"reviewer": AICellRoles.role_name(reviewer_role),
		}


## Aktif oturum.
var _session: ReflectionSession


func _init() -> void:
	_session = ReflectionSession.new()


# ============================================================
# OTURUM YÖNETİMİ
# ============================================================

## Yeni bir reflection oturumu başlatır.
func begin() -> void:
	_session = ReflectionSession.new()
	_session.round = 0


## Mevcut tur numarası.
func current_round() -> int:
	return _session.round


## Bir sonraki tura geçilebilir mi?
## (Henüz yakınsamadı VE max tur aşılmadı.)
func can_continue() -> bool:
	if _session.converged:
		return false
	return _session.round < MAX_ROUNDS


# ============================================================
# ELEŞTİRİ DEĞERLENDİRME
# ============================================================

## Bir turun eleştirisini oturuma kaydeder ve devam/dur kararı verir.
##
## critique: bu turun Critique'i.
## Dönen: {
##   continue: bool,    bir tur daha mı (ajan tekrar denemeli)
##   converged: bool,   eleştiri kalmadı, kabul
##   exhausted: bool,   max tur aşıldı, zorla dur
##   round: int
## }
func submit_critique(critique: Critique) -> Dictionary:
	critique.round = _session.round
	_session.critiques.append(critique)

	# Eleştiri yok — yakınsadı, kabul
	if not critique.has_issues:
		_session.converged = true
		return {
			"continue": false,
			"converged": true,
			"exhausted": false,
			"round": _session.round,
		}

	# Eleştiri var — bir tur daha mümkün mü
	if _session.round + 1 >= MAX_ROUNDS:
		# Max tura ulaşıldı — zorla dur (yakınsamadı ama bitir)
		_session.exhausted = true
		return {
			"continue": false,
			"converged": false,
			"exhausted": true,
			"round": _session.round,
		}

	# Bir tur daha — ajan düzeltsin
	_session.round += 1
	return {
		"continue": true,
		"converged": false,
		"exhausted": false,
		"round": _session.round,
	}


## Bir eleştiri nesnesi oluşturur — yardımcı.
## issues boşsa "sorun yok" eleştirisi (yakınsama tetikler).
func make_critique(issues: PackedStringArray, reviewer_role: int) -> Critique:
	var critique := Critique.new()
	critique.issues = issues
	critique.has_issues = issues.size() > 0
	critique.reviewer_role = reviewer_role
	return critique


# ============================================================
# DURUM
# ============================================================

## Aktif oturum.
func session() -> ReflectionSession:
	return _session


## Oturum tamamlandı mı?
func is_complete() -> bool:
	return _session.is_complete()


## Oturum başarıyla yakınsadı mı (eleştiri kalmadan bitti)?
## exhausted (max tur) ile karıştırılmamalı — o "zorla dur".
func did_converge() -> bool:
	return _session.converged


## Reflection sonucunun özeti.
func summary() -> Dictionary:
	return {
		"rounds_used": _session.round + 1,
		"max_rounds": MAX_ROUNDS,
		"converged": _session.converged,
		"exhausted": _session.exhausted,
		"total_critiques": _session.critiques.size(),
	}
