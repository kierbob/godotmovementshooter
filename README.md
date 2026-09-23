# Movement Shooter (Godot)

Godot 4.6 port of the web game (`../movement-shooter`). Single player for now; multiplayer comes later.

## Play

- Double-click `play.bat` (uses `Downloads\Godot_v4.6.2-stable_win64.exe\...`), or
- open this folder in Godot 4.6 and press **F5**.

Main menu → pick a map → **Play**. **Esc** pauses (Resume / Settings / Main Menu / Quit).
Settings (mouse sensitivity + FOV, video, lighting, volume, every keybind) are saved to
`%APPDATA%/Godot/app_userdata/Movement Shooter/settings.cfg`.

| Key | Action |
| --- | --- |
| WASD | move |
| Shift | sprint |
| Space | jump / wall jump |
| C | slide |
| Ctrl | crouch |
| K | respawn |
| Esc | pause menu |
| F2 | next map (dev shortcut) |
| F4 | stats panel (full / compact / off) |
| F11 | fullscreen |

## What's in

- **Movement**: a line-for-line port of the web game's `src/player.js` (sprint, slide, wall jumps,
  ramps, jump pads, momentum), fixed 120 Hz ticks with smooth camera interpolation. Mouse look uses
  Godot's raw mouse input.
- **Maps**: the dev arena (exported from the web game) and Bean Street, loaded from the same JSON
  files the web editor makes (`data/`).
- **Look**: toon shading (3 light bands + sky/ground fill), Candy Pastel sky, clouds, shadows.

## Proving the movement matches the web game

`tools/make_traces.mjs` records 16 movement runs with the web game's real code (needs Node and the
web project next to this folder). `check-movement.bat` (or `tests/compare.gd`) replays them in Godot:
before every tick it copies the web game's exact player state, runs one tick, and compares.

```
node tools/make_traces.mjs
godot --headless --path . --script res://tests/compare.gd
```

`tests/menu_test.gd` clicks through the menus headless (play, pause, settings, rebinding, map switch).

## Next

Guns and abilities, dummies taking damage, cartoon effects and sounds, then Bot Arena, time trial,
menus and settings.
