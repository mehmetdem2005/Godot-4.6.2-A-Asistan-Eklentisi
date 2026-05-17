@tool
class_name AISaveBackupRotator
extends RefCounted

## BackupRotator — yedek rotasyonu (Madde 09 / Save/Load / backup).
##
## Tek bir kayıt dosyası kırılgandır — bozulursa oyuncu her şeyi
## kaybeder. Çözüm: her kayıtta eski dosyayı yedeğe taşı, sınırlı
## sayıda yedek tut (dönüşümlü).
##
## Rotasyon mantığı: save.dat -> save.bak.1, save.bak.1 -> save.bak.2 ...
## En eski yedek (save.bak.N) silinir. Böylece son N kaydın geçmişi
## her zaman elde olur ama disk sınırsız büyümez.
##
## Bu sınıf rotasyon KARARINI üretir — hangi dosya nereye taşınacak.
## Gerçek dosya işlemleri atomic_writer'ın işi; bu saf mantık.
##
## Mock policy: rotasyon planı gerçek yedek sayımından.

## Varsayılan tutulacak yedek sayısı.
const DEFAULT_BACKUP_COUNT: int = 3

## Tutulacak maksimum yedek sayısı.
var backup_count: int = DEFAULT_BACKUP_COUNT


func _init(p_backup_count: int = DEFAULT_BACKUP_COUNT) -> void:
	backup_count = clampi(p_backup_count, 1, 20)


# ============================================================
# ROTASYON PLANI
# ============================================================

## Bir kayıt dosyası için yedek adı üretir.
## base_path: ana kayıt yolu (örn. "user://save.dat").
## index: yedek numarası (1 = en yeni yedek).
func backup_name(base_path: String, index: int) -> String:
	return "%s.bak.%d" % [base_path, index]


## Bir kayıt öncesi yapılacak rotasyon adımlarını planlar.
## base_path: ana kayıt yolu.
## existing_backups: şu an var olan yedek indeksleri (sıralı dizi).
## Dönen: sırayla uygulanacak taşıma/silme adımları.
##   Her adım: {action: "move"|"delete", from: String, to: String}
## ÖNEMLİ: adımlar VERİLEN SIRADA uygulanmalı — en eskiden başlar,
## yoksa dosyaların üzerine yazılır.
func plan_rotation(
	base_path: String, existing_backups: Array
) -> Array:
	var steps: Array = []

	# Mevcut yedekleri büyükten küçüğe işle — en eski önce kayar
	var indices: Array = existing_backups.duplicate()
	indices.sort()
	indices.reverse()  # büyük index (eski) önce

	for idx in indices:
		var index: int = int(idx)
		var next_index: int = index + 1
		if next_index > backup_count:
			# Sınırı aşan en eski yedek — silinir
			steps.append({
				"action": "delete",
				"from": backup_name(base_path, index),
				"to": "",
			})
		else:
			# Bir sonraki slota kaydır
			steps.append({
				"action": "move",
				"from": backup_name(base_path, index),
				"to": backup_name(base_path, next_index),
			})

	# Mevcut ana dosya -> bak.1
	steps.append({
		"action": "move",
		"from": base_path,
		"to": backup_name(base_path, 1),
	})

	return steps


# ============================================================
# SORGULAMA
# ============================================================

## Bir yedek indeksi geçerli mi (tutulan aralıkta)?
func is_valid_index(index: int) -> bool:
	return index >= 1 and index <= backup_count


## Tüm geçerli yedek adlarını döndürür.
func all_backup_names(base_path: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for i in range(1, backup_count + 1):
		names.append(backup_name(base_path, i))
	return names


## En yeni yedeğin adı.
func newest_backup(base_path: String) -> String:
	return backup_name(base_path, 1)


## En eski (tutulan) yedeğin adı.
func oldest_backup(base_path: String) -> String:
	return backup_name(base_path, backup_count)
