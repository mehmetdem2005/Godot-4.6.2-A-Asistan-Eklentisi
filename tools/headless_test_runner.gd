@tool
extends SceneTree

## Headless test koşturucu — GUI'siz ortam için.
##
## GUI panel (test_panel.gd) bir Window'dur, headless açılamaz.
## Bu araç aynı çekirdeği — AIContractSelfTest.run_all() — doğrudan
## çağırır, raporu stdout'a basar, başarısızlıkta çıkış kodu 1 verir.
##
## Çalıştırma:
##   godot --headless --path . --script res://tools/headless_test_runner.gd

const SelfTest := preload("res://addons/ai_assistant/contracts/_self_test.gd")


func _initialize() -> void:
	print("=== HEADLESS TEST KOŞUMU BAŞLADI ===")
	var out: Dictionary = SelfTest.run_all()
	var passed: int = int(out.get("passed", 0))
	var failed: int = int(out.get("failed", 0))
	var total: int = passed + failed
	print(str(out.get("report", "")))
	print("=== TOPLAM: %d/%d geçti, %d başarısız ===" % [passed, total, failed])
	if failed == 0:
		print("SONUC: TUM_TESTLER_GECTI")
	else:
		print("SONUC: BASARISIZ_VAR")
	quit(0 if failed == 0 else 1)
