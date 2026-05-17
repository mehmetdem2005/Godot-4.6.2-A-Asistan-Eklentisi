@tool
class_name AIExplicitReplaceHandler
extends RefCounted

## ExplicitReplaceHandler — açık tam-değişim protokolü (Surgical Edit).
##
## Surgical Edit'in temel kuralı: "asla tüm dosyayı yeniden yazma".
## AMA bazen GERÇEKTEN gerekir — dosya baştan yazılacak kadar değişti,
## ya da yeni bir dosya oluşturuluyor.
##
## Bu protokol o istisnayı GÜVENLİ yönetir. Tam dosya değişimi:
##   - ASLA otomatik olmaz — açık onay gerektirir (HITL)
##   - Eski içerik kayıt altına alınır (geri alınabilirlik)
##   - "Bu gerçekten gerekli mi" kontrolünden geçer
##
## Yani full-rewrite yasak değil — KONTROLSÜZ full-rewrite yasak.
## Bu protokol onu kontrollü kılar.
##
## Mock policy: onaysız tam değişim uygulanmaz — açık ret.

## Bir tam-değişim sonucu.
class ReplaceResult extends RefCounted:
	var ok: bool = false
	var new_content: String = ""
	var old_content: String = ""       ## Geri alma için saklanır
	var needs_approval: bool = false   ## HITL onayı gerekli mi
	var is_new_file: bool = false      ## Yeni dosya mı
	var rejected_reason: String = ""
	var change_ratio: float = 0.0      ## Ne kadar değişti (0-1)

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"needs_approval": needs_approval,
			"is_new_file": is_new_file,
			"change_ratio": change_ratio,
			"rejected_reason": rejected_reason,
		}


## Tam değişim için "gerçekten gerekli" eşiği.
## İçeriğin bu orandan azı değişiyorsa, surgical edit önerilir.
const FULL_REWRITE_JUSTIFIED_RATIO: float = 0.6


# ============================================================
# TAM DEĞİŞİM
# ============================================================

## Bir dosyanın tam içeriğini değiştirir.
## old_content: mevcut içerik (yeni dosya ise boş).
## new_content: yeni tam içerik.
## approved: kullanıcı onayı verildi mi.
## Dönen: ReplaceResult.
func apply(
	old_content: String, new_content: String, approved: bool
) -> ReplaceResult:
	var result := ReplaceResult.new()
	result.old_content = old_content

	if new_content.strip_edges().is_empty():
		result.rejected_reason = "Yeni içerik boş — tam değişim reddedildi"
		return result

	# Yeni dosya mı (eski içerik boş)
	result.is_new_file = old_content.strip_edges().is_empty()

	# Yeni dosya — onay yine de gerekli ama risk düşük
	if result.is_new_file:
		if not approved:
			result.needs_approval = true
			result.rejected_reason = "Yeni dosya oluşturma onayı bekleniyor"
			return result
		result.new_content = new_content
		result.ok = true
		result.change_ratio = 1.0
		return result

	# Mevcut dosya — tam değişim. Ne kadar değiştiğini ölç.
	result.change_ratio = _compute_change_ratio(old_content, new_content)

	# Değişim azsa — full rewrite gereksiz, surgical edit öner
	if result.change_ratio < FULL_REWRITE_JUSTIFIED_RATIO:
		result.rejected_reason = (
			"Değişim oranı düşük (%.0f%%) — tam değişim yerine "
			% (result.change_ratio * 100.0)
			+ "cerrahi düzenleme (SEARCH/REPLACE) kullanılmalı"
		)
		return result

	# Tam değişim haklı — ama onay şart
	if not approved:
		result.needs_approval = true
		result.rejected_reason = (
			"Tam dosya değişimi onay bekliyor (%.0f%% değişiyor)"
			% (result.change_ratio * 100.0)
		)
		return result

	# Onaylı tam değişim — uygula
	result.new_content = new_content
	result.ok = true
	return result


## Bir tam değişimi geri alır — eski içeriği döndürür.
## result: daha önceki bir ReplaceResult.
## Dönen: {ok: bool, content: String}
func revert(result: ReplaceResult) -> Dictionary:
	if result == null:
		return {"ok": false, "content": ""}
	return {"ok": true, "content": result.old_content}


# ============================================================
# DAHİLİ
# ============================================================

## İki içerik arasındaki değişim oranını hesaplar (0.0 - 1.0).
## Satır-tabanlı kaba ölçüm: kaç satır farklı.
func _compute_change_ratio(old_content: String, new_content: String) -> float:
	var old_lines: PackedStringArray = old_content.split("\n")
	var new_lines: PackedStringArray = new_content.split("\n")

	# Eski satırları bir kümeye al
	var old_set: Dictionary = {}
	for line in old_lines:
		old_set[line] = true

	# Yeni satırların kaçı eskide yok (değişmiş/eklenmiş)
	var changed: int = 0
	for line in new_lines:
		if not old_set.has(line):
			changed += 1

	var total: int = maxi(old_lines.size(), new_lines.size())
	if total == 0:
		return 0.0
	return float(changed) / float(total)


## LLM'e verilecek protokol talimatı.
static func protocol_instructions() -> String:
	return (
		"Tam dosya değişimi SADECE dosya baştan yazılacak kadar "
		+ "değiştiğinde veya yeni dosya oluşturulduğunda kullanılır. "
		+ "Küçük değişiklikler için SEARCH/REPLACE kullan. Tam değişim "
		+ "her zaman kullanıcı onayı gerektirir."
	)
