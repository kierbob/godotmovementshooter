class_name TimeTrial
extends RefCounted
## Time trial (the web game's trial.js): portals in the hub take you to the course, the clock
## starts when you cross the start line and stops in the finish gate, which sends you back to the
## start. Two modes with their own records: guns off (pure movement) and guns on (shotgun boosts,
## rocket jumps...). Pure logic that runs in the fixed sim tick; best times are saved to
## user://trials.cfg.

## Bump the version whenever the course layout changes, so old records don't carry over.
const SECTION := "v2"

static var path := "user://trials.cfg" # tests point this elsewhere

var course := {} # map JSON "trial": start, startLineZ, killY, finish, exit, board
var portals: Array = [] # map JSON "portals": [{x, y, z, guns, label, sub}]
var spawn := {} # where "BACK TO HUB" drops you
var active := false # on the course
var guns := false # which mode
var running := false # clock ticking
var time := 0.0
var last := {"on": -1.0, "off": -1.0} # -1 = no run yet
var best := {"on": -1.0, "off": -1.0}
var cooldown := 0.0 # stops portals re-triggering right after a teleport
var events: Array[Dictionary] = [] # {type: teleport, to} | enter | leave | start | finish | fell | restart


func _init(map: MapData) -> void:
	course = map.trial
	portals = map.portals
	spawn = map.spawn
	_load_best()


func mode() -> String:
	return "on" if guns else "off"


## "mm:ss.mmm", or dashes for no time.
static func format_time(t: float) -> String:
	if t < 0:
		return "--:--.---"
	var m := floori(t / 60)
	return "%02d:%06.3f" % [m, t - m * 60]


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for k: String in ["on", "off"]:
		var v: Variant = cf.get_value(SECTION, k, -1.0)
		best[k] = float(v) if (v is float or v is int) and float(v) > 0 else -1.0


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.load(path) # keep other versions' records
	for k: String in ["on", "off"]:
		cf.set_value(SECTION, k, best[k])
	cf.save(path)


static func _in_portal(p: PlayerSim, portal: Dictionary) -> bool:
	var dy := p.py - float(portal.y)
	return dy > -0.5 and dy < 2 and PlayerSim.hyp2(p.px - float(portal.x), p.pz - float(portal.z)) < 1.1


static func _in_box(p: PlayerSim, b: Dictionary) -> bool:
	return p.px > b.min.x and p.px < b.max.x and p.py > b.min.y and p.py < b.max.y \
		and p.pz > b.min.z and p.pz < b.max.z


## Put the player somewhere with no leftover momentum or movement state.
static func teleport(p: PlayerSim, to: Dictionary) -> void:
	p.px = float(to.x)
	p.py = float(to.y)
	p.pz = float(to.z)
	p.vx = 0.0
	p.vy = 0.0
	p.vz = 0.0
	p.grounded = false
	p.sliding = false
	p.wall_jumps = 0
	p.air_time = 0.0
	p.friction_grace = 0.0


func _go(p: PlayerSim, to: Dictionary, type: String, extra := {}) -> void:
	teleport(p, to)
	cooldown = 0.6
	events.append({"type": "teleport", "to": to})
	var e := {"type": type}
	e.merge(extra)
	events.append(e)


func enter(p: PlayerSim, with_guns: bool) -> void:
	active = true
	guns = with_guns
	running = false
	time = 0.0
	_go(p, course.start, "enter", {"guns": with_guns})


func leave(p: PlayerSim) -> void:
	active = false
	running = false
	_go(p, spawn, "leave")


func restart(p: PlayerSim, reason := "restart") -> void:
	running = false
	time = 0.0
	_go(p, course.start, reason)


## Off the course without teleporting anyone (new run / back to the menu).
func reset() -> void:
	active = false
	running = false
	time = 0.0
	cooldown = 0.0
	events.clear()


func tick(p: PlayerSim, dt: float) -> void:
	cooldown = maxf(0.0, cooldown - dt)
	if not active:
		if cooldown == 0:
			for portal: Dictionary in portals:
				if _in_portal(p, portal):
					enter(p, portal.guns)
					break
		return
	if cooldown == 0 and _in_portal(p, course.exit):
		leave(p)
		return
	if p.py < float(course.killY):
		restart(p, "fell")
		return
	if not running and p.pz < float(course.startLineZ):
		running = true
		time = 0.0
		events.append({"type": "start"})
	if not running:
		return
	time += dt
	if _in_box(p, course.finish):
		_finish(p)


func _finish(p: PlayerSim) -> void:
	var k := mode()
	var t := time
	running = false
	last[k] = t
	var is_best: bool = best[k] < 0 or t < best[k]
	if is_best:
		best[k] = t
		_save_best()
	_go(p, course.start, "finish", {"time": t, "best": is_best})
