@tool
class_name AIContractTestPanel
extends Window

## Contract Test Paneli — editör içinde tek tıkla çalışan görsel test penceresi.
##
## Kullanım: "Testleri Çalıştır" düğmesine bas, sonuçlar listede görünür.
## Yeşil = geçti, kırmızı = başarısız. Sonuç alanı serbest kaydırılabilir.

var _result_label: RichTextLabel
var _run_button: Button
var _summary_label: Label


func _init() -> void:
	title = "AI Assistant — Contract Testleri"
	size = Vector2i(1100, 1300)
	min_size = Vector2i(480, 600)
	unresizable = false
	close_requested.connect(_on_close)
	_build_ui()


func _build_ui() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 20)
	root.add_theme_constant_override("margin_right", 20)
	root.add_theme_constant_override("margin_top", 20)
	root.add_theme_constant_override("margin_bottom", 20)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	root.add_child(vbox)

	var header := Label.new()
	header.text = "AI Assistant — Sistem Doğrulama (Phase 0 + 1)"
	header.add_theme_font_size_override("font_size", 24)
	vbox.add_child(header)

	var subtitle := Label.new()
	subtitle.text = "Düğmeye bas — contract'ları ve bellek sistemini kontrol eder."
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	_run_button = Button.new()
	_run_button.text = "▶  Testleri Çalıştır"
	_run_button.custom_minimum_size = Vector2(0, 64)
	_run_button.add_theme_font_size_override("font_size", 20)
	_run_button.pressed.connect(_on_run_pressed)
	vbox.add_child(_run_button)

	_summary_label = Label.new()
	_summary_label.text = "Henüz çalıştırılmadı."
	_summary_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_summary_label)

	vbox.add_child(HSeparator.new())

	# Sonuç listesi — serbest kaydırılabilir, ekranı doldurur
	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.scroll_active = true
	_result_label.scroll_following = false
	_result_label.selection_enabled = true
	_result_label.fit_content = false
	_result_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.custom_minimum_size = Vector2(0, 300)
	_result_label.add_theme_font_size_override("normal_font_size", 17)
	_result_label.add_theme_font_size_override("bold_font_size", 19)
	_result_label.text = "[color=#888888]Sonuçlar burada görünecek...[/color]"
	vbox.add_child(_result_label)


func _on_run_pressed() -> void:
	_run_button.disabled = true
	_run_button.text = "⏳  Çalışıyor..."
	_result_label.text = ""
	_summary_label.text = "Testler çalışıyor..."

	await get_tree().process_frame

	var output: Dictionary = _run_tests()
	_display_results(output)

	_run_button.disabled = false
	_run_button.text = "▶  Testleri Tekrar Çalıştır"


## Testleri çalıştırır. AIContractSelfTest sınıfını kullanır.
func _run_tests() -> Dictionary:
	var test_output: Dictionary = AIContractSelfTest.run_all()
	test_output["error"] = false
	return test_output


func _display_results(output: Dictionary) -> void:
	if output.get("error", false):
		_summary_label.text = "✗ HATA"
		_summary_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		_result_label.text = "[color=#EF4444]%s[/color]" % output.get("message", "Bilinmeyen hata")
		return

	var passed: int = output.get("passed", 0)
	var failed: int = output.get("failed", 0)
	var total: int = passed + failed

	if failed == 0:
		_summary_label.text = "✓ %d/%d test geçti" % [passed, total]
		_summary_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
	else:
		_summary_label.text = "✗ %d/%d geçti, %d başarısız" % [passed, total, failed]
		_summary_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))

	var report: String = output.get("report", "")
	var bb: PackedStringArray = PackedStringArray()
	for line in report.split("\n"):
		var l: String = line
		if l.contains("✓"):
			bb.append("[color=#22C55E]%s[/color]" % l)
		elif l.contains("✗"):
			bb.append("[color=#EF4444]%s[/color]" % l)
		elif l.begins_with("==="):
			bb.append("[b][color=#3B82F6]%s[/color][/b]" % l)
		elif l.begins_with("---"):
			bb.append("[b]%s[/b]" % l)
		else:
			bb.append(l)
	_result_label.text = "\n".join(bb)


func _on_close() -> void:
	queue_free()
