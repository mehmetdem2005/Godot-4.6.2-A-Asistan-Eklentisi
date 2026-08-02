@tool
class_name AIAgentLiveBridge
extends Node

## AgentLiveBridge — Pilot Cell ↔ Router CANLI köprüsü (Aşama 4a/6).
##
## AIAgentBrain.think() senkrondur; gerçek HTTP çağrısı ise asenkrondur.
## Bu Node, Brain'in hazırladığı ProviderRequest'i Router → Transport →
## Adapter hattından geçirir ve sonucu sinyalle döndürür.
##
## Faz 6: yalnız metin değil, üretimde tanı ve maliyet hesabı için gereken
## güvenli sağlayıcı metadata'sı da sonuç sözleşmesine taşınır. API anahtarı,
## Authorization başlığı ve ham hassas istek/yanıt gövdeleri sonuçlara girmez.
##
## Mock policy: ağ/anahtar yoksa veya sağlayıcı hata dönerse açık
## başarısızlık yayılır — sahte ajan çıktısı ÜRETİLMEZ.

## Bir ajan canlı düşünme sonucu.
## result alanları:
## {ok, role, role_name, content, llm_called, latency_ms, status_note,
##  finish_reason, provider, provider_name, model, input_tokens,
##  output_tokens, total_tokens, from_cache, http_status, request_ref}
signal thought_completed(result: Dictionary)

## İlerleme bildirimi (UI için).
signal thought_progress(step: String)

## DeepSeek SSE parçası. kind: reasoning | content.
signal thought_stream(kind: String, text: String, metadata: Dictionary)

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
		_transport = AIStreamingHTTPTransport.new()
		_transport.name = "AgentLiveTransport"
		_transport.live_mode = true
		add_child(_transport)
	_connect_stream_transport()


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
	_connect_stream_transport()


## Bir rol + görev için AIProviderRequest kurar.
## Brain'i değiştirmeden onun kendi kurulumunu yeniden kullanır:
## think(live_mode=false) zaten prepared_request döndürür.
## model: boş değilse istek o belirli modele sabitlenir;
## boş = router/adapter varsayılanını kullanır.
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
## Verifier/HITL/Executor yok — düz konuşma yanıtı döner.
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
		+ "başlama.\n"
		+ "ÖNEMLİ: Bu asistanın GERÇEK üretim hattı vardır — proje "
		+ "dosyalarını res://game/ altına yazıp çalışan kod/sahne "
		+ "ÜRETEBİLİR. ASLA 'yazma yetkim yok / sadece okuyabiliyorum / "
		+ "elle şöyle yap' deme. Kullanıcı bir şey yapılmasını isterse "
		+ "kısaca 'üretebilirim' de ve 'oluştur', 'yap' veya 'üret' "
		+ "yazmasını iste — sistem o komutu otomatik üretim hattına "
		+ "alır. Adım adım elle tarif YERİNE üretimi öner."
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
## kullanıcı mesajından önce). Yalnız user/assistant turları alınır.
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


func _connect_stream_transport() -> void:
	if not (_transport is AIStreamingHTTPTransport):
		return
	var streaming := _transport as AIStreamingHTTPTransport
	if not streaming.stream_delta.is_connected(_on_transport_stream_delta):
		streaming.stream_delta.connect(_on_transport_stream_delta)


func _on_transport_stream_delta(
	kind: String, text: String, metadata: Dictionary
) -> void:
	if text.is_empty():
		return
	thought_stream.emit(kind, text, metadata.duplicate(true))


## Hazır bir isteği yönlendirir (cache/ağ) ve sonucu sinyalle döndürür.
func _dispatch(request: AIProviderRequest, role: int) -> bool:
	_active_request = request
	_active_role = role
	thought_progress.emit("İstek hazırlandı, yönlendiriliyor...")

	var routed: Dictionary = _router.route(request)

	# Cache hit veya hazırlık hatası — anında çözüldü.
	if bool(routed["resolved"]):
		var resp: AIProviderResponse = routed["response"]
		if resp != null and resp.is_usable():
			_emit_provider_response(role, resp)
		else:
			var msg: String = "Router isteği hazırlayamadı"
			if resp != null and not resp.error_message.is_empty():
				msg = resp.error_message
			var failure: Dictionary = _result_dict(
				false, role, "", msg, 0
			)
			if resp != null:
				failure = _with_response_metadata(failure, resp)
			_emit_result(failure)
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
	_emit_result(mapped)


## Ham HTTP sonucunu ajan-sonuç sözleşmesine çevirir.
## Senkron ve saf — gerçek ağ olmadan test edilebilir.
func finalize_raw(
	raw_result: Dictionary, request: AIProviderRequest, role: int
) -> Dictionary:
	var latency: int = int(raw_result.get("latency_ms", 0))
	var status: int = int(raw_result.get("status", 0))

	if not bool(raw_result.get("ok", false)):
		var net_err: String = str(raw_result.get("error", "?"))
		if status == 401:
			net_err = "API anahtarı reddedildi (401)"
		elif status == 429:
			net_err = "İstek limiti aşıldı (429)"
		var network_failure: Dictionary = _result_dict(
			false, role, "", net_err, latency
		)
		return _with_request_metadata(network_failure, request, status)

	if _router == null:
		var router_failure: Dictionary = _result_dict(
			false, role, "", "Router yok — yanıt çözülemez", latency
		)
		return _with_request_metadata(router_failure, request, status)

	var handled: Dictionary = _router.handle_response(
		raw_result, request, AIProviderRequest.Provider.DEEPSEEK
	)
	var response: AIProviderResponse = handled["response"]
	if response == null or not response.is_usable():
		var reason: String = "Sağlayıcı yanıtı kullanılamadı"
		if response != null and not response.error_message.is_empty():
			reason = response.error_message
		var provider_failure: Dictionary = _result_dict(
			false, role, "", reason, latency
		)
		if response != null:
			return _with_response_metadata(provider_failure, response)
		return _with_request_metadata(provider_failure, request, status)

	var mapped: Dictionary = _result_from_response(role, response)
	mapped["reasoning_content"] = str(raw_result.get("reasoning_content", ""))
	mapped["streamed"] = bool(raw_result.get("streamed", false))
	return mapped


## Köprü durumu — test ve UI için.
func bridge_status() -> Dictionary:
	return {
		"router_attached": _router != null,
		"transport_attached": _transport != null,
		"busy": _busy,
	}


# ============================================================
# SONUÇ + METADATA YARDIMCILARI
# ============================================================

func _result_dict(
	ok: bool, role: int, content: String, note: String, latency: int,
	finish_reason: String = ""
) -> Dictionary:
	return {
		"ok": ok,
		"role": role,
		"role_name": AICellRoles.role_name(role),
		"content": content,
		"reasoning_content": "",
		"streamed": false,
		"llm_called": true,
		"latency_ms": latency,
		"status_note": note,
		"finish_reason": finish_reason,
		"provider": -1,
		"provider_name": "",
		"model": "",
		"input_tokens": 0,
		"output_tokens": 0,
		"total_tokens": 0,
		"from_cache": false,
		"http_status": 0,
		"request_ref": "",
	}


func _result_from_response(
	role: int, response: AIProviderResponse
) -> Dictionary:
	var result: Dictionary = _result_dict(
		true,
		role,
		response.content,
		"LLM cevabı alındı",
		response.latency_ms,
		response.finish_reason
	)
	return _with_response_metadata(result, response)


func _with_response_metadata(
	result: Dictionary, response: AIProviderResponse
) -> Dictionary:
	result["provider"] = response.provider
	result["provider_name"] = str(
		AIProviderRequest.PROVIDER_NAMES.get(response.provider, "unknown")
	)
	result["model"] = response.model
	result["input_tokens"] = response.input_tokens
	result["output_tokens"] = response.output_tokens
	result["total_tokens"] = response.total_tokens()
	result["from_cache"] = response.from_cache
	result["finish_reason"] = response.finish_reason
	result["http_status"] = response.http_status
	result["latency_ms"] = response.latency_ms
	result["request_ref"] = response.request_ref
	return result


## Ağ seviyesi hata henüz ProviderResponse üretmediğinde yalnız güvenli
## istek kimliğini taşır. Anahtar, header ve ham gövde asla eklenmez.
func _with_request_metadata(
	result: Dictionary, request: AIProviderRequest, http_status: int
) -> Dictionary:
	result["http_status"] = http_status
	if request == null:
		return result
	result["provider"] = request.provider
	result["provider_name"] = request.provider_name()
	result["request_ref"] = request.id
	if request.provider == AIProviderRequest.Provider.DEEPSEEK:
		result["model"] = AIDeepSeekModelPolicy.canonical_model(request.model)
	else:
		result["model"] = request.model
	return result


func _emit_provider_response(role: int, response: AIProviderResponse) -> void:
	_emit_result(_result_from_response(role, response))


func _emit_result(result: Dictionary) -> void:
	thought_completed.emit(result)


func _emit_fail(role: int, note: String, latency: int = 0) -> void:
	var result: Dictionary = _result_dict(false, role, "", note, latency)
	result["llm_called"] = false
	_emit_result(result)
