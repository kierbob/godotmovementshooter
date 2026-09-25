class_name Characters
## The playable characters: each one is a fixed kit (roguelite style: builds come from the items
## you find, not from your starting pick) and a passive of its own (what it does lives in
## Upgrades: PASSIVE and the hooks; on in solo play). Pure data, like Items. The run's stages too.

const LIST := {
	"brawler": {
		"id": "brawler", "name": "Brawler", "color": Color("ff8a3d"),
		"role": "Up close and airborne",
		"desc": "Blasts people at point blank and uses every shot to fly. Shoot the floor to launch yourself.",
		"primary": "shotgun", "secondary": "kickpistol", "ability": "impulse",
		"passive": {"name": "Scrapper", "desc": "Kills within 8 m heal you 12. Gun hits while you're in the air deal +15%."},
	},
	"bomber": {
		"id": "bomber", "name": "Bomber", "color": Color("ff5a6e"),
		"role": "Splash and rocket jumps",
		"desc": "Rockets for everything: crowds, walls, and getting up on the roof. Aim at your feet and jump.",
		"primary": "rocket", "secondary": "pistol", "ability": "frag",
		"passive": {"name": "Demolition", "desc": "Your blasts are 20% bigger, and every enemy one catches takes 0.4 s off your Frag."},
	},
	"sharpshooter": {
		"id": "sharpshooter", "name": "Sharpshooter", "color": Color("4fc3ff"),
		"role": "Long range, quick feet",
		"desc": "Headshots from across the map, a buzz SMG for anything close, and a knife that kills.",
		"primary": "sniper", "secondary": "smg", "ability": "knife",
		"passive": {"name": "Deadeye", "desc": "Hits from 20 m or more deal +25%. A headshot kill gives your knife straight back."},
	},
	"commando": {
		"id": "commando", "name": "Commando", "color": Color("6fdc6a"),
		"role": "Steady fire, never still",
		"desc": "A Pulse Rifle that shreds at any range, a Deagle for the big hits, and a dash to be anywhere else.",
		"primary": "rifle", "secondary": "deagle", "ability": "dash",
		"passive": {"name": "Run and Gun", "desc": "Dashing reloads both guns, and for 2 s after a dash your shots deal +20%."},
	},
}
const ORDER := ["brawler", "bomber", "sharpshooter", "commando"]
const DEFAULT := "brawler"

## Runs start here, then go through STAGES in order (looping, harder each time round). A stage
## whose map isn't there yet is skipped (fantasy-village is next, once it's built).
const FIRST_STAGE := "sunstone-valley"
const STAGES := ["sunstone-valley", "fantasy-village"]


## The map for stage n (1-based) of a run.
static func stage_map(n: int) -> String:
	var have := MapData.list()
	var pool := STAGES.filter(func(id: String) -> bool: return id in have)
	return FIRST_STAGE if pool.is_empty() else pool[(n - 1) % pool.size()]


static func get_info(id: String) -> Dictionary:
	return LIST.get(id, LIST[DEFAULT])


static func is_valid(id: String) -> bool:
	return LIST.has(id)


## The character's kit as a Combat loadout {primary, secondary, ability}.
static func loadout(id: String) -> Dictionary:
	var c := get_info(id)
	return {"primary": c.primary, "secondary": c.secondary, "ability": c.ability}
