@tool
class_name AIResourceQuota
extends RefCounted

## ResourceQuota — sandbox kaynak limitleri (Layer 4).
##
## Sandbox sınırsız yazamamalı. Kontrolden çıkmış bir döngü veya hatalı
## plan diski doldurmasın. Bu sınıf üç limit uygular:
##   1. Toplam yazılan bayt — sandbox ömrü boyunca kümülatif tavan
##   2. Toplam dosya sayısı — kaç dosya oluşturulabilir
##   3. Tek dosya max boyutu — bir dosya ne kadar büyük olabilir
##
## Executor her yazma ÖNCESİ check_write_allowed() çağırır. Limit aşılırsa
## işlem reddedilir — mock policy: sahte başarı yok, açık red.

## Varsayılan limitler — mobil-dostu, makul tavanlar.
const DEFAULT_MAX_TOTAL_BYTES: int = 50 * 1024 * 1024   # 50 MB toplam
const DEFAULT_MAX_FILE_COUNT: int = 2000                 # 2000 dosya
const DEFAULT_MAX_SINGLE_FILE_BYTES: int = 5 * 1024 * 1024  # 5 MB tek dosya

## Aktif limitler — yapılandırılabilir.
var max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES
var max_file_count: int = DEFAULT_MAX_FILE_COUNT
var max_single_file_bytes: int = DEFAULT_MAX_SINGLE_FILE_BYTES

## Kullanım sayaçları.
var _used_bytes: int = 0
var _file_count: int = 0


## Mevcut kullanımı sıfırlar (yeni oturum / plan başında).
func reset() -> void:
	_used_bytes = 0
	_file_count = 0


## Bir yazma işlemine kota açısından izin var mı kontrol eder.
## content_size: yazılacak içeriğin bayt boyutu.
## is_new_file: bu yeni bir dosya mı (dosya sayısı limiti için).
## old_size: üzerine yazılıyorsa eski boyut (net değişim hesabı için).
## Dönen: {allowed: bool, reason: String}
func check_write_allowed(
	content_size: int, is_new_file: bool, old_size: int = 0
) -> Dictionary:
	# 1. Tek dosya boyut limiti
	if content_size > max_single_file_bytes:
		return _deny(
			"Tek dosya limiti aşıldı: %d > %d bayt"
			% [content_size, max_single_file_bytes]
		)

	# 2. Dosya sayısı limiti — sadece yeni dosyalar sayılır
	if is_new_file and _file_count >= max_file_count:
		return _deny(
			"Dosya sayısı limiti aşıldı: %d dosya (max %d)"
			% [_file_count, max_file_count]
		)

	# 3. Toplam bayt limiti — net değişim hesaplanır
	# (üzerine yazma: yeni boyut - eski boyut; yeni dosya: tam boyut)
	var net_delta: int = content_size
	if not is_new_file:
		net_delta = content_size - old_size
	# Negatif delta (dosya küçüldü) toplamı azaltır ama altına düşmez
	var projected: int = _used_bytes + net_delta
	if projected > max_total_bytes:
		return _deny(
			"Toplam disk kotası aşıldı: %d > %d bayt"
			% [projected, max_total_bytes]
		)

	return {"allowed": true, "reason": ""}


## Bir yazma işlemi BAŞARIYLA tamamlandıktan sonra çağrılır — sayaçları günceller.
func record_write(content_size: int, is_new_file: bool, old_size: int = 0) -> void:
	if is_new_file:
		_file_count += 1
		_used_bytes += content_size
	else:
		_used_bytes += (content_size - old_size)
	# Negatife düşmesin
	if _used_bytes < 0:
		_used_bytes = 0


## Bir dosya silindiğinde çağrılır — sayaçları azaltır.
func record_delete(file_size: int) -> void:
	_file_count = maxi(0, _file_count - 1)
	_used_bytes = maxi(0, _used_bytes - file_size)


## Kota kısa kontrolü (bool).
func can_write(content_size: int, is_new_file: bool, old_size: int = 0) -> bool:
	return check_write_allowed(content_size, is_new_file, old_size)["allowed"]


## Mevcut kullanım durumu.
func usage() -> Dictionary:
	return {
		"used_bytes": _used_bytes,
		"max_total_bytes": max_total_bytes,
		"file_count": _file_count,
		"max_file_count": max_file_count,
		"bytes_remaining": maxi(0, max_total_bytes - _used_bytes),
		"files_remaining": maxi(0, max_file_count - _file_count),
		"usage_ratio": (
			float(_used_bytes) / float(max_total_bytes)
			if max_total_bytes > 0 else 0.0
		),
	}


static func _deny(reason: String) -> Dictionary:
	return {"allowed": false, "reason": reason}
