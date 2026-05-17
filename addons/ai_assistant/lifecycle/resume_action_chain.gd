@tool
class_name AILifecycleResumeChain
extends RefCounted

## ResumeActionChain — geri dönüş zinciri (Madde 10 / App Lifecycle).
##
## Uygulama arka plandan döndüğünde tek bir şey değil, BİR DİZİ şey
## yapılmalı ve SIRA önemli:
##   1. Kayıt bütünlüğünü kontrol et
##   2. Ağ durumunu yenile
##   3. Sesi geri başlat
##   4. Oyun saatini senkronize et
##   5. Arayüzü tazele
##
## Bu sınıf o zinciri yönetir — adımları sırayla çalıştırır, biri
## başarısız olursa NE YAPILACAĞINI bilir (kritik adım başarısızsa
## zincir durur; opsiyonel adım başarısızsa devam eder).
##
## Mock policy: adımlar gerçek Callable'lar; başarı gerçek
## sonuçtan — sahte "tamamlandı" yok.

## Bir zincir adımı.
class ResumeStep extends RefCounted:
	var step_name: String = ""
	var action: Callable
	var critical: bool = false         ## Başarısızsa zincir durur mu

	func _init(p_name: String, p_action: Callable, p_critical: bool) -> void:
		step_name = p_name
		action = p_action
		critical = p_critical


## Zincir adımları — eklenme sırasıyla çalışır.
var _steps: Array = []


# ============================================================
# ADIM TANIMLAMA
# ============================================================

## Zincire bir adım ekler.
## step_name: adım adı. action: çalıştırılacak (bool döndürmeli —
## true=başarılı). critical: başarısızsa zincir durur mu.
func add_step(
	step_name: String, action: Callable, critical: bool = false
) -> void:
	if step_name.is_empty() or not action.is_valid():
		push_warning("ResumeChain: geçersiz adım reddedildi")
		return
	_steps.append(ResumeStep.new(step_name, action, critical))


## Tanımlı adım sayısı.
func step_count() -> int:
	return _steps.size()


# ============================================================
# ÇALIŞTIRMA
# ============================================================

## Geri dönüş zincirini çalıştırır.
## Adımlar sırayla çalışır. Kritik adım başarısız olursa zincir DURUR.
## Opsiyonel adım başarısız olursa loglanır ama DEVAM edilir.
## Dönen: {ok, completed, failed, halted_at, results}
func run() -> Dictionary:
	var results: Array = []
	var completed: int = 0
	var failed: int = 0
	var halted_at: String = ""

	for step_obj in _steps:
		var step: ResumeStep = step_obj
		var success: bool = false

		# Adımı çalıştır — Callable bool döndürmeli
		if step.action.is_valid():
			var outcome: Variant = step.action.call()
			success = (typeof(outcome) == TYPE_BOOL and outcome)

		results.append({
			"step": step.step_name,
			"success": success,
			"critical": step.critical,
		})

		if success:
			completed += 1
		else:
			failed += 1
			# Kritik adım başarısız — zincir durur
			if step.critical:
				halted_at = step.step_name
				break

	return {
		"ok": halted_at.is_empty(),
		"completed": completed,
		"failed": failed,
		"halted_at": halted_at,
		"results": results,
	}


## Sadece kritik adımları çalıştırır — hızlı/minimal geri dönüş.
## Dönen: {ok: bool, completed: int}
func run_critical_only() -> Dictionary:
	var completed: int = 0
	var all_ok: bool = true
	for step_obj in _steps:
		var step: ResumeStep = step_obj
		if not step.critical:
			continue
		var success: bool = false
		if step.action.is_valid():
			var outcome: Variant = step.action.call()
			success = (typeof(outcome) == TYPE_BOOL and outcome)
		if success:
			completed += 1
		else:
			all_ok = false
	return {"ok": all_ok, "completed": completed}


# ============================================================
# DURUM
# ============================================================

## Kritik adım sayısı.
func critical_step_count() -> int:
	var n: int = 0
	for step_obj in _steps:
		if (step_obj as ResumeStep).critical:
			n += 1
	return n


## Zinciri temizler.
func clear() -> void:
	_steps.clear()


## Zincir özeti.
func summary() -> Dictionary:
	return {
		"step_count": _steps.size(),
		"critical_steps": critical_step_count(),
	}
