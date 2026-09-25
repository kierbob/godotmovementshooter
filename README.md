# Movement Shooter (Godot)

Godot 4.6 port of the web game (`../movement-shooter`). Play solo, or online with friends (one of
you hosts, see "Playing online").

## Play

- Double-click `play.bat` (uses `Downloads\Godot_v4.6.2-stable_win64.exe\...`), or
- open this folder in Godot 4.6 and press **F5**.

**Staying up to date without re-downloading:** get the game once as a git clone instead of a zip
(GitHub Desktop: File → Clone repository → `kierbob/godotmovementshooter`, or
`git clone https://github.com/kierbob/godotmovementshooter`). After that `play.bat` pulls the
latest version by itself before it starts (or press **Fetch origin → Pull origin** in GitHub
Desktop): only what changed comes down, and Godot keeps its imported assets instead of importing
everything again.

The game is heading toward a Risk of Rain style roguelite (runs over several stages, enemies,
items that stack). The menus already work that way:

- **SINGLEPLAYER** → the lobby: pick your character (Brawler, Bomber, Sharpshooter, Commando; each is a
  fixed kit), press **READY** → the loading screen → stage 1, Sunstone Valley: survive 8 waves,
  kill the boss, and on to the next stage (see "A run").
- **MULTIPLAYER**: greyed out for now (the code is there, parked while the solo game comes
  together).
- **PRACTICE** → the Dev Arena (free play with the dummies) and the two **time trials** (guns
  off / guns on); in the Dev Arena you can walk into their portals too.
- **F10** opens the admin console (see "Enemies").
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
| E | open a chest |
| K | respawn (on the time trial: restart the run; not online) |
| Tab | scoreboard (online, hold) |
| Esc | pause menu |
| F2 | next map (dev shortcut) |
| F4 | stats panel (full / compact / off) |
| F10 | admin console (spawn enemies, god mode...) |
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
  - **Sunstone Valley** (stage 1): a big valley (about 240 x 240 m, 8x Bean Town) walled in by
    cliffs, with a set piece in every direction:
    - **Center, the Sunstone Ruins**: a stepped plaza with four 22 m pillars holding up a crown
      you can walk around, a gold platform floating above it and a giant gem above that (you can
      see it from anywhere). Pads chain you up: ground → pillar ledge → crown → Sunstone.
    - **North, the highlands**: a plateau 10 m up with two ramps (slide down them), a cave with a
      chamber and a skylight pad up through the roof, and three mesas (18, 28 and 18 m) with a
      sky bridge across and launch pads between them.
    - **East, the canyon**: 10 m deep. Slide in down the north ramp; a stone bridge, a broken
      bridge you jump, ramps and pads out, launchers that fling you across, a grotto at the end.
    - **South, the ridge**: 20 m up, with a ski slope down into the valley (slide it for speed)
      and a kicker at the bottom that throws you into the air.
    - **West, the old fort**: walls you can walk along (stairs inside), two towers with pads up,
      a ruined keep, breaches and a gate.
    - **Around**: four floating sky isles (a pad up to each, a cannon from each to the crown),
      trees, boulders and sunstone shards.
  - **Fantasy Village** (stage 2): a big medieval town (320 x 320 m, about 1.8x Sunstone Valley)
    built from the Medieval Village MegaKit (Quaternius, CC0, `assets/VillageFBX`): about 80
    timber-framed houses put together from the kit's walls, corners, windows (with glass and
    shutters), doors, chimneys, gables and tiled roofs, 6,800 pieces in all. Every roof is two
    steep ramps you can run up. The kit comes without its textures, so each of its materials gets
    a toon color (terracotta tiles, cream plaster, brown timber, grey-blue stone).
    - **Center, the market square**: cobbles, a clock tower (a pad at its foot up the wall onto
      its top, a belfry and spire above), a well, wagons and crate stacks, houses all around.
    - **North-east, the old town**: up on a 6 m stone plateau (a grand staircase from the square
      side, a long ramp from the north road, a launcher): tight lanes between 2-3 story houses,
      and the guildhall with a golden chest spot on its ridge.
    - **West, the river**: a sunken channel with water, a stone bridge on the west road and two
      wooden ones, ramps out of the water, and a hamlet on the far bank.
    - **North-west, the castle**: terraces up to a keep with battlements (a pad up its wall) and
      a watchtower.
    - **East, the chapel**: a long chapel with a bell tower, a walled graveyard with a shrine.
    - **South, the farms**: fields in rows, fences, hay, wagons and a big barn.
    - Hills all the way around, trees, 40 chest spots (tower tops, the keep, rooftops, alleys).
    `tools/make_village.gd` builds it (re-running it overwrites the scene).
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
  Knife), Commando (Pulse Rifle, Deagle, Combat Dash: 22 m/s wherever you look plus a hop, on the
  ground or in the air, every 3.5 s). Picked in the lobby, shown on a 3D stage in their color;
  saved with your settings.
- **Levels**: kills give XP (the same as their gold); each level is +10% damage, +12 max health and
  a full heal ("LEVEL UP!", a gold ring). Your level and XP bar sit over your health.
- **Lobby and loading screen**: Risk of Rain style. Everyone ready → (online: a 3 s countdown) →
  a loading card with the stage number, name, progress and tips, which stays up while the stage
  loads and, online, until everyone has loaded.
- **A run** (see "A run" below): 8 waves that get bigger and tougher (enemies find their way to
  you around walls and up to ledges, never spawn inside anything, and the last few of a wave are
  marked on screen), then the Colossus boss;
  kill it and the stage is cleared (a rare or legendary drop, 12 s to grab loot), then the loading
  screen and the next stage with your items, level and gold. Die and the run is over (a results
  screen: TRY AGAIN / MAIN MENU).
- **Enemies** (see "Enemies" below): 9 types in 3 families plus the Colossus boss, with solo
  health and regen (practice respawns you; a run doesn't).
- **Gold and chests** (see "Items" below): kills pay gold, chests around the stage cost gold, and
  an opened chest throws out an item that floats in a glow of its rarity's color until you walk
  into it.
- **Items** (see "Items" below): 40 stacking items in three rarities: status effects (burn, bleed,
  chill/freeze, marks, sticky bombs), chain lightning, kill explosions, Triple Tap's V of shots,
  movement items (speed, wall jumps, air jumps, Slide Spikes, Stomp Boots), an item bar and pickup
  banner on the HUD.
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

## Enemies

`scripts/enemies.gd` (logic), `scripts/enemy_view.gd` (looks). Three families, three variants each:

| Family | Variant | What it does |
| --- | --- | --- |
| Runner | **Charger** | walks up, winds up (0.65 s), then dashes where you were; side-step it |
| Runner | **Brute** | slow and tanky (400 HP), winds up 1.1 s, slams: a shockwave rolls out along the ground; jump it |
| Runner | **Swarmer** | small, 30 HP, nips at you in packs (6 m/s: slower than you walk) |
| Shooter | **Gunner** | keeps its distance, 3-shot bursts of slow shots |
| Shooter | **Lobber** | arcing grenades that land where you stood (a red ring marks the spot) |
| Shooter | **Sniper** | a faint red laser tracks you, turns bright white when it locks, then fires: move after the lock (only the 3 nearest tracking lasers are drawn, so a crowd of snipers doesn't fill the screen with lines) |
| Flyer | **Projectile** | circles you and fires dodgeable orbs |
| Flyer | **Beam** | Moira-style lock-on beam up close; breaks if you get out of range or behind cover |
| Flyer | **Healer** | never hurts you; heals the most hurt enemy with a green beam (never another healer), runs from you |

Fair-play rules every attack follows (tests/enemy_test.gd checks them): a visible windup (red
"!", glow, a click) of at least 0.25 s before anything can hurt you, no attack without line of
sight, shots aimed where you are (never led) and slow enough to dodge. You have 100 HP,
regenerate 3 s after the last hit. In practice you get back up 2.5 s after being splatted (1.5 s
of spawn protection); in a run, being splatted ends it.

**The Colossus** (the boss, 2500 HP, 2.6 m tall with a gold crown) rotates three attacks, each
with its own windup: a **slam** when you're close (a big shockwave ring rolls out 24 m: jump it),
a **volley** of 7 slow orbs in a fan when you're not, and every third attack it **summons** 4
swarmers.

Flyers hover 2.5-8 m over the ground (or over you, if you're up high). Big crowds stay cheap:
enemies think and move 60 times a second (30 once they're 40 m away) instead of every 120 Hz
tick, rays (line of sight, the ground under a flyer, bullets) only test the map boxes along their
path, and far enemies drop their small details and particles. 80 enemies cost about 2 ms of sim
per tick.

**Admin console (F10):** buttons for every enemy (x1 / x3 / x5, or ANY of a family) and GOD /
FREEZE / HEAL / KILL ALL, next to a text bar that takes the same as commands: `spawn flyer beam`,
`spawn beam`, `spawn swarmer 5`, `spawn runner` (a random runner), `killall`, `god [on/off]`,
`heal`, `freeze [on/off]` / `unfreeze`, `list`, `help`. Up/Down recalls what you typed. Enemies
spawn 12 m in front of you, facing you (or the nearest spot they fit, if that's inside something). The console gives items too (see "Items"). In a run:
`wave <n>` (skip to wave n), `boss` (straight to the boss), `nextstage` (clear the stage now),
`levelup [n]`, `chest <kind>`.

## A run

`scripts/director.gd` (the waves and the boss), `scripts/run_hud.gd` (the wave counter, banners,
boss bar and results). Each stage:

1. 5 s to look around, then **wave 1**. A wave has a budget (28 at wave 1, +10 a wave, x1.5 a
   stage) spent on enemies by cost (swarmers 2 each in packs of 3, chargers and gunners 4, lobbers
   and projectile flyers 5, snipers and beam flyers 6, healers 7, brutes 10). New types unlock as
   the waves go by: lobbers and projectile flyers at wave 2, snipers and beam flyers at 3, brutes
   at 4, healers at 5.
2. They arrive in groups of 1-3 over the first seconds of the wave, 16-34 m from you, at most 36
   alive at once. Each one appears on a spot of its own on the nav grid (below) with room for its
   whole body (a brute or the Colossus needs more), on ground that can walk to you: never inside a
   wall, a rock or a tree, never on a tree top or a ledge it can't get down from. The HUD says
   `WAVE 3 / 8` and how many are left; the wave ends when all of it is dead, then a 7 s break.
   **The last 5 of a wave are marked**: a red marker over each one, seen through walls, with how
   far it is; off screen, an arrow on the edge of the screen points to it. The boss gets a gold
   one. A wave enemy that hasn't seen you for 25 s (stuck, or lost somewhere) is brought back
   16-34 m from you, so a wave never hangs on one you can't find.
3. Every wave is tougher (+15% health, +6% damage a wave); every stage more so (+60% health, +30%
   damage), and pays more (+50% gold, and chests cost 50% more).
4. After wave 8: **BOSS INCOMING**, and the Colossus lands near you with a health bar across the
   top of the screen.
5. Kill it: **STAGE CLEARED**, it drops a rare (or, 35% of the time, a legendary) item, and 12 s
   later the loading screen takes you to the next stage. Items, level, XP, gold, kills and time
   carry over; you arrive at full health.

**Pathfinding** (`scripts/nav.gd`): when a stage loads, a grid of standing spots 1.5 m apart is
built over it (the tops of boxes and ramps where a body fits, about 30,000 on Sunstone Valley and
46,000 on the Fantasy Village, in
under a second on a worker thread behind the loading screen), linked where you can walk, step,
jump (up to 1 m), drop (up to 10 m) or ride a launch pad. A ground enemy that sees you with flat
ground between you walks straight at you; otherwise it follows a path from Godot's AStar3D
around walls, up ramps, off ledges and over pads (a new one about every second; a path costs a
fraction of a millisecond). Paths never cut corners over a drop. When you're somewhere it can't
reach, it goes as close as it can get. Flyers fly straight at you as before.

Stages are listed in `Characters.STAGES`: Sunstone Valley, then the Fantasy Village. After stage 2
it loops back to Sunstone Valley for now (harder every stage) until there are more.

## Items

`scripts/upgrades.gd` (the list and what they do), `scripts/status_fx.gd` (statuses on beans),
`scripts/item_hud.gd` (the item bar and pickup banner). Risk of Rain style: 34 items in three
rarities plus 6 legendaries, every one stacks.

**Getting them** (`scripts/loot.gd`, `scripts/loot_view.gd`): every kill pays gold (a swarmer $3,
most enemies $7-10, a brute $18; shown top right). Each run fills 18 of the stage's chest spots,
some out in the open, some as rewards up high (the crown, the Sunstone, the mesa tops, the sky
isles, the fort towers) or tucked away (the cave chamber, the canyon grotto), and puts barrels on
8 of the rest. **Every cleared wave drops an item** in front of you too, better the later the
wave (waves 1-2: mostly uncommon; 3-5: uncommon or rare, sometimes legendary; 6-8: mostly rare,
10% legendary). Walk up to a chest and press **E**:

| What | Cost | Inside |
| --- | --- | --- |
| Chest (wood) | $25 | 60% common, 33% uncommon, 7% rare |
| Large Chest (purple) | $50 | 60% uncommon, 37% rare, 3% legendary |
| Golden Chest (in a pillar of gold light) | $150 | always a **legendary** |
| Damage / Utility / Healing Chest (red / blue / green) | $30 | only that kind of item: guns and damage, movement and kills, or staying alive |
| Terminals (three in a row, each showing its item) | $35 | buy the one you want; the other two shut |
| Shrine of Chance | $20, then more each try | 45%: an item; otherwise nothing. Two gifts, then it's spent |
| Barrel | free | smash it for a little gold |

Opening one shoots a beam of the item's rarity color into the sky (a rare shouts "RARE!", a
legendary "LEGENDARY!!"); the item hops out toward you and floats in the loot glow for its rarity
(white, green, red, gold: the BinbunVFX loot pack in `assets/fx/GodotLootVFX`); walk into it to take
it. Chest spots are MapChest nodes (under `Chests` in the map): move them, add more, and set `size`
(any rolls it; or small, large, golden, damage, utility, healing, shop, shrine).

| Rarity | Item | One of them | More of them |
| --- | --- | --- | --- |
| Common | Running Shoes | run 10% faster | +10% |
| Common | Wall Grips | +1 wall jump before you land | +1 |
| Common | Extended Mag | +25% magazine | +25% |
| Common | Quick Hands | reload 15% faster | +15% |
| Common | Hair Trigger | fire 12% faster | +12% |
| Common | Lucky Penny | 10% crit chance (double damage) | +10% |
| Common | Point Blank | +25% damage within 7 m | +25% |
| Common | Opening Act | +50% damage to enemies above 90% health | +50% |
| Common | Match Head | 10% chance to set them on fire (3 s) | +10% |
| Common | Rusty Nail | 10% chance to make them bleed (bleeds stack) | +10% |
| Common | Vampire Fangs | heal 2 per hit | +2 |
| Common | Tough Skin | +25 max health | +25 |
| Common | Bubble Wrap | 12% chance to block a hit | more (never 100%) |
| Common | Adrenaline | kills: 30% faster for 2 s | +1 s |
| Common | Sticky Bomb | 8% chance to stick a bomb on them (180%) | +8% |
| Common | Knockout Glove | hits knock enemies back (each one at most every 0.6 s, so a shotgun blast shoves once; brutes half as far, bosses not at all) | harder |
| Uncommon | Frost Tip | hits chill (half speed); keep hitting to freeze; frozen ones shatter below 25% | freezes sooner |
| Uncommon | Static Coil | 20% chance: lightning to 3 nearby enemies for 60% | +2 targets |
| Uncommon | Party Popper | enemies explode when they die | bigger, harder |
| Uncommon | Speed Loader | kills refill your gun | 2+: both guns |
| Uncommon | Recharger | kills take 1 s off your ability | +1 s |
| Uncommon | Sky Striker | +30% damage in the air | +30% |
| Uncommon | Momentum Engine | +3% damage per m/s over a run | +3% |
| Uncommon | Headhunter | headshots +40% | +40% |
| Uncommon | Spring Heels | +1 jump in mid-air | +1 |
| Uncommon | Slide Spikes | slide into enemies: 40 damage, launches them | +30 |
| Uncommon | Razor Wire | getting hurt lashes 3 enemies nearby for 25 | +2 targets, +15 |
| Uncommon | Ricochet | 25% chance a bullet off a wall bounces into the nearest enemy | +25% |
| Uncommon | Tracker Dart | hits mark for 4 s: +20% damage from everything | +20% |
| Rare | Triple Tap | every shot and throw fires 2 extra copies in a V (a rocket V!) | +2 copies |
| Rare | Big Bang | every hit explodes for 60% | +1 m radius |
| Rare | Stomp Boots | landing from a big fall slams the ground (faster = harder) | +50%, +1 m |
| Rare | Wisp Jar | kills release 2 wisps that hunt enemies for 40 each | +1 wisp |
| Rare | Four Leaf | every chance rolls twice | +1 reroll |
| Legendary | Drone Buddy | a drone orbits you and shoots enemies (12 a shot, 4 a second) | +1 drone |
| Legendary | Orbital Strike | every 6 s a laser from the sky hits the toughest enemy near you for 250 | 1 s sooner |
| Legendary | Hydra Launcher | every 5th shot also fires 4 homing missiles | +2 missiles |
| Legendary | Singularity | 10% chance on hit: a black hole drags enemies in, grinds them, implodes for 120 | +5% |
| Legendary | Phoenix Feather | the hit that would kill you doesn't: back up at half health | +1 life |
| Legendary | Glass Cannon | double damage, half max health | again |

How they work together: only your guns' own hits (bullets, rockets, knives, Slide Spikes) roll
the "on hit" items; burn/bleed ticks, lightning, item explosions and wisps don't, so chains can't
run forever (kill effects still chain: a Party Popper kill can pop the next one). Triple Tap's
copies do damage but don't push you (a rocket jump is the same height with or without it).
Statuses show on the bean: burning (orange, flames), bleeding (drips), chilled (blue, snow),
frozen (an ice block, "FROZEN!"), marked (a red ring over its head, seen through walls), a
blinking sticky bomb. Damage numbers tell the sources apart: big orange "!" crits, small orange
burn, dark red bleed, light blue item damage. They work on the practice dummies too.

**Console:** `give triple tap 3`, `give random 5`, `take <item>`, `items` (what you carry),
`items all` (every item), `clearitems`; or the item buttons under the text bar (hover for the
name; the x1 / x3 / x5 count applies). `gold [amount]` (+100 GOLD button), `chest [small|large]`
(CHEST button) puts one right in front of you (`chest golden`, `chest shop`, `chest shrine`...),
`levelup [n]` gains levels.

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

Open a map in `maps/` (`dev_map.tscn`, `sunstone-valley.tscn`, `bean-town.tscn`) in the Godot editor. Every piece is a node:

- **MapBox**: a solid box. Move it and scale it with the normal gizmos (position = center, scale =
  size in meters). In the Inspector: `kind` (its color: floor, wall, grass, road, house_blue,
  roof, bus...; the list is `WorldView.COLORS`; `barrier` is an invisible wall shots pass
  through; `hidden` is solid for everything but not drawn: the collision under a model) and `ramp`
  (a sloped top rising toward x+, x-, z+ or z-). Don't rotate boxes: collision is axis-aligned
  (the editor shows a warning if you do). Ctrl+D duplicates a box to make a new one.
- **MapPad**: jump pad (radius, launch speed, directional launchers). A pad throws you at most
  about 13 m up (the movement caps rising speed at 24 m/s), so anything higher needs a ledge on
  the way. Put a pad against a wall to slide up it and over the top (the top must not overhang).
- **MapModel**: a model placed in the map (`model`: a kit piece like
  `res://assets/VillageFBX/Wall_Plaster_Straight.fbx`, `yaw`, `size`). Looks only: put `hidden`
  boxes under it for collision. Every copy of a model is drawn in one batch in the game.
- **MapSpawn**: where you start; turn it to set which way you face. The first one is used.
- **MapTarget**: a bean dummy (optionally sliding back and forth).
- **MapPortal**: the hub portals to the time trial (guns on / off).
- **MapTrial** (Dev Arena): the course's Start, Exit portal, Finish zone and timer Board, plus the
  start line and fall-off height. The course itself is ordinary boxes under it.
- The root (**MapRoot**) holds the map's name and its card text and colors for the map screen,
  and `view_scale` (big maps push the distance haze out; Sunstone Valley uses 1.6).

Group nodes under plain Node3Ds however you like; moving a group moves everything in it. Bean
Town is grouped by place (`BlueHouse/Walls`, `BlueHouse/Roof`, `Street`, `BlueBackyard`...), and the
yellow side is the blue side turned around, so change both if you want it to stay fair. Save
(Ctrl+S) and press F5. Sunstone Valley is grouped the same way (`SunstoneRuins/Crown`,
`Highlands/Cave`, `Mesas/MesaWest`, `Canyon/StoneBridge`, `OldFort/Walls`, `SkyIsles/IsleNE`...);
when you move a platform, move the pads that throw you onto it too (`tests/map_test.gd` checks
every launcher still lands you on something). Positions snap to the millimeter; turn on Godot's grid snap for tidy
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
`tests/enemy_test.gd` checks every enemy plays fair (windups, line of sight, dodging, the beam
breaking, the healer only healing, guns killing them) and the console's commands.
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
godot --headless --path . --script res://tests/enemy_test.gd
```

## Next

The roguelite, in this order:

1. ~~Enemies~~ (done: 9 types, admin console). ~~Waves~~ (done: the director). Next: tuning from
   playtests.
2. ~~"Run over" when you die in a run~~ (done: the results screen).
3. ~~Stacking items~~ (done: 40 with 6 legendaries, see "Items"). ~~Gold, chests, shops, shrines,
   barrels~~ (done). ~~Levels~~ (done). Next: chest prices that rise over the run, equipment
   (an active item on a key), more items.
4. ~~Run structure~~ (done: 8 waves → the Colossus → stage cleared → the next stage). Next: the
   ~~Fantasy Village as stage 2~~ (done). Next: a boss per stage, stage 3.
5. More stages, character passives, unlocks. Multiplayer becomes co-op.
