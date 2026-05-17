@tool
class_name AIContextRelay
extends RefCounted

## ContextRelay — bağlam aktarıcı (Layer 9 / Pilot Cell zekâsı).
##
## Pipeline'da bir ajanın çıktısı bir sonraki ajana aktarılmalı.
## Önceki sürüm sadece KISA ÖZET geçiriyordu — DeliveryManager'ın
## task listesi, CodeEngineer'a "3 task çıkarıldı" gibi bir özet
## olarak ulaşıyordu; gerçek task'lar (yapılandırılmış items)
## kayboluyordu.
##
## Bu sınıf bağlamı YAPILANDIRILMIŞ taşır. Her rolün çıktısı:
##   - özet (kısa, insan-okunur)
##   - yapılandırılmış maddeler (items — task/plan/bulgu listesi)
##   - ham metin (gerekirse tam erişim)
## olarak saklanır. Sonraki ajan "önceki aşamadan ne geldi" diye
## baktığında gerçek veriyi görür.
##
## Ayrıca: bir rol, kendinden ÖNCEKİ ilgili rollerin çıktısına
## odaklanabilir (CodeEngineer için DeliveryManager'ın task'ları
## en önemli; ProductManager'ın hedefi ikincil).
##
## Mock policy: relay sadece gerçek çıktıları taşır — veri ekleme/
## uydurma yok.

## Tek bir rol çıktısının aktarılabilir kaydı.
class RelayEntry extends RefCounted:
	var role: int = 0
	var role_name: String = ""
	var summary: String = ""           ## Kısa özet
	var parsed_kind: String = ""       ## ParsedOutput.kind adı
	var items: Array = []              ## Yapılandırılmış maddeler
	var verdict: String = ""           ## İnceleme rolleri için
	var structured: bool = false
	var raw_text: String = ""

	func to_dict() -> Dictionary:
		return {
			"role": role_name,
			"summary": summary,
			"parsed_kind": parsed_kind,
			"item_count": items.size(),
			"verdict": verdict,
			"structured": structured,
		}


## Pipeline boyunca biriken kayıtlar — rol enum -> RelayEntry.
var _entries: Dictionary = {}

## Orijinal görev — her zaman erişilebilir.
var original_task: String = ""


func _init(task: String = "") -> void:
	original_task = task


# ============================================================
# KAYIT — bir rolün çıktısını bağlama ekle
# ============================================================

## Bir ajanın WorkResult'ını relay'e kaydeder.
## result: AICellAgent.WorkResult — artifacts yapılandırılmış veri taşır.
func record(role: int, result) -> void:
	if result == null:
		return
	var entry := RelayEntry.new()
	entry.role = role
	entry.role_name = AICellRoles.role_name(role)
	entry.summary = result.summary
	entry.raw_text = result.output

	# WorkResult.artifacts içinden yapılandırılmış veriyi al
	var artifacts: Dictionary = result.artifacts
	entry.parsed_kind = str(artifacts.get("parsed_kind", ""))
	entry.structured = bool(artifacts.get("structured", false))
	entry.verdict = str(artifacts.get("verdict", ""))
	var items_raw = artifacts.get("items", [])
	if items_raw is Array:
		entry.items = items_raw

	_entries[role] = entry


# ============================================================
# BAĞLAM ÜRETİMİ — bir sonraki ajan için
# ============================================================

## Belirli bir rol için bağlam sözlüğü üretir.
## Bu sözlük o rolün process_task'ına context olarak verilir.
##
## İçerik: orijinal görev + önceki rollerin özetleri. İlgili
## roller (örn. kod rolü için DeliveryManager) öne çıkarılır.
func build_context_for(role: int) -> Dictionary:
	var context: Dictionary = {"original_task": original_task}

	# Önceki tüm rollerin özetlerini ekle
	for prev_role in _entries:
		var entry: RelayEntry = _entries[prev_role]
		context[entry.role_name] = entry.summary

	# İlgili rolün yapılandırılmış çıktısını öne çıkar
	var key_role: int = _key_predecessor_for(role)
	if key_role >= 0 and _entries.has(key_role):
		var key_entry: RelayEntry = _entries[key_role]
		# Yapılandırılmış maddeleri doğrudan ver — özet değil
		if key_entry.structured and not key_entry.items.is_empty():
			context["_key_input_role"] = key_entry.role_name
			context["_key_input_items"] = key_entry.items
			context["_key_input_kind"] = key_entry.parsed_kind

	return context


## Bir rol için "en önemli öncül" rolü belirler.
## Kod üreten roller için DeliveryManager'ın task'ları kritik;
## QA için kod rollerinin çıktısı; vb.
func _key_predecessor_for(role: int) -> int:
	if AICellRoles.is_code_generating(role):
		# Kod rolleri DeliveryManager'ın task listesine bakar
		return AICellRoles.Role.DELIVERY_MANAGER
	match role:
		AICellRoles.Role.DELIVERY_MANAGER:
			# DeliveryManager Architect'in tasarımına bakar
			return AICellRoles.Role.ARCHITECT
		AICellRoles.Role.ARCHITECT:
			# Architect ProductManager'ın hedefine bakar
			return AICellRoles.Role.PRODUCT_MANAGER
		AICellRoles.Role.QA_ENGINEER, AICellRoles.Role.TEST_ENGINEER:
			# QA/Test kod mühendisinin çıktısına bakar
			return AICellRoles.Role.CODE_ENGINEER
		AICellRoles.Role.REVIEWER:
			# Reviewer QA'nın kararına bakar
			return AICellRoles.Role.QA_ENGINEER
		_:
			# Pipeline'da bir önceki rol
			return AICellRoles.prev_in_pipeline(role)


# ============================================================
# SORGULAMA
# ============================================================

## Bir rolün kaydını döndürür. Yoksa null.
func entry_for(role: int) -> RelayEntry:
	return _entries.get(role, null)


## Bir rolün çıktısı kayıtlı mı?
func has_entry(role: int) -> bool:
	return _entries.has(role)


## Kayıtlı rol sayısı.
func entry_count() -> int:
	return _entries.size()


## Yapılandırılmış çıktı veren rollerin sayısı.
func structured_count() -> int:
	var n: int = 0
	for role in _entries:
		if (_entries[role] as RelayEntry).structured:
			n += 1
	return n


## Pipeline'da herhangi bir rol FAIL kararı verdi mi?
## (QA/Reviewer "fail" verdict'i — pipeline sorunlu demektir.)
func has_fail_verdict() -> bool:
	for role in _entries:
		if (_entries[role] as RelayEntry).verdict == "fail":
			return true
	return false


## Relay durum özeti.
func summary() -> Dictionary:
	return {
		"entries": _entries.size(),
		"structured": structured_count(),
		"has_fail": has_fail_verdict(),
		"original_task": original_task,
	}


## Tüm kayıtları temizler.
func reset() -> void:
	_entries.clear()
