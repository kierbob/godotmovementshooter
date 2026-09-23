# Movement Shooter (Godot) — notes for Claude

Godot 4.6 port of the web movement shooter. Read README.md first, then the scripts.
Single player for now, multiplayer later. The owner plays on Windows (`play.bat` or F5 in Godot).

## The web game

The original lives in the public repo `kierbob/MovementShooter` (not in this repo). Clone it
read-only for reference: `git clone --depth 1 https://github.com/kierbob/movementshooter`.
Useful files: `src/items.js` (weapon/ability data), `src/combat.js`, `src/hud.js`, `src/player.js`,
`src/config.js`, `src/world.js`.

Port only what the current step needs, not the whole web game. Right now that means the weapons
and the combat HUD. Bots, time trial, effects and sound come later, in their own steps.

## Files

- `scripts/main.gd`: game entry. Builds the map, runs the sim at a fixed 120 ticks/s, moves the
  camera between ticks, switches menu/playing/paused. Test flags: `--map=`, `--at=`, `--screen=`, `--shot=`.
- `scripts/player_sim.gd`: the movement, line for line from the web game's `src/player.js`. It uses
  plain 64-bit floats on purpose (Vector3 is 32-bit). Do NOT refactor it to Vector3.
- `scripts/cfg.gd`: every movement number, 1:1 from the web game's `config.js`.
- `scripts/cmd.gd`: one tick of input as plain data (already has fire/reload/ability/slot/cycle).
- `scripts/map_data.gd`: loads `data/*.json` maps and does collision (matches `world.js`).
- `scripts/world_view.gd`: map meshes, jump pads, bean dummies, clouds.
- `scripts/menu.gd`, `ui_style.gd`, `hud.gd`, `settings.gd`: menus, styling, HUD, saved settings
  and keybinds (combat keybinds already exist).
- `shaders/`: toon shading, sky, clouds.
- `tests/compare.gd`: replays web-game movement (`tests/traces.json`) and checks every tick.
  `tests/menu_test.gd` clicks through the menus headless.

## Rules

- Movement must stay identical to the web game. After touching `player_sim.gd`, `cfg.gd` or
  collision in `map_data.gd`, run `tests/compare.gd`; it must pass.
- Don't regenerate traces: `tools/make_traces.mjs` needs the web project next to this folder.
- Style: a `##` doc comment at the top of each script, typed GDScript, short comments that
  explain why.
- Update README.md ("What's in" and "Next") when a feature lands.
- Commit and push as you go.
- Never claim something is tested unless the test actually ran.

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
```

## Roadmap

1. Guns and abilities: primary and secondary weapon, fire, reload, ability on Q.
2. Bean dummies take damage (PlayerSim already has hp, max_hp, dead).
3. Cartoon effects and sounds.
4. Bot Arena mode and a time trial mode.
5. More menu and settings polish.
6. Later: multiplayer.
