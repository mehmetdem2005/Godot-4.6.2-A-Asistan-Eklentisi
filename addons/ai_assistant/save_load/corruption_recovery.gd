@tool
class_name AISaveCorruptionRecovery
extends RefCounted

## CorruptionRecovery — bozulma kurtarma (Madde 09 / Save/Load / backup).
##
## Kayıt bozulduğunda ne yapılır? Tek bir cevap yok — bozulmanın
## TÜRÜNE bağlı:
##   - JSON ayrıştırılamıyor    -> yedekten geri yükle
##   - imza geçersiz (kurcalama) -> yedekten geri yükle + uyar
##   - kısmi veri (eksik alan)  -> varsayılanla tamamla denenebilir
##   - dosya hiç yok            -> yeni oyun başlat
##
## Bu sınıf bozulma türünü kurtarma STRATEJİSİNE bağlar — sistemin
## bir sonraki adımda ne yapacağını söyler.
##
## "Mock yasak": bozuk veriyi "tamir ettim" demez. Kurtarma ya
## yedekten ya varsayılandan; başarısızsa açıkça başarısız.
##
## Mock policy: strateji gerçek bozulma türünden.

## Bozulma türleri.
enum CorruptionType { NONE, UNPARSEABLE, TAMPERED, PARTIAL, MISSING }

const CORRUPTION_NAMES: Dictionary = {
	CorruptionType.NONE: "none",
	CorruptionType.UNPARSEABLE: "unparseable",
	CorruptionType.TAMPERED: "tampered",
	CorruptionType.PARTIAL: "partial",
	CorruptionType.MISSING: "missing",
}

## Kurtarma stratejileri.
enum RecoveryStrategy { NO_ACTION, RESTORE_BACKUP, FILL_DEFAULTS, NEW_GAME, UNRECOVERABLE }

const STRATEGY_NAMES: Dictionary = {
	RecoveryStrategy.NO_ACTION: "no_action",
	RecoveryStrategy.RESTORE_BACKUP: "restore_backup",
	RecoveryStrategy.FILL_DEFAULTS: "fill_defaults",
	RecoveryStrategy.NEW_GAME: "new_game",
	RecoveryStrategy.UNRECOVERABLE: "unrecoverable",
}


## Bir kurtarma planı.
class RecoveryPlan extends RefCounted:
	var corruption: int = AISaveCorruptionRecovery.CorruptionType.NONE
	var strategy: int = AISaveCorruptionRecovery.RecoveryStrategy.NO_ACTION
	var needs_user_notice: bool = false   ## Kullanıcı bilgilendirilmeli mi
	var description: String = ""

	func corruption_name() -> String:
		return AISaveCorruptionRecovery.CORRUPTION_NAMES.get(
			corruption, "?"
		)

	func strategy_name() -> String:
		return AISaveCorruptionRecovery.STRATEGY_NAMES.get(strategy, "?")

	func to_dict() -> Dictionary:
		return {
			"corruption": corruption_name(),
			"strategy": strategy_name(),
			"needs_user_notice": needs_user_notice,
		}


# ============================================================
# KURTARMA PLANLAMA
# ============================================================

## Bir bozulma türü için kurtarma planı üretir.
## corruption_type: tespit edilen bozulma türü.
## has_backup: kurtarılabilir yedek var mı.
## Dönen: RecoveryPlan.
func plan_recovery(
	corruption_type: int, has_backup: bool = false
) -> RecoveryPlan:
	var plan := RecoveryPlan.new()
	if CORRUPTION_NAMES.has(corruption_type):
		plan.corruption = corruption_type

	match corruption_type:
		CorruptionType.NONE:
			plan.strategy = RecoveryStrategy.NO_ACTION
			plan.description = "Kayıt sağlam — işlem gerekmiyor"

		CorruptionType.MISSING:
			# Dosya yok — bu bir bozulma değil, ilk açılış olabilir
			plan.strategy = RecoveryStrategy.NEW_GAME
			plan.description = "Kayıt yok — yeni oyun başlatılacak"

		CorruptionType.UNPARSEABLE, CorruptionType.TAMPERED:
			# Ciddi bozulma — yedek şart
			if has_backup:
				plan.strategy = RecoveryStrategy.RESTORE_BACKUP
				plan.needs_user_notice = true
				plan.description = "Kayıt bozuk — yedekten geri yüklenecek"
			else:
				plan.strategy = RecoveryStrategy.UNRECOVERABLE
				plan.needs_user_notice = true
				plan.description = "Kayıt bozuk ve yedek yok — kurtarılamaz"

		CorruptionType.PARTIAL:
			# Kısmi veri — önce yedek, yoksa varsayılanla tamamla
			if has_backup:
				plan.strategy = RecoveryStrategy.RESTORE_BACKUP
				plan.needs_user_notice = true
				plan.description = "Eksik veri — yedekten geri yüklenecek"
			else:
				plan.strategy = RecoveryStrategy.FILL_DEFAULTS
				plan.needs_user_notice = true
				plan.description = "Eksik veri — varsayılanlarla tamamlanacak"

		_:
			plan.strategy = RecoveryStrategy.UNRECOVERABLE
			plan.description = "Bilinmeyen bozulma"

	return plan


# ============================================================
# SORGULAMA
# ============================================================

## Bir bozulma türü kurtarılabilir mi (yedek varsayımıyla)?
func is_recoverable(corruption_type: int, has_backup: bool) -> bool:
	var plan: RecoveryPlan = plan_recovery(corruption_type, has_backup)
	return plan.strategy != RecoveryStrategy.UNRECOVERABLE


## Bir bozulma türü kullanıcıya bildirim gerektirir mi?
func requires_notice(corruption_type: int, has_backup: bool) -> bool:
	var plan: RecoveryPlan = plan_recovery(corruption_type, has_backup)
	return plan.needs_user_notice
