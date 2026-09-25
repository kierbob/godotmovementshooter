class_name LootView
extends Node3D
## Draws Loot: chests (a wooden one, a bigger purple one; gold trim, a lid that swings open), the
## price over each closed one (gold if you can afford it, red if not), and dropped items floating
## in the loot pack's floating effect in their rarity's color (BinbunVFX, assets/fx/GodotLootVFX),
## with a spinning chip of the item's color and letters in the middle.

const VFX_DIR := "res://assets/fx/GodotLootVFX/assets/BinbunVFX/loot_effects/effects/floating/"
## Our rarities -> the pack's effects (their mythic is red, like our rares).
const VFX := {"common": "loot_vfx_common.tscn", "uncommon": "loot_vfx_uncommon.tscn", "rare": "loot_vfx_mythic.tscn"}
const OPEN_TIME := 0.35
const VFX_SCALE := 1.6
const VFX_EMISSION := 1.0 # the pack's default is 2 (bright enough to hide the item in it)
const LABEL_RANGE := 70.0

var _chests := {} # chest id -> {node, hinge, label, open_t}
var _drops := {} # drop id -> {node, chip}
var _vfx := {} # rarity -> PackedScene
var _time := 0.0


func _ready() -> void:
	for r: String in VFX:
		_vfx[r] = load(VFX_DIR + VFX[r])


func update(loot: Loot, camera: Camera3D, dt: float) -> void:
	_time += dt
	for c in loot.chests:
		var v: Dictionary = _chests.get(c.id, {})
		if v.is_empty():
			v = _make_chest_view(c)
			_chests[c.id] = v
		var label: Label3D = v.label
		if c.opened:
			label.visible = false
			if v.open_t < 1.0:
				v.open_t = minf(1.0, v.open_t + dt / OPEN_TIME)
				var k: float = 1.0 - pow(1.0 - v.open_t, 3.0) # ease out, with a little overshoot
				(v.hinge as Node3D).rotation.x = deg_to_rad(110.0) * k + sin(v.open_t * PI) * 0.15 # front swings up and back
		else:
			var near := camera == null or camera.global_position.distance_to(c.pos) < LABEL_RANGE
			label.visible = near
			if near:
				label.modulate = Color("ffd84a") if loot.gold >= Loot.cost(c) else Color("ff6a5a")
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


func clear() -> void:
	for v: Dictionary in _chests.values():
		(v.node as Node3D).queue_free()
	_chests.clear()
	for v: Dictionary in _drops.values():
		(v.node as Node3D).queue_free()
	_drops.clear()


func _make_chest_view(c: Loot.Chest) -> Dictionary:
	var node := make_chest(c.size)
	node.position = c.pos
	node.rotation.y = c.yaw
	add_child(node)
	var label := MapPoint._label("$%d" % Loot.cost(c), 64, Color("ffd84a"))
	label.pixel_size = 0.006
	label.no_depth_test = false
	label.position.y = 1.5 if c.size == "large" else 1.25
	node.add_child(label)
	return {"node": node, "hinge": node.get_node("Hinge"), "label": label, "open_t": 0.0}


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
	# the item itself: a chip in its color with its letters on both faces
	var chip := Node3D.new()
	node.add_child(chip)
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.6, 0.6, 0.14)
	mi.mesh = b
	mi.material_override = WorldView.with_outline(WorldView.toon_material(it.color, false, 0.15), 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chip.add_child(mi)
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = it.icon
		l.font = Models.font("res://assets/fonts/Bangers-Regular.ttf")
		l.font_size = 64
		l.pixel_size = 0.006
		l.outline_size = 12
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.position.z = 0.08 * side
		l.rotation.y = 0.0 if side > 0 else PI
		chip.add_child(l)
	node.position = d.pos
	return {"node": node, "chip": chip}


## A chest model: "small" is wood, "large" bigger and purple; both gold-trimmed. The lid hangs off a
## "Hinge" node at the back edge (rotate it around X to open). Faces -Z. (MapChest draws it too.)
static func make_chest(size: String) -> Node3D:
	var big := size == "large"
	var w := 1.5 if big else 1.1
	var h := 0.75 if big else 0.55
	var dp := 1.0 if big else 0.75
	var lid_h := 0.35 if big else 0.28
	var body_col := Color("7a4fd6") if big else Color("a8743f")
	var trim := Color("ffcf3a")
	var g := Node3D.new()
	_block(g, Vector3(w, h, dp), Vector3(0, h / 2, 0), body_col)
	for x: float in [-w / 2 + 0.08, w / 2 - 0.08]: # corner bands
		_block(g, Vector3(0.1, h + 0.02, dp + 0.02), Vector3(x, h / 2, 0), trim)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(0, h, dp / 2)
	g.add_child(hinge)
	_block(hinge, Vector3(w, lid_h, dp), Vector3(0, lid_h / 2, -dp / 2), body_col.lightened(0.12))
	for x: float in [-w / 2 + 0.08, w / 2 - 0.08]:
		_block(hinge, Vector3(0.1, lid_h + 0.02, dp + 0.02), Vector3(x, lid_h / 2, -dp / 2), trim)
	_block(hinge, Vector3(0.18, 0.22, 0.06), Vector3(0, 0.0, -dp - 0.02), trim) # the lock
	return g


static func _block(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = WorldView.with_outline(WorldView.toon_material(color), 0.02)
	mi.position = pos
	parent.add_child(mi)
