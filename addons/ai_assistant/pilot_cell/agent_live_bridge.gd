@tool
class_name AIAgentLiveBridge
extends Node

## AgentLiveBridge — Pilot Cell ↔ Router CANLI köprüsü (Aşama 4a).
##
## SORUN (devir ADIM 2a): AIAgentBrain.think() SENKRONdur — _router.route()
## çağırıp anında "response" bekler. Ama gerçek ağ çağrısı ASENKRONdur
## (AIHTTPTransport sinyal-tabanlı). route() ağ gereken durumda
## {resolved:false, needs_network:true, response:null} döndürür; bu
## yüzden senkron Brain canlı modda HİÇBİR zaman gerçek cevap alamaz —
## hep NEEDS_LLM döner. provider_router.gd yorumundaki "route_async"
## hiç yazılmamıştı.
##
## ÇÖZÜM: Mevcut hiçbir dosyayı değiştirmeyen ince bir köprü Node'u.
## Brain'in zaten ürettiği prepared_request'i alır, live_connection_test
## ile birebir aynı kanıtlanmış asenkron deseni (route → send_post →
## handle_response) bir ajan için genelleştirir. Sonuç sinyalle gelir.
##
## Mock policy: ağ/anahtar yoksa veya sağlayıcı hata dönerse açık
## başarısızlık yayılır — sahte ajan çıktısı ÜRETİLMEZ.

## Bir ajan canlı düşünme sonucu.
## result: {ok, role, role_name, content, llm_called, latency_ms, status_note}
signal thought_completed(result: Dictionary)

## İlerleme bildirimi (UI için).
signal thought_progress(step: String)

## Bağlı Router — API anahtarları bunda ayarlı olmalı.
var _router: AIProviderRouter = null

## HTTP taşıyıcısı (çocuk Node — ağaca girer).
var _transport: AIHTTPTransport = null

## Şu an süren isteğin referansı (yanıt eşleştirme için).
var _active_request: AIProviderRequest = null

## Aktif düşünmenin rolü.
var _active_role: int = -1

## Bir düşünme sürüyor mu.
var _busy: bool = false


func _ready() -> void:
	if _transport == null:
		_transport = AIHTTPTransport.new()
		_transport.name = "AgentLiveTransport"
		_transport.live_mode = true
		add_child(_transport)


## Router'ı bağlar (orkestratörün anahtarlı router'ı verilmeli).
func attach_router(router: AIProviderRouter) -> void:
	_router = router


## Bağlı router (çok-adımlı akışta yardımcı köprüler aynı anahtarlı
## router'ı paylaşsın diye — additive, yan etkisiz).
func router() -> AIProviderRouter:
	return _router


## Test/ileri kullanım: dış taşıyıcı enjekte eder (ağaca eklenmiş olmalı).
func attach_transport(transport: AIHTTPTransport) -> void:
	_transport = transport


## Bir rol + görev için AIProviderRequest kurar.
## Brain'i HİÇ değiştirmeden onun kendi kurulumunu yeniden kullanır:
## think(live_mode=false) zaten prepared_request döndürür.
## model: boş değilse istek o belirli modele sabitlenir (UI model seçimi);
## boş = router/adapter varsayılanını kullanır (geriye uyumlu).
func build_request_for(
	role: int, task: String, context: Dictionary = {},
	model: String = ""
) -> AIProviderRequest:
	var brain := AIAgentBrain.new()
	var thought: AIAgentBrain.ThoughtResult = brain.think(role, task, context)
	var request: AIProviderRequest = thought.prepared_request
	if request != null and not model.strip_edges().is_empty():
		request.model = model.strip_edges()
	return request


## Bir ajan rolü için CANLI düşünme başlatır (asenkron).
## Sonuç 'thought_completed' sinyali ile gelir — bu fonksiyon beklemez.
## Dönen: başlatılabildi mi (false = ön koşul hatası, sinyal yine yayılır).
func think_live(
	role: int, task: String, context: Dictionary = {},
	model: String = ""
) -> bool:
	if _busy:
		_emit_fail(role, "Köprü meşgul — başka bir düşünme sürüyor")
		return false
	if _router == null:
		_emit_fail(role, "Router bağlı değil — canlı çağrı yapılamaz")
		return false

	var request: AIProviderRequest = build_request_for(
		role, task, context, model
	)
	if request == null:
		_emit_fail(role, "İstek kurulamadı (rol promptsuz olabilir)")
		return false
	return _dispatch(request, role)


## Doğal SOHBET cevabı için CANLI çağrı (asenkron). Kod hattı değil:
## Verifier/HITL/Executor YOK — düz konuşma yanıtı döner.
## Sohbet/kod ayrımı kullanıcıyı "syntactic" hatasına boğmasın diye.
## history: önceki konuşma turları [{role, content}] (eski→yeni) —
## çok-turlu hafıza. Boş = eski stateless davranış (geriye uyumlu).
func think_chat(
	message: String, model: String = "", history: Array = [],
	project_context: String = ""
) -> bool:
	if _busy:
		_emit_fail(-1, "Köprü meşgul — başka bir düşünme sürüyor")
		return false
	if _router == null:
		_emit_fail(-1, "Router bağlı değil — canlı çağrı yapılamaz")
		return false

	var request := AIProviderRequest.create(
		AIProviderRequest.Purpose.REASONING, "ChatAssistant"
	)
	request.add_message("system", (
		"Rolün: Godot 4.6 oyun motoru için yardımcı, Türkçe konuşan "
		+ "bir AI asistan. Kullanıcıyla doğal sohbet et; net, kısa ve "
		+ "yararlı yanıtlar ver. Önceki konuşma turlarını dikkate al "
		+ "(kullanıcı 'az önce' dediğinde geçmişe bak). Kod istenmedikçe "
		+ "kod bloğu yazma. Yanıta kendi rol tanımını tekrar ederek "
		+ "başlama."
	))
	if not project_context.strip_edges().is_empty():
		request.add_message("system", (
			"Aşağıda kullanıcının Godot projesinin GERÇEK dosya/klasör "
			+ "listesi var. 'Hangi dosyalar var' gibi sorularda BUNU "
			+ "kullan — erişimin yok deme.\n" + project_context
		))
	_append_history(request, history)
	request.add_message("user", message)
	if not model.strip_edges().is_empty():
		request.model = model.strip_edges()
	return _dispatch(request, -1)


## Konuşma geçmişini isteğe ekler (sistem promptu sonrası, güncel
## kullanıcı mesajından önce). Yalnız user/assistant turları; bozuk
## girdiler sessizce atlanır (geriye uyumlu — boş history etkisiz).
func _append_history(request: AIProviderRequest, history: Array) -> void:
	for turn in history:
		if typeof(turn) != TYPE_DICTIONARY:
			continue
		var role: String = str(turn.get("role", "")).strip_edges()
		var content: String = str(turn.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		if role != "user" and role != "assistant":
			continue
		request.add_message(role, content)


## Hazır bir isteği yönlendirir (cache/ağ) ve sonucu sinyalle döndürür.
## think_live ve think_chat ortak asenkron çekirdeği — kanıtlanmış desen.
func _dispatch(request: AIProviderRequest, role: int) -> bool:
	_active_request = request
	_active_role = role
	thought_progress.emit("İstek hazırlandı, yönlendiriliyor...")

	var routed: Dictionary = _router.route(request)

	# Cache hit veya hazırlık hatası — anında çözüldü
	if bool(routed["resolved"]):
		var resp: AIProviderResponse = routed["response"]
		if resp != null and resp.is_usable():
			_emit_ok(role, resp.content, 0)
		else:
			var msg: String = "Router isteği hazırlayamadı"
			if resp != null and not resp.error_message.is_empty():
				msg = resp.error_message
			_emit_fail(role, msg)
		return true

	if not bool(routed["needs_network"]):
		_emit_fail(role, "Beklenmeyen router durumu")
		return false

	if _transport == null:
		_emit_fail(role, "HTTP taşıyıcısı yok — ağ çağrısı yapılamaz")
		return false

	var prepared: Dictionary = routed["prepared"]
	_busy = true
	thought_progress.emit("Sağlayıcıya bağlanılıyor...")
	var started: bool = _transport.send_post(
		str(prepared["url"]),
		prepared["headers"],
		prepared["body"],
		_on_net_result
	)
	if not started:
		_busy = false
		_emit_fail(role, "HTTP isteği başlatılamadı (taşıyıcı meşgul?)")
		return false
	return true


## Transport ağ çağrısını bitirince çağrılır.
func _on_net_result(raw_result: Dictionary) -> void:
	_busy = false
	var mapped: Dictionary = finalize_raw(
		raw_result, _active_request, _active_role
	)
	if bool(mapped["ok"]):
		_emit_ok(_active_role, str(mapped["content"]),
			int(mapped["latency_ms"]))
	else:
		_emit_fail(_active_role, str(mapped["status_note"]),
			int(mapped["latency_ms"]))


## Ham HTTP sonucunu ajan-sonuç sözleşmesine çevirir.
## SENKRON ve saf — gerçek ağ olmadan test edilebilir (sahte raw verilir).
## provider: bu sürümde DeepSeek (router fallback zinciri yönetir).
func finalize_raw(
	raw_result: Dictionary, request: AIProviderRequest, role: int
) -> Dictionary:
	var latency: int = int(raw_result.get("latency_ms", 0))

	if not bool(raw_result.get("ok", false)):
		var net_err: String = str(raw_result.get("error", "?"))
		var status: int = int(raw_result.get("status", 0))
		if status == 401:
			net_err = "API anahtarı reddedildi (401)"
		elif status == 429:
			net_err = "İstek limiti aşıldı (429)"
		return _result_dict(false, role, "", net_err, latency)

	if _router == null:
		return _result_dict(
			false, role, "", "Router yok — yanıt çözülemez", latency
		)

	var handled: Dictionary = _router.handle_response(
		raw_result, request, AIProviderRequest.Provider.DEEPSEEK
	)
	var response: AIProviderResponse = handled["response"]
	if response == null or not response.is_usable():
		var reason: String = "Sağlayıcı yanıtı kullanılamadı"
		if response != null and not response.error_message.is_empty():
			reason = response.error_message
		return _result_dict(false, role, "", reason, latency)

	return _result_dict(true, role, response.content, "LLM cevabı alındı",
		latency)


## Köprü durumu — test ve UI için.
func bridge_status() -> Dictionary:
	return {
		"router_attached": _router != null,
		"transport_attached": _transport != null,
		"busy": _busy,
	}


# ============================================================
# İÇ YARDIMCILAR
# ============================================================

func _result_dict(
	ok: bool, role: int, content: String, note: String, latency: int
) -> Dictionary:
	return {
		"ok": ok,
		"role": role,
		"role_name": AICellRoles.role_name(role),
		"content": content,
		"llm_called": true,
		"latency_ms": latency,
		"status_note": note,
	}


func _emit_ok(role: int, content: String, latency: int) -> void:
	thought_completed.emit(
		_result_dict(true, role, content, "LLM cevabı alındı", latency)
	)


func _emit_fail(role: int, note: String, latency: int = 0) -> void:
	var d: Dictionary = _result_dict(false, role, "", note, latency)
	d["llm_called"] = false
	thought_completed.emit(d)
