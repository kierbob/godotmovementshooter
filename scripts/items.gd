class_name Items
## Weapon and ability definitions, copied 1:1 from the web game's src/items.js. Pure data: add a
## gun by adding an entry here (and a model in MODELS). The loadout screen lists everything here.
##
## Weapon fields:
##   slot        "primary" | "secondary"
##   type        "hitscan" | "projectile"
##   auto        hold to fire (true) or one shot per click (false)
##   damage      per bullet/pellet; head_mult multiplies it on headshots
##   fire_rate   shots per second
##   mag, reload magazine size, reload seconds (reserve ammo is infinite)
##   spread      cone half-angle in degrees; pellets = bullets per shot
##   knockback   m/s pushed opposite to where you aim when firing (mobility)
##   kick        how hard the gun model recoils
##   crosshair   "ring" | "cross" | "dot" | "rocket" | "scope" | "bracket" (drawn by hud.gd)
##   projectile  for type "projectile" (see below)
##
## Projectile fields:
##   speed, up (extra upward throw speed), gravity, radius
##   impact      "explode" | "stick"
##   explode     {radius, damage, knockback}: knockback also launches YOU (rocket/grenade jumps)
##   damage, head_mult for "stick" projectiles (knives)
##   hit_pad     extra radius added to dummy hitboxes for this projectile (aim forgiveness)
##   inherit     false = don't add the thrower's velocity (default true)

const WEAPONS := {
	"shotgun": {
		"id": "shotgun", "slot": "primary", "name": "Boomstick",
		"desc": "Close-range blast. Shoot the floor to launch yourself.",
		"type": "hitscan", "auto": false, "damage": 9.0, "head_mult": 1.25, "pellets": 10, "spread": 5.0,
		"fire_rate": 1.3, "mag": 4, "reload": 1.5, "range": 60.0, "knockback": 16.0, "kick": 1.0, "crosshair": "ring",
	},
	"rifle": {
		"id": "rifle", "slot": "primary", "name": "Pulse Rifle",
		"desc": "Full-auto all-rounder. Accurate at range.",
		"type": "hitscan", "auto": true, "damage": 14.0, "head_mult": 1.5, "pellets": 1, "spread": 0.6,
		"fire_rate": 10.0, "mag": 30, "reload": 1.1, "range": 200.0, "knockback": 0.0, "kick": 0.25, "crosshair": "cross",
	},
	"rocket": {
		"id": "rocket", "slot": "primary", "name": "Rocket Launcher",
		"desc": "Splash damage. Aim at your feet and jump for a rocket jump.",
		"type": "projectile", "auto": false, "fire_rate": 1.1, "mag": 2, "reload": 1.8, "knockback": 0.0, "kick": 0.8,
		"crosshair": "rocket",
		"projectile": {
			"speed": 38.0, "up": 0.0, "gravity": 0.0, "radius": 0.15, "impact": "explode",
			"explode": {"radius": 4.5, "damage": 85.0, "knockback": 13.0},
		},
	},
	"sniper": {
		"id": "sniper", "slot": "primary", "name": "Long Shot",
		"desc": "Two heavy rounds. Headshots kill, and each shot shoves you back hard.",
		"type": "hitscan", "auto": false, "damage": 75.0, "head_mult": 2.0, "pellets": 1, "spread": 0.0,
		"fire_rate": 1.25, "mag": 2, "reload": 1.8, "range": 400.0, "knockback": 13.0, "kick": 1.2, "crosshair": "scope",
	},
	"pistol": {
		"id": "pistol", "slot": "secondary", "name": "Sidearm",
		"desc": "Reliable semi-auto. Rewards headshots.",
		"type": "hitscan", "auto": false, "damage": 20.0, "head_mult": 2.0, "pellets": 1, "spread": 0.3,
		"fire_rate": 6.0, "mag": 12, "reload": 1.1, "range": 150.0, "knockback": 0.0, "kick": 0.35, "crosshair": "dot",
	},
	"smg": {
		"id": "smg", "slot": "secondary", "name": "Buzz SMG",
		"desc": "Sprays fast. Great for finishing people mid-air.",
		"type": "hitscan", "auto": true, "damage": 8.0, "head_mult": 1.4, "pellets": 1, "spread": 1.6,
		"fire_rate": 16.0, "mag": 32, "reload": 1.4, "range": 80.0, "knockback": 0.0, "kick": 0.18, "crosshair": "cross",
	},
	"kickpistol": {
		"id": "kickpistol", "slot": "secondary", "name": "Kick Pistol",
		"desc": "Heavy hand cannon. Every shot shoves you backwards — a mini boost.",
		"type": "hitscan", "auto": false, "damage": 30.0, "head_mult": 1.5, "pellets": 1, "spread": 0.2,
		"fire_rate": 2.5, "mag": 6, "reload": 1.3, "range": 120.0, "knockback": 6.5, "kick": 0.8, "crosshair": "bracket",
	},
	"deagle": {
		"id": "deagle", "slot": "secondary", "name": "Deagle",
		"desc": "No push, all punch. One tap to the head.",
		"type": "hitscan", "auto": false, "damage": 50.0, "head_mult": 2.0, "pellets": 1, "spread": 0.1,
		"fire_rate": 2.8, "mag": 7, "reload": 1.4, "range": 180.0, "knockback": 0.0, "kick": 0.9, "crosshair": "dot",
	},
}

## Abilities are thrown on the ability key and recharge on a cooldown.
const ABILITIES := {
	"frag": {
		"id": "frag", "name": "Impact Grenade",
		"desc": "Explodes the instant it touches anything. Hurts targets and launches you.",
		"cooldown": 7.0,
		"projectile": {
			"speed": 24.0, "up": 2.5, "gravity": 22.0, "radius": 0.12, "impact": "explode",
			"explode": {"radius": 5.0, "damage": 70.0, "knockback": 14.0},
		},
	},
	"knife": {
		"id": "knife", "name": "Throwing Knife",
		"desc": "Fast and precise. Headshots nearly one-shot.",
		"cooldown": 4.0,
		# hit_pad fattens every hitbox for this projectile (forgiving, arcade-style);
		# inherit false = flies exactly where you aim, no matter how fast you're moving.
		"projectile": {
			"speed": 95.0, "up": 0.0, "gravity": 2.0, "radius": 0.05, "impact": "stick", "damage": 200.0, "head_mult": 1.8,
			"hit_pad": 0.14, "inherit": false,
		},
	},
	"impulse": {
		"id": "impulse", "name": "Impulse Charge",
		"desc": "Pops on impact. Barely scratches, but throws you (and everything) hard.",
		"cooldown": 6.0,
		"projectile": {
			"speed": 24.0, "up": 2.0, "gravity": 22.0, "radius": 0.15, "impact": "explode",
			"explode": {"radius": 4.5, "damage": 15.0, "knockback": 17.0},
		},
	},
}

const DEFAULT_LOADOUT := {"primary": "shotgun", "secondary": "pistol", "ability": "frag"}

## Loadout slots in the order the loadout screen shows them.
const SLOTS := [
	{"id": "primary", "label": "Primary", "title": "Primary Weapons"},
	{"id": "secondary", "label": "Secondary", "title": "Secondary Weapons"},
	{"id": "ability", "label": "Ability", "title": "Abilities"},
]

## Gun model files (assets/models/weapons) and how they sit in first person (web models.js):
##   length  how long the gun is in viewmodel space (bigger = chunkier on screen)
##   offset  nudge after fitting
## The knife has no file: models.gd builds it from boxes.
const MODELS := {
	"shotgun": {"file": "boomstick.glb", "length": 0.55, "offset": Vector3.ZERO},
	"rifle": {"file": "puslerifle.glb", "length": 0.64, "offset": Vector3.ZERO},
	"rocket": {"file": "rocketlauncher.glb", "length": 0.72, "offset": Vector3(0.03, 0, 0)},
	"pistol": {"file": "sidearm.glb", "length": 0.34, "offset": Vector3.ZERO},
	"smg": {"file": "buzzsmg.glb", "length": 0.5, "offset": Vector3.ZERO},
	"kickpistol": {"file": "kickpistol.glb", "length": 0.4, "offset": Vector3.ZERO},
	"sniper": {"file": "sniper.glb", "length": 0.8, "offset": Vector3.ZERO},
	"deagle": {"file": "deagle.glb", "length": 0.36, "offset": Vector3.ZERO},
	"frag": {"file": "grenade.glb"},
	"impulse": {"file": "impulse.glb"},
}


static func item(slot: String, id: String) -> Dictionary:
	return ABILITIES[id] if slot == "ability" else WEAPONS[id]


static func items_for_slot(slot: String) -> Array:
	if slot == "ability":
		return ABILITIES.values()
	return WEAPONS.values().filter(func(w: Dictionary) -> bool: return w.slot == slot)


static func is_valid(slot: String, id: String) -> bool:
	if slot == "ability":
		return ABILITIES.has(id)
	return WEAPONS.has(id) and WEAPONS[id].slot == slot


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.1f" % v


## Loadout screen stats: [label, 0..1 bar, value text].
static func weapon_stats(w: Dictionary) -> Array:
	var p: Dictionary = w.get("projectile", {}).get("explode", {})
	var dmg: String
	if not p.is_empty():
		dmg = "%s splash" % _num(p.damage)
	elif w.pellets > 1:
		dmg = "%s×%d" % [_num(w.damage), w.pellets]
	else:
		dmg = "%s · %s head" % [_num(w.damage), _num(w.damage * w.head_mult)]
	var mob: float = w.knockback if w.knockback > 0 else p.get("knockback", 0.0)
	return [
		["Damage", clampf((p.damage if not p.is_empty() else w.damage * w.pellets) / 100.0, 0, 1), dmg],
		["Fire rate", clampf(w.fire_rate / 16.0, 0, 1), "%d rpm" % roundi(w.fire_rate * 60)],
		["Magazine", clampf(w.mag / 32.0, 0, 1), str(w.mag)],
		["Reload", clampf(1 - (w.reload - 0.8) / 1.4, 0, 1), "%ss" % _num(w.reload)],
		["Mobility", clampf(mob / 16.0, 0, 1), "%s m/s" % _num(mob) if mob > 0 else "none"],
	]


static func ability_stats(a: Dictionary) -> Array:
	var p: Dictionary = a.projectile
	var e: Dictionary = p.get("explode", {})
	var dmg: float = e.damage if not e.is_empty() else p.damage
	var mob: float = e.get("knockback", 0.0)
	return [
		["Damage", clampf(dmg / 100.0, 0, 1), "%s splash" % _num(dmg) if not e.is_empty() else _num(dmg)],
		["Recharge", clampf(3.0 / a.cooldown, 0, 1), "%ss" % _num(a.cooldown)],
		["Mobility", clampf(mob / 17.0, 0, 1), "%s m/s" % _num(mob) if mob > 0 else "none"],
	]


## Short class line shown above the item name.
static func item_class(it: Dictionary) -> String:
	if not it.has("slot"):
		return "Throwable · Precision" if it.projectile.impact == "stick" else "Throwable · Explosive"
	if it.type == "projectile":
		return "Launcher · Explosive"
	if it.pellets > 1:
		return "Shotgun · Mobility"
	var kind := "Sniper" if it.id == "sniper" else ("SMG" if it.auto else "Pistol") if it.slot == "secondary" else "Rifle"
	return "%s · %s" % [kind, "Full-auto" if it.auto else "Semi-auto"]
