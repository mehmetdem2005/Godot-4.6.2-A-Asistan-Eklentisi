@tool
class_name AISaveSerializerRegistry
extends RefCounted

## SerializerRegistry — serileştirici kayıt defteri (Madde 09).
##
## JSON sadece temel tipleri bilir: sayı, metin, dizi, sözlük, bool.
## Ama oyun özel tipler kullanır: Vector2, Color, custom Resource'lar.
## Bunlar doğrudan JSON'a yazılamaz — bir DÖNÜŞTÜRÜCÜ gerekir.
##
## Bu sınıf her özel tip için iki yönlü dönüştürücü kaydeder:
##   - encode: özel tip -> JSON-uyumlu Dictionary
##   - decode: Dictionary -> özel tip
##
## Kayıt sırasında encode, yükleme sırasında decode çağrılır.
## Tip adı dönüşmüş veride saklanır ki decode doğru dönüştürücüyü
## bulsun.
##
## Mock policy: dönüşüm gerçek kayıtlı dönüştürücülerden; bilinmeyen
## tip açıkça reddedilir.

## Bir tip dönüştürücüsü.
class TypeSerializer extends RefCounted:
	var type_name: String = ""
	var encoder: Callable           ## değer -> Dictionary
	var decoder: Callable           ## Dictionary -> değer

	func _init(
		p_name: String, p_encoder: Callable, p_decoder: Callable
	) -> void:
		type_name = p_name
		encoder = p_encoder
		decoder = p_decoder


## Kayıtlı dönüştürücüler — type_name -> TypeSerializer.
var _serializers: Dictionary = {}

## Dönüşmüş veride tip adının saklandığı anahtar.
const TYPE_KEY: String = "__type__"

## Dönüşmüş veride asıl verinin saklandığı anahtar.
const DATA_KEY: String = "__data__"


# ============================================================
# KAYIT
# ============================================================

## Bir özel tip için dönüştürücü kaydeder.
## type_name: tipin benzersiz adı.
## encoder: değeri Dictionary'ye çeviren Callable.
## decoder: Dictionary'yi değere çeviren Callable.
## Dönen: true = kayıt başarılı.
func register(
	type_name: String, encoder: Callable, decoder: Callable
) -> bool:
	if type_name.is_empty():
		push_warning("SerializerRegistry: boş tip adı")
		return false
	if not encoder.is_valid() or not decoder.is_valid():
		push_warning("SerializerRegistry: geçersiz dönüştürücü")
		return false
	_serializers[type_name] = TypeSerializer.new(
		type_name, encoder, decoder
	)
	return true


## Bir tip için dönüştürücü kayıtlı mı?
func has_serializer(type_name: String) -> bool:
	return _serializers.has(type_name)


# ============================================================
# DÖNÜŞTÜRME
# ============================================================

## Bir özel tip değerini JSON-uyumlu zarfa çevirir.
## type_name: değerin tipi. value: dönüştürülecek değer.
## Dönen: {ok: bool, encoded: Dictionary, reason: String}
func encode(type_name: String, value: Variant) -> Dictionary:
	if not _serializers.has(type_name):
		return {
			"ok": false, "encoded": {},
			"reason": "Kayıtlı dönüştürücü yok: " + type_name,
		}
	var serializer: TypeSerializer = _serializers[type_name]
	var data: Variant = serializer.encoder.call(value)
	# Encoder Dictionary döndürmeli
	if typeof(data) != TYPE_DICTIONARY:
		return {
			"ok": false, "encoded": {},
			"reason": "Dönüştürücü Dictionary döndürmedi",
		}
	# Tip-etiketli zarf
	return {
		"ok": true,
		"encoded": {TYPE_KEY: type_name, DATA_KEY: data},
		"reason": "Dönüştürüldü",
	}


## Tip-etiketli bir zarfı geri özel tipe çevirir.
## envelope: encode'un ürettiği zarf.
## Dönen: {ok: bool, value: Variant, reason: String}
func decode(envelope: Dictionary) -> Dictionary:
	# Zarf geçerli mi
	if not envelope.has(TYPE_KEY) or not envelope.has(DATA_KEY):
		return {
			"ok": false, "value": null,
			"reason": "Geçersiz zarf — tip etiketi yok",
		}
	var type_name: String = str(envelope[TYPE_KEY])
	if not _serializers.has(type_name):
		return {
			"ok": false, "value": null,
			"reason": "Kayıtlı dönüştürücü yok: " + type_name,
		}
	var serializer: TypeSerializer = _serializers[type_name]
	var value: Variant = serializer.decoder.call(envelope[DATA_KEY])
	return {"ok": true, "value": value, "reason": "Geri dönüştürüldü"}


# ============================================================
# SORGULAMA
# ============================================================

## Bir sözlük tip-etiketli zarf mı?
func is_envelope(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = data
	return dict.has(TYPE_KEY) and dict.has(DATA_KEY)


## Kayıtlı dönüştürücü sayısı.
func serializer_count() -> int:
	return _serializers.size()


## Kayıtlı tüm tip adları.
func registered_types() -> Array:
	return _serializers.keys()
