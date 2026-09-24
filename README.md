# Movement Shooter (Godot)

Godot 4.6 port of the web game (`../movement-shooter`). Single player for now; multiplayer comes later.

## Play

- Double-click `play.bat` (uses `Downloads\Godot_v4.6.2-stable_win64.exe\...`), or
- open this folder in Godot 4.6 and press **F5**.

Main menu → pick a map (and your guns under **Loadout**) → **Play**. The map screen also has the
two **time trials** (guns off / guns on); in the Dev Arena you can walk into their portals too. **Esc** pauses (Resume / Settings / Main Menu / Quit).
Settings (mouse sensitivity + FOV, video, lighting, volume, every keybind) are saved to
`%APPDATA%/Godot/app_userdata/Movement Shooter/settings.cfg`.

| Key | Action |
| --- | --- |
| WASD | move |
| Shift | sprint |
| Space | jump / wall jump |
| C | slide |
| Ctrl | crouch |
| Left mouse | fire |
| R | reload |
| 1 / 2 / mouse wheel | primary / secondary weapon |
| Q | ability (grenade / knife / impulse charge) |
| K | respawn (on the time trial: restart the run) |
| Esc | pause menu |
| F2 | next map (dev shortcut) |
| F4 | stats panel (full / compact / off) |
| F11 | fullscreen |

## What's in

- **Movement**: a line-for-line port of the web game's `src/player.js` (sprint, slide, wall jumps,
  ramps, jump pads, momentum), fixed 120 Hz ticks with smooth camera interpolation. One fix on
  top: flying or jumping into a ramp uphill lands you on the slope instead of teleporting you back
  to its bottom (a bug the web game still has). Mouse look uses
  Godot's raw mouse input.
- **Maps**, as scenes you edit in the Godot editor (`maps/`, see "Editing maps" below):
  - **Dev Arena**: the web game's dev map with every number kept exact, plus the time trial.
  - **Bean Town**: a Nuketown-style FFA map. Two two-story houses face each other across a
    cul-de-sac, with a school bus, trucks and cars in the street. Built for speed: doors and windows
    3-5 m wide with knee-high sills you can sprint or slide straight through, stairs to the upstairs,
    upstairs windows out onto the porch and garage roofs, trampolines in the yards up to the garage
    roof and the main roof, ramps onto the bus and a street launcher at each end.
- **Look**: toon shading (3 light bands + sky/ground fill), Candy Pastel sky, clouds, shadows.
- **Guns and abilities** (`scripts/items.gd`, `scripts/combat.gd`): a port of the web game's
  `items.js` / `combat.js`. Primaries: Boomstick, Pulse Rifle, Rocket Launcher, Long Shot.
  Secondaries: Sidearm, Buzz SMG, Kick Pistol, Deagle. Abilities on Q: Impact Grenade, Throwing
  Knife, Impulse Charge. Semi/full-auto, spread and pellets, reloads (a holstered gun keeps
  reloading), weapon switching, projectiles, explosions, and knockback through the movement code,
  so shotgun boosts and rocket/grenade jumps work like the web game.
- **Gun models**: Kenney's Blaster Kit (CC0, `assets/models/weapons`) in first person with the
  web game's draw, recoil, bob, sway and reload animations, drawn in their own view so they never
  clip into walls.
- **Combat HUD**: a crosshair per weapon (the Boomstick's ring is its real spread), recoil bloom,
  hitmarkers, weapon slots, ammo, reload bar and the ability cooldown.
- **Loadout screen**: pick a primary, secondary and ability, with a 3D preview you can spin,
  stats and item thumbnails. Saved with your settings.
- **Bean dummies** stop shots, take damage (headshots count), flash white when hit, show a health
  bar with their HP (e.g. "105 / 150"), go down at 0 HP and pop back 2.5 s later.
- **Cartoon effects** (the web game's `fx.js`): muzzle flash, POW star and action lines, smoke puffs
  and shell casings; tracers, bullet holes and chip puffs on walls; bean-juice splats; explosions
  with a fireball, smoke, debris, a shockwave ring and a flash of light; smoke trails behind
  rockets and grenades; the reload throws the empty gun, which spins and bounces away; camera
  shake. Comic words ("BLAM!", "KABOOM!", "SPLAT!", "BONK!") in the Bangers font, floating damage
  numbers and a punchy hitmarker (white body, yellow headshot, red kill).
- **Sounds** (the web game's `sound.js`): every gun, hits / headshots / kills, wall impacts,
  explosions, throws, weapon switch, the reload toss and catch, jumps, wall jumps, landings, slides,
  jump pads, time trial cues and menu clicks. They're the web game's synth recipes, baked to
  `assets/sounds/*.wav` by `tools/make_sounds.gd`; swap any WAV for a real recording. Explosions
  and impacts pan and fade with distance. The volume slider controls them.
- **Time trial** (the web game's `trial.js`): a course far off the Dev Arena (slide under a bar, gap
  jumps, a jump pad, a wall-jump gap, a slide-jump gap, a launcher to the finish). Two modes with
  their own records: **guns off** (pure movement) and **guns on** (shotgun boosts, rocket jumps).
  The clock starts at the start line and stops in the checkered finish gate; falling off or
  pressing K restarts; best and last times show on the timer board and the HUD and are saved.

## Editing maps

Open `maps/dev_map.tscn` or `maps/bean-town.tscn` in the Godot editor. Every piece is a node:

- **MapBox**: a solid box. Move it and scale it with the normal gizmos (position = center, scale =
  size in meters). In the Inspector: `kind` (its color: floor, wall, grass, road, house_blue,
  roof, bus...; the list is `WorldView.COLORS`) and `ramp`
  (a sloped top rising toward x+, x-, z+ or z-). Don't rotate boxes: collision is axis-aligned
  (the editor shows a warning if you do). Ctrl+D duplicates a box to make a new one.
- **MapPad**: jump pad (radius, launch speed, directional launchers).
- **MapSpawn**: where you start; turn it to set which way you face. The first one is used.
- **MapTarget**: a bean dummy (optionally sliding back and forth).
- **MapPortal**: the hub portals to the time trial (guns on / off).
- **MapTrial** (Dev Arena): the course's Start, Exit portal, Finish zone and timer Board, plus the
  start line and fall-off height. The course itself is ordinary boxes under it.
- The root (**MapRoot**) holds the map's name and its card text and colors for the map screen.

Group nodes under plain Node3Ds however you like; moving a group moves everything in it. Bean
Town is grouped by place (`BlueHouse/Walls`, `BlueHouse/Roof`, `Street`, `BlueBackyard`...), and the
yellow side is the blue side turned around, so change both if you want it to stay fair. Save
(Ctrl+S) and press F5. Positions snap to the millimeter; turn on Godot's grid snap for tidy
numbers. A new map: duplicate a `.tscn` in `maps/` and rename it; it shows up on the map screen.

Maps from the web game's map editor can be brought in with
`godot --headless --path . --script res://tools/json_to_map.gd -- <map.json> <id> [name]`.

## Proving the movement matches the web game

`tools/make_traces.mjs` records 16 movement runs with the web game's real code (needs Node and the
web project next to this folder). `check-movement.bat` (or `tests/compare.gd`) replays them in Godot:
before every tick it copies the web game's exact player state, runs one tick, and compares. The
runs were recorded on the original maps, kept as frozen copies in `tests/maps/*.json`, so editing
`maps/` never breaks this check.

```
node tools/make_traces.mjs
godot --headless --path . --script res://tests/compare.gd
```

`tests/menu_test.gd` clicks through the menus headless (play, pause, settings, rebinding, loadout,
map switch). `tests/combat_test.gd` checks the guns: fire rate, reloads, switching, hits and
headshots on the dummies, knockback, rocket jumps, abilities and shots against ramps.
`tests/trial_test.gd` checks the time trial (portals, start line, finish, falling off, records,
guns off/on), `tests/sound_test.gd` checks every sound is there and plays, and
`tests/map_test.gd` checks map scenes (JSON to scene is exact, maps load, editing rewrites values).

```
godot --headless --path . --script res://tests/menu_test.gd
godot --headless --path . --script res://tests/combat_test.gd
godot --headless --path . --script res://tests/trial_test.gd
godot --headless --path . --script res://tests/sound_test.gd
godot --headless --path . --script res://tests/map_test.gd
```

## Next

1. Bot Arena mode: bean bots that move, aim and shoot back; your health, dying and respawning.
2. More menu and settings polish (a mode picker once the modes exist).
3. Later: multiplayer.
