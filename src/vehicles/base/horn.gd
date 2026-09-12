class_name Horn
extends RefCounted
## Procedural car-horn tone: synthesized once as a looping AudioStreamWAV, no audio asset.
## BaseVehicle plays it on the horn rising edge and fades it over RELEASE_SECONDS on release.

const RATE := 22050            ## Hz sample rate
## One loop of the sustained tone. Every periodic term below (pitches, wobbles, flutter) is a
## multiple of 1 / LOOP_SECONDS (2 Hz), so it completes whole cycles in the loop and the seam
## is silent.
const LOOP_SECONDS := 0.5
const ATTACK_SECONDS := 0.04   ## played once before the loop: the diaphragm kicking into pitch
const ONSET_SECONDS := 0.006   ## amplitude ramp at the very start, so play() never clicks
const ONSET_FLAT := 0.04       ## the attack starts this fraction flat and glides up to pitch
const ONSET_DRIVE := 0.6       ## extra soft-clip drive at the first sample: the opening blat
const RELEASE_SECONDS := 0.06  ## BaseVehicle's fade-out, so stop() never clicks
const TOP_HZ := 5000.0         ## highest partial synthesized; a horn's buzz lives below this
## The flared trumpet resonates the diaphragm's buzz into the nasal "honk" band.
const FORMANT_HZ := 2400.0
const FORMANT_WIDTH_HZ := 900.0
const DRIVE := 1.8             ## tanh soft-clip: the growl of a diaphragm hitting its stop
const PEAK := 0.4              ## output peak, full scale = 1
## The dual-tone pair a minor third apart, each a separate unit with its own slight pitch wobble
## and loudness flutter — two identical, perfectly steady tones is what reads as synthetic.
## `wobble` is [rate Hz, depth Hz] pairs, `flutter` is [rate Hz, depth fraction].
const HORNS := [
	{f = 420.0, gain = 1.0, wobble = [[2.0, 0.9], [6.0, 0.5]], flutter = [8.0, 0.03], phase = 0.0},
	{f = 500.0, gain = 0.8, wobble = [[4.0, 1.1], [10.0, 0.5]], flutter = [14.0, 0.03], phase = 1.7},
]

static var _cached: AudioStreamWAV


## Pure (no scene) so a test can assert it produces non-empty 16-bit data with a forward loop.
## Every vehicle shares the one stream: it is read-only once built.
static func make_stream() -> AudioStreamWAV:
	if _cached != null:
		return _cached
	var attack := int(RATE * ATTACK_SECONDS)
	var frames := attack + int(RATE * LOOP_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var weights: Array[PackedFloat32Array] = []
	var theta: Array[float] = []
	for h in HORNS:
		weights.append(_harmonic_weights(h.f))
		theta.append(h.phase)
	var peak := 0.0
	for i in frames:
		var t := float(i) / float(RATE)
		var rise := 1.0 - minf(float(i) / float(attack), 1.0)  # 1 at the first sample, 0 from the loop on
		var s := 0.0
		for k in HORNS.size():
			var h: Dictionary = HORNS[k]
			var f: float = h.f * (1.0 - ONSET_FLAT * rise * rise)
			for w in h.wobble:
				f += w[1] * cos(TAU * w[0] * t)
			theta[k] += TAU * f / RATE
			var flutter: float = 1.0 + h.flutter[1] * sin(TAU * h.flutter[0] * t + h.phase)
			s += h.gain * flutter * _buzz(theta[k], weights[k])
		s = tanh(DRIVE * (1.0 + ONSET_DRIVE * rise) * s) * minf(t / ONSET_SECONDS, 1.0)
		samples[i] = s
		peak = maxf(peak, absf(s))

	var data := PackedByteArray()
	data.resize(frames * 2)  # 16-bit mono
	for i in frames:
		data.encode_s16(i * 2, int(samples[i] * PEAK / peak * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = attack
	wav.loop_end = frames
	_cached = wav
	return wav


## One horn's harmonic amplitudes: a sawtooth-like 1/n series, lifted around the trumpet formant.
static func _harmonic_weights(f: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	var n := 1
	while n * f <= TOP_HZ:
		var hz := n * f
		w.append(0.5 * (1.0 + 1.5 * exp(-pow((hz - FORMANT_HZ) / FORMANT_WIDTH_HZ, 2.0))) / n)
		n += 1
	return w


## Sums sin(n * theta) against the weights by the Chebyshev recurrence: one sin/cos per sample
## instead of one sin per partial.
static func _buzz(theta: float, w: PackedFloat32Array) -> float:
	var c2 := 2.0 * cos(theta)
	var prev := 0.0
	var cur := sin(theta)
	var s := 0.0
	for a in w:
		s += a * cur
		var nxt := c2 * cur - prev
		prev = cur
		cur = nxt
	return s
