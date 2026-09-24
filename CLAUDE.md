# Movement Shooter (Godot) — notes for Claude

Godot 4.6 port of the web movement shooter. Read README.md first, then the scripts.
Single player for now, multiplayer later. The owner plays on Windows (`play.bat` or F5 in Godot)
and works on the game in Claude Code cloud sessions.

## The web game

The original lives in the public repo `kierbob/MovementShooter` (not in this repo). Clone it
read-only for reference: `git clone --depth 1 https://github.com/kierbob/movementshooter`.
Useful files: `src/items.js` (weapon/ability data), `src/combat.js`, `src/hud.js`, `src/player.js`,
`src/config.js`, `src/world.js`.

Port only what the current step needs, not the whole web game. Guns, gun models, the combat HUD,
the loadout screen, the cartoon effects, sound and the time trial are in; bots come later, in their
own step.

## Files

- `maps/*.tscn`: the maps, edited in the Godot editor. Node scripts in `scripts/map/` (@tool):
  MapRoot, MapBox (solid box; exact edges in `box`, or web-editor numbers in `web_box`), MapVolume
  (trigger box), MapPad, MapSpawn, MapTarget, MapPortal, MapTrial, MapBoard. The exact 64-bit
  values are the truth; the node transform (32-bit) mirrors them and edits write back rounded to
  the millimeter. Only store short decimals: Godot misreads some 17-digit numbers from scenes.
  `MapData.load_map(id)` reads a map scene; `MapConvert` / `tools/json_to_map.gd` make one from a
  map JSON. Maps: `dev_map` (web dev arena + time trial) and `bean-town` (Nuketown-style FFA,
  grouped by place; the yellow half mirrors the blue half through the center). A box's `kind` is
  its color from `WorldView.COLORS` (add new kinds there and to MapBox's enum).
- `scripts/main.gd`: game entry. Builds the map, runs the sim at a fixed 120 ticks/s, moves the
  camera between ticks, switches menu/playing/paused. Test flags: `--map=`, `--at=`, `--screen=`, `--shot=`.
- `scripts/player_sim.gd`: the movement, line for line from the web game's `src/player.js`. It uses
  plain 64-bit floats on purpose (Vector3 is 32-bit). Do NOT refactor it to Vector3.
- `scripts/cfg.gd`: every movement number, 1:1 from the web game's `config.js`.
- `scripts/cmd.gd`: one tick of input as plain data (network-ready for multiplayer), including
  fire/reload/ability/slot/cycle.
- `scripts/items.gd`: weapon + ability data, 1:1 from `items.js`, plus loadout-screen stats.
- `scripts/combat.gd`: guns, projectiles, damage and knockback (port of `combat.js`, no bots yet).
  Ticks before `player.step`, like the web game. Uses Vector3 (spread is random, so no bit-exact
  match needed); knockback goes through `PlayerSim.apply_impulse`.
- `scripts/models.gd`, `viewmodel.gd`, `combat_view.gd`, `showcase.gd`: gun models (toon look,
  smooth-normal outline shells), the first-person gun and its muzzle effects (its own SubViewport),
  world effects (port of `fx.js`: projectiles, tracers, bullet holes, explosions, gun toss), and the
  loadout 3D stage. `particles.gd` is the pooled particle system (`particles.js`).
- `assets/fx/*.png` are baked by `tools/make_fx_textures.gd` (needs a renderer: run it under Xvfb).
  `assets/fonts/Bangers-Regular.ttf` (OFL) is the comic-word font.
- `scripts/sound.gd` plays `assets/sounds/*.wav`, which `tools/make_sounds.gd` bakes from the web
  game's `sound.js` synth recipes (runs headless). Variants are `name_1.wav`, `name_2.wav`...
- `scripts/trial.gd` (time trial logic, port of `trial.js`; records in `user://trials.cfg`) and
  `trial_view.gd` (portals, timer board, banners). The course, portals and trial settings are in
  `maps/dev_map.tscn` (the MapTrial node and MapPortals).
- `scripts/map_data.gd`: loads map scenes (and map JSON) and does collision (matches `world.js`).
- `scripts/world_view.gd`: map meshes, jump pads, bean dummies, clouds.
- `scripts/menu.gd`, `ui_style.gd`, `hud.gd`, `settings.gd`: menus, styling, HUD, saved settings
  and keybinds (combat keybinds already exist).
- `shaders/`: toon shading, sky, clouds.
- `tests/compare.gd`: replays web-game movement (`tests/traces.json`) and checks every tick, on the
  frozen original maps in `tests/maps/*.json` (so map edits don't break it). The combat and trial
  logic tests use those too; `tests/map_test.gd` checks the map scenes.
  `tests/menu_test.gd` clicks through the menus headless. `tests/combat_test.gd` checks the guns,
  `tests/trial_test.gd` the time trial, `tests/sound_test.gd` the sounds.

## Rules

- Movement must stay identical to the web game. After touching `player_sim.gd`, `cfg.gd` or
  collision in `map_data.gd`, run `tests/compare.gd`; it must pass.
- After touching combat or menus, run `tests/combat_test.gd` and `tests/menu_test.gd` (and
  `tests/trial_test.gd` / `tests/sound_test.gd` for those areas).
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
```

Headless runs draw nothing. To see the game, render under Xvfb (it falls back to OpenGL, so the
lighting differs a little from Forward+ on Windows) and use the `--shot` flag:

```
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 -- --screen=loadout --shot=/tmp/s.png --frames=90
```

## Roadmap

1. ~~Guns and abilities~~ (done: guns, abilities, gun models, combat HUD, loadout screen).
2. ~~Bean dummies take damage~~ (done: damage, hit flash, health bars, damage numbers).
3. ~~Cartoon effects and sounds~~ (done).
4. Bot Arena mode (still to do) and a time trial mode (done: guns off and guns on).
5. More menu and settings polish.
6. Later: multiplayer.
