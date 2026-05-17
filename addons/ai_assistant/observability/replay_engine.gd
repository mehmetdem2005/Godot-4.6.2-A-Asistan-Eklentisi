@tool
class_name AIReplayEngine
extends RefCounted

## ReplayEngine — iz geri sarma motoru (Layer 6).
##
## TraceCollector izleri kaydeder. Bir task başarısız olduğunda "ne oldu?"
## sorusunu cevaplamak için izleri ADIM ADIM geri oynatmak gerekir.
##
## Bu sınıf bir iz dizisi alır ve:
##   - İleri/geri adımlama (step) sağlar
##   - Belirli bir olaya atlama (seek) sağlar
##   - Bir span'in tam zaman çizelgesini çıkarır
##   - İki nokta arasındaki olayları özetler
##
## Mock policy: replay sadece GERÇEK kaydedilmiş izleri oynatır.

## Oynatılan iz dizisi (AITraceCollector.TraceEntry listesi).
var _traces: Array = []

## Mevcut oynatma konumu (indeks). -1 = henüz başlamadı.
var _cursor: int = -1


## Bir iz dizisini replay'e yükler. İzler sequence'a göre sıralanır.
func load_traces(traces: Array) -> void:
	_traces = traces.duplicate()
	# Sequence'a göre sırala — deterministik oynatma
	_traces.sort_custom(func(a, b): return a.sequence < b.sequence)
	_cursor = -1


## Yüklü iz sayısı.
func trace_count() -> int:
	return _traces.size()


## Replay boş mu?
func is_empty() -> bool:
	return _traces.is_empty()


# ============================================================
# ADIMLAMA
# ============================================================

## Bir adım ileri gider. Dönen: o adımdaki TraceEntry, veya son ise null.
func step_forward() -> Variant:
	if _cursor + 1 >= _traces.size():
		return null
	_cursor += 1
	return _traces[_cursor]


## Bir adım geri gider. Dönen: o adımdaki TraceEntry, veya baş ise null.
func step_backward() -> Variant:
	if _cursor <= 0:
		_cursor = -1
		return null
	_cursor -= 1
	return _traces[_cursor]


## Mevcut konumdaki izi döndürür. Konum geçersizse null.
func current() -> Variant:
	if _cursor < 0 or _cursor >= _traces.size():
		return null
	return _traces[_cursor]


## Oynatmayı başa sarar.
func rewind() -> void:
	_cursor = -1


## Oynatmayı sona alır.
func fast_forward() -> void:
	_cursor = _traces.size() - 1


## Mevcut oynatma konumu (indeks).
func cursor_position() -> int:
	return _cursor


# ============================================================
# ATLAMA (SEEK)
# ============================================================

## Belirli bir sequence numarasına atlar.
## Dönen: o izin TraceEntry'si, bulunamazsa null.
func seek_to_sequence(sequence: int) -> Variant:
	for i in range(_traces.size()):
		if _traces[i].sequence == sequence:
			_cursor = i
			return _traces[i]
	return null


## Belirli bir olay tipine ait İLK ize atlar (mevcut konumdan sonra).
## Dönen: bulunan TraceEntry, yoksa null.
func seek_to_event(event_name: String) -> Variant:
	for i in range(_cursor + 1, _traces.size()):
		if _traces[i].event == event_name:
			_cursor = i
			return _traces[i]
	return null


## İlk hata izine atlar — tanı için en kullanışlı.
## Dönen: ilk ERROR seviyeli iz, yoksa null.
func seek_to_first_error() -> Variant:
	for i in range(_traces.size()):
		if _traces[i].level == AITraceCollector.TraceLevel.ERROR:
			_cursor = i
			return _traces[i]
	return null


# ============================================================
# ANALİZ
# ============================================================

## Belirli bir span'in tam zaman çizelgesini döndürür.
## Span başlangıcından bitişine kadar olan tüm izler, sırayla.
func span_timeline(span_id: String) -> Array:
	var result: Array = []
	for t in _traces:
		if t.span_id == span_id or t.parent_span_id == span_id:
			result.append(t)
	return result


## İki sequence arasındaki izleri döndürür (dahil).
func slice_between(from_seq: int, to_seq: int) -> Array:
	var result: Array = []
	for t in _traces:
		if t.sequence >= from_seq and t.sequence <= to_seq:
			result.append(t)
	return result


## Replay'in özetini çıkarır — kaç iz, kaç hata, hangi kategoriler.
func summary() -> Dictionary:
	var error_count: int = 0
	var warn_count: int = 0
	var categories: Dictionary = {}
	for t in _traces:
		if t.level == AITraceCollector.TraceLevel.ERROR:
			error_count += 1
		elif t.level == AITraceCollector.TraceLevel.WARN:
			warn_count += 1
		categories[t.category] = int(categories.get(t.category, 0)) + 1
	return {
		"total_traces": _traces.size(),
		"error_count": error_count,
		"warn_count": warn_count,
		"categories": categories,
		"cursor": _cursor,
	}


## Hata bağlamı — ilk hatanın etrafındaki izleri döndürür.
## context_size: hatadan önce/sonra kaç iz dahil edilsin.
## Tanı için: "hata olmadan hemen önce ne oldu?"
func error_context(context_size: int = 5) -> Array:
	var error_idx: int = -1
	for i in range(_traces.size()):
		if _traces[i].level == AITraceCollector.TraceLevel.ERROR:
			error_idx = i
			break
	if error_idx < 0:
		return []
	var start: int = maxi(0, error_idx - context_size)
	var end: int = mini(_traces.size(), error_idx + context_size + 1)
	return _traces.slice(start, end)
