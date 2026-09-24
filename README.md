# Movement Shooter (Godot)

Godot 4.6 port of the web game (`../movement-shooter`). Play solo, or online with friends (one of
you hosts, see "Playing online").

## Play

- Double-click `play.bat` (uses `Downloads\Godot_v4.6.2-stable_win64.exe\...`), or
- open this folder in Godot 4.6 and press **F5**.

The game is heading toward a Risk of Rain style roguelite (runs over several stages, enemies,
items that stack). The menus already work that way:

- **SINGLEPLAYER** → the lobby: pick your character (Brawler, Bomber, Sharpshooter; each is a
  fixed kit), press **READY** → the loading screen → stage 1 (Bean Town for now).
- **MULTIPLAYER** → host or join a lobby (see "Playing online").
- **PRACTICE** → free play on any map with the dummies, and the two **time trials** (guns off /
  guns on); in the Dev Arena you can walk into their portals too.
- **SETTINGS**, **QUIT**. **Esc** pauses in game (Resume / Settings / Main Menu / Quit).
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
| K | respawn (on the time trial: restart the run; not online) |
| Tab | scoreboard (online, hold) |
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
- **Multiplayer** (see "Playing online"): host or join by address (playit.gg works), free-for-all
  up to 8, other players as beans in their color with name tags and their gun, predicted
  movement with corrections, lag-compensated hits, health / regen / respawns / spawn
  protection, kill feed, hold-Tab scoreboard, hurt flash and a direction arrow.
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
- **Characters** (`scripts/characters.gd`): Brawler (Boomstick, Kick Pistol, Impulse Charge),
  Bomber (Rocket Launcher, Sidearm, Impact Grenade), Sharpshooter (Long Shot, Buzz SMG, Throwing
  Knife). Picked in the lobby, shown on a 3D stage in their color; saved with your settings.
- **Lobby and loading screen**: Risk of Rain style. Everyone ready → (online: a 3 s countdown) →
  a loading card with the stage number, name, progress and tips, which stays up while the stage
  loads and, online, until everyone has loaded.
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

## Playing online

One player hosts; the match runs on their PC and they play in it like everyone else. Up to 8
players. Everyone needs the same version of the game (and the same maps).

**Host:** Main menu → **MULTIPLAYER** → set your name → **HOST**. You land in the lobby.
The game listens on UDP port 7777 (change it on the same screen). If Windows Firewall asks, allow
it. Then give your friends an address:

- **Friends over the internet: playit.gg** (free). Install and run the playit.gg program, sign
  in, and add a **UDP** tunnel pointing at local port **7777** (the port on the host screen).
  playit shows a public address like `abc.gl.at.ply.gg:12345`: send your friends that. Keep
  playit running while you play. (Port-forwarding UDP 7777 on your router works too, then they
  use your public IP.)
- **Same Wi-Fi:** they can use your PC's local address; the host screen lists it
  (like `192.168.1.20:7777`).

**Join:** **MULTIPLAYER** → set your name → paste the address → **JOIN**. In the lobby everyone
picks a character and readies up; when all are ready a 3 s countdown starts, everyone loads the
stage, and the run starts together. Joining a run in progress drops you straight in.

In the match: free-for-all. 100 HP, you regenerate 3 s after the last hit, respawn 2.5 s after
getting splatted with 1.5 s of spawn protection (you blink, your health bar turns blue). Hold
**Tab** for the scoreboard. Esc opens the menu but the match keeps going (**LEAVE MATCH** to
go). If the host leaves, everyone goes back to the menu.

How it works (the web game's netcode, ported): the host runs everyone's movement and guns at
120 ticks/s (`MatchServer`) and sends 30 snapshots a second. Your own movement and gun run on
your PC straight away (no input lag) and get corrected if the host disagrees; other players are
drawn 100 ms in the past, smoothed between snapshots, and the host checks your shots against
where people were on your screen (lag compensation). Tested headless with a relay adding 60 ms
each way plus 2% packet loss.

Shortcuts for testing: `-- --host`, `-- --host=7777`, `-- --join=address:port`, `-- --name=Bean`
on the Godot command line (after `--`).

## Editing maps

Open `maps/dev_map.tscn` or `maps/bean-town.tscn` in the Godot editor. Every piece is a node:

- **MapBox**: a solid box. Move it and scale it with the normal gizmos (position = center, scale =
  size in meters). In the Inspector: `kind` (its color: floor, wall, grass, road, house_blue,
  roof, bus...; the list is `WorldView.COLORS`; `barrier` is an invisible wall) and `ramp`
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

`tests/menu_test.gd` clicks through the menus headless (main screen, practice through the loading
screen, pause, settings, rebinding, the solo lobby starting a run with your character's kit). `tests/combat_test.gd` checks the guns: fire rate, reloads, switching, hits and
headshots on the dummies, knockback, rocket jumps, abilities and shots against ramps.
`tests/trial_test.gd` checks the time trial (portals, start line, finish, falling off, records,
guns off/on), `tests/sound_test.gd` checks every sound is there and plays, and
`tests/map_test.gd` checks map scenes (JSON to scene is exact, maps load, editing rewrites values).
`tests/net_test.gd` checks multiplayer: packing, the host's simulation matching your prediction
exactly, damage / kills / respawns, knockback on other players, lag compensation, corrections
under lag, and a real host and client over localhost.

```
godot --headless --path . --script res://tests/menu_test.gd
godot --headless --path . --script res://tests/combat_test.gd
godot --headless --path . --script res://tests/trial_test.gd
godot --headless --path . --script res://tests/sound_test.gd
godot --headless --path . --script res://tests/map_test.gd
godot --headless --path . --script res://tests/net_test.gd
```

## Next

The roguelite, in this order:

1. Enemies: three bean types (melee charger, ranged shooter, flyer) and a spawn director that
   ramps up over time.
2. Solo health, dying and "run over".
3. Gold, chests and stacking items (movement-themed: speed, extra wall jumps, slide damage...).
4. Run structure: teleporter + boss wave, then the next stage (the loading screen is ready for
   it), a difficulty clock.
5. More stages, character passives, unlocks. Multiplayer becomes co-op.
