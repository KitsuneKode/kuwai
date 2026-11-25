import { test, expect } from 'bun:test';
import { readFileSync, writeFileSync } from 'node:fs';
import { functions } from '../helpers/qml.mjs';

const theme = readFileSync(new URL('../../shell/config/Theme.qml', import.meta.url), 'utf8');
const tier = name => {
  const m = theme.match(new RegExp(`readonly property var ${name}: \\(\\{ stiffness: ([\\d.]+), damping: ([\\d.]+)`));
  if (!m) throw new Error(name);
  return { stiffness: Number(m[1]), damping: Number(m[2]) };
};
const TIERS = ['springFast', 'springModerate', 'springSlow', 'surfaceIn', 'surfaceOut', 'surfaceKeyIn', 'surfaceKeyOut'];

function run(name, frame = 1 / 60) {
  const s = functions('shell/components/Spring.qml', ['step', 'settle'], {
    Theme: { reduceMotion: false }, tier: tier(name), target: 1, value: 0, velocity: 0, epsilon: 0.0005, settled: false,
  });
  const samples = [0];
  let t = 0;
  while (!s.settled && t < 3) { s.step(frame); t += frame; samples.push(s.value); }
  return { samples, settleMs: Math.round(t * 1000), overshoot: Math.max(...samples) - 1 };
}

const runs = Object.fromEntries(TIERS.map(n => [n, run(n)]));

test('every tier settles, with no more than a hair of overshoot and no wobble back', () => {
  for (const [name, r] of Object.entries(runs)) {
    expect(r.settleMs, name).toBeLessThan(1500);
    expect(r.overshoot, name).toBeLessThan(0.02);
    let back = 0;
    for (let i = 1; i < r.samples.length; i++) back = Math.max(back, r.samples[i - 1] - r.samples[i]);
    expect(back, name).toBeLessThan(0.01);
  }
});

test('closing is quicker than opening, and a key quicker than the pointer', () => {
  expect(runs.surfaceOut.settleMs).toBeLessThan(runs.surfaceIn.settleMs);
  expect(runs.surfaceKeyOut.settleMs).toBeLessThan(runs.surfaceKeyIn.settleMs);
  expect(runs.surfaceKeyIn.settleMs).toBeLessThan(runs.surfaceIn.settleMs);
  expect(runs.springFast.settleMs).toBeLessThan(runs.springModerate.settleMs);
  expect(runs.springModerate.settleMs).toBeLessThan(runs.springSlow.settleMs);
});

test('the reference timeline is current (KUWAI_UPDATE_TIMELINE=1 rewrites it)', () => {
  const W = 640, H = 300, pad = 36, maxMs = 1200;
  const colours = ['#0a84ff', '#30d158', '#ff9f0a', '#bf5af2', '#ff453a', '#64d2ff', '#ffd60a'];
  const x = ms => (pad + (W - 2 * pad) * Math.min(ms, maxMs) / maxMs).toFixed(1);
  const y = v => (H - pad - (H - 2 * pad) * v).toFixed(1);
  const lines = TIERS.map((name, i) => {
    const pts = runs[name].samples.map((v, k) => `${x(k * 1000 / 60)},${y(v)}`).join(' ');
    return `  <polyline fill="none" stroke="${colours[i]}" stroke-width="2" points="${pts}"/>\n` +
      `  <text x="${W - pad}" y="${H - pad - 14 * (TIERS.length - i)}" text-anchor="end" fill="${colours[i]}" font-size="11" font-family="sans-serif">${name} · ${runs[name].settleMs} ms</text>`;
  }).join('\n');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">\n` +
    `  <rect width="${W}" height="${H}" fill="#111114"/>\n` +
    `  <line x1="${pad}" y1="${y(1)}" x2="${W - pad}" y2="${y(1)}" stroke="#444" stroke-dasharray="4 4"/>\n` +
    `  <line x1="${pad}" y1="${y(0)}" x2="${W - pad}" y2="${y(0)}" stroke="#444"/>\n` +
    `  <text x="${pad}" y="${H - 10}" fill="#888" font-size="11" font-family="sans-serif">0 ms</text>\n` +
    `  <text x="${W - pad}" y="${H - 10}" text-anchor="end" fill="#888" font-size="11" font-family="sans-serif">${maxMs} ms</text>\n` +
    lines + '\n</svg>\n';
  const ref = new URL('../../docs/design/motion-timeline.svg', import.meta.url);
  if (process.env.KUWAI_UPDATE_TIMELINE === '1') writeFileSync(ref, svg);
  expect(svg).toBe(readFileSync(ref, 'utf8'));
});
