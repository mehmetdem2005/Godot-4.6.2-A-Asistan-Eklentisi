@tool
class_name AIRoleChainRunner
extends Node

## RoleChainRunner — görev başına çoklu rol hattı (Plan C).
##
## SORUN: tek CodeEngineer çağrısı kalitesizdi; cell_orchestrator'ın
## 14-rol hattı SENKRON (gerçek async wiring YOK) — canlıya çeviren
## tek kanıtlanmış desen AIAgentLiveBridge._dispatch.
##
## ÇÖZÜM: Bridge'in kanıtlanmış tek-rol async desenini KISA bir rol
## zincirinde tekrar kullan: Architect → CodeEngineer → Reviewer.
## Her rolün çıktısı bir sonrakinin context'ine aktarılır (Brain
## zaten "ÖNCEKİ AŞAMALARDAN BAĞLAM" olarak işler). Reviewer FAIL
## derse TEK bir düzeltme turu (CodeEngineer yeniden) — sınırlı,
## sonsuz döngü yok. Tek köprü _busy olduğundan zincir doğal serileşir.
##
## Mock policy: bir rol düşerse zincir dürüstçe başarısız döner —
## sahte ara çıktı uydurulmaz. Nihai artefakt CodeEngineer kodudur
## (Reviewer PASS/FAIL üretir, kod değil — orkestratör Verifier ile
## son kapıyı zaten uygular).

signal chain_progress(step: String)
signal chain_completed(result: Dictionary)

## Sabit zincir (Plan C kapsamı — düşük risk, çoklu rol).
const BASE_CHAIN: Array = [
	AICellRoles.Role.ARCHITECT,
	AICellRoles.Role.CODE_ENGINEER,
	AICellRoles.Role.REVIEWER,
]

## Kod üreten roller için zorunlu model. deepseek-reasoner kod
## adımında token bütçesini düşünce zincirine harcayıp final içeriği
## BOŞ döndürüyor ("Sağlayıcı yanıtı kullanılamadı" — telefon testi
## kanıtı). deepseek-chat kod emisyonu için doğru araç; planlama/
## inceleme kullanıcının seçtiği modelde kalır.
const CODE_MODEL: String = "deepseek-chat"

## BÖLÜNMÜŞ ÜRETİM: tek çağrı sağlayıcı tavanında (8192) kesilirse
## kaldığı yerden devam parçaları istenir, birleştirilir. Sınırlı —
## sonsuz döngü yok.
const MAX_CODE_CHUNKS: int = 6
const CONT_TAIL_CHARS: int = 2000

var _bridge: AIAgentLiveBridge = null
var _task: String = ""
var _model: String = ""
var _steps: Array = []
var _idx: int = 0
var _context: Dictionary = {}
var _code: String = ""
var _transcript: Array = []
var _corrected: bool = false
var _running: bool = false
var _code_accum: String = ""
var _chunk: int = 0


## Köprüyü bağlar (paylaşılan anahtarlı router'lı).
func attach_bridge(bridge: AIAgentLiveBridge) -> void:
	_bridge = bridge


## Bir alt görev için rol zincirini başlatır (asenkron).
## mode: "full" = Architect→CodeEngineer→Reviewer; "repair" =
## CodeEngineer→Reviewer (Architect'siz — hata zaten belli, daha
## hızlı/ucuz). Sonuç 'chain_completed' ile.
func run(task: String, model: String = "", mode: String = "full") -> bool:
	if _running:
		_finish(false, "Zincir zaten çalışıyor")
		return false
	if _bridge == null:
		_finish(false, "Köprü bağlı değil")
		return false
	_task = task
	_model = model
	_idx = 0
	_context = {}
	_code = ""
	_transcript = []
	_corrected = false
	_code_accum = ""
	_chunk = 0
	if mode == "repair":
		_steps = [
			AICellRoles.Role.CODE_ENGINEER,
			AICellRoles.Role.REVIEWER,
		]
	else:
		_steps = BASE_CHAIN.duplicate()
	if not _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.connect(_on_thought)
	_running = true
	return _dispatch_step()


func _dispatch_step() -> bool:
	var role: int = int(_steps[_idx])
	chain_progress.emit(AICellRoles.role_name(role) + " düşünüyor...")
	# Kod üreten roller deepseek-chat'e zorlanır (reasoner boş-içerik
	# hatası); diğer roller kullanıcının seçtiği modelde kalır.
	var model: String = _model
	if AICellRoles.is_code_generating(role):
		model = CODE_MODEL
	return _bridge.think_live(role, _task, _context, model)


func _on_thought(thought: Dictionary) -> void:
	if not _running:
		return
	var role: int = int(_steps[_idx])
	var role_name: String = AICellRoles.role_name(role)
	if not bool(thought.get("ok", false)):
		_finish(false, "Rol başarısız (%s): %s" % [
			role_name, str(thought.get("status_note", ""))
		])
		return
	var content: String = str(thought.get("content", ""))
	_transcript.append({"role": role_name, "content": content})
	match role:
		AICellRoles.Role.ARCHITECT:
			_context["mimari_tasarim"] = content
		AICellRoles.Role.CODE_ENGINEER:
			_code_accum += content
			# Sağlayıcı tavanında kesildiyse: kaldığı yerden devam iste.
			if (str(thought.get("finish_reason", "")) == "length"
					and _chunk < MAX_CODE_CHUNKS):
				_chunk += 1
				chain_progress.emit(
					"Kod uzun — bölünmüş üretim (parça %d)" % (_chunk + 1)
				)
				var cont: String = (
					_task + "\n\n[BÖLÜNMÜŞ ÜRETİM] Önceki çıktı uzunluk "
					+ "sınırında kesildi. Aşağıdaki kısmı AYNEN TEKRARLAMA; "
					+ "tam kaldığın yerden devam et, SADECE eksik kalan "
					+ "GDScript'i ekle, markdown/açıklama yazma:\n"
					+ _tail(_code_accum)
				)
				_bridge.think_live(
					AICellRoles.Role.CODE_ENGINEER, cont, {}, CODE_MODEL
				)
				return
			_code = _join_clean(_code_accum)
			_context["uretilen_kod"] = _code
			_code_accum = ""
			_chunk = 0
		AICellRoles.Role.REVIEWER:
			_context["inceleme_bulgulari"] = content
			if _is_fail(content) and not _corrected:
				# TEK düzeltme turu — Reviewer bulgularıyla yeniden kodla.
				_corrected = true
				_steps.append(AICellRoles.Role.CODE_ENGINEER)
	_idx += 1
	if _idx >= _steps.size():
		_finish(true, "Zincir tamam (%d rol)" % _transcript.size())
		return
	_dispatch_step()


## Birleştirilen kodun son CONT_TAIL_CHARS karakteri (devam bağlamı).
func _tail(text: String) -> String:
	if text.length() <= CONT_TAIL_CHARS:
		return text
	return text.substr(text.length() - CONT_TAIL_CHARS)


## Parçaları birleştirir, markdown çit satırlarını (```), söker.
## GDScript'te ``` sözdizimi yoktur → güvenli; extract_code sonra
## çitsiz metni aynen geçirir (tutarlı, kesintisiz kod).
func _join_clean(raw: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in raw.split("\n"):
		if str(line).strip_edges().begins_with("```"):
			continue
		out.append(line)
	return "\n".join(out).strip_edges()


## Reviewer çıktısı FAIL mi (PASS varsa geçer kabul — heuristik).
func _is_fail(content: String) -> bool:
	var u: String = content.to_upper()
	return u.contains("FAIL") and not u.contains("PASS")


func _finish(ok: bool, note: String) -> void:
	_running = false
	if _bridge != null and _bridge.thought_completed.is_connected(_on_thought):
		_bridge.thought_completed.disconnect(_on_thought)
	chain_completed.emit({
		"ok": ok,
		"content": _code,
		"transcript": _transcript,
		"status_note": note,
		"role_name": AICellRoles.role_name(AICellRoles.Role.CODE_ENGINEER),
	})
