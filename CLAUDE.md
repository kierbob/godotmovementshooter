# Movement Shooter (Godot) — notes for Claude

A Godot 4.6 port of a web movement shooter (the web project, `../movement-shooter`, is NOT in this
repo). Single player for now; multiplayer later. The owner plays on Windows (`play.bat`, F5 in the
editor) and works on the game in Claude Code cloud sessions.

## Layout

- `scripts/main.gd`: game entry. Builds the map, runs the 120 Hz fixed-tick sim, camera
  interpolation, menu/playing/paused state. Has CLI flags for testing (`--map=`, `--at=`, `--screen=`,
  `--shot=`).
- `scripts/player_sim.gd`: movement sim, a line-for-line port of the web game's `src/player.js`.
  It uses plain 64-bit floats on purpose (Vector3 is 32-bit). **Don't "clean it up" into Vector3.**
- `scripts/cfg.gd`: all movement tuning, copied 1:1 from the web game's `src/config.js`.
- `scripts/cmd.gd`: one tick of input as plain data (network-ready). It already has
  fire/reload/ability/slot/cycle fields for combat.
- `scripts/map_data.gd`: loads map JSON (`data/*.json`) and handles collision (mirrors `src/world.js`).
- `scripts/world_view.gd`: builds visuals from MapData (merged meshes per color, pads, bean
  dummies, clouds).
- `scripts/menu.gd`, `ui_style.gd`, `hud.gd`, `settings.gd`: menus, styling, HUD, saved settings
  and keybinds (InputMap).
- `shaders/`: toon, sky, cloud.
- `tests/compare.gd`: replays `tests/traces.json` (recorded from the web game by
  `tools/make_traces.mjs`) and checks the port matches every tick. `tests/menu_test.gd` clicks
  through the menus headless.

## Rules

- Keep movement identical to the web game. After any change that touches `player_sim.gd`,
  `cfg.gd` or `map_data.gd` collision, run
  `godot --headless --path . --script res://tests/compare.gd`. It must pass.
- The cloud container has no Godot installed. Before testing, try downloading the Godot 4.6.2
  Linux build (`Godot_v4.6.2-stable_linux.x86_64.zip` from the godotengine/godot GitHub
  releases). If the network blocks that, say so and don't claim anything was tested.
- `tools/make_traces.mjs` needs the web project, which isn't here. Don't regenerate traces.
- Match the existing code style: a `##` doc comment at the top of each script, typed GDScript,
  short comments that explain *why*.
- Update README.md ("What's in" / "Next") when a feature lands.

## Roadmap (from README "Next")

1. Guns and abilities: primary and secondary weapon, fire, reload, ability on Q. The binds
   already exist in `settings.gd`.
2. Bean dummies take damage (PlayerSim already has hp/max_hp/dead).
3. Cartoon effects and sounds.
4. Bot Arena mode, time trial mode.
5. More menus and settings polish.
6. Later: multiplayer. `Cmd` is already plain data for this.
