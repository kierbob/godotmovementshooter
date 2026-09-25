extends SceneTree
## Bakes the cartoon sound effects to assets/sounds/*.wav. The recipes are the web game's
## src/sound.js SYNTH table line for line (oscillator sweeps + filtered noise bursts with
## exponential envelopes, like Web Audio), rendered in software here once. Sounds whose recipe
## has randomness get a few variants (name_1.wav, name_2.wav, ...) that the game picks between.
##   godot --headless --path . --script res://tools/make_sounds.gd
## To use a real recording instead, drop name.wav (or name_1.wav, name_2.wav...) into
## assets/sounds/ in place of the baked one.

const RATE := 44100
const OUT := "res://assets/sounds/"
const LEVEL := 0.5 # headroom: the game plays these 6 dB louder through a compressor
const VARIANTS := 3

var buf := PackedFloat32Array()


# ---------- building blocks (sound.js Voice) ----------

func _ensure(n: int) -> void:
	if buf.size() < n:
		var old := buf.size()
		buf.resize(n)
		for i in range(old, n):
			buf[i] = 0.0


## Web Audio exponential envelope: 0.0001 -> vol over `attack`, then down to 0.0001 at `dur`.
static func env(t: float, vol: float, dur: float, attack: float) -> float:
	if t < attack:
		return 0.0001 * pow(vol / 0.0001, t / attack)
	if t < dur:
		return vol * pow(0.0001 / vol, (t - attack) / (dur - attack))
	return 0.0


## Oscillator sweeping f0 -> f1 (exponentially) over dur. o: {delay, attack, vibrato: [rate, depth]}
func tone(type: String, f0: float, f1: float, dur: float, vol: float, o := {}) -> void:
	var start := int(o.get("delay", 0.0) * RATE)
	var n := int((dur + 0.02) * RATE)
	var attack: float = o.get("attack", 0.003)
	var vib: Array = o.get("vibrato", [])
	f1 = maxf(1.0, f1)
	_ensure(start + n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, minf(t, dur) / dur)
		if not vib.is_empty():
			f += sin(TAU * vib[0] * t) * vib[1]
		phase = fposmod(phase + f / RATE, 1.0)
		var w: float
		match type:
			"sine": w = sin(TAU * phase)
			"square": w = 1.0 if phase < 0.5 else -1.0
			"triangle": w = 4.0 * absf(phase - 0.5) - 1.0
			_: w = 2.0 * phase - 1.0 # sawtooth
		buf[start + i] += w * env(t, vol, dur, attack)


## White noise through a biquad whose cutoff sweeps f0 -> f1. o: {type, q, delay, attack}
func noise(dur: float, vol: float, f0: float, f1: float, o := {}) -> void:
	var start := int(o.get("delay", 0.0) * RATE)
	var n := int((dur + 0.02) * RATE)
	var attack: float = o.get("attack", 0.003)
	var ftype: String = o.get("type", "lowpass")
	var q: float = o.get("q", 0.7)
	# Web Audio reads lowpass/highpass Q in dB of resonance, bandpass Q as-is.
	var ql := pow(10.0, q / 20.0) if ftype != "bandpass" else q
	f1 = maxf(20.0, f1)
	_ensure(start + n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	for i in n:
		var t := float(i) / RATE
		if i % 16 == 0: # RBJ cookbook coefficients, refreshed as the cutoff sweeps
			var fc := minf(f0 * pow(f1 / f0, minf(t, dur) / dur), RATE * 0.45)
			var w0 := TAU * fc / RATE
			var cw := cos(w0)
			var alpha := sin(w0) / (2.0 * ql)
			var a0 := 1.0 + alpha
			match ftype:
				"lowpass":
					b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
				"highpass":
					b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
				_: # bandpass, 0 dB peak
					b0 = alpha; b1 = 0; b2 = -alpha
			b0 /= a0; b1 /= a0; b2 /= a0
			a1 = -2 * cw / a0
			a2 = (1 - alpha) / a0
		var x := randf() * 2.0 - 1.0
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		buf[start + i] += y * env(t, vol, dur, attack)


static func rnd(a: float, b: float) -> float:
	return randf_range(a, b)


# ---------- recipes (sound.js SYNTH) ----------

func recipe(name: String) -> void:
	match name:
		# ---- guns ----
		"shotgun":
			noise(0.35, 0.9, 5000, 250)
			tone("sine", 150, 38, 0.3, 0.9)
			tone("square", 95, 50, 0.08, 0.25)
			noise(0.05, 0.3, 1800, 1800, {"type": "bandpass", "q": 2, "delay": 0.32}) # pump click
			noise(0.05, 0.3, 2400, 2400, {"type": "bandpass", "q": 2, "delay": 0.42})
		"rifle":
			noise(0.08, 0.45, 3200, 1200, {"type": "bandpass", "q": 0.8})
			tone("square", rnd(400, 440), 150, 0.06, 0.16)
		"smg":
			noise(0.05, 0.38, 4000, 1800, {"type": "bandpass", "q": 0.9})
			tone("square", rnd(600, 660), 250, 0.04, 0.12)
		"pistol":
			noise(0.12, 0.6, 2600, 700, {"type": "bandpass", "q": 0.7})
			tone("triangle", 560, 120, 0.1, 0.35)
		"kickpistol":
			noise(0.25, 0.9, 3000, 200)
			tone("sine", 115, 35, 0.3, 1)
			tone("triangle", 280, 900, 0.16, 0.14, {"delay": 0.04, "vibrato": [30, 60]}) # boing tail
		"sniper":
			noise(0.45, 1, 6000, 180)
			tone("sine", 130, 30, 0.4, 1)
			tone("square", 1800, 300, 0.06, 0.2) # crack
			noise(0.05, 0.3, 2000, 2000, {"type": "bandpass", "q": 2, "delay": 0.45}) # bolt
			noise(0.05, 0.3, 2600, 2600, {"type": "bandpass", "q": 2, "delay": 0.55})
		"deagle":
			noise(0.22, 0.85, 3600, 300)
			tone("sine", 140, 40, 0.22, 0.8)
			tone("square", 700, 160, 0.07, 0.2)
		"rocket":
			noise(0.5, 0.5, 500, 2600, {"type": "bandpass", "q": 1.4})
			tone("sawtooth", 80, 210, 0.4, 0.12)
			tone("sine", 120, 50, 0.15, 0.5)
		"dry":
			tone("square", 1500, 1400, 0.03, 0.12)
		"reload":
			noise(0.03, 0.3, 3000, 3000, {"type": "highpass"})
			tone("square", 900, 700, 0.03, 0.08)
			noise(0.04, 0.35, 2200, 2200, {"type": "bandpass", "q": 3, "delay": 0.2})
			tone("square", 600, 1100, 0.05, 0.1, {"delay": 0.2})
		"switch":
			tone("square", 1300, 900, 0.025, 0.08)
			noise(0.04, 0.2, 2500, 2500, {"type": "bandpass", "q": 2, "delay": 0.06})
		"throw":
			noise(0.2, 0.35, 400, 1800, {"type": "bandpass", "q": 1.2})
		"knifeThrow":
			noise(0.18, 0.3, 600, 2400, {"type": "bandpass", "q": 1.5})
			tone("sine", 2400, 1900, 0.2, 0.08)
		# ---- explosions ----
		"explosion":
			tone("sine", 95, 26, 0.9, 1)
			noise(1.0, 0.9, 2000, 110)
			noise(0.12, 0.45, 3500, 3500, {"type": "highpass"})
			noise(0.4, 0.25, 900, 300, {"type": "bandpass", "q": 3, "delay": 0.15}) # rumble tail
		"impulse":
			tone("sine", 180, 950, 0.35, 0.6)
			tone("square", 90, 450, 0.3, 0.1)
			noise(0.3, 0.3, 1400, 4200, {"type": "bandpass", "q": 1})
		# ---- hits ----
		"impact":
			noise(0.03, 0.15, 4000, 4000, {"type": "highpass"})
			tone("triangle", rnd(1100, 1400), 500, 0.035, 0.07)
		"hit": # squish!
			noise(0.12, 0.5, 1400, 250, {"type": "bandpass", "q": 3})
			tone("sine", 700, 260, 0.09, 0.3)
		"headshot": # ding!
			tone("sine", 1760, 1740, 0.5, 0.32)
			tone("sine", 2640, 2620, 0.35, 0.14)
			noise(0.02, 0.25, 5000, 5000, {"type": "highpass"})
		"kill": # pop + happy arpeggio
			noise(0.08, 0.6, 3000, 400, {"type": "bandpass", "q": 1.5})
			tone("sine", 400, 1200, 0.08, 0.4)
			var notes := [523, 659, 784, 1046]
			for i in notes.size():
				tone("triangle", notes[i], notes[i], 0.14, 0.2, {"delay": 0.06 + i * 0.06})
		# ---- movement ----
		"jump":
			tone("sine", 250, 430, 0.1, 0.12)
		"land": # baked at full strength; the game scales the volume by how far you fell
			tone("sine", 130, 55, 0.12, 0.5)
			noise(0.08, 0.3, 600, 150)
		"slide":
			noise(0.5, 0.3, 1400, 500, {"type": "bandpass", "q": 0.8, "attack": 0.02})
		"wallJump":
			tone("triangle", 300, 760, 0.12, 0.25)
			noise(0.03, 0.25, 2500, 2500, {"type": "bandpass", "q": 2})
		"pad": # BOING
			tone("sine", 140, 620, 0.4, 0.55, {"vibrato": [18, 40]})
			tone("triangle", 280, 1240, 0.3, 0.15)
		# ---- getting hit (online) ----
		"hurt": # oof
			noise(0.14, 0.45, 900, 200, {"type": "bandpass", "q": 2})
			tone("sine", 320, 120, 0.16, 0.45)
		"death": # sad trombone
			var notes := [392, 370, 349, 311]
			for i in notes.size():
				var last := i == 3
				var o := {"delay": i * 0.26}
				if last:
					o.vibrato = [6, 10]
				tone("triangle", notes[i], notes[i] * 0.85 if last else notes[i], 0.6 if last else 0.24, 0.22, o)
		# ---- time trial ----
		"teleport":
			tone("sine", 200, 1600, 0.35, 0.35, {"vibrato": [25, 80]})
			noise(0.35, 0.2, 800, 5000, {"type": "bandpass", "q": 1.5})
		"go":
			tone("square", 880, 880, 0.18, 0.18)
			tone("square", 1320, 1320, 0.25, 0.14, {"delay": 0.1})
		"finish": # ta-da!
			var notes := [523, 659, 784, 1046, 1318]
			for i in notes.size():
				tone("triangle", notes[i], notes[i], 0.22, 0.22, {"delay": i * 0.08})
			tone("sine", 1046, 1046, 0.6, 0.15, {"delay": 0.4})
		# ---- UI ----
		"ui":
			tone("triangle", 660, 990, 0.06, 0.12)
		# ---- loot ----
		"coin": # ka-ching
			tone("square", 988, 988, 0.06, 0.1)
			tone("square", 1318, 1318, 0.18, 0.1, {"delay": 0.06})
		"chest": # creak, then a bright pop
			noise(0.22, 0.25, 300, 900, {"type": "bandpass", "q": 3})
			tone("sawtooth", 110, 180, 0.2, 0.08)
			tone("triangle", 523, 1046, 0.18, 0.2, {"delay": 0.2})
			noise(0.12, 0.15, 3000, 6000, {"type": "bandpass", "q": 1.5, "delay": 0.22})
		"pickup": # a quick rising arpeggio
			var notes := [784, 988, 1175, 1568]
			for i in notes.size():
				tone("triangle", notes[i], notes[i], 0.12, 0.2, {"delay": i * 0.05})
		"deny": # can't afford it
			tone("square", 196, 185, 0.12, 0.12)
			tone("square", 147, 139, 0.16, 0.12, {"delay": 0.1})


## Recipes with random pitch get a few baked variants.
const RANDOM := ["rifle", "smg", "impact"]
const NAMES := ["shotgun", "rifle", "smg", "pistol", "kickpistol", "sniper", "deagle", "rocket", "dry", "reload",
	"switch", "throw", "knifeThrow", "explosion", "impulse", "impact", "hit", "headshot", "kill", "jump", "land",
	"slide", "wallJump", "pad", "teleport", "go", "finish", "ui", "hurt", "death", "coin", "chest", "pickup", "deny"]


func save(name: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		# gentle soft clip so stacked layers never wrap around
		var s := buf[i] * LEVEL
		s = s if absf(s) < 0.8 else signf(s) * (0.8 + 0.2 * tanh((absf(s) - 0.8) / 0.2))
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.save_to_wav(OUT + name + ".wav")


func _init() -> void:
	seed(11)
	DirAccess.make_dir_recursive_absolute(OUT)
	for name: String in NAMES:
		var count := VARIANTS if name in RANDOM else 1
		for v in count:
			buf = PackedFloat32Array()
			recipe(name)
			var file := name if count == 1 else "%s_%d" % [name, v + 1]
			save(file)
			print("wrote %s.wav (%.2f s)" % [file, float(buf.size()) / RATE])
	quit()
