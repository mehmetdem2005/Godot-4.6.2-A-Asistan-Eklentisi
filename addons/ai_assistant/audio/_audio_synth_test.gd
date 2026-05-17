@tool
class_name AIAudioSynthTest
extends RefCounted

## Madde 08 — Audio Sentez Self-Test
##
## Sıkı testler: procedural_synth (oscillator, envelope, filter,
## noise, lfo, sample_buffer, sfxr_presets, synth_engine,
## vorbis_encoder), music_layering (intensity_manager,
## crossfade_engine, stem_player_pool, loop_point_handler).


static func run_all() -> Array:
	var results: Array = []

	# Oscillator
	results.append(_b("Synth: Osc", _test_osc_waveforms()))
	results.append(_b("Synth: Osc", _test_osc_phase_wrap()))
	results.append(_b("Synth: Osc", _test_osc_buffer()))

	# Envelope
	results.append(_b("Synth: Envelope", _test_env_adsr_phases()))
	results.append(_b("Synth: Envelope", _test_env_release()))

	# Filter
	results.append(_b("Synth: Filter", _test_filter_lowpass_dc()))
	results.append(_b("Synth: Filter", _test_filter_reset()))

	# Noise
	results.append(_b("Synth: Noise", _test_noise_deterministic()))
	results.append(_b("Synth: Noise", _test_noise_range()))

	# LFO
	results.append(_b("Synth: LFO", _test_lfo_range()))
	results.append(_b("Synth: LFO", _test_lfo_depth()))

	# SampleBuffer
	results.append(_b("Synth: Buffer", _test_buffer_mix()))
	results.append(_b("Synth: Buffer", _test_buffer_normalize()))
	results.append(_b("Synth: Buffer", _test_buffer_fade()))

	# SfxrPresets
	results.append(_b("Synth: Sfxr", _test_sfxr_presets()))
	results.append(_b("Synth: Sfxr", _test_sfxr_customize()))

	# SynthEngine
	results.append(_b("Synth: Engine", _test_synth_generate()))
	results.append(_b("Synth: Engine", _test_synth_empty()))

	# VorbisEncoder
	results.append(_b("Synth: Vorbis", _test_vorbis_pcm_roundtrip()))
	results.append(_b("Synth: Vorbis", _test_vorbis_empty()))

	# IntensityManager
	results.append(_b("Music: Intensity", _test_intensity_levels()))
	results.append(_b("Music: Intensity", _test_intensity_smooth()))

	# CrossfadeEngine
	results.append(_b("Music: Crossfade", _test_crossfade_endpoints()))
	results.append(_b("Music: Crossfade", _test_crossfade_equal_power()))

	# StemPlayerPool
	results.append(_b("Music: Stems", _test_stem_active_layers()))

	# LoopPointHandler
	results.append(_b("Music: Loop", _test_loop_jump()))
	results.append(_b("Music: Loop", _test_loop_disabled()))

	return results


static func _b(batch: String, result: Dictionary) -> Dictionary:
	result["batch"] = batch
	return result


static func _ok(n: String) -> Dictionary:
	return {"ok": true, "name": n, "reason": ""}


static func _fail(n: String, r: String) -> Dictionary:
	return {"ok": false, "name": n, "reason": r}


# ============================================================
# OSCILLATOR
# ============================================================

static func _test_osc_waveforms() -> Dictionary:
	var name := "Oscillator dalga formları"
	# Sine — faz 0.25'te tepe (+1)
	var sine := AIAudioOscillator.new(AIAudioOscillator.Waveform.SINE)
	if absf(sine.sample_at_phase(0.25) - 1.0) > 0.001:
		return _fail(name, "sine faz 0.25'te +1 olmalı")
	# Square — ilk yarı +1
	var square := AIAudioOscillator.new(AIAudioOscillator.Waveform.SQUARE)
	if square.sample_at_phase(0.2) != 1.0:
		return _fail(name, "square ilk yarıda +1 olmalı")
	# Saw — 0'da -1
	var saw := AIAudioOscillator.new(AIAudioOscillator.Waveform.SAW)
	if absf(saw.sample_at_phase(0.0) - (-1.0)) > 0.001:
		return _fail(name, "saw 0'da -1 olmalı")
	return _ok(name)


static func _test_osc_phase_wrap() -> Dictionary:
	var name := "Oscillator faz sarması"
	var osc := AIAudioOscillator.new(AIAudioOscillator.Waveform.SINE)
	# Faz 1.25 ile 0.25 aynı dalga noktası olmalı
	var a: float = osc.sample_at_phase(1.25)
	var b: float = osc.sample_at_phase(0.25)
	if absf(a - b) > 0.001:
		return _fail(name, "faz 1.25 ve 0.25 aynı olmalı")
	return _ok(name)


static func _test_osc_buffer() -> Dictionary:
	var name := "Oscillator tampon üretimi"
	var osc := AIAudioOscillator.new(AIAudioOscillator.Waveform.SINE, 440.0)
	var buffer: PackedFloat32Array = osc.generate_buffer(100)
	if buffer.size() != 100:
		return _fail(name, "tampon istenen boyutta olmalı")
	# Tüm örnekler -1..1 aralığında
	for sample in buffer:
		if sample < -1.001 or sample > 1.001:
			return _fail(name, "örnekler -1..1 aralığında olmalı")
	return _ok(name)


# ============================================================
# ENVELOPE
# ============================================================

static func _test_env_adsr_phases() -> Dictionary:
	var name := "Envelope ADSR evreleri"
	var env := AIAudioEnvelope.new(0.1, 0.1, 0.7, 0.2)
	# Attack başı — 0
	if absf(env.value_at(0.0, true)) > 0.001:
		return _fail(name, "attack başında 0 olmalı")
	# Attack tepesi — 1
	if absf(env.value_at(0.1, true) - 1.0) > 0.001:
		return _fail(name, "attack tepesinde 1 olmalı")
	# Sustain — sabit 0.7
	if absf(env.value_at(0.5, true) - 0.7) > 0.001:
		return _fail(name, "sustain'de 0.7 olmalı")
	return _ok(name)


static func _test_env_release() -> Dictionary:
	var name := "Envelope release evresi"
	var env := AIAudioEnvelope.new(0.1, 0.1, 0.7, 0.2)
	# Release tamamlandıktan sonra — 0
	# release_start=0.5, release=0.2 -> 0.7'de tamamen söner
	if absf(env.value_at(0.7, false, 0.5)) > 0.001:
		return _fail(name, "release sonunda 0 olmalı")
	# Release ortası — 0 ile sustain arası
	var mid: float = env.value_at(0.6, false, 0.5)
	if mid <= 0.0 or mid >= 0.7:
		return _fail(name, "release ortası ara değer olmalı")
	return _ok(name)


# ============================================================
# FILTER
# ============================================================

static func _test_filter_lowpass_dc() -> Dictionary:
	var name := "Filter low-pass DC geçişi"
	var filter := AIAudioFilter.new(
		AIAudioFilter.FilterType.LOW_PASS, 1000.0
	)
	# Sabit 1.0 girdi — low-pass eninde sonunda 1.0'a yakınsamalı
	var output: float = 0.0
	for i in range(2000):
		output = filter.process(1.0)
	if absf(output - 1.0) > 0.05:
		return _fail(name, "low-pass DC sinyali geçirmeli")
	return _ok(name)


static func _test_filter_reset() -> Dictionary:
	var name := "Filter durum sıfırlama"
	var filter := AIAudioFilter.new()
	filter.process(0.8)
	filter.process(0.9)
	filter.reset()
	# Reset sonrası ilk çıkış sıfır durumdan başlamalı
	var after: float = filter.process(0.0)
	if absf(after) > 0.001:
		return _fail(name, "reset sonrası durum temizlenmeli")
	return _ok(name)


# ============================================================
# NOISE
# ============================================================

static func _test_noise_deterministic() -> Dictionary:
	var name := "Noise deterministik üretim"
	var noise_a := AIAudioNoise.new(AIAudioNoise.NoiseType.WHITE, 42)
	var noise_b := AIAudioNoise.new(AIAudioNoise.NoiseType.WHITE, 42)
	# Aynı tohum — aynı dizi
	for i in range(20):
		if absf(noise_a.next_sample() - noise_b.next_sample()) > 0.0001:
			return _fail(name, "aynı tohum aynı diziyi vermeli")
	return _ok(name)


static func _test_noise_range() -> Dictionary:
	var name := "Noise değer aralığı"
	var noise := AIAudioNoise.new(AIAudioNoise.NoiseType.WHITE, 7)
	for i in range(100):
		var sample: float = noise.next_sample()
		if sample < -1.001 or sample > 1.001:
			return _fail(name, "gürültü -1..1 aralığında olmalı")
	return _ok(name)


# ============================================================
# LFO
# ============================================================

static func _test_lfo_range() -> Dictionary:
	var name := "LFO değer aralıkları"
	var lfo := AIAudioLFO.new(5.0, 1.0)
	for i in range(20):
		var t: float = float(i) / 10.0
		# Raw -1..1
		var raw: float = lfo.raw_value(t)
		if raw < -1.001 or raw > 1.001:
			return _fail(name, "raw -1..1 aralığında olmalı")
		# Unipolar 0..1
		var uni: float = lfo.unipolar_value(t)
		if uni < -0.001 or uni > 1.001:
			return _fail(name, "unipolar 0..1 aralığında olmalı")
	return _ok(name)


static func _test_lfo_depth() -> Dictionary:
	var name := "LFO derinlik etkisi"
	# Derinlik 0 — çıkış hep 0
	var lfo := AIAudioLFO.new(5.0, 0.0)
	if absf(lfo.raw_value(0.3)) > 0.001:
		return _fail(name, "derinlik 0 sabit 0 vermeli")
	return _ok(name)


# ============================================================
# SAMPLE BUFFER
# ============================================================

static func _test_buffer_mix() -> Dictionary:
	var name := "SampleBuffer karıştırma"
	var a := PackedFloat32Array([0.3, 0.4])
	var b := PackedFloat32Array([0.2, 0.1])
	var mixed: PackedFloat32Array = AIAudioSampleBuffer.mix(a, b)
	if absf(mixed[0] - 0.5) > 0.001:
		return _fail(name, "mix örnekleri toplamalı")
	# Klipleme — 1.0 üstü kesilir
	var loud := AIAudioSampleBuffer.mix(
		PackedFloat32Array([0.8]), PackedFloat32Array([0.8])
	)
	if loud[0] != 1.0:
		return _fail(name, "mix 1.0 üstünü kliplemeli")
	return _ok(name)


static func _test_buffer_normalize() -> Dictionary:
	var name := "SampleBuffer normalize"
	var buffer := PackedFloat32Array([0.2, 0.4, -0.5])
	var normalized: PackedFloat32Array = AIAudioSampleBuffer.normalize(
		buffer
	)
	# Normalize sonrası peak tam 1.0 olmalı
	if absf(AIAudioSampleBuffer.peak(normalized) - 1.0) > 0.001:
		return _fail(name, "normalize peak'i 1.0 yapmalı")
	return _ok(name)


static func _test_buffer_fade() -> Dictionary:
	var name := "SampleBuffer fade"
	var buffer := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	var faded: PackedFloat32Array = AIAudioSampleBuffer.fade_in(buffer, 4)
	# İlk örnek 0'a yakın (fade başı)
	if faded[0] > 0.1:
		return _fail(name, "fade-in ilk örneği kısmalı")
	return _ok(name)


# ============================================================
# SFXR PRESETS
# ============================================================

static func _test_sfxr_presets() -> Dictionary:
	var name := "Sfxr 10 önayar"
	var presets := AIAudioSfxrPresets.new()
	if presets.preset_count() != 10:
		return _fail(name, "10 önayar tanımlı olmalı")
	# Bilinen önayar
	if not presets.has_preset("explosion"):
		return _fail(name, "explosion önayarı olmalı")
	# Bilinmeyen önayar boş
	if not presets.get_preset("olmayan_onayar").is_empty():
		return _fail(name, "bilinmeyen önayar boş dönmeli")
	return _ok(name)


static func _test_sfxr_customize() -> Dictionary:
	var name := "Sfxr özelleştirme"
	var presets := AIAudioSfxrPresets.new()
	var custom: Dictionary = presets.customize(
		"pickup_coin", {"frequency": 999.0}
	)
	if custom.is_empty():
		return _fail(name, "geçerli önayar özelleştirilebilmeli")
	if absf(float(custom["frequency"]) - 999.0) > 0.001:
		return _fail(name, "özelleştirme parametreyi değiştirmeli")
	return _ok(name)


# ============================================================
# SYNTH ENGINE
# ============================================================

static func _test_synth_generate() -> Dictionary:
	var name := "SynthEngine ses üretimi"
	var engine := AIAudioSynthEngine.new()
	var presets := AIAudioSfxrPresets.new()
	var params: Dictionary = presets.get_preset("jump")
	var result: Dictionary = engine.synthesize(params, 0.3)
	if not bool(result["ok"]):
		return _fail(name, "geçerli parametre sentezlenebilmeli")
	var buffer: PackedFloat32Array = result["buffer"]
	if buffer.is_empty():
		return _fail(name, "sentez boş olmayan tampon üretmeli")
	return _ok(name)


static func _test_synth_empty() -> Dictionary:
	var name := "SynthEngine boş parametre"
	var engine := AIAudioSynthEngine.new()
	var result: Dictionary = engine.synthesize({}, 0.3)
	# Boş parametre — sentezlenemez
	if bool(result["ok"]):
		return _fail(name, "boş parametre reddedilmeli")
	return _ok(name)


# ============================================================
# VORBIS ENCODER
# ============================================================

static func _test_vorbis_pcm_roundtrip() -> Dictionary:
	var name := "Vorbis PCM round-trip"
	var encoder := AIAudioVorbisEncoder.new()
	var buffer := PackedFloat32Array([0.0, 0.5, -0.5, 1.0, -1.0])
	# float -> pcm -> float kayıp küçük olmalı
	var error: float = encoder.roundtrip_error(buffer)
	if error > 0.001:
		return _fail(name, "PCM round-trip hatası küçük olmalı")
	return _ok(name)


static func _test_vorbis_empty() -> Dictionary:
	var name := "Vorbis boş tampon"
	var encoder := AIAudioVorbisEncoder.new()
	var result: Dictionary = encoder.prepare_encoding(
		PackedFloat32Array()
	)
	# Boş tampon kodlanamaz
	if bool(result["ok"]):
		return _fail(name, "boş tampon kodlanamaz olmalı")
	return _ok(name)


# ============================================================
# INTENSITY MANAGER
# ============================================================

static func _test_intensity_levels() -> Dictionary:
	var name := "Intensity seviye eşikleri"
	var manager := AIAudioIntensityManager.new()
	# Yoğunluk 0 — calm
	manager.current_intensity = 0.1
	if manager.current_level() != AIAudioIntensityManager.IntensityLevel \
			.CALM:
		return _fail(name, "düşük yoğunluk CALM olmalı")
	# Yoğunluk yüksek — intense
	manager.current_intensity = 0.95
	if manager.current_level() != AIAudioIntensityManager.IntensityLevel \
			.INTENSE:
		return _fail(name, "yüksek yoğunluk INTENSE olmalı")
	if manager.active_layer_count() != 4:
		return _fail(name, "INTENSE'de 4 katman aktif olmalı")
	return _ok(name)


static func _test_intensity_smooth() -> Dictionary:
	var name := "Intensity yumuşak geçiş"
	var manager := AIAudioIntensityManager.new()
	manager.transition_rate = 0.5
	manager.set_target(1.0)
	# Bir tick'te hedefe ANINDA ulaşmamalı
	manager.tick(0.1)
	if manager.current_intensity >= 1.0:
		return _fail(name, "yoğunluk ani sıçramamalı")
	if manager.current_intensity <= 0.0:
		return _fail(name, "yoğunluk biraz ilerlemeli")
	return _ok(name)


# ============================================================
# CROSSFADE ENGINE
# ============================================================

static func _test_crossfade_endpoints() -> Dictionary:
	var name := "Crossfade uç noktalar"
	var fade := AIAudioCrossfadeEngine.new(2.0)
	fade.start()
	# Başlangıç — eski tam, yeni sıfır
	if absf(fade.fade_out_level() - 1.0) > 0.001:
		return _fail(name, "başlangıçta eski ses tam olmalı")
	if absf(fade.fade_in_level()) > 0.001:
		return _fail(name, "başlangıçta yeni ses sıfır olmalı")
	# Tam ilerlet — eski sıfır, yeni tam
	fade.tick(2.0)
	if absf(fade.fade_out_level()) > 0.001:
		return _fail(name, "sonda eski ses sıfır olmalı")
	if absf(fade.fade_in_level() - 1.0) > 0.001:
		return _fail(name, "sonda yeni ses tam olmalı")
	return _ok(name)


static func _test_crossfade_equal_power() -> Dictionary:
	var name := "Crossfade eşit-güç eğrisi"
	var fade := AIAudioCrossfadeEngine.new(2.0)
	fade.curve = AIAudioCrossfadeEngine.FadeCurve.EQUAL_POWER
	fade.start()
	# Ortaya ilerlet — eşit-güç eğrisinde toplam güç ~1.0 olmalı
	fade.tick(1.0)
	var power: float = fade.combined_power()
	if absf(power - 1.0) > 0.05:
		return _fail(name, "eşit-güç ortada toplam güç ~1.0 olmalı")
	return _ok(name)


# ============================================================
# STEM PLAYER POOL
# ============================================================

static func _test_stem_active_layers() -> Dictionary:
	var name := "Stem aktif katman uygulaması"
	var pool := AIAudioStemPlayerPool.new()
	pool.add_stem("base", 0)
	pool.add_stem("melody", 1)
	pool.add_stem("drums", 2)
	pool.add_stem("tension", 3)
	# 2 katman aktif et
	pool.set_active_layers(2)
	# Katman 0 ve 1 hedefi 1, 2 ve 3 hedefi 0
	var base_stem: AIAudioStemPlayerPool.Stem = pool.get_stem(0)
	var drums_stem: AIAudioStemPlayerPool.Stem = pool.get_stem(2)
	if not is_equal_approx(base_stem.target_volume, 1.0):
		return _fail(name, "aktif katman hedefi 1.0 olmalı")
	if not is_zero_approx(drums_stem.target_volume):
		return _fail(name, "pasif katman hedefi 0.0 olmalı")
	return _ok(name)


# ============================================================
# LOOP POINT HANDLER
# ============================================================

static func _test_loop_jump() -> Dictionary:
	var name := "Loop döngü atlaması"
	var loop := AIAudioLoopPointHandler.new()
	loop.configure(2.0, 10.0, 12.0)
	# Döngü sonunda — loop aksiyonu
	var at_end: Dictionary = loop.evaluate(10.0)
	if str(at_end["action"]) != "loop":
		return _fail(name, "döngü sonunda loop aksiyonu olmalı")
	# Döngü içinde — continue
	var in_loop: Dictionary = loop.evaluate(5.0)
	if str(in_loop["action"]) != "continue":
		return _fail(name, "döngü içinde continue olmalı")
	return _ok(name)


static func _test_loop_disabled() -> Dictionary:
	var name := "Loop devre dışı"
	var loop := AIAudioLoopPointHandler.new()
	loop.configure_full_loop(12.0)
	loop.loop_enabled = false
	# Döngü kapalı, parça sonu — stop
	var at_end: Dictionary = loop.evaluate(12.0)
	if str(at_end["action"]) != "stop":
		return _fail(name, "döngü kapalıyken parça sonu stop olmalı")
	return _ok(name)
