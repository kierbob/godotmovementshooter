class_name Characters
## The playable characters: each one is a fixed kit (roguelite style: builds come from the items
## you find, not from your starting pick). Pure data, like Items. The first run stage is here too.

const LIST := {
	"brawler": {
		"id": "brawler", "name": "Brawler", "color": Color("ff8a3d"),
		"role": "Up close and airborne",
		"desc": "Blasts people at point blank and uses every shot to fly. Shoot the floor to launch yourself.",
		"primary": "shotgun", "secondary": "kickpistol", "ability": "impulse",
	},
	"bomber": {
		"id": "bomber", "name": "Bomber", "color": Color("ff5a6e"),
		"role": "Splash and rocket jumps",
		"desc": "Rockets for everything: crowds, walls, and getting up on the roof. Aim at your feet and jump.",
		"primary": "rocket", "secondary": "pistol", "ability": "frag",
	},
	"sharpshooter": {
		"id": "sharpshooter", "name": "Sharpshooter", "color": Color("4fc3ff"),
		"role": "Long range, quick feet",
		"desc": "Headshots from across the map, a buzz SMG for anything close, and a knife that kills.",
		"primary": "sniper", "secondary": "smg", "ability": "knife",
	},
}
const ORDER := ["brawler", "bomber", "sharpshooter"]
const DEFAULT := "brawler"

## Runs start here (later: a random pick from the stage pool, then the next floors).
const FIRST_STAGE := "sunstone-valley"


static func get_info(id: String) -> Dictionary:
	return LIST.get(id, LIST[DEFAULT])


static func is_valid(id: String) -> bool:
	return LIST.has(id)


## The character's kit as a Combat loadout {primary, secondary, ability}.
static func loadout(id: String) -> Dictionary:
	var c := get_info(id)
	return {"primary": c.primary, "secondary": c.secondary, "ability": c.ability}
