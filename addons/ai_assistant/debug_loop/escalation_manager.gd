@tool
class_name AIDebugEscalationManager
extends RefCounted

## EscalationManager — yükseltme yöneticisi (Madde 02 / Debug Loop).
##
## Debug Loop her zaman kazanamaz. Bazen 3 deneme de tükenir, ya da
## circuit breaker devreyi açar. O noktada sistem PES ETMEZ ama
## DÜRÜST olur: insana devreder.
##
## Bu sınıf yükseltme (escalation) mesajını hazırlar — kullanıcıya
## NE olduğunu net anlatır: hangi hata, kaç deneme yapıldı, neler
## denendi, neden çözülemedi. Trace dışa aktarılır ki kullanıcı
## kendi bakabilsin.
##
## "Mock yasak" ilkesinin son hattı: çözülemeyen şeyi "çözüldü"
## demek yok — açık bir başarısızlık raporu.
##
## Mock policy: rapor gerçek deneme geçmişinden.

## Yükseltme sebebi.
enum EscalationReason { MAX_RETRIES, CIRCUIT_OPEN, UNANALYZABLE, NEEDS_LLM }

const REASON_NAMES: Dictionary = {
	EscalationReason.MAX_RETRIES: "max_retries_exhausted",
	EscalationReason.CIRCUIT_OPEN: "circuit_breaker_open",
	EscalationReason.UNANALYZABLE: "unanalyzable_error",
	EscalationReason.NEEDS_LLM: "needs_llm_unavailable",
}

## Sebep -> kullanıcı-dostu açıklama.
const REASON_MESSAGES: Dictionary = {
	EscalationReason.MAX_RETRIES: "Hata 3 denemede çözülemedi. "
		+ "Otomatik düzeltme yetersiz kaldı.",
	EscalationReason.CIRCUIT_OPEN: "Düzeltmeler aynı hatayı tekrar "
		+ "üretti — döngü ilerlemiyor, deneme durduruldu.",
	EscalationReason.UNANALYZABLE: "Hatanın kök nedeni otomatik "
		+ "belirlenemedi.",
	EscalationReason.NEEDS_LLM: "Bu hata için LLM analizi gerekli "
		+ "ama şu an kullanılamıyor.",
}


## Bir yükseltme raporu.
class EscalationReport extends RefCounted:
	var reason: int = AIDebugEscalationManager.EscalationReason.MAX_RETRIES
	var original_error: String = ""
	var attempts_made: int = 0
	var attempted_fixes: PackedStringArray = PackedStringArray()
	var user_message: String = ""

	func reason_name() -> String:
		return AIDebugEscalationManager.REASON_NAMES.get(reason, "?")

	func to_dict() -> Dictionary:
		return {
			"reason": reason_name(),
			"original_error": original_error,
			"attempts_made": attempts_made,
			"fix_count": attempted_fixes.size(),
		}


# ============================================================
# YÜKSELTME
# ============================================================

## Bir debug loop başarısızlığı için yükseltme raporu hazırlar.
## reason: yükseltme sebebi. original_error: ilk yakalanan hata.
## attempts: yapılan deneme sayısı. fixes: denenmiş düzeltmeler.
## Dönen: EscalationReport.
func escalate(
	reason: int, original_error: String, attempts: int,
	fixes: PackedStringArray
) -> EscalationReport:
	var report := EscalationReport.new()
	if REASON_NAMES.has(reason):
		report.reason = reason
	report.original_error = original_error
	report.attempts_made = maxi(attempts, 0)
	report.attempted_fixes = fixes
	report.user_message = _build_message(report)
	return report


## Kullanıcıya gösterilecek tam mesajı kurar.
func _build_message(report: EscalationReport) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("⚠ Otomatik düzeltme tamamlanamadı")
	lines.append("")
	# Sebep açıklaması
	lines.append(str(REASON_MESSAGES.get(report.reason, "Bilinmeyen sebep")))
	lines.append("")
	# Hata detayı
	lines.append("Hata: " + report.original_error)
	lines.append("Yapılan deneme: %d" % report.attempts_made)
	# Denenen düzeltmeler
	if not report.attempted_fixes.is_empty():
		lines.append("")
		lines.append("Denenen düzeltmeler:")
		for fix in report.attempted_fixes:
			lines.append("  • " + fix)
	lines.append("")
	lines.append("Bu noktada sizin incelemeniz gerekiyor. "
		+ "Tüm deneme kaydı (trace) dışa aktarıldı.")
	return "\n".join(lines)


# ============================================================
# TRACE DIŞA AKTARMA
# ============================================================

## Yükseltme raporunu dışa aktarılabilir sözlüğe çevirir.
## Kullanıcı bunu kaydedip kendi inceleyebilir.
func export_trace(report: EscalationReport) -> Dictionary:
	return {
		"escalation_reason": report.reason_name(),
		"original_error": report.original_error,
		"attempts_made": report.attempts_made,
		"attempted_fixes": report.attempted_fixes,
		"exported_at_unix": int(Time.get_unix_time_from_system()),
	}


# ============================================================
# SORGULAMA
# ============================================================

## Bir sebep için kullanıcı-dostu açıklamayı döndürür.
func reason_message(reason: int) -> String:
	return str(REASON_MESSAGES.get(reason, "Bilinmeyen sebep"))
