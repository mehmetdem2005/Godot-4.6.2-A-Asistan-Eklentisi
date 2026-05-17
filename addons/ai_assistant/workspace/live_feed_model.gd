@tool
class_name AILiveFeedModel
extends RefCounted

## LiveFeedModel — canlı akış sekmesi modeli (Layer 11).
##
## Live Feed sekmesinin altındaki mantık. Layer 6'daki AIFeedEmitter
## olayları yayınlar; bu model onları alır, UI'ın göstereceği biçimde
## filtreler/biriktirir. Görsel liste Control'ü bu modeli okur.
##
## Sağladıkları:
##   - Olay biriktirme (sınırlı tampon — UI donmasın)
##   - Severity filtresi (sadece hata göster vb.)
##   - Kategori/task filtresi
##   - Otomatik kaydırma durumu (yeni olayda en alta in)
##
## Mock policy: feed gerçek sistem olaylarından beslenir.

## UI'da gösterilecek maksimum olay (tampon).
const MAX_DISPLAYED: int = 300

## Görüntülenen olaylar (AIFeedEvent listesi) — en yeni sonda.
var _events: Array = []

## Aktif severity filtresi — bu seviye ve üstü gösterilir.
## AIFeedEvent.Severity.DEBUG = hepsini göster.
var min_severity_filter: int = AIFeedEvent.Severity.DEBUG

## Aktif kategori filtresi — boş = tüm kategoriler.
var category_filter: String = ""

## Otomatik kaydırma açık mı (yeni olayda listenin sonuna in).
var auto_scroll: bool = true


# ============================================================
# OLAY ALMA — FeedEmitter aboneliği
# ============================================================

## Bir olayı modele ekler. AIFeedEmitter.subscribe ile bağlanır:
##   feed_emitter.subscribe(live_feed_model.on_event)
func on_event(event: AIFeedEvent) -> void:
	if event == null:
		return
	_events.append(event)
	# Tampon taşarsa en eskiyi at
	if _events.size() > MAX_DISPLAYED:
		_events.pop_front()


## Bir AIFeedEmitter'a bu modeli abone yapar.
func attach_to(emitter: AIFeedEmitter) -> void:
	if emitter == null:
		push_warning("LiveFeedModel.attach_to: null emitter")
		return
	emitter.subscribe(on_event)
	# Geçmiş olayları da al — UI ilk açılışta dolu görünsün
	for e in emitter.recent_events(MAX_DISPLAYED):
		_events.append(e)


# ============================================================
# FİLTRELEME — UI'ın göstereceği olaylar
# ============================================================

## Filtrelerden geçen olayları döndürür — UI bunu çizer.
func visible_events() -> Array:
	var result: Array = []
	for e in _events:
		var event: AIFeedEvent = e
		# Severity filtresi
		if event.severity < min_severity_filter:
			continue
		# Kategori filtresi (event_type üzerinden)
		if not category_filter.is_empty():
			if not event.event_type.contains(category_filter):
				continue
		result.append(event)
	return result


## Görünür olay sayısı (filtre uygulanmış).
func visible_count() -> int:
	return visible_events().size()


## Toplam olay sayısı (filtresiz).
func total_count() -> int:
	return _events.size()


## Severity filtresini ayarlar.
func set_severity_filter(min_severity: int) -> void:
	min_severity_filter = min_severity


## Kategori filtresini ayarlar. Boş string = filtre kapalı.
func set_category_filter(category: String) -> void:
	category_filter = category


## Tüm filtreleri sıfırlar — her şey görünür olur.
func clear_filters() -> void:
	min_severity_filter = AIFeedEvent.Severity.DEBUG
	category_filter = ""


# ============================================================
# SORGULAMA
# ============================================================

## En son n görünür olay — UI'ın alt kısmı.
func recent_visible(n: int) -> Array:
	var visible: Array = visible_events()
	if n >= visible.size():
		return visible
	return visible.slice(visible.size() - n, visible.size())


## Sadece hata olaylarının sayısı — UI rozet/uyarı için.
func error_count() -> int:
	var count: int = 0
	for e in _events:
		if (e as AIFeedEvent).severity >= AIFeedEvent.Severity.ERROR:
			count += 1
	return count


## En son olay. Yoksa null.
func last_event() -> AIFeedEvent:
	if _events.is_empty():
		return null
	return _events[_events.size() - 1]


## Model durum özeti.
func summary() -> Dictionary:
	return {
		"total": _events.size(),
		"visible": visible_count(),
		"errors": error_count(),
		"auto_scroll": auto_scroll,
		"severity_filter": min_severity_filter,
		"category_filter": category_filter,
	}


## Olay geçmişini temizler.
func clear() -> void:
	_events.clear()
