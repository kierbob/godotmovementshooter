class_name Sound
extends Node
## Plays the cartoon sound effects (the web game's sound.js). The sounds are baked to
## assets/sounds/*.wav by tools/make_sounds.gd from the web game's synth recipes; a name with
## variants (rifle_1.wav, rifle_2.wav...) picks one at random. Swap any file for a real recording
## and it's used instead.
##
## play(name, {pos, vol, gap}): pos = world position (pans and fades with distance, like the web
## game), vol = 0..1+, gap = min seconds between two plays of the same sound (default 0.015, so
## full-auto fire doesn't stack into mush).

const DIR := "res://assets/sounds/"
const BOOST_DB := 6.0 # the files are baked with 6 dB of headroom
const VOICES := 24

var _streams := {} # name -> Array[AudioStream]
var _last := {} # name -> last play time (s)
var _flat: Array[AudioStreamPlayer] = []
var _spatial: Array[AudioStreamPlayer3D] = []
var _next_flat := 0
var _next_spatial := 0
var listener := Vector3.ZERO # where your ears are (the camera), for distance fading


func _ready() -> void:
	_load_all()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat.append(p)
		var s := AudioStreamPlayer3D.new()
		# Distance fade is done by hand (web formula); the 3D player just pans left/right.
		s.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		s.panning_strength = 0.8
		s.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(s)
		_spatial.append(s)
	# Keeps stacked explosions from clipping (web: DynamicsCompressor, -12 dB, 6:1).
	if AudioServer.get_bus_effect_count(0) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -12.0
		comp.ratio = 6.0
		AudioServer.add_bus_effect(0, comp)


func _load_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		push_warning("No sounds folder at %s" % DIR)
		return
	var seen := {}
	for f in dir.get_files():
		# the editor lists "x.wav" and "x.wav.import"; exported builds only the .import/.remap
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not file.ends_with(".wav") or seen.has(file):
			continue
		seen[file] = true
		var stream := _load_wav(DIR + file)
		if stream == null:
			continue
		var name := file.get_basename()
		var parts := name.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			name = parts[0]
		if not _streams.has(name):
			_streams[name] = []
		_streams[name].append(stream)


## Godot's imported copy when there is one; otherwise read the WAV directly (a fresh download
## run before the editor has imported anything).
static func _load_wav(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))


func has(name: String) -> bool:
	return _streams.has(name)


func play(name: String, opts := {}) -> void:
	var list: Array = _streams.get(name, [])
	if list.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	if t - _last.get(name, -1.0) < opts.get("gap", 0.015):
		return
	_last[name] = t
	var vol: float = opts.get("vol", 1.0)
	var stream: AudioStream = list.pick_random()
	var pitch := 1.0 + randf_range(-0.04, 0.04) # a little variety between repeats
	if opts.has("pos"):
		var pos: Vector3 = opts.pos
		vol *= 1.0 / (1.0 + pos.distance_to(listener) * 0.07)
		var p := _spatial[_next_spatial % VOICES]
		_next_spatial += 1
		p.stream = stream
		p.global_position = pos
		p.volume_db = linear_to_db(maxf(vol, 0.0001)) + BOOST_DB
		p.pitch_scale = pitch
		p.play()
	else:
		var p := _flat[_next_flat % VOICES]
		_next_flat += 1
		p.stream = stream
		p.volume_db = linear_to_db(maxf(vol, 0.0001)) + BOOST_DB
		p.pitch_scale = pitch
		p.play()
