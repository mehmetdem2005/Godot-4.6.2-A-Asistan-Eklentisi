@tool
class_name AILifecycleIntentHandler
extends RefCounted

## IntentHandler — intent yöneticisi (Madde 10 / deep_links).
##
## Deep link: oyunu belirli bir duruma açan özel bir bağlantı.
## "mygame://event/halloween" gibi bir link tıklanınca oyun açılır
## ve doğrudan Halloween etkinliğine gider.
##
## Bu sınıf gelen bir intent/link'i AYRIŞTIRIR — şema, yol, parametre
## parçalarına böler. Geçersiz/zararlı linkleri reddeder.
##
## Phase 1 — temel ayrıştırma. Karmaşık yönlendirme url_router'da,
## ertelenmiş linkler deferred_link_resolver'da.
##
## "Mock yasak": geçersiz link "geçerli" sayılmaz — açıkça reddedilir.
##
## Mock policy: ayrıştırma gerçek link metninden.

## Oyunun kabul ettiği link şeması.
const APP_SCHEME: String = "mygame"


## Ayrıştırılmış bir deep link.
class ParsedLink extends RefCounted:
	var valid: bool = false
	var scheme: String = ""
	var host: String = ""              ## İlk yol parçası (örn. "event")
	var path_segments: PackedStringArray = PackedStringArray()
	var params: Dictionary = {}        ## ?key=value parametreleri
	var error: String = ""

	func to_dict() -> Dictionary:
		return {
			"valid": valid, "scheme": scheme, "host": host,
			"segments": path_segments.size(), "param_count": params.size(),
		}


# ============================================================
# AYRIŞTIRMA
# ============================================================

## Bir deep link metnini ayrıştırır.
## Beklenen biçim: scheme://host/segment1/segment2?key=value
## link: ayrıştırılacak link metni.
## Dönen: ParsedLink.
func parse(link: String) -> ParsedLink:
	var result := ParsedLink.new()
	var trimmed: String = link.strip_edges()

	if trimmed.is_empty():
		result.error = "Boş link"
		return result

	# Şema ayır — "scheme://"
	var scheme_sep: int = trimmed.find("://")
	if scheme_sep == -1:
		result.error = "Geçersiz link — şema yok"
		return result

	result.scheme = trimmed.substr(0, scheme_sep)
	# Sadece bizim şemamızı kabul et
	if result.scheme != APP_SCHEME:
		result.error = "Bilinmeyen şema: " + result.scheme
		return result

	var rest: String = trimmed.substr(scheme_sep + 3)
	if rest.is_empty():
		result.error = "Link gövdesi boş"
		return result

	# Parametreleri ayır — "?key=value&..."
	var query_sep: int = rest.find("?")
	var path_part: String = rest
	if query_sep != -1:
		path_part = rest.substr(0, query_sep)
		var query_part: String = rest.substr(query_sep + 1)
		result.params = _parse_query(query_part)

	# Yol parçalarını ayır
	var segments: PackedStringArray = path_part.split("/", false)
	if segments.is_empty():
		result.error = "Link yolu boş"
		return result

	result.host = segments[0]
	for i in range(1, segments.size()):
		result.path_segments.append(segments[i])

	result.valid = true
	return result


## Sorgu dizesini parametre sözlüğüne ayrıştırır.
## "key1=val1&key2=val2" -> {key1: val1, key2: val2}
func _parse_query(query: String) -> Dictionary:
	var params: Dictionary = {}
	var pairs: PackedStringArray = query.split("&", false)
	for pair in pairs:
		var eq: int = pair.find("=")
		if eq > 0:
			var key: String = pair.substr(0, eq)
			var value: String = pair.substr(eq + 1)
			params[key] = value
	return params


# ============================================================
# SORGULAMA
# ============================================================

## Bir link geçerli bir deep link mi?
func is_valid_link(link: String) -> bool:
	return parse(link).valid


## Bir link bizim uygulamamıza mı ait?
func is_app_link(link: String) -> bool:
	var trimmed: String = link.strip_edges()
	return trimmed.begins_with(APP_SCHEME + "://")
