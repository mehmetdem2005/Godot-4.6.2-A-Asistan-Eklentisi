@tool
class_name AIAgentWorkOrder
extends RefCounted

## Bir görevin organizasyon içindeki imzalı yönlendirme sözleşmesi.
## WorkOrder doğrudan araç çalıştırmaz; mevcut pipeline/executor için
## birincil rol, bağımsız denetçiler ve escalation bağlamı üretir.

var task_id: String = ""
var title: String = ""
var description: String = ""
var target_path: String = ""
var primary_role_id: String = ""
var department: String = ""
var reviewer_ids: PackedStringArray = PackedStringArray()
var escalation_role_id: String = ""
var required_capabilities: PackedStringArray = PackedStringArray()
var confidence: float = 0.0
var rationale: String = ""
var status: String = "assigned"
var high_risk: bool = false


func validate(chart: AIAgentOrgChart) -> Dictionary:
	var errors := PackedStringArray()
	if task_id.is_empty():
		errors.append("task_id boş")
	if title.is_empty():
		errors.append("başlık boş")
	if not chart.has_role(primary_role_id):
		errors.append("birincil rol yok: " + primary_role_id)
	else:
		var primary := chart.role(primary_role_id)
		if primary.department != department:
			errors.append("departman/rol uyuşmuyor")
		if primary.can_execute and reviewer_ids.is_empty():
			errors.append("uygulayıcı görev bağımsız denetçisiz olamaz")
	for reviewer_id in reviewer_ids:
		if reviewer_id == primary_role_id:
			errors.append("ajan kendi işini inceleyemez")
		elif not chart.has_role(reviewer_id):
			errors.append("denetçi rolü yok: " + reviewer_id)
		else:
			var reviewer := chart.role(reviewer_id)
			if not reviewer.can_approve:
				errors.append("denetçi onay yetkili değil: " + reviewer_id)
	if high_risk and not reviewer_ids.has("security_reviewer"):
		errors.append("yüksek riskli görev güvenlik incelemesi gerektirir")
	if not escalation_role_id.is_empty() and not chart.has_role(escalation_role_id):
		errors.append("escalation rolü yok")
	return {"ok": errors.is_empty(), "errors": Array(errors)}


func to_dict() -> Dictionary:
	return {
		"task_id": task_id,
		"title": title,
		"description": description,
		"target_path": target_path,
		"primary_role_id": primary_role_id,
		"department": department,
		"reviewer_ids": Array(reviewer_ids),
		"escalation_role_id": escalation_role_id,
		"required_capabilities": Array(required_capabilities),
		"confidence": confidence,
		"rationale": rationale,
		"status": status,
		"high_risk": high_risk,
	}


func prompt_context(chart: AIAgentOrgChart) -> String:
	var primary := chart.role(primary_role_id)
	if primary == null:
		return ""
	var reviewers := PackedStringArray()
	for reviewer_id in reviewer_ids:
		var reviewer := chart.role(reviewer_id)
		if reviewer != null:
			reviewers.append("%s (%s)" % [reviewer.title, reviewer.role_id])
	return (
		"ORGANİZASYON İŞ EMRİ\n"
		+ "Görev: %s\n" % title
		+ "Birincil ajan: %s (%s)\n" % [primary.title, primary.role_id]
		+ "Departman: %s\n" % department
		+ "Bağımsız denetçiler: %s\n" % ", ".join(reviewers)
		+ "Yetki sınırı: Yalnız öneri/çıktı üret; gerçek mutasyon Executor ve HITL üzerinden.\n"
		+ "Gerekçe: %s" % rationale
	)
