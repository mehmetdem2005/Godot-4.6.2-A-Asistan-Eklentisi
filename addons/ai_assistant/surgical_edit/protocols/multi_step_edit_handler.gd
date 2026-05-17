@tool
class_name AIMultiStepEditHandler
extends RefCounted

## MultiStepEditHandler — çok adımlı düzenleme protokolü (Surgical Edit).
##
## Bazı düzenlemeler tek adımda yapılamaz: "şu fonksiyonu yeniden
## adlandır, sonra gövdesini değiştir, sonra çağrıldığı yeri güncelle".
## Bu protokol birden çok düzenleme adımını SIRAYLA uygular.
##
## Kritik kural: adımlar SIRALI ve ATOMİK. Bir adım başarısız olursa
## tüm dizi durur — yarım uygulanmış düzenleme YOK. Ya hepsi ya hiçbiri.
## (Layer 4 transaction_batch ile aynı felsefe.)
##
## Her adım bir alt-protokole devreder: search_replace, insert,
## delete. Bu sınıf adımları koordine eder.
##
## Mock policy: bir adım başarısızsa dizi durur, kısmi sonuç
## kabul edilmez — açık hata.

## Adım tipleri — hangi alt-protokol kullanılacak.
enum StepKind { SEARCH_REPLACE, INSERT, DELETE }

const STEP_KIND_NAMES: Dictionary = {
	StepKind.SEARCH_REPLACE: "search_replace",
	StepKind.INSERT: "insert",
	StepKind.DELETE: "delete",
}


## Tek bir düzenleme adımı.
class EditStep extends RefCounted:
	var kind: int = AIMultiStepEditHandler.StepKind.SEARCH_REPLACE
	var description: String = ""
	## Adıma özel parametreler — kind'a göre değişir.
	var params: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"kind": AIMultiStepEditHandler.STEP_KIND_NAMES.get(kind, "?"),
			"description": description,
		}


## Çok adımlı düzenleme sonucu.
class MultiStepResult extends RefCounted:
	var ok: bool = false
	var new_content: String = ""
	var steps_applied: int = 0
	var steps_total: int = 0
	var failed_step: int = -1          ## Başarısız adım indeksi (-1 = yok)
	var rejected_reason: String = ""

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"steps_applied": steps_applied,
			"steps_total": steps_total,
			"failed_step": failed_step,
			"rejected_reason": rejected_reason,
		}


## Alt-protokol işleyicileri.
var _search_replace: AISearchReplaceHandler
var _insert: AIInsertAtAnchorHandler
var _delete: AIDeleteBlockHandler


func _init() -> void:
	_search_replace = AISearchReplaceHandler.new()
	_insert = AIInsertAtAnchorHandler.new()
	_delete = AIDeleteBlockHandler.new()


# ============================================================
# ÇOK ADIMLI UYGULAMA
# ============================================================

## Bir düzenleme adımları dizisini sırayla uygular.
## source: başlangıç içeriği. steps: EditStep listesi.
## Dönen: MultiStepResult.
##
## Atomik: bir adım başarısızsa dizi durur, o ana kadarki
## değişiklikler GEÇERSİZ — orijinal source döndürülür.
func apply_steps(source: String, steps: Array) -> MultiStepResult:
	var result := MultiStepResult.new()
	result.steps_total = steps.size()

	if steps.is_empty():
		result.rejected_reason = "Boş adım dizisi"
		return result

	# Adımları geçici içerik üzerinde sırayla uygula
	var working: String = source
	for i in range(steps.size()):
		var step: EditStep = steps[i]
		var step_result: Dictionary = _apply_single_step(working, step)
		if not step_result["ok"]:
			# Bir adım başarısız — tüm dizi iptal (atomik)
			result.ok = false
			result.failed_step = i
			result.steps_applied = i
			result.rejected_reason = "Adım %d başarısız: %s" % [
				i + 1, step_result["reason"]
			]
			# Orijinali döndür — yarım düzenleme yok
			result.new_content = source
			return result
		working = step_result["content"]
		result.steps_applied += 1

	# Tüm adımlar başarılı
	result.ok = true
	result.new_content = working
	return result


## Tek bir adımı uygun alt-protokole devreder.
## Dönen: {ok: bool, content: String, reason: String}
func _apply_single_step(content: String, step: EditStep) -> Dictionary:
	match step.kind:
		StepKind.SEARCH_REPLACE:
			var llm_output: String = step.params.get("llm_output", "")
			var apply: AISearchReplaceHandler.ApplyResult = \
				_search_replace.process(content, llm_output)
			if apply.ok:
				return {"ok": true, "content": apply.new_content, "reason": ""}
			return {
				"ok": false,
				"content": content,
				"reason": apply.rejected_reason,
			}
		StepKind.INSERT:
			var anchor: String = step.params.get("anchor", "")
			var code: String = step.params.get("code", "")
			var pos: int = step.params.get(
				"position", AIInsertAtAnchorHandler.InsertPosition.AFTER_ANCHOR
			)
			var ins: AIInsertAtAnchorHandler.InsertResult = _insert.apply(
				content, anchor, code, pos
			)
			if ins.ok:
				return {"ok": true, "content": ins.new_content, "reason": ""}
			return {
				"ok": false,
				"content": content,
				"reason": ins.rejected_reason,
			}
		StepKind.DELETE:
			var block: String = step.params.get("block", "")
			var del: AIDeleteBlockHandler.DeleteResult = \
				_delete.delete_text_block(content, block)
			if del.ok:
				return {"ok": true, "content": del.new_content, "reason": ""}
			return {
				"ok": false,
				"content": content,
				"reason": del.rejected_reason,
			}
		_:
			return {
				"ok": false,
				"content": content,
				"reason": "Bilinmeyen adım tipi",
			}


# ============================================================
# ADIM OLUŞTURMA — yardımcılar
# ============================================================

## SEARCH/REPLACE adımı oluşturur.
func make_search_replace_step(
	llm_output: String, description: String = ""
) -> EditStep:
	var step := EditStep.new()
	step.kind = StepKind.SEARCH_REPLACE
	step.description = description
	step.params = {"llm_output": llm_output}
	return step


## Ekleme adımı oluşturur.
func make_insert_step(
	anchor: String, code: String, position: int, description: String = ""
) -> EditStep:
	var step := EditStep.new()
	step.kind = StepKind.INSERT
	step.description = description
	step.params = {"anchor": anchor, "code": code, "position": position}
	return step


## Silme adımı oluşturur.
func make_delete_step(block: String, description: String = "") -> EditStep:
	var step := EditStep.new()
	step.kind = StepKind.DELETE
	step.description = description
	step.params = {"block": block}
	return step
