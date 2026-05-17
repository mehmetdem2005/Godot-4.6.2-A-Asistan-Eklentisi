@tool
class_name AISaveICloudStub
extends AISaveCloudSyncInterface

## ICloudStub — Apple iCloud bulut stub (Madde 09 / cloud_stubs).
##
## Apple'ın bulut kayıt çözümü: iCloud Key-Value Storage / CloudKit.
## iOS sürümü için kullanılır. Phase 1'de STUB — gerçek entegrasyon
## iOS native eklentisi ister (Phase 2+).
##
## Proje hedefi öncelikle Android; iOS Phase 2+ olası bir genişleme.
## Bu stub arayüz tamlığı için var.
##
## "Mock yasak": sahte başarı yok — her çağrı NOT_AVAILABLE.


var _connected: bool = false


func provider_name() -> String:
	return "icloud"


func is_available() -> bool:
	# Phase 1 — iOS native eklenti yok
	return _connected


func upload(save_data: Dictionary, slot_id: String) -> SyncResult:
	if not _connected:
		return _not_available_result()
	return _not_available_result()


func download(slot_id: String) -> SyncResult:
	if not _connected:
		return _not_available_result()
	return _not_available_result()


## Phase 2+ — iOS CloudKit entegrasyonu.
func attempt_connect() -> bool:
	# Phase 1 — iOS eklentisi yok
	return false
