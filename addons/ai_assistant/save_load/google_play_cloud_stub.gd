@tool
class_name AISaveGooglePlayCloudStub
extends AISaveCloudSyncInterface

## GooglePlayCloudStub — Google Play Games bulut stub (Madde 09).
##
## Android'in resmi bulut kayıt çözümü: Google Play Games Saved
## Games. Phase 1'de STUB — gerçek entegrasyon Android eklentisi
## ister (Phase 2+).
##
## Bu stub arayüzü uygular ama dürüstçe "kullanılamıyor" der.
## Phase 2+'da gerçek Google Play Games API'si buraya takılır.
## Sandbox'ta ağ ve native eklenti yok — stub doğru davranıştır.
##
## "Mock yasak": sahte başarı yok — her çağrı NOT_AVAILABLE.


## Phase 2+'da gerçek bağlantı kurulduğunda true olacak.
var _connected: bool = false


func provider_name() -> String:
	return "google_play_games"


func is_available() -> bool:
	# Phase 1 — gerçek entegrasyon yok
	return _connected


func upload(save_data: Dictionary, slot_id: String) -> SyncResult:
	if not _connected:
		return _not_available_result()
	# Phase 2+ — gerçek Play Games upload buraya
	return _not_available_result()


func download(slot_id: String) -> SyncResult:
	if not _connected:
		return _not_available_result()
	# Phase 2+ — gerçek Play Games download buraya
	return _not_available_result()


## Phase 2+ entegrasyonu — gerçek bağlantı kurulduğunda çağrılır.
## Şimdilik dürüstçe başarısız.
func attempt_connect() -> bool:
	# Phase 1 — Android Play Games eklentisi yok
	return false
