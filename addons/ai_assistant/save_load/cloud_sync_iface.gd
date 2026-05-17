@tool
class_name AISaveCloudSyncInterface
extends RefCounted

## CloudSyncInterface — bulut senkr. arayüzü (Madde 09 / cloud_stubs).
##
## Oyuncular kaydını cihazlar arası taşımak ister: telefonda
## başla, tablette devam et. Bu bulut senkronizasyonu gerektirir —
## Google Play Games, Steam Cloud, iCloud...
##
## Her platform farklı API'ye sahip ama MANTIK aynı: yükle, indir,
## çakışma çöz. Bu sınıf o ortak sözleşmeyi (interface) tanımlar —
## platform stub'ları bunu uygular.
##
## Phase 1'de gerçek bulut yok — stub'lar dürüstçe "henüz bağlı
## değil" der. Bu arayüz Phase 2+'da gerçek implementasyonun
## takılacağı yer.
##
## "Mock yasak": stub sahte "senkronize edildi" demez — açıkça
## NOT_AVAILABLE döner.

## Senkronizasyon işlem sonucu.
enum SyncStatus { SUCCESS, NOT_AVAILABLE, CONFLICT, NETWORK_ERROR, AUTH_ERROR }

const STATUS_NAMES: Dictionary = {
	SyncStatus.SUCCESS: "success",
	SyncStatus.NOT_AVAILABLE: "not_available",
	SyncStatus.CONFLICT: "conflict",
	SyncStatus.NETWORK_ERROR: "network_error",
	SyncStatus.AUTH_ERROR: "auth_error",
}


## Bir senkronizasyon sonucu.
class SyncResult extends RefCounted:
	var status: int = AISaveCloudSyncInterface.SyncStatus.NOT_AVAILABLE
	var provider: String = ""
	var reason: String = ""
	var payload: Dictionary = {}     ## İndirme sonucunda gelen veri

	func is_success() -> bool:
		return status == AISaveCloudSyncInterface.SyncStatus.SUCCESS

	func has_conflict() -> bool:
		return status == AISaveCloudSyncInterface.SyncStatus.CONFLICT

	func status_name() -> String:
		return AISaveCloudSyncInterface.STATUS_NAMES.get(status, "?")

	func to_dict() -> Dictionary:
		return {
			"status": status_name(),
			"provider": provider,
			"reason": reason,
		}


# ============================================================
# ARAYÜZ SÖZLEŞMESİ — alt sınıflar uygular
# ============================================================

## Bulut sağlayıcının adı. Alt sınıf override eder.
func provider_name() -> String:
	return "base"


## Bulut senkronizasyonu kullanılabilir mi (bağlı + giriş yapılmış)?
## Alt sınıf override eder. Temel: kullanılamaz.
func is_available() -> bool:
	return false


## Bir kaydı buluta yükler.
## save_data: yüklenecek kayıt. slot_id: hangi slot.
## Alt sınıf override eder.
func upload(_save_data: Dictionary, _slot_id: String) -> SyncResult:
	return _not_available_result()


## Buluttan bir kaydı indirir.
## slot_id: hangi slot. Alt sınıf override eder.
func download(_slot_id: String) -> SyncResult:
	return _not_available_result()


## Bulut tarafındaki kaydın metadata'sını sorgular (içeriği indirmeden).
## Çakışma tespiti için kullanılır. Alt sınıf override eder.
func fetch_metadata(_slot_id: String) -> Dictionary:
	return {"available": false}


# ============================================================
# ORTAK YARDIMCILAR
# ============================================================

## "Kullanılamaz" sonucu üretir — stub'lar ve hata durumları için.
func _not_available_result() -> SyncResult:
	var result := SyncResult.new()
	result.status = SyncStatus.NOT_AVAILABLE
	result.provider = provider_name()
	result.reason = "Bulut senkronizasyonu şu an kullanılamıyor"
	return result


## Başarılı bir sonuç üretir — alt sınıflar kullanır.
func _success_result(payload: Dictionary = {}) -> SyncResult:
	var result := SyncResult.new()
	result.status = SyncStatus.SUCCESS
	result.provider = provider_name()
	result.reason = "İşlem başarılı"
	result.payload = payload
	return result
