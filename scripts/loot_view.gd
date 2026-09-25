class_name LootView
extends Node3D
## Draws Loot. Chests (a lid that swings open): wood, a bigger purple large one, a golden one
## standing in a pillar of gold light, and red / blue / green themed ones with their word on the
## front. Shop terminals with their item floating over them, the Shrine of Chance (a pillar with a
## spinning coin), barrels that burst. The price over each (gold if you can afford it, red if not).
## Dropped items float in the loot pack's floating effect in their rarity's color (BinbunVFX,
## assets/fx/GodotLootVFX) with a spinning chip of the item's color and letters in the middle, and
## opening something shoots a beam of that color into the sky.

const VFX_DIR := "res://assets/fx/GodotLootVFX/assets/BinbunVFX/loot_effects/effects/"
## Our rarities -> the pack's effects (their mythic is red, like our rares).
const VFX := {"common": "loot_vfx_common.tscn", "uncommon": "loot_vfx_uncommon.tscn", "rare": "loot_vfx_mythic.tscn",
	"legendary": "loot_vfx_legendary.tscn"}
const OPEN_TIME := 0.35
const VFX_SCALE := 1.6
const VFX_EMISSION := 1.0 # the pack's default is 2 (bright enough to hide the item in it)
const LABEL_RANGE := 70.0
const BEAM_TIME := 0.9
## Chest colors by kind: [body, trim].
const LOOKS := {
	"small": [Color("a8743f"), Color("ffcf3a")], "large": [Color("7a4fd6"), Color("ffcf3a")],
	"golden": [Color("ffc21a"), Color("fff6d8")], "damage": [Color("d8423a"), Color("ffcf3a")],
	"utility": [Color("3f8fe0"), Color("ffcf3a")], "healing": [Color("47b85a"), Color("ffcf3a")],
}
const THEME_WORD := {"damage": "DAMAGE", "utility": "UTILITY", "healing": "HEALING"}

var particles: Particles # the world's (main hands CombatView's over): coins, splinters
var _chests := {} # chest id -> {node, hinge, label, open_t, cost, extra}
var _drops := {} # drop id -> {node, chip}
var _vfx := {} # rarity -> PackedScene (floating)
var _beams: Array = [] # [{node, mat, life}]
var _time := 0.0


func _ready() -> void:
	for r: String in VFX:
		_vfx[r] = load(VFX_DIR + "floating/" + VFX[r])
	_vfx["golden_ground"] = load(VFX_DIR + "ground/ground_loot_vfx_legendary.tscn")


func update(loot: Loot, camera: Camera3D, dt: float) -> void:
	_time += dt
	for c in loot.chests:
		var v: Dictionary = _chests.get(c.id, {})
		if v.is_empty():
			v = _make_chest_view(c)
			_chests[c.id] = v
		_update_chest(c, v, loot, camera, dt)
	var seen := {}
	for d in loot.drops:
		seen[d.id] = true
		var v: Dictionary = _drops.get(d.id, {})
		if v.is_empty():
			v = _make_drop_view(d)
			_drops[d.id] = v
		var node: Node3D = v.node
		node.position = d.pos + (Vector3(0, sin(_time * 2.5 + d.id) * 0.12, 0) if d.landed else Vector3.ZERO)
		(v.chip as Node3D).rotation.y = _time * 2.0
	for id: int in _drops.keys():
		if not seen.has(id):
			(_drops[id].node as Node3D).queue_free()
			_drops.erase(id)
	var left: Array = []
	for b: Dictionary in _beams:
		b.life -= dt
		if b.life <= 0:
			(b.node as Node3D).queue_free()
			continue
		var k: float = b.life / BEAM_TIME
		(b.mat as StandardMaterial3D).albedo_color.a = 0.8 * k
		(b.node as Node3D).scale = Vector3(k, 1.0 + (1.0 - k) * 0.3, k)
		left.append(b)
	_beams = left


## The juice when something opens: a beam in the item's rarity color, coins, a lid pop.
func on_events(events: Array[Dictionary]) -> void:
	for e in events:
		match e.type:
			"chest_open":
				_beam(e.pos, Upgrades.RARITY[e.rarity].color, 3.0 if e.rarity == "legendary" else 1.0)
				_burst(e.pos + Vector3(0, 0.8, 0), Color("ffd84a"), 10, true)
			"barrel":
				_burst(e.pos + Vector3(0, 0.5, 0), Color("a8743f"), 12, false)
				_burst(e.pos + Vector3(0, 0.5, 0), Color("ffd84a"), 6, true)
			"shrine_fail":
				_burst(e.pos + Vector3(0, 1.8, 0), Color("9aa3b5"), 8, false)


func clear() -> void:
	for v: Dictionary in _chests.values():
		(v.node as Node3D).queue_free()
	_chests.clear()
	for v: Dictionary in _drops.values():
		(v.node as Node3D).queue_free()
	_drops.clear()


func _update_chest(c: Loot.Chest, v: Dictionary, loot: Loot, camera: Camera3D, dt: float) -> void:
	var label: Label3D = v.label
	var near := camera == null or camera.global_position.distance_to(c.pos) < LABEL_RANGE
	match c.size:
		"barrel":
			(v.node as Node3D).visible = not c.opened
			return
		"shop":
			var extra: Node3D = v.extra
			if c.opened:
				extra.visible = false
			else:
				extra.rotation.y = _time * 1.5
				extra.position.y = 1.7 + sin(_time * 2.0 + c.id) * 0.08
		"shrine":
			var coin: Node3D = v.extra
			coin.visible = not c.opened
			coin.rotation.y = _time * 3.0
	if c.opened:
		label.visible = false
		var hinge: Node3D = v.hinge
		if hinge and v.open_t < 1.0:
			v.open_t = minf(1.0, v.open_t + dt / OPEN_TIME)
			var k: float = 1.0 - pow(1.0 - v.open_t, 3.0) # ease out, with a little overshoot
			hinge.rotation.x = deg_to_rad(110.0) * k + sin(v.open_t * PI) * 0.15 # front swings up and back
		return
	label.visible = near
	if near:
		if c.cost != v.cost: # shrines get pricier
			v.cost = c.cost
			label.text = "$%d" % c.cost
		label.modulate = Color("ffd84a") if loot.gold >= c.cost else Color("ff6a5a")


func _make_chest_view(c: Loot.Chest) -> Dictionary:
	var node: Node3D
	var extra: Node3D = null
	var label_y := 1.25
	match c.size:
		"shop":
			node = make_terminal()
			extra = _item_chip(c.item, 0.8)
			var glow: PackedScene = _vfx.get(Upgrades.LIST[c.item].rarity)
			if glow:
				var fx := glow.instantiate() as Node3D
				fx.scale = Vector3.ONE * 0.9
				extra.add_child(fx)
				if fx is VFXLoot:
					(fx as VFXLoot).emission = VFX_EMISSION
			node.add_child(extra)
			label_y = 2.45
		"shrine":
			node = make_shrine()
			extra = node.get_node("Coin")
			label_y = 2.6
		"barrel":
			node = make_barrel()
		_:
			node = make_chest(c.size)
			label_y = 1.5 if c.size in ["large", "golden"] else 1.25
			if c.size == "golden":
				var pillar: PackedScene = _vfx.get("golden_ground")
				if pillar:
					node.add_child(pillar.instantiate())
	node.position = c.pos
	node.rotation.y = c.yaw
	add_child(node)
	var label := MapPoint._label("$%d" % c.cost, 64, Color("ffd84a"))
	label.pixel_size = 0.006
	label.no_depth_test = false
	label.position.y = label_y
	label.visible = c.size != "barrel"
	node.add_child(label)
	return {"node": node, "hinge": node.get_node_or_null("Hinge"), "label": label, "open_t": 0.0, "cost": c.cost, "extra": extra}


func _make_drop_view(d: Loot.Drop) -> Dictionary:
	var it: Dictionary = Upgrades.LIST[d.item]
	var node := Node3D.new()
	add_child(node)
	var ps: PackedScene = _vfx.get(it.rarity)
	if ps:
		var vfx := ps.instantiate() as Node3D
		vfx.scale = Vector3.ONE * VFX_SCALE # the pack's effect is sized for small pickups
		node.add_child(vfx)
		if vfx is VFXLoot:
			(vfx as VFXLoot).emission = VFX_EMISSION # the item chip shows through the glow
	var chip := _item_chip(d.item, 1.0)
	node.add_child(chip)
	node.position = d.pos
	return {"node": node, "chip": chip}


## The item itself: a chip in its color with its letters on both faces.
func _item_chip(id: String, scale: float) -> Node3D:
	var it: Dictionary = Upgrades.LIST[id]
	var chip := Node3D.new()
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.6, 0.6, 0.14) * scale
	mi.mesh = b
	mi.material_override = WorldView.with_outline(WorldView.toon_material(it.color, false, 0.15), 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chip.add_child(mi)
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = it.icon
		l.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
		l.font_size = 64
		l.pixel_size = 0.006 * scale
		l.outline_size = 12
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.position.z = 0.08 * side * scale
		l.rotation.y = 0.0 if side > 0 else PI
		chip.add_child(l)
	return chip


func _beam(at: Vector3, color: Color, width: float) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.18 * width
	c.bottom_radius = 0.3 * width
	c.height = 14.0
	c.radial_segments = 10
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color, 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, 7.0, 0)
	add_child(mi)
	_beams.append({"node": mi, "mat": m, "life": BEAM_TIME})


func _burst(at: Vector3, color: Color, n: int, shiny: bool) -> void:
	if particles == null:
		return
	for i in n:
		var a := randf() * TAU
		particles.spawn({"cube": true, "lit": not shiny, "pos": at, "gravity": 16.0, "spin": 12.0, "life": randf_range(0.6, 0.9),
			"vel": Vector3(cos(a) * randf_range(1.5, 3.5), randf_range(4, 7), sin(a) * randf_range(1.5, 3.5)),
			"size": [0.12, 0.08], "color": color, "opacity": [1.0, 1.0]})


## A chest model, colored by kind (LOOKS; large and golden are bigger; themed ones have their word
## on the front). The lid hangs off a "Hinge" node at the back edge (rotate it around X to open).
## Faces -Z. (MapChest draws them too.)
static func make_chest(size: String) -> Node3D:
	var big := size in ["large", "golden"]
	var w := 1.5 if big else 1.1
	var h := 0.75 if big else 0.55
	var dp := 1.0 if big else 0.75
	var lid_h := 0.35 if big else 0.28
	var look: Array = LOOKS.get(size, LOOKS.small)
	var body_col: Color = look[0]
	var trim: Color = look[1]
	var g := Node3D.new()
	_block(g, Vector3(w, h, dp), Vector3(0, h / 2, 0), body_col, size == "golden")
	for x: float in [-w / 2 + 0.08, w / 2 - 0.08]: # corner bands
		_block(g, Vector3(0.1, h + 0.02, dp + 0.02), Vector3(x, h / 2, 0), trim)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(0, h, dp / 2)
	g.add_child(hinge)
	_block(hinge, Vector3(w, lid_h, dp), Vector3(0, lid_h / 2, -dp / 2), body_col.lightened(0.12), size == "golden")
	for x: float in [-w / 2 + 0.08, w / 2 - 0.08]:
		_block(hinge, Vector3(0.1, lid_h + 0.02, dp + 0.02), Vector3(x, lid_h / 2, -dp / 2), trim)
	_block(hinge, Vector3(0.18, 0.22, 0.06), Vector3(0, 0.0, -dp - 0.02), trim) # the lock
	if THEME_WORD.has(size):
		var l := Label3D.new()
		l.text = THEME_WORD[size]
		l.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
		l.font_size = 40
		l.pixel_size = 0.005
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.position = Vector3(0, h * 0.45, -dp / 2 - 0.01)
		l.rotation.y = PI # face -Z (the front)
		g.add_child(l)
	return g


## A shop terminal: a squat console with a screen; its item floats over it.
static func make_terminal() -> Node3D:
	var g := Node3D.new()
	_block(g, Vector3(0.8, 0.9, 0.6), Vector3(0, 0.45, 0), Color("5a6075"))
	_block(g, Vector3(0.9, 0.12, 0.7), Vector3(0, 0.96, 0), Color("c7ccd9"))
	_block(g, Vector3(0.6, 0.4, 0.05), Vector3(0, 0.55, -0.31), Color("6fe0ff"), true) # the screen
	return g


## The Shrine of Chance: a carved stone pillar with a gold coin spinning over it.
static func make_shrine() -> Node3D:
	var g := Node3D.new()
	_block(g, Vector3(1.2, 0.3, 1.2), Vector3(0, 0.15, 0), Color("aaa08c"))
	_block(g, Vector3(0.7, 1.4, 0.7), Vector3(0, 1.0, 0), Color("ddd5c2"))
	_block(g, Vector3(0.95, 0.2, 0.95), Vector3(0, 1.8, 0), Color("aaa08c"))
	var coin := Node3D.new()
	coin.name = "Coin"
	coin.position.y = 2.25
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.28
	c.bottom_radius = 0.28
	c.height = 0.07
	mi.mesh = c
	mi.material_override = WorldView.with_outline(WorldView.toon_material(Color("ffcf2e"), false, 0.4), 0.02)
	mi.rotation.x = PI / 2
	coin.add_child(mi)
	g.add_child(coin)
	return g


## A barrel: wood with two dark hoops.
static func make_barrel() -> Node3D:
	var g := Node3D.new()
	var body := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.38
	c.bottom_radius = 0.38
	c.height = 1.0
	c.radial_segments = 12
	body.mesh = c
	body.material_override = WorldView.with_outline(WorldView.toon_material(Color("a8743f")), 0.02)
	body.position.y = 0.5
	g.add_child(body)
	for y: float in [0.22, 0.78]:
		var hoop := MeshInstance3D.new()
		var t := CylinderMesh.new()
		t.top_radius = 0.4
		t.bottom_radius = 0.4
		t.height = 0.08
		t.radial_segments = 12
		hoop.mesh = t
		hoop.material_override = WorldView.toon_material(Color("3a3f4b"))
		hoop.position.y = y
		g.add_child(hoop)
	return g


static func _block(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := false) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = WorldView.with_outline(WorldView.toon_material(color, false, 0.35 if glow else 0.0), 0.02)
	mi.position = pos
	parent.add_child(mi)
