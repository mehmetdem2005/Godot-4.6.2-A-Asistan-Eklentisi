@tool
class_name AILifecycleBackButton
extends RefCounted

## BackButtonHandler — geri tuşu yöneticisi (Madde 10 / device_control).
##
## Android'in fiziksel/jest geri tuşu özeldir: basıldığında VARSAYILAN
## davranış uygulamadan çıkmaktır. Oyun bunu yönetmezse oyuncu
## yanlışlıkla oyundan çıkar — kayıt kaybı, sinir.
##
## Doğru davranış BAĞLAMA bağlıdır:
##   - alt menüdeyken      -> üst menüye dön
##   - oyun ekranındayken  -> duraklat menüsü aç
##   - ana menüdeyken      -> çıkış onayı sor ("Emin misin?")
##   - duraklat menüsünde  -> oyuna geri dön
##
## Bu sınıf bir geri tuşu olayında ne yapılacağını belirler — bir
## navigasyon yığını (stack) tutar, geri tuşu yığını geri sarar.
##
## Mock policy: karar gerçek navigasyon yığınından.

## Geri tuşu eylemi.
enum BackAction { POP_SCREEN, OPEN_PAUSE, CONFIRM_EXIT, RESUME_GAME, BLOCKED }

const ACTION_NAMES: Dictionary = {
	BackAction.POP_SCREEN: "pop_screen",
	BackAction.OPEN_PAUSE: "open_pause",
	BackAction.CONFIRM_EXIT: "confirm_exit",
	BackAction.RESUME_GAME: "resume_game",
	BackAction.BLOCKED: "blocked",
}

## Bilinen ekran tipleri.
const SCREEN_MAIN_MENU: String = "main_menu"
const SCREEN_GAMEPLAY: String = "gameplay"
const SCREEN_PAUSE_MENU: String = "pause_menu"
const SCREEN_SUBMENU: String = "submenu"


## Navigasyon yığını — en üstteki mevcut ekran.
var _nav_stack: Array = []

## Geri tuşu geçici olarak engelli mi (örn. cutscene sırasında).
var _blocked: bool = false


# ============================================================
# NAVİGASYON YIĞINI
# ============================================================

## Yığına bir ekran ekler (yeni ekrana geçince).
func push_screen(screen: String) -> void:
	if not screen.is_empty():
		_nav_stack.append(screen)


## Yığının en üstündeki ekranı döndürür. Boşsa boş string.
func current_screen() -> String:
	if _nav_stack.is_empty():
		return ""
	return str(_nav_stack[_nav_stack.size() - 1])


## Yığındaki ekran sayısı.
func stack_depth() -> int:
	return _nav_stack.size()


# ============================================================
# GERİ TUŞU İŞLEME
# ============================================================

## Geri tuşu olayını işler ve yapılacak eylemi belirler.
## Dönen: {action: String, new_screen: String, reason: String}
func handle_back() -> Dictionary:
	# Geri tuşu engelliyse — hiçbir şey yapma
	if _blocked:
		return {
			"action": ACTION_NAMES[BackAction.BLOCKED],
			"new_screen": current_screen(),
			"reason": "Geri tuşu şu an engelli (cutscene vb.)",
		}

	var screen: String = current_screen()

	match screen:
		SCREEN_SUBMENU:
			# Alt menü — bir üst ekrana dön
			_nav_stack.pop_back()
			return {
				"action": ACTION_NAMES[BackAction.POP_SCREEN],
				"new_screen": current_screen(),
				"reason": "Alt menüden üst ekrana dönüldü",
			}
		SCREEN_GAMEPLAY:
			# Oyun ekranı — duraklat menüsü aç
			_nav_stack.append(SCREEN_PAUSE_MENU)
			return {
				"action": ACTION_NAMES[BackAction.OPEN_PAUSE],
				"new_screen": SCREEN_PAUSE_MENU,
				"reason": "Oyun duraklatıldı",
			}
		SCREEN_PAUSE_MENU:
			# Duraklat menüsü — oyuna dön
			_nav_stack.pop_back()
			return {
				"action": ACTION_NAMES[BackAction.RESUME_GAME],
				"new_screen": current_screen(),
				"reason": "Oyuna geri dönüldü",
			}
		SCREEN_MAIN_MENU:
			# Ana menü — çıkış onayı
			return {
				"action": ACTION_NAMES[BackAction.CONFIRM_EXIT],
				"new_screen": SCREEN_MAIN_MENU,
				"reason": "Çıkış onayı isteniyor",
			}
		_:
			# Bilinmeyen/boş — güvenli: çıkış onayı
			return {
				"action": ACTION_NAMES[BackAction.CONFIRM_EXIT],
				"new_screen": screen,
				"reason": "Bilinmeyen ekran — çıkış onayı",
			}


# ============================================================
# ENGELLEME
# ============================================================

## Geri tuşunu geçici engeller — cutscene, yükleme ekranı vb.
func block() -> void:
	_blocked = true


## Geri tuşu engelini kaldırır.
func unblock() -> void:
	_blocked = false


## Geri tuşu şu an engelli mi?
func is_blocked() -> bool:
	return _blocked
