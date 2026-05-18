@tool
class_name AIProjectScanner
extends RefCounted

## ProjectScanner — asistana proje dosya/klasör görünürlüğü verir.
##
## SORUN (telefon testi): asistan "proje klasörünüze doğrudan erişimim
## yok" diyordu — motoru/dosyaları göremediği için ne var olduğunu
## bilmiyor, proje-bilinçli kod üretemiyordu.
##
## ÇÖZÜM: SALT-OKUNUR, güvenli bir tarayıcı. res:// (proje) ve
## user:// ağacını listeler, küçük dosyaları okur. Yazma YOK — yıkıcı
## işlem yüzeyi açılmaz. Yol güvenliği: yalnız res:// / user://,
## ".." reddedilir (traversal imkânsız).
##
## Mock policy: tarama gerçek diskten yapılır — sahte ağaç üretilmez;
## erişilemeyen kök boş liste döner (dürüst).

## Bağlam şişmesini önleyen üst sınırlar.
const MAX_ENTRIES: int = 300
const MAX_DEPTH: int = 8
const MAX_FILE_CHARS: int = 20000

## Gürültü/çöp dizinler — listelenmez.
const SKIP_DIRS: Array = [".godot", ".git", ".import"]

## İçeriği bağlama gömülecek anahtar dosyalar (varsa).
const KEY_FILES: Array = ["res://project.godot"]


## Proje ağacını listeler (salt-okunur). Dönen: sıralı yol dizisi;
## dizinler "/" ile biter. Erişilemezse boş (dürüst).
## BFS: kök seviye önce listelenir — böylece project.godot gibi önemli
## kök dosyalar derin addon ağacına takılıp üst sınıra kurban gitmez.
func scan_tree(root: String = "res://", max_entries: int = MAX_ENTRIES) -> Array:
	var out: Array = []
	if not _is_safe_root(root):
		return out
	var queue: Array = [{"path": root, "depth": 0}]
	while not queue.is_empty() and out.size() < max_entries:
		var cur: Dictionary = queue.pop_front()
		var dir_path: String = str(cur["path"])
		var depth: int = int(cur["depth"])
		if depth > MAX_DEPTH:
			continue
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name: String = d.get_next()
		while name != "":
			if name == "." or name == "..":
				name = d.get_next()
				continue
			var child: String = dir_path.path_join(name)
			if d.current_is_dir():
				if not SKIP_DIRS.has(name) and not name.begins_with("."):
					if out.size() < max_entries:
						out.append(child + "/")
					queue.append({"path": child, "depth": depth + 1})
			elif out.size() < max_entries:
				out.append(child)
			name = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


## Tek bir dosyayı güvenle okur (salt-okunur). Yalnız res:// / user://,
## ".." reddedilir. Büyük dosya kırpılır. Dönen: {ok, content, reason}.
func read_file(path: String) -> Dictionary:
	var p: String = path.strip_edges()
	if not _is_safe_path(p):
		return {"ok": false, "content": "", "reason": "Güvensiz yol reddedildi"}
	if not FileAccess.file_exists(p):
		return {"ok": false, "content": "", "reason": "Dosya yok"}
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "content": "", "reason": "Açılamadı"}
	var text: String = f.get_as_text()
	f.close()
	var truncated: bool = text.length() > MAX_FILE_CHARS
	if truncated:
		text = text.left(MAX_FILE_CHARS) + "\n…(kırpıldı)"
	return {"ok": true, "content": text, "reason": "", "truncated": truncated}


## LLM'e gömülecek proje özeti: ağaç + anahtar dosya içerikleri.
## Boş/erişilemez proje → dürüst "görünür dosya yok" notu.
func project_summary(max_entries: int = MAX_ENTRIES) -> String:
	var tree: Array = scan_tree("res://", max_entries)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("PROJE DOSYALARI (res://, salt-okunur görünüm):")
	if tree.is_empty():
		lines.append("(görünür dosya yok)")
	else:
		for entry in tree:
			lines.append("  " + str(entry))
	for key in KEY_FILES:
		var r: Dictionary = read_file(str(key))
		if bool(r.get("ok", false)):
			lines.append("")
			lines.append("--- " + str(key) + " ---")
			lines.append(str(r["content"]))
	return "\n".join(lines)


# ============================================================
# YOL GÜVENLİĞİ — traversal / dış erişim imkânsız
# ============================================================

func _is_safe_root(path: String) -> bool:
	return _is_safe_path(path)


func _is_safe_path(path: String) -> bool:
	if path.is_empty() or path.contains(".."):
		return false
	return path.begins_with("res://") or path.begins_with("user://")
