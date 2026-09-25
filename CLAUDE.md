# Movement Shooter (Godot) — notes for Claude

Godot 4.6 port of the web movement shooter. Read README.md first, then the scripts.
Solo modes plus online multiplayer (one player hosts over ENet/UDP; friends join via playit.gg). The owner plays on Windows (`play.bat` or F5 in Godot)
and works on the game in Claude Code cloud sessions.

## The web game

The original lives in the public repo `kierbob/MovementShooter` (not in this repo). Clone it
read-only for reference: `git clone --depth 1 https://github.com/kierbob/movementshooter`.
Useful files: `src/items.js` (weapon/ability data), `src/combat.js`, `src/hud.js`, `src/player.js`,
`src/config.js`, `src/world.js`.

Port only what the current step needs, not the whole web game. Guns, gun models, the combat HUD,
the cartoon effects, sound, the time trial and multiplayer are in.

Direction (the owner's call): a Risk of Rain style first-person roguelite. Characters with fixed
kits, runs over stages with a loading screen between them, enemies and stacking items next;
multiplayer becomes optional co-op later (the owner said to leave multiplayer alone for now).

## Files

- `maps/*.tscn`: the maps, edited in the Godot editor. Node scripts in `scripts/map/` (@tool):
  MapRoot, MapBox (solid box; exact edges in `box`, or web-editor numbers in `web_box`), MapVolume
  (trigger box), MapPad, MapSpawn, MapTarget, MapPortal, MapTrial, MapBoard. The exact 64-bit
  values are the truth; the node transform (32-bit) mirrors them and edits write back rounded to
  the millimeter. Only store short decimals: Godot misreads some 17-digit numbers from scenes.
  `MapData.load_map(id)` reads a map scene; `MapConvert` / `tools/json_to_map.gd` make one from a
  map JSON. Maps: `dev_map` (web dev arena + time trial), `sunstone-valley` (stage 1, the
  first run stage: a 240 m valley, grouped by area; big maps set `MapRoot.view_scale` to push the
  haze out) and `bean-town` (Nuketown-style FFA,
  grouped by place; the yellow half mirrors the blue half through the center). A box's `kind` is
  its color from `WorldView.COLORS` (add new kinds there and to MapBox's enum). Kind `barrier` is
  an invisible wall: solid for players, not drawn, ignored by shots.
- `scripts/main.gd`: game entry. Builds the map, runs the sim at a fixed 120 ticks/s, moves the
  camera between ticks, switches menu/playing/paused. Test flags: `--map=`, `--at=`, `--screen=`, `--shot=`,
  `--solo` (straight into a solo run), `--host`, `--join=`, `--ready`, `--name=`.
- `scripts/player_sim.gd`: the movement, line for line from the web game's `src/player.js`. It uses
  plain 64-bit floats on purpose (Vector3 is 32-bit). Do NOT refactor it to Vector3.
- `scripts/cfg.gd`: every movement number, 1:1 from the web game's `config.js`.
- `scripts/cmd.gd`: one tick of input as plain data (network-ready for multiplayer), including
  fire/reload/ability/slot/cycle.
- `scripts/items.gd`: weapon + ability data from `items.js` (Boomstick and Sidearm buffed since).
- `scripts/characters.gd`: the characters (fixed kits: primary, secondary, ability; color, blurb)
  and the first stage. `Settings.character` picks one; `Settings.loadout()` is its kit.
- `scripts/combat.gd`: guns, projectiles, damage and knockback (port of `combat.js`, no bots yet).
  Ticks before `player.step`, like the web game. Uses Vector3 (spread is random, so no bit-exact
  match needed); knockback goes through `PlayerSim.apply_impulse`.
- `scripts/models.gd`, `viewmodel.gd`, `combat_view.gd`, `showcase.gd`: gun models (toon look,
  smooth-normal outline shells), the first-person gun and its muzzle effects (its own SubViewport),
  world effects (port of `fx.js`: projectiles, tracers, bullet holes, explosions, gun toss), and the
  lobby's 3D stage (`show_character`). `particles.gd` is the pooled particle system (`particles.js`).
- `assets/fx/*.png` are baked by `tools/make_fx_textures.gd` (needs a renderer: run it under Xvfb).
  `assets/fonts/Bangers-Regular.ttf` (OFL) is the comic-word font.
- `scripts/sound.gd` plays `assets/sounds/*.wav`, which `tools/make_sounds.gd` bakes from the web
  game's `sound.js` synth recipes (runs headless). Variants are `name_1.wav`, `name_2.wav`...
- `scripts/trial.gd` (time trial logic, port of `trial.js`; records in `user://trials.cfg`) and
  `trial_view.gd` (portals, timer board, banners). The course, portals and trial settings are in
  `maps/dev_map.tscn` (the MapTrial node and MapPortals).
- Multiplayer (port of the web game's `src/net.js` + `server/server.js`):
  `scripts/match_server.gd` (MatchServer: every player's PlayerSim + Combat on the host, one step
  per input, lag compensation, damage/kills/respawns/regen, snapshots and events; no sockets, so
  tests drive it directly), `scripts/net.gd` (Net: ENet host/join, RPCs, input resend, snapshot
  interpolation, ping; lives under the tree root so it survives reloading into the host's map),
  `scripts/net_codec.gd` (byte packing; inputs and your own state stay 64-bit so prediction
  matches exactly), `scripts/remote_view.gd` (other players' beans), `scripts/online_hud.gd`
  (health, kill feed, scoreboard, death screen). main.gd does prediction + reconciliation
  (`_online_tick`, `_reconcile`) and handles host events. `PlayerSim.save_state/load_state` and
  its impulse log exist for this. Anything that changes the player's state on the host but not
  on their screen (like resetting their guns) makes the two drift: keep them in step.
- Enemies: `scripts/enemies.gd` (Enemies: logic for the 9 types in `TYPES` / `FAMILIES`,
  attacks, enemy projectiles, hurting the player; they update at 60 Hz, 30 past `LOD_FAR`, staggered,
  to keep crowds cheap (timings are in seconds); ground types move with PlayerSim, flyers steer
  and get pushed out of walls; each enemy is a Combat target of kind "enemy" so the guns hit it),
  `scripts/enemy_view.gd` (models, health bars, "!" windups, lasers/beams/rings/shots),
  `scripts/admin_console.gd` (F10: spawn/killall/god/heal/freeze/list; `parse_spawn`). main.gd
  ticks enemies after the player (not on time trials) and runs solo health (`_tick_health`).
  Fair-play rules for every attack are in the enemies.gd header; `tests/enemy_test.gd` checks
  them, so keep it passing when adding or tuning enemies.
- Items: `scripts/upgrades.gd` (Upgrades: the 34 items in `LIST`, stacks, and every effect;
  Combat owns one as `combat.up` and calls its hooks: fire_dirs, modify_damage, on_hit, on_kill,
  on_hurt from Enemies.hurt_player, tick). Damage has a source: "gun" procs items, "dot" and
  "item" don't (no endless chains). Statuses live on `Combat.Target.status`; Enemies slows or
  stops them via `Upgrades.time_scale`; `scripts/status_fx.gd` draws them on enemies and dummies;
  `scripts/item_hud.gd` is the item bar + pickup banner. PlayerSim has `speed_mult`,
  `extra_wall_jumps`, `air_jumps` whose defaults change nothing (compare.gd must keep passing).
  With no items every hook is a no-op. F10: give/take/items/clearitems + item buttons.
  `tests/item_test.gd` checks every item.
- Loot: `scripts/loot.gd` (Loot: gold per kill from `Enemies.deaths`, chests with costs and rarity
  odds on a random pick of the map's MapChest spots, drops that hop out, land, float and get picked
  up; ticked after the enemies), `scripts/loot_view.gd` (chest models, price tags, dropped items in
  the BinbunVFX floating loot effects from `assets/fx/GodotLootVFX`), `scripts/map/map_chest.gd`
  (chest spots in the editor). E ("interact") opens a chest. `tests/loot_test.gd` checks it.
- `scripts/map_data.gd`: loads map scenes (and map JSON) and does collision (matches `world.js`).
  `nearby()` looks boxes up in an 8 m grid but returns exactly what a full scan would, in map order;
  `ray_boxes()` walks a ray through that grid (Combat.raycast uses it when `combat.grid` is set,
  Enemies always). `max_physics_steps_per_frame` is 5 so a slow frame can't snowball.
- `scripts/world_view.gd`: map meshes, jump pads, bean dummies, clouds.
- `scripts/menu.gd`, `ui_style.gd`, `hud.gd`, `settings.gd`: menus, styling, HUD, saved settings
  and keybinds. The main screen is a Risk of Rain style column (singleplayer, multiplayer,
  practice, settings, quit). `scripts/lobby_screen.gd` is the lobby (character select, players,
  ready). `scripts/loading_screen.gd` is the loading card: it lives under the tree root, loads the
  stage's files on a thread, and stays up across the reload; main.gd's `_ready` yields a frame
  between build steps while it's up (`_step`), and `pending_run` says what to do after the reload
  (solo run / online run / practice). Runs and practice always go through `_load_into`.
- `shaders/`: toon shading, sky, clouds.
- `tests/compare.gd`: replays web-game movement (`tests/traces.json`) and checks every tick, on the
  frozen original maps in `tests/maps/*.json` (so map edits don't break it). The combat and trial
  logic tests use those too; `tests/map_test.gd` checks the map scenes (spawns, ramps, the collision grid, every launcher lands).
  `tests/menu_test.gd` clicks through the menus headless. `tests/combat_test.gd` checks the guns,
  `tests/trial_test.gd` the time trial, `tests/sound_test.gd` the sounds, `tests/net_test.gd`
  multiplayer (codec, server matches prediction, combat, lag comp, a real ENet host + client),
  `tests/enemy_test.gd` the enemies (fairness, every type, console parsing), `tests/item_test.gd`
  the items, `tests/loot_test.gd` gold, chests and drops.

## Rules

- Movement must stay identical to the web game. After touching `player_sim.gd`, `cfg.gd` or
  collision in `map_data.gd`, run `tests/compare.gd`; it must pass. One deliberate difference: in
  the air, moving uphill into a ramp rides up onto it (the web game teleports you to the ramp's
  low end); see `PlayerSim._move_horizontal` and the ramp check in `tests/map_test.gd`.
- After touching combat, items or menus, run `tests/combat_test.gd`, `tests/item_test.gd` and `tests/menu_test.gd` (and
  `tests/trial_test.gd` / `tests/sound_test.gd` for those areas). After touching multiplayer,
  PlayerSim or Combat, run `tests/net_test.gd`.
- Don't regenerate traces: `tools/make_traces.mjs` needs the web project next to this folder.
- Style: a `##` doc comment at the top of each script, typed GDScript, short comments that
  explain why.
- Update README.md ("What's in" and "Next") when a feature lands.
- Commit and push as you go.
- Never claim something is tested unless the test actually ran. If the network blocks the Godot
  download below, say so.

## Running Godot in the cloud container

The container has no Godot. Download the Linux build into the scratchpad:

```
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.6.2-stable/Godot_v4.6.2-stable_linux.x86_64.zip
unzip godot.zip
```

Then, from the repo root (import once so class_name scripts resolve):

```
godot --headless --path . --import
godot --headless --path . --script res://tests/compare.gd
godot --headless --path . --script res://tests/menu_test.gd
godot --headless --path . --script res://tests/combat_test.gd
godot --headless --path . --script res://tests/trial_test.gd
godot --headless --path . --script res://tests/sound_test.gd
godot --headless --path . --script res://tests/map_test.gd
godot --headless --path . --script res://tests/net_test.gd
godot --headless --path . --script res://tests/enemy_test.gd
godot --headless --path . --script res://tests/item_test.gd
godot --headless --path . --script res://tests/loot_test.gd
```

To try two real games against each other, start one with `-- --host=7777` and another with
`-- --join=127.0.0.1:7777` (both work headless too).

Headless runs draw nothing. To see the game, render under Xvfb (it falls back to OpenGL, so the
lighting differs a little from Forward+ on Windows) and use the `--shot` flag:

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 -- --screen=maps --shot=/tmp/s.png --frames=90
```

## Roadmap

1. ~~Guns and abilities~~ (done: guns, abilities, gun models, combat HUD, loadout screen).
2. ~~Bean dummies take damage~~ (done: damage, hit flash, health bars, damage numbers).
3. ~~Cartoon effects and sounds~~ (done).
4. ~~Time trial~~ (done: guns off and guns on). ~~Risk of Rain style menus~~ (done: characters,
   lobby, loading screen).
5. Roguelite: ~~enemies~~ (9 types + F10 admin console), ~~stage 1 map~~ (Sunstone Valley),
   ~~stacking items~~ (34, F10 give), ~~gold + chests~~, spawn director, run over on death, teleporter/boss/next stage, more stages, character passives.
6. ~~Multiplayer~~ (first version done: host/join, FFA, prediction, lag compensation). Later:
   teams, match rules, dedicated server.
