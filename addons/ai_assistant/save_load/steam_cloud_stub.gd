@tool
class_name AISaveSteamCloudStub
extends AISaveCloudSyncInterface

## SteamCloudStub — Steam Cloud bulut stub (Madde 09 / cloud_stubs).
##
## Steam'in bulut kayıt çözümü: Steam Cloud (Remote Storage). PC'ye
## çıkış yapılırsa kullanılır. Phase 1'de STUB — gerçek entegrasyon
## Steamworks SDK ister (Phase 2+).
##
## Proje hedefi Android-mobil olduğu için Steam düşük öncelikli; bu
## stub arayüz tamlığı için var. Phase 2+'da PC sürümü olursa gerçek
## Steamworks buraya takılır.
##
## "Mock yasak": sahte başarı yok — her çağrı NOT_AVAILABLE.


var _connected: bool = false


func provider_name() -> String:
	return "steam_cloud"


func is_available() -> bool:
	# Phase 1 — Steamworks SDK yok, proje mobil odaklı
	return _connected


func upload(save_data: Dictionary, slot_id: String) -> SyncResult:
	if not _connected:
		return _not_available_result()
	return _not_available_result()


func download(slot_id: String) -> SyncResult:
	if not _connected:
		return _not_available_result()
	return _not_available_result()


## Phase 2+ — Steamworks SDK entegrasyonu.
func attempt_connect() -> bool:
	# Phase 1 — Steam SDK yok
	return false
