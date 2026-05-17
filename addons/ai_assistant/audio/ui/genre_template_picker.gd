@tool
class_name AIAudioGenreTemplatePicker
extends RefCounted

## GenreTemplatePicker — tür şablonu seçici (Madde 08 / audio / ui).
##
## genre_audio_registry'deki 9 tür ses şablonunu görsel bir seçiciye
## çevirir: her tür bir kart (ad, açıklama, ses kimliği önizleme),
## kullanıcı seçer, "uygula" der.
##
## Bu view-model seçici durumunu tutar: hangi tür seçili, uygulama
## planının önizlemesi. Görsel seçici Control'ü kartları çizer.
##
## genre_audio_registry + template_applier (mantık katmanı) ile
## beslenir; bu sınıf seçim oturumunu yönetir.
##
## Mock policy: seçici gerçek şablon verisinden.

## Tür şablonu kartları — her biri {genre, label, description}.
const GENRE_CARDS: Array = [
	{"genre": "fps_3d", "label": "FPS / Nişancı"},
	{"genre": "platformer_2d", "label": "2D Platform"},
	{"genre": "rpg_topdown", "label": "RPG"},
	{"genre": "puzzle", "label": "Bulmaca"},
	{"genre": "racing_3d", "label": "Yarış"},
	{"genre": "survival_3d", "label": "Hayatta Kalma"},
	{"genre": "horror_3d", "label": "Korku"},
	{"genre": "visual_novel", "label": "Görsel Roman"},
	{"genre": "strategy_isometric", "label": "Strateji"},
]


## Şu an seçili tür (yoksa boş).
var selected_genre: String = ""

## Şablon uygulandı mı.
var _applied: bool = false


# ============================================================
# SEÇİM
# ============================================================

## Bir tür kartını seçer.
## genre: tür adı.
## Dönen: true = geçerli tür.
func select_genre(genre: String) -> bool:
	for card in GENRE_CARDS:
		if str(card["genre"]) == genre:
			selected_genre = genre
			_applied = false
			return true
	return false


## Seçimi temizler.
func clear_selection() -> void:
	selected_genre = ""
	_applied = false


# ============================================================
# UYGULAMA
# ============================================================

## Seçili şablonu uygulanmış olarak işaretler.
## Gerçek uygulama template_applier'ın işi; bu sadece UI durumu.
## Dönen: true = uygulanabildi.
func mark_applied() -> bool:
	if selected_genre.is_empty():
		return false
	_applied = true
	return true


## Şablon uygulandı mı?
func is_applied() -> bool:
	return _applied


# ============================================================
# SUNUM
# ============================================================

## Tüm tür kartlarının görsel listesini üretir.
## Dönen: her biri {genre, label, selected} dizi.
func build_cards() -> Array:
	var cards: Array = []
	for card in GENRE_CARDS:
		var genre: String = str(card["genre"])
		cards.append({
			"genre": genre,
			"label": str(card["label"]),
			"selected": genre == selected_genre,
		})
	return cards


## Seçili türün etiketini döndürür. Seçim yoksa boş string.
func selected_label() -> String:
	for card in GENRE_CARDS:
		if str(card["genre"]) == selected_genre:
			return str(card["label"])
	return ""


# ============================================================
# SORGULAMA
# ============================================================

## Bir tür seçili mi?
func has_selection() -> bool:
	return not selected_genre.is_empty()


## "Uygula" butonu etkin olmalı mı (seçim var, henüz uygulanmadı)?
func can_apply() -> bool:
	return has_selection() and not _applied


## Toplam tür kartı sayısı.
func card_count() -> int:
	return GENRE_CARDS.size()
