// Records movement runs from the WEB game's real movement code (../movement-shooter/src) into
// tests/traces.json. tests/compare.gd replays the same inputs through the Godot port and checks
// every tick lands in the same place.
//   node tools/make_traces.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, '..', '..', 'movement-shooter', 'src');
const imp = (f) => import(pathToFileURL(join(web, f)).href);
const W = await imp('world.js');
const { createPlayer, stepPlayer, applyImpulse, snapshotState } = await imp('player.js');
const { TICK_DT } = await imp('config.js');

const E = Math.PI / 2;
const base = {
  forward: 0, right: 0, jump: false, jumpHeld: false, sprint: false, crouch: false, slide: false, slidePressed: false,
  fire: false, firePressed: false, reload: false, ability: false, slot: null, cycle: 0, yaw: 0, pitch: 0,
};

// brain(p, t, i) -> partial cmd. impulses: { tick: {x, y, z} } applied before that tick's step.
function record(name, map, start, secs, brain, impulses = {}) {
  const p = createPlayer(start);
  const ticks = [];
  const n = Math.round(secs * 120);
  for (let i = 0; i < n; i++) {
    const c = { ...base, ...brain(p, i * TICK_DT, i) };
    const im = impulses[i];
    if (im) applyImpulse(p, im, 'test');
    const before = snapshotState(p); // full state going into this tick (for one-tick checks)
    delete before.rampDown; // recomputed every tick
    for (const k of ['hp', 'maxHp', 'dead', 'regenDelay', 'invuln', 'state']) delete before[k];
    stepPlayer(p, c, W.BOXES, TICK_DT);
    const t = {
      s: before,
      c: [c.forward, c.right, +c.jump, +c.jumpHeld, +c.sprint, +c.crouch, +c.slide, +c.slidePressed, c.yaw],
      p: [p.pos.x, p.pos.y, p.pos.z, p.vel.x, p.vel.y, p.vel.z, +p.grounded],
    };
    if (im) t.imp = [im.x, im.y, im.z];
    ticks.push(t);
  }
  return { name, map, start: { x: start.x, y: start.y, z: start.z }, ticks };
}

// Deterministic pseudo-random inputs.
function randomBrain(seed) {
  let s = seed >>> 0;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  let cur = {};
  let yaw = 0;
  return (p, t, i) => {
    if (i % 30 === 0) {
      cur = {
        forward: rnd() < 0.8 ? 1 : rnd() < 0.5 ? 0 : -1, right: rnd() < 0.6 ? 0 : rnd() < 0.5 ? 1 : -1,
        sprint: rnd() < 0.7, crouch: rnd() < 0.1, slide: rnd() < 0.25, jumpEvery: 20 + Math.floor(rnd() * 60), turn: (rnd() - 0.5) * 4,
      };
    }
    yaw += cur.turn * TICK_DT;
    const jump = i % cur.jumpEvery === 0;
    return { forward: cur.forward, right: cur.right, sprint: cur.sprint, crouch: cur.crouch, slide: cur.slide,
      slidePressed: cur.slide && i % 30 === 0, jump, jumpHeld: jump, yaw };
  };
}

// Climb between two parallel walls (normal along `axis`) with wall jumps.
function chimneyBrain(axis, mid, towardLow, towardHigh) {
  return (p, t) => {
    const pos = axis === 'x' ? p.pos.x : p.pos.z;
    const aim = pos < mid ? towardLow : towardHigh;
    const touching = p.wallCoyote > 0 && p.wallNormal;
    const kick = touching && p.vel.y < 1.5;
    const n = p.wallNormal;
    const away = touching ? ((axis === 'x' ? n.x : n.z) > 0 ? towardHigh : towardLow) : aim;
    return { forward: 1, yaw: kick ? away : aim, jump: (p.grounded && t < 0.2) || kick, jumpHeld: true };
  };
}

const scenarios = [];

// ---------- dev map ----------
scenarios.push(record('dev: sprint, jumps, turning', 'dev_map', W.SPAWN, 6,
  (p, t, i) => ({ forward: 1, sprint: true, yaw: t * 0.8, jump: i % 84 === 0, jumpHeld: i % 84 < 10 })));
scenarios.push(record('dev: slide + slide jump', 'dev_map', { x: 0, y: 0, z: 30 }, 3,
  (p, t, i) => ({ forward: 1, sprint: true, yaw: 0, slide: i >= 110 && i < 200, slidePressed: i === 110, jump: i === 170, jumpHeld: i >= 170 && i < 180 })));
scenarios.push(record('dev: step-up row', 'dev_map', { x: -12, y: 0, z: 22 }, 2.5, () => ({ forward: 1, yaw: -E })));
scenarios.push(record('dev: wall-jump corridor', 'dev_map', { x: -14, y: 0, z: -34.5 }, 3,
  chimneyBrain('z', -34.5, Math.PI, 0)));
scenarios.push(record('dev: jump pad', 'dev_map', { x: 0, y: 0, z: 30 }, 2.5, () => ({ forward: 1, yaw: -E })));
scenarios.push(record('dev: crouch through slide tunnel', 'dev_map', { x: 10, y: 0, z: 22 }, 2.5, () => ({ forward: 1, yaw: 0, crouch: true })));
scenarios.push(record('dev: knockback + air control', 'dev_map', { x: 0, y: 0, z: 30 }, 3,
  (p, t, i) => ({ forward: i > 40 ? 1 : 0, yaw: -0.5 + t * 0.3 }), { 30: { x: 0, y: 12, z: -10 }, 200: { x: 8, y: 6, z: 0 } }));
scenarios.push(record('dev: sprint then crouch', 'dev_map', { x: 0, y: 0, z: 30 }, 2,
  (p, t, i) => ({ forward: 1, sprint: i < 100, crouch: i >= 100 && i < 180, yaw: 0.2 })));
scenarios.push(record('dev: slide, release slide, keep crouch', 'dev_map', { x: 0, y: 0, z: 30 }, 2.5,
  (p, t, i) => ({ forward: 1, sprint: true, yaw: 0, slide: i >= 90 && i < 130, slidePressed: i === 90, crouch: i >= 90 && i < 220 })));
scenarios.push(record('dev: slide then carve at speed', 'dev_map', { x: 0, y: 0, z: 30 }, 2.5,
  (p, t, i) => ({ forward: 1, sprint: true, yaw: i < 120 ? 0 : 0.6 * Math.sin((i - 120) / 40), slide: i >= 60 && i < 80, slidePressed: i === 60 })));
scenarios.push(record('dev: runway launcher', 'dev_map', { x: -33, y: 0, z: 34 }, 3, () => ({ forward: 1, sprint: true, yaw: 0 })));
scenarios.push(record('dev: random inputs A', 'dev_map', W.SPAWN, 12, randomBrain(1234)));
scenarios.push(record('dev: random inputs B', 'dev_map', { x: 0, y: 3.2, z: 0 }, 12, randomBrain(98765)));

// ---------- Bean Street (has ramps) ----------
W.loadCustomMap(JSON.parse(readFileSync(join(here, '..', 'tests', 'maps', 'bean-street.json'), 'utf8')));
scenarios.push(record('bean: house ramp up', 'bean-street', { x: -12.9, y: 0, z: 3.8 }, 1.3,
  (p, t) => (t < 0.62 ? { forward: 1, yaw: E } : { forward: 1, yaw: 0 })));
scenarios.push(record('bean: launch ramp into window', 'bean-street', { x: -36.3, y: 0, z: 0 }, 2.2,
  (p) => ({ forward: 1, sprint: true, yaw: -E, jump: p.pos.x > -29.8 && p.pos.x < -28 && p.grounded, jumpHeld: true })));
scenarios.push(record('bean: border chimney', 'bean-street', { x: -35.5, y: 0, z: 17 }, 3,
  chimneyBrain('x', -35.5, -E, E)));
scenarios.push(record('bean: bus bridge slide', 'bean-street', { x: 0, y: 0, z: 14 }, 2.6, (p) => {
  const onFarRamp = p.pos.z < -5.4 && p.pos.y > 0.2;
  return { forward: 1, sprint: true, yaw: 0, slide: onFarRamp || p.sliding, slidePressed: onFarRamp && !p.sliding };
}));
scenarios.push(record('bean: walk down ramp', 'bean-street', { x: -19, y: 3.2, z: 3.8 }, 1.5, () => ({ forward: 1, yaw: -E })));
scenarios.push(record('bean: random inputs', 'bean-street', { x: 20, y: 0, z: 23 }, 12, randomBrain(4242)));

const out = join(here, '..', 'tests', 'traces.json');
writeFileSync(out, JSON.stringify({ scenarios }));
console.log(`${scenarios.length} scenarios, ${scenarios.reduce((s, x) => s + x.ticks.length, 0)} ticks -> ${out}`);
