class_name NetCodec
extends RefCounted
## Packs what multiplayer sends every tick into small byte arrays: input commands (client to
## server) and snapshots (server to client). Rare things (joins, kills, hits, shots) go as plain
## reliable RPC arguments instead (see Net).
##
## Inputs and your own movement state keep full 64-bit precision, so the client's prediction and
## the server run the exact same numbers and agree to the last digit. Other players only need to
## look right, so their positions are 32-bit.

const MAX_CMDS := 16 # per input packet (unacknowledged inputs are resent until the server has them)

# Snapshot player flags
const F_CROUCH := 1
const F_SLIDE := 2
const F_GROUNDED := 4
const F_DEAD := 8
const F_PROTECTED := 16

## Weapon and ability ids as one small number each.
static var KINDS: Array = Items.WEAPONS.keys() + Items.ABILITIES.keys()


static func kind_index(id: String) -> int:
	return maxi(0, KINDS.find(id))


static func kind_id(i: int) -> String:
	return KINDS[i] if i >= 0 and i < KINDS.size() else KINDS[0]


# ---------- input commands ----------

## cmds: [[seq, view_tick, Cmd], ...]
static func pack_cmds(cmds: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	var n := mini(cmds.size(), MAX_CMDS)
	b.put_u8(n)
	for i in range(cmds.size() - n, cmds.size()): # the newest ones
		var e: Array = cmds[i]
		var c: Cmd = e[2]
		b.put_u32(e[0])
		b.put_u32(e[1])
		b.put_8(int(signf(c.forward)))
		b.put_8(int(signf(c.right)))
		var f := 0
		for bit: Array in [[c.jump, 1], [c.jump_held, 2], [c.sprint, 4], [c.crouch, 8], [c.slide, 16],
				[c.slide_pressed, 32], [c.fire, 64], [c.fire_pressed, 128], [c.reload, 256], [c.ability, 512]]:
			if bit[0]:
				f |= bit[1]
		b.put_u16(f)
		b.put_u8(1 if c.slot == "primary" else 2 if c.slot == "secondary" else 0)
		b.put_8(clampi(c.cycle, -1, 1))
		b.put_double(c.yaw)
		b.put_double(c.pitch)
	return b.data_array


## Returns [[seq, view_tick, Cmd], ...]. Anything malformed is dropped; values are clamped to what
## a real client could send (the server only trusts what the game code reads).
static func unpack_cmds(data: PackedByteArray) -> Array:
	var out := []
	if data.is_empty():
		return out
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	if data.size() < 1 + n * 30:
		return out
	for i in n:
		var seq := b.get_u32()
		var vt := b.get_u32()
		var c := Cmd.new()
		c.forward = clampf(b.get_8(), -1, 1)
		c.right = clampf(b.get_8(), -1, 1)
		var f := b.get_u16()
		c.jump = f & 1 != 0
		c.jump_held = f & 2 != 0
		c.sprint = f & 4 != 0
		c.crouch = f & 8 != 0
		c.slide = f & 16 != 0
		c.slide_pressed = f & 32 != 0
		c.fire = f & 64 != 0
		c.fire_pressed = f & 128 != 0
		c.reload = f & 256 != 0
		c.ability = f & 512 != 0
		var slot := b.get_u8()
		c.slot = "primary" if slot == 1 else "secondary" if slot == 2 else ""
		c.cycle = clampi(b.get_8(), -1, 1)
		var yaw := b.get_double()
		var pitch := b.get_double()
		c.yaw = yaw if is_finite(yaw) else 0.0
		c.pitch = clampf(pitch, -1.6, 1.6) if is_finite(pitch) else 0.0
		out.append([seq, vt, c])
	return out


# ---------- snapshots ----------

## snap: {tick, me: {seq, respawn_in, state: PackedFloat64Array}, players: [{id, x, y, z, yaw,
## pitch, flags, weapon, hp, kills, deaths}], proj: [{owner, id, kind, stuck, pos, vel}]}
static func pack_snapshot(snap: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(snap.tick)
	var me: Dictionary = snap.me
	b.put_u32(me.seq)
	b.put_float(me.respawn_in)
	var st: PackedFloat64Array = me.state
	b.put_u8(st.size())
	for v in st:
		b.put_double(v)
	var players: Array = snap.players
	b.put_u8(players.size())
	for p: Dictionary in players:
		b.put_u32(p.id)
		b.put_float(p.x)
		b.put_float(p.y)
		b.put_float(p.z)
		b.put_float(p.yaw)
		b.put_float(p.pitch)
		b.put_u8(p.flags)
		b.put_u8(kind_index(p.weapon))
		b.put_u8(clampi(ceili(p.hp), 0, 255))
		b.put_16(p.kills)
		b.put_16(p.deaths)
	var proj: Array = snap.proj
	b.put_u8(mini(proj.size(), 255))
	for i in mini(proj.size(), 255):
		var pr: Dictionary = proj[i]
		b.put_u32(pr.owner)
		b.put_u32(pr.id)
		b.put_u8(kind_index(pr.kind))
		b.put_u8(1 if pr.stuck else 0)
		var pos: Vector3 = pr.pos
		b.put_float(pos.x)
		b.put_float(pos.y)
		b.put_float(pos.z)
		# Velocity only extrapolates the drawing between snapshots: centimeters per second is plenty.
		var vel: Vector3 = pr.vel
		b.put_16(clampi(roundi(vel.x * 100), -32767, 32767))
		b.put_16(clampi(roundi(vel.y * 100), -32767, 32767))
		b.put_16(clampi(roundi(vel.z * 100), -32767, 32767))
	return b.data_array


static func unpack_snapshot(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var snap := {"tick": b.get_u32()}
	var me := {"seq": b.get_u32(), "respawn_in": b.get_float()}
	var st := PackedFloat64Array()
	var n := b.get_u8()
	st.resize(n)
	for i in n:
		st[i] = b.get_double()
	me.state = st
	snap.me = me
	var players := []
	for i in b.get_u8():
		var p := {"id": b.get_u32(), "x": b.get_float(), "y": b.get_float(), "z": b.get_float(),
			"yaw": b.get_float(), "pitch": b.get_float(), "flags": b.get_u8()}
		p.weapon = kind_id(b.get_u8())
		p.hp = b.get_u8()
		p.kills = b.get_16()
		p.deaths = b.get_16()
		players.append(p)
	snap.players = players
	var proj := []
	for i in b.get_u8():
		var pr := {"owner": b.get_u32(), "id": b.get_u32()}
		pr.kind = kind_id(b.get_u8())
		pr.stuck = b.get_u8() != 0
		pr.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
		pr.vel = Vector3(b.get_16(), b.get_16(), b.get_16()) / 100.0
		proj.append(pr)
	snap.proj = proj
	return snap
