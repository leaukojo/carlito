class_name Horn
extends RefCounted
## Procedural car-horn tone. No audio asset: the sample is
## synthesized once as a looping AudioStreamWAV so the horn honks for as long as
## the button is held. BaseVehicle plays it on the horn rising edge (source-agnostic
## — local key or bridge bit, whichever set VehicleInput.horn).

const RATE := 22050        ## Hz sample rate
const LOOP_SECONDS := 0.2  ## one loop of the sustained tone
## Two sine partials a major-third-ish apart give the classic dual-tone honk; a
## quiet third harmonic adds the buzzy edge.
const F1 := 440.0
const F2 := 554.37


## Build the looping horn stream. Pure (no scene): a test can assert it produces
## non-empty 16-bit data with a forward loop.
static func make_stream() -> AudioStreamWAV:
	var frames := int(RATE * LOOP_SECONDS)
	var data := PackedByteArray()
	data.resize(frames * 2)  # 16-bit mono
	for i in frames:
		var t := float(i) / float(RATE)
		var s := 0.5 * sin(TAU * F1 * t) + 0.4 * sin(TAU * F2 * t) + 0.1 * sin(TAU * 3.0 * F1 * t)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
