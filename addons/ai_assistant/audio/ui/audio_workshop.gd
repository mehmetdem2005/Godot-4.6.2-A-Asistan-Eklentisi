@tool
class_name AIAudioWorkshop
extends RefCounted

## AudioWorkshop — ana ses sekmesi (Madde 08 / audio / ui).
##
## Ses sisteminin ana UI sekmesi (🎵 Ses). Alt panelleri barındırır:
## bus mikseri, prosedürel ses tasarımcısı, müzik katmanlama, bütçe
## göstergesi, tür şablonu seçici.
##
## Bu view-model sekmenin durumunu tutar: hangi alt-panel aktif,
## genel ses sistemi durumu. Görsel sekme Control'ü bunu okur.
##
## Mock policy: durum gerçek alt-panel seçiminden.

## Ses sekmesinin alt panelleri.
enum AudioPanel { BUS_MIXER, SFX_DESIGNER, MUSIC_LAYERING, BUDGET, TEMPLATES }

const PANEL_NAMES: Dictionary = {
	AudioPanel.BUS_MIXER: "bus_mixer",
	AudioPanel.SFX_DESIGNER: "sfx_designer",
	AudioPanel.MUSIC_LAYERING: "music_layering",
	AudioPanel.BUDGET: "budget",
	AudioPanel.TEMPLATES: "templates",
}

const PANEL_LABELS: Dictionary = {
	AudioPanel.BUS_MIXER: "Bus Mikseri",
	AudioPanel.SFX_DESIGNER: "Ses Efekti Tasarımı",
	AudioPanel.MUSIC_LAYERING: "Müzik Katmanlama",
	AudioPanel.BUDGET: "Bellek Bütçesi",
	AudioPanel.TEMPLATES: "Tür Şablonları",
}


## Şu an aktif alt-panel.
var active_panel: int = AudioPanel.BUS_MIXER

## Panel geçiş geçmişi — geri navigasyon için.
var _history: Array = []


# ============================================================
# PANEL GEÇİŞİ
# ============================================================

## Bir alt-panele geçer.
## panel: AudioPanel değeri.
## Dönen: true = geçerli geçiş.
func switch_panel(panel: int) -> bool:
	if not PANEL_NAMES.has(panel):
		return false
	if panel == active_panel:
		return true
	_history.append(active_panel)
	active_panel = panel
	return true


## Bir önceki panele döner.
## Dönen: true = dönüldü, false = geçmiş boş.
func go_back() -> bool:
	if _history.is_empty():
		return false
	active_panel = _history.pop_back()
	return true


# ============================================================
# SUNUM
# ============================================================

## Tüm panellerin sekme listesini üretir.
## Dönen: her biri {panel, name, label, active} dizi.
func build_tabs() -> Array:
	var tabs: Array = []
	for panel in PANEL_NAMES:
		tabs.append({
			"panel": panel,
			"name": PANEL_NAMES[panel],
			"label": PANEL_LABELS[panel],
			"active": panel == active_panel,
		})
	return tabs


## Aktif panelin adı.
func active_panel_name() -> String:
	return PANEL_NAMES.get(active_panel, "?")


## Aktif panelin etiketi.
func active_panel_label() -> String:
	return PANEL_LABELS.get(active_panel, "?")


# ============================================================
# SORGULAMA
# ============================================================

## Geri navigasyon mümkün mü?
func can_go_back() -> bool:
	return not _history.is_empty()


## Toplam alt-panel sayısı.
func panel_count() -> int:
	return PANEL_NAMES.size()
