@tool
class_name AIWorkspaceState
extends RefCounted

## WorkspaceState — workspace UI durum modeli (Layer 11).
##
## ÖNEMLİ MİMARİ NOTU:
##   Godot UI'ı Control node'ları + sahne demek — gözle, telefonda
##   görülür, test panelinde doğrulanamaz. AMA UI'ın ALTINDAKİ MANTIK
##   (hangi sekme aktif, Kanban hangi kolonda kaç task, feed filtresi)
##   saf veri — test edilebilir.
##
##   Bu sınıf o mantık katmanı. Görsel Control node'ları bunu okur ve
##   çizer; bu sınıf hiçbir Control'e dokunmaz. Böylece UI mantığı
##   RefCounted olarak test edilir, görsel kısım sahnede doğrulanır.
##
## 9 sekme (master plan): Overview, Kanban, Live Feed, Iteration,
## Plan Tree, Cost, Verifier, Checkpoints, Settings.
## Bu sürüm çekirdek 3'ü tam modeller: Kanban, Live Feed, Iteration.
##
## Mock policy: durum gerçek sistem verisinden beslenir.

## 9 workspace sekmesi.
enum Tab {
	OVERVIEW,      ## Genel bakış — özet dashboard
	KANBAN,        ## Task panosu — kolonlar
	LIVE_FEED,     ## Canlı olay akışı
	ITERATION,     ## Iteration planlama
	PLAN_TREE,     ## Hiyerarşik plan ağacı
	COST,          ## Maliyet takibi
	VERIFIER,      ## Doğrulama sonuçları
	CHECKPOINTS,   ## HITL bekleyen kararlar
	SETTINGS,      ## Ayarlar
}

const TAB_NAMES: Dictionary = {
	Tab.OVERVIEW: "Genel Bakış",
	Tab.KANBAN: "Kanban",
	Tab.LIVE_FEED: "Canlı Akış",
	Tab.ITERATION: "Iteration",
	Tab.PLAN_TREE: "Plan Ağacı",
	Tab.COST: "Maliyet",
	Tab.VERIFIER: "Doğrulama",
	Tab.CHECKPOINTS: "Kontrol Noktaları",
	Tab.SETTINGS: "Ayarlar",
}

## Şu an aktif sekme.
var active_tab: int = Tab.OVERVIEW

## Sekme geçmişi — geri navigasyon için.
var _tab_history: Array = []


# ============================================================
# SEKME YÖNETİMİ
# ============================================================

## Bir sekmeye geçer. Geçerli sekme geçmişe eklenir.
func switch_tab(tab: int) -> bool:
	if not TAB_NAMES.has(tab):
		push_warning("WorkspaceState: geçersiz sekme %d" % tab)
		return false
	if tab == active_tab:
		return true  # zaten o sekmede
	_tab_history.append(active_tab)
	# Geçmiş çok uzamasın
	if _tab_history.size() > 20:
		_tab_history.pop_front()
	active_tab = tab
	return true


## Bir önceki sekmeye döner. Geçmiş boşsa değişmez.
func go_back() -> bool:
	if _tab_history.is_empty():
		return false
	active_tab = _tab_history.pop_back()
	return true


## Aktif sekmenin adı.
func active_tab_name() -> String:
	return TAB_NAMES.get(active_tab, "?")


## Tüm sekmelerin sıralı listesi — UI sekme çubuğu için.
func all_tabs() -> Array:
	var tabs: Array = []
	for tab in TAB_NAMES:
		tabs.append({"id": tab, "name": TAB_NAMES[tab]})
	return tabs


# ============================================================
# DPI / MOBİL UYUM
# ============================================================

## Ekran genişliğine göre UI ölçek faktörü hesaplar.
## Mobilde DPI-aware olmak şart — telefon ekranları çok çeşitli.
## screen_width: piksel. Dönen: 1.0-3.0 arası ölçek.
func compute_ui_scale(screen_width: int, screen_dpi: int) -> float:
	# Temel: DPI 160 referans (mdpi). Yüksek DPI'da ölçek artar.
	var dpi_scale: float = float(screen_dpi) / 160.0
	# Dar ekranlarda biraz küçült — sığsın
	var width_factor: float = 1.0
	if screen_width < 720:
		width_factor = 0.85
	elif screen_width > 1440:
		width_factor = 1.15
	var scale: float = dpi_scale * width_factor
	# Makul sınırlar. Alt sınır 0.75: dar ekranda gerçek küçültmeye
	# izin ver (alt sınır 1.0 olsaydı dar-ekran küçültmesi clamp ile
	# yutulurdu). Üst sınır 3.0: çok yüksek DPI'da dev UI olmasın.
	return clampf(scale, 0.75, 3.0)


## Sekme çubuğu dar ekrana sığar mı, yoksa kaydırma mı gerekir?
## tab_count sekme, her biri min_tab_width piksel.
func tabs_need_scroll(screen_width: int, min_tab_width: int = 90) -> bool:
	var total_needed: int = TAB_NAMES.size() * min_tab_width
	return total_needed > screen_width
