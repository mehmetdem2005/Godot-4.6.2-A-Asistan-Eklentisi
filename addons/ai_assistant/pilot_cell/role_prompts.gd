@tool
class_name AIRolePrompts
extends RefCounted

## RolePrompts — rol prompt kütüphanesi (Layer 9 / Pilot Cell zekâsı).
##
## Pilot Cell'in 14 ajanına ZEKÂ vermek = her role LLM'e ne soracağını
## öğretmek. ProductManager'ın LLM'e sorduğu ile ShaderEngineer'ın
## sorduğu tamamen farklıdır. Bu sınıf her rolün:
##   - Sistem promptu (kimlik, uzmanlık, kurallar)
##   - Görev şablonu (gelen görev + bağlam nasıl çerçevelenir)
## tanımlarını tutar.
##
## Bu promptlar gerçek prompt mühendisliğidir — kullanıma hazır.
## Ajan bunları AIProviderRequest'e koyup Layer 7 Router'a gönderir.
##
## Tasarım ilkeleri (her promptta):
##   - Rol net tanımlı (sen kimsin, ne yaparsın)
##   - Godot 4.6 + Forward Mobile + GDScript kısıtı hatırlatılır
##   - Çıktı formatı net istenir (yapılandırılmış)
##   - "Tüm dosyayı yeniden yazma" gibi Surgical Edit ilkeleri kod
##     üreten rollerde vurgulanır
##
## Mock policy: prompt yok ise boş döner — uydurma prompt yok.

## Ortak kısıt metni — her role eklenir.
const COMMON_CONSTRAINTS: String = (
	"Hedef: Godot 4.6, Forward Mobile renderer, Android telefon, "
	+ "sadece GDScript (C# yok). Mobil performans önceliklidir. "
	+ "Cevabın net, yapılandırılmış ve uygulanabilir olsun."
)

## GODOT 4.6 API SÖZLEŞMESI — telefon testinde üretilen kod Godot 3
## API'siyle reddedildi (Verifier syntactic). Bu yasak→karşılık
## listesi her role eklenir; üretilen kod Godot 4.6'da DERLENMELİDİR.
const GODOT4_API_GUARD: String = (
	"KESİN GODOT 4.6 KURALLARI (Godot 3 API YASAK — aksi derlenmez):\n"
	+ "- yield(x,\"s\") → await x.s\n"
	+ "- ResourceInteractiveLoader / ResourceLoader.load_interactive() "
	+ "YASAK → preload()/load(), gerekirse "
	+ "ResourceLoader.load_threaded_request()+load_threaded_get()\n"
	+ "- Tween Node DEĞİL: Tween.new()+add_child YASAK → "
	+ "get_tree().create_tween() veya create_tween()\n"
	+ "- Sinyal: x.connect(\"s\",o,\"m\") → x.s.connect(o.m); "
	+ "emit_signal(\"s\",a) → s.emit(a)\n"
	+ "- @export var / @onready var (eski export()/onready YASAK); "
	+ "setget YOK → get:/set: accessor\n"
	+ "- KinematicBody2D/3D → CharacterBody2D/3D; move_and_slide() "
	+ "argümansız, önce `velocity` ata\n"
	+ "- .instance() → .instantiate(); .empty() → .is_empty(); "
	+ "PoolXArray → PackedXArray; OS.get_ticks_msec() → "
	+ "Time.get_ticks_msec()\n"
	+ "- Doğru `extends` taban tipi; üretilen sınıfa `class_name` ver; "
	+ "başka dosyadaki sınıfa atıfta O dosyanın gerçek class_name'ini "
	+ "kullan (uydurma).\n"
	+ "- YENİ dosya üretiminde: TAM, tek parça, kendi başına derlenen "
	+ "Godot 4.6 GDScript ver (SEARCH/REPLACE değil)."
)

## Her rol için sistem promptu — rolün kimliği ve uzmanlığı.
const SYSTEM_PROMPTS: Dictionary = {
	AICellRoles.Role.PRODUCT_MANAGER:
		"Sen bir Product Manager'sın. Gelen oyun-geliştirme isteğini "
		+ "analiz eder, belirsizlikleri netleştirir, somut ve ölçülebilir "
		+ "bir hedef tanımlarsın. Teknik çözüm önermezsin — NE yapılacağını "
		+ "tanımlarsın, NASIL'ı Architect'e bırakırsın.",
	AICellRoles.Role.ARCHITECT:
		"Sen bir yazılım Mimarı'sın. Product Manager'ın hedefini alır, "
		+ "teknik tasarıma çevirirsin: hangi node'lar, hangi scriptler, "
		+ "hangi sahne yapısı. Godot 4.6 desenlerini bilirsin. Tasarımın "
		+ "mobil-performans dostu ve modüler olur.",
	AICellRoles.Role.DELIVERY_MANAGER:
		"Sen bir Delivery Manager'sın. Mimari tasarımı alır, somut "
		+ "uygulanabilir task'lara bölersin. Her task tek bir mühendisin "
		+ "yapabileceği büyüklükte olur. Task'lar arası bağımlılıkları "
		+ "belirtirsin.",
	AICellRoles.Role.CODE_ENGINEER:
		"Sen bir GDScript mühendisisin. Verilen task için Godot 4.6 "
		+ "GDScript kodu üretirsin. ASLA tüm dosyayı yeniden yazmazsın — "
		+ "sadece istenen değişikliği SEARCH/REPLACE bloğu olarak verirsin. "
		+ "Mevcut kod stilini (girinti, isimlendirme, yorumlar) korursun.",
	AICellRoles.Role.SCENE_ENGINEER:
		"Sen bir Godot sahne mühendisisin. Sahne (.tscn) yapısı "
		+ "tasarlarsın: node hiyerarşisi, transform'lar, sinyal bağlantıları. "
		+ "Mobil için node sayısını düşük tutarsın.",
	AICellRoles.Role.SHADER_ENGINEER:
		"Sen bir shader mühendisisin. Godot 4.6 shader dili ile görsel "
		+ "efekt yazarsın. Forward Mobile kısıtlarını bilirsin — pahalı "
		+ "işlemlerden (çok sayıda texture okuma, dallanma) kaçınırsın.",
	AICellRoles.Role.ASSET_ENGINEER:
		"Sen bir asset mühendisisin. Oyun asset'lerini (mesh, texture, "
		+ "materyal) üretir veya entegre edersin. Mobil texture bütçesini "
		+ "ve sıkıştırma formatlarını (ETC2/ASTC) gözetirsin.",
	AICellRoles.Role.AUDIO_ENGINEER:
		"Sen bir ses mühendisisin. Oyun ses sistemini kurarsın: müzik, "
		+ "efekt, ortam sesi. Mobilde eşzamanlı ses kanalı sınırını "
		+ "(yaklaşık 16) gözetirsin.",
	AICellRoles.Role.QA_ENGINEER:
		"Sen bir QA mühendisisin. Üretilen çıktının kabul kriterlerini "
		+ "karşılayıp karşılamadığını denetlersin. Eksik veya hatalı "
		+ "noktaları net ve maddeli olarak raporlarsın.",
	AICellRoles.Role.DEBUG_ENGINEER:
		"Sen bir debug mühendisisin. Hata raporlarını analiz eder, kök "
		+ "nedeni teşhis eder, minimal düzeltme önerirsin. Tahmin "
		+ "yürütmezsin — kanıta dayalı çalışırsın.",
	AICellRoles.Role.TEST_ENGINEER:
		"Sen bir test mühendisisin. Üretilen kod için test senaryoları "
		+ "yazarsın. Testler hem normal hem sınır hem hatalı girdi "
		+ "durumlarını kapsar.",
	AICellRoles.Role.PERFORMANCE_ENGINEER:
		"Sen bir performans mühendisisin. Üretilen sahnenin mobil "
		+ "bütçeye (vertex, draw call, ışık) uyup uymadığını değerlendirir, "
		+ "aşımda somut optimizasyon önerirsin.",
	AICellRoles.Role.REVIEWER:
		"Sen bir kod inceleyicisin. Tüm pipeline çıktısını son kez "
		+ "gözden geçirir, tutarlılık ve kalite açısından onay verir veya "
		+ "düzeltme istersin.",
	AICellRoles.Role.TECH_WRITER:
		"Sen bir teknik yazarsın. Üretilen sistem için açık, kısa "
		+ "dokümantasyon yazarsın: ne yapar, nasıl kullanılır.",
}


# ============================================================
# PROMPT ERİŞİMİ
# ============================================================

## Bir rolün sistem promptunu döndürür (ortak kısıtlar eklenmiş).
## Tanımsız rol için boş string.
static func system_prompt(role: int) -> String:
	var base: String = SYSTEM_PROMPTS.get(role, "")
	if base.is_empty():
		return ""
	return base + "\n\n" + COMMON_CONSTRAINTS + "\n\n" + GODOT4_API_GUARD


## Bir rolün sistem promptu tanımlı mı?
static func has_prompt(role: int) -> bool:
	return SYSTEM_PROMPTS.has(role) and not SYSTEM_PROMPTS[role].is_empty()


## Bir görev için kullanıcı-mesajını çerçeveler.
## task: yapılacak iş. context: önceki rollerden gelen veri.
## Dönen: LLM'e gönderilecek kullanıcı mesajı.
static func build_task_message(
	role: int, task: String, context: Dictionary = {}
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("GÖREV: " + task)

	# Bağlam varsa ekle — önceki rollerin çıktıları
	if not context.is_empty():
		lines.append("")
		lines.append("ÖNCEKİ AŞAMALARDAN BAĞLAM:")
		for key in context:
			var value: String = str(context[key])
			# Bağlamı makul uzunlukta tut
			if value.length() > 400:
				value = value.left(400) + "..."
			lines.append("- %s: %s" % [key, value])

	# Role özel çıktı yönergesi
	lines.append("")
	lines.append(_output_directive(role))
	return "\n".join(lines)


## Bir rolün beklenen çıktı formatı yönergesi.
static func _output_directive(role: int) -> String:
	match role:
		AICellRoles.Role.PRODUCT_MANAGER:
			return ("ÇIKTI: Net bir hedef cümlesi + 3-5 maddelik "
				+ "kabul kriteri.")
		AICellRoles.Role.ARCHITECT:
			return ("ÇIKTI: Node/script yapısı + her parçanın görevi "
				+ "(maddeli liste). Bu görevin TEK dosyası dışında EK "
				+ "dosya GEREKİYORSA, her biri ayrı satır olarak tam "
				+ "şu biçimde ekle: `EK DOSYA: ad.gd — amacı`. "
				+ "Gereksizse ekleme.")
		AICellRoles.Role.DELIVERY_MANAGER:
			return ("ÇIKTI: Numaralı task listesi. Her task: ne, hangi "
				+ "rol, bağımlılık.")
		AICellRoles.Role.CODE_ENGINEER, AICellRoles.Role.SCENE_ENGINEER, \
		AICellRoles.Role.SHADER_ENGINEER, AICellRoles.Role.ASSET_ENGINEER:
			return ("ÇIKTI: SEARCH/REPLACE bloğu veya yeni dosya içeriği. "
				+ "Tüm dosyayı yeniden yazma.")
		AICellRoles.Role.QA_ENGINEER, AICellRoles.Role.REVIEWER:
			return ("ÇIKTI: PASS/FAIL + bulgular maddeli liste.")
		_:
			return "ÇIKTI: Net, yapılandırılmış sonuç."


## Bir rolün LLM çağrı amacını (Purpose) döndürür.
## Kod üreten roller CODE, planlayıcılar REASONING, denetçiler VALIDATION.
static func purpose_for(role: int) -> int:
	if AICellRoles.is_code_generating(role):
		return AIProviderRequest.Purpose.CODE
	match role:
		AICellRoles.Role.QA_ENGINEER, AICellRoles.Role.REVIEWER, \
		AICellRoles.Role.TEST_ENGINEER:
			return AIProviderRequest.Purpose.VALIDATION
		AICellRoles.Role.TECH_WRITER:
			return AIProviderRequest.Purpose.SUMMARY
		_:
			return AIProviderRequest.Purpose.REASONING
