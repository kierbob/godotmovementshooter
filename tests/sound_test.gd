extends SceneTree
## Checks the baked sounds: every sound the game plays exists and loads, and playing them
## (flat and positional) doesn't error.
##   godot --headless --path . --script res://tests/sound_test.gd

var fails := 0


func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		fails += 1


func _init() -> void:
	await run() # in its own function so its locals are gone before quitting (no leak warnings)
	print("\n%s" % ("all sound checks passed" if fails == 0 else "%d sound checks FAILED" % fails))
	quit(1 if fails > 0 else 0)


func run() -> void:
	await process_frame
	var sound := Sound.new()
	root.add_child(sound)
	var needed: Array = Items.WEAPONS.keys()
	needed.append_array(["reload", "switch", "throw", "knifeThrow", "explosion", "impulse", "impact", "hit",
		"headshot", "kill", "jump", "land", "slide", "wallJump", "pad", "teleport", "go", "finish", "ui",
		"coin", "chest", "pickup", "deny"])
	var missing := needed.filter(func(n: String) -> bool: return not sound.has(n))
	check("every sound the game plays is there (%d)" % needed.size(), missing.is_empty())
	if not missing.is_empty():
		print("      missing: ", missing)
	check("variants are grouped (rifle has 3)", sound._streams.get("rifle", []).size() == 3)
	var lengths_ok := true
	for n: String in needed:
		for st: AudioStream in sound._streams.get(n, []):
			if st.get_length() <= 0.02 or st.get_length() > 2.0:
				lengths_ok = false
				print("      odd length: %s %.2f s" % [n, st.get_length()])
	check("every sound is between 0.02 s and 2 s long", lengths_ok)
	for n: String in needed:
		sound.play(n)
		sound.play(n, {"pos": Vector3(5, 0, 5), "gap": 0.0})
	await process_frame
	check("playing every sound (flat and positional) works", true)
	sound._last.erase("smg")
	var t0: int = sound._next_flat
	sound.play("smg", {"gap": 0.5})
	sound.play("smg", {"gap": 0.5})
	check("gap stops the same sound stacking", sound._next_flat == t0 + 1)
	sound.queue_free()
	await create_timer(1.2).timeout # let the audio thread finish with the (up to 1 s) sounds
