@tool
class_name AILifecycleNotificationStub
extends RefCounted

## NotificationStub — native bildirim stub (Madde 10 / notifications).
##
## Phase 2+ için yer tutucu. Gerçek Android sistem bildirimleri —
## oyun KAPALIYKEN bile çalışan, durum çubuğunda görünen bildirimler
## — bir Android native eklentisi ister.
##
## Phase 1'de bu yok. Phase 1 çözümü foreground_overlay (oyun
## açıkken oyun içi banner). Bu stub, Phase 2+'da gerçek native
## bildirim eklentisinin takılacağı arayüzü tanımlar.
##
## "Mock yasak": sahte "bildirim gönderildi" demez — açıkça
## NOT_AVAILABLE der ve foreground_overlay'e yönlendirir.
##
## Mock policy: stub her zaman kullanılamaz; gerçek native Phase 2+.

## Native bildirim sonucu.
enum NativeStatus { SENT, NOT_AVAILABLE, PERMISSION_DENIED }

const STATUS_NAMES: Dictionary = {
	NativeStatus.SENT: "sent",
	NativeStatus.NOT_AVAILABLE: "not_available",
	NativeStatus.PERMISSION_DENIED: "permission_denied",
}


## Native bildirim eklentisi bağlı mı — Phase 2+'da true olur.
var _native_available: bool = false


# ============================================================
# NATIVE BİLDİRİM
# ============================================================

## Native bildirim sistemi kullanılabilir mi? Phase 1 — hayır.
func is_available() -> bool:
	return _native_available


## Bir native sistem bildirimi gönderir.
## title/body: bildirim içeriği. channel_id: kanal.
## Dönen: {status: String, used_fallback: bool, reason: String}
func send_native(
	_title: String, _body: String, _channel_id: String
) -> Dictionary:
	# Phase 1 — native eklenti yok
	if not _native_available:
		return {
			"status": STATUS_NAMES[NativeStatus.NOT_AVAILABLE],
			"used_fallback": true,
			"reason": "Native bildirim Phase 2+ — foreground overlay "
				+ "kullanılmalı",
		}
	# Phase 2+ — gerçek native bildirim buraya
	return {
		"status": STATUS_NAMES[NativeStatus.NOT_AVAILABLE],
		"used_fallback": true,
		"reason": "Native bildirim henüz uygulanmadı",
	}


## Native bildirimleri zamanlayabilir mi (gelecekte gösterim)?
## Phase 1 — hayır, foreground overlay sadece oyun açıkken çalışır.
func can_schedule_offline() -> bool:
	return _native_available


# ============================================================
# PHASE 2+ ENTEGRASYON
# ============================================================

## Phase 2+ — native eklenti bağlanma denemesi.
func attempt_native_connect() -> bool:
	# Phase 1 — Android native bildirim eklentisi yok
	return false


## Bir bildirim için doğru yolu önerir.
## Phase 1: foreground overlay; Phase 2+: native.
## Dönen: "foreground_overlay" | "native"
func recommended_path() -> String:
	return "native" if _native_available else "foreground_overlay"
