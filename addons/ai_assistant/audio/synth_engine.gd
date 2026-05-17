@tool
class_name AIAudioSynthEngine
extends RefCounted

## SynthEngine — sentez orkestratörü (Madde 08 / procedural_synth).
##
## Tek tek parçaları (oscillator, envelope, filter, noise) bir araya
## getirip GERÇEK BİR SES tamponu üreten motor. Sentez zinciri:
##
##   1. kaynak üret (oscillator VEYA noise)
##   2. frekans kayması uygula (slide — laser/coin için)
##   3. zarf uygula (envelope — sesi canlı yap)
##   4. filtre uygula (filter — sesi şekillendir)
##   5. normalize + fade (sample_buffer — temizle)
##
## sfxr_presets'ten gelen parametre sözlüğünü alıp çalıştırır.
## Sonuç: çalmaya hazır bir örnek tamponu.
##
## Bu sınıf saf DSP'dir — Godot gerektirmez, tam test edilebilir.
## Gerçek OGG'ye çevirme vorbis_encoder + Godot'un işi.
##
## Mock policy: ses gerçek sentez zincirinden; sahte tampon yok.

const SAMPLE_RATE: int = 44100


# ============================================================
# SENTEZ
# ============================================================

## Bir parametre sözlüğünden ses tamponu sentezler.
## params: sfxr_presets parametre sözlüğü.
## duration: ses süresi (saniye, parametrelerden hesaplanmazsa).
## Dönen: {ok: bool, buffer: PackedFloat32Array, reason: String}
func synthesize(
	params: Dictionary, duration: float = 0.0
) -> Dictionary:
	# Parametreler geçerli mi
	if params.is_empty():
		return {
			"ok": false, "buffer": PackedFloat32Array(),
			"reason": "Boş parametre — sentezlenecek bir şey yok",
		}

	# Süreyi belirle — verilmezse zarftan hesapla
	var attack: float = float(params.get("attack", 0.01))
	var decay: float = float(params.get("decay", 0.1))
	var release: float = float(params.get("release", 0.2))
	var total_duration: float = duration
	if total_duration <= 0.0:
		# Zarf evrelerinin toplamı + biraz sustain
		total_duration = attack + decay + 0.2 + release

	var sample_count: int = int(total_duration * SAMPLE_RATE)
	if sample_count <= 0:
		return {
			"ok": false, "buffer": PackedFloat32Array(),
			"reason": "Süre çok kısa",
		}

	# --- 1. Kaynak üret ---
	var waveform_str: String = str(params.get("waveform", "sine"))
	var raw: PackedFloat32Array
	if waveform_str == "noise":
		raw = _generate_noise(sample_count)
	else:
		raw = _generate_oscillator(params, sample_count, total_duration)

	# --- 2-3. Zarf uygula ---
	var envelope := AIAudioEnvelope.new(attack, decay,
		float(params.get("sustain", 0.7)), release)
	var hold_until: float = total_duration - release
	var enveloped: PackedFloat32Array = _apply_envelope(
		raw, envelope, hold_until
	)

	# --- 4. Filtre (isteğe bağlı) ---
	var output: PackedFloat32Array = enveloped
	if params.has("filter_cutoff"):
		var filter := AIAudioFilter.new(
			AIAudioFilter.FilterType.LOW_PASS,
			float(params["filter_cutoff"])
		)
		output = filter.process_buffer(output)

	# --- 5. Normalize ---
	output = AIAudioSampleBuffer.normalize(output)

	return {
		"ok": true,
		"buffer": output,
		"reason": "Sentezlendi (%d örnek, %.2fs)" % [
			output.size(), total_duration
		],
	}


# ============================================================
# KAYNAK ÜRETİMİ
# ============================================================

## Oscillator tabanlı kaynak — frekans kayması (slide) dahil.
func _generate_oscillator(
	params: Dictionary, sample_count: int, total_duration: float
) -> PackedFloat32Array:
	var base_freq: float = float(params.get("frequency", 440.0))
	var freq_slide: float = float(params.get("freq_slide", 0.0))
	var waveform: int = _waveform_from_string(
		str(params.get("waveform", "sine"))
	)

	var buffer: PackedFloat32Array = PackedFloat32Array()
	var time_step: float = 1.0 / float(SAMPLE_RATE)
	var phase: float = 0.0

	for i in range(sample_count):
		var t: float = float(i) * time_step
		# Frekans zamanla kayar (slide)
		var progress: float = t / maxf(total_duration, 0.001)
		var current_freq: float = base_freq + freq_slide * progress
		current_freq = maxf(current_freq, 1.0)
		# Faz birikimi
		phase += current_freq * time_step
		var osc := AIAudioOscillator.new(waveform, current_freq)
		buffer.append(osc.sample_at_phase(phase))

	return buffer


## Gürültü tabanlı kaynak.
func _generate_noise(sample_count: int) -> PackedFloat32Array:
	var noise := AIAudioNoise.new(AIAudioNoise.NoiseType.WHITE, 12345)
	return noise.generate_buffer(sample_count)


## Zarfı bir tampona uygular.
func _apply_envelope(
	buffer: PackedFloat32Array, envelope: AIAudioEnvelope,
	hold_until: float
) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	var time_step: float = 1.0 / float(SAMPLE_RATE)
	for i in range(buffer.size()):
		var t: float = float(i) * time_step
		var note_held: bool = t < hold_until
		var env: float = envelope.value_at(t, note_held, hold_until)
		result.append(buffer[i] * env)
	return result


## Dalga formu string'ini Oscillator enum'una çevirir.
func _waveform_from_string(name: String) -> int:
	match name:
		"square":
			return AIAudioOscillator.Waveform.SQUARE
		"saw":
			return AIAudioOscillator.Waveform.SAW
		"triangle":
			return AIAudioOscillator.Waveform.TRIANGLE
		_:
			return AIAudioOscillator.Waveform.SINE


# ============================================================
# SORGULAMA
# ============================================================

## Bir parametre sözlüğü sentezlenebilir mi?
func can_synthesize(params: Dictionary) -> bool:
	return not params.is_empty() and params.has("waveform")
