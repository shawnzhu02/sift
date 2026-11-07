// Tests the swipe decision in Sift/Resources/swipe.js. Run: node tests/swipe.test.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const src = readFileSync(fileURLToPath(new URL('../Sift/Resources/swipe.js', import.meta.url)), 'utf8');
new Function(src)();  // defines globalThis.__siftSwipeDecision (no document in node)
const decide = globalThis.__siftSwipeDecision;

const base = {
  touches: 1, dx: -120, dy: 10, dt: 250, startX: 300,
  viewportWidth: 390, path: '/direct/inbox/', blocked: false, selection: false,
};
const d = (over) => decide({ ...base, ...over });

const cases = [
  ['flick left goes next', {}, 'next'],
  ['flick right goes prev', { dx: 120, startX: 100 }, 'prev'],
  ['too short', { dx: -50 }, null],
  ['too vertical', { dx: -100, dy: 60 }, null],
  ['just horizontal enough', { dx: -110, dy: 49 }, 'next'],
  ['too slow', { dt: 900 }, null],
  ['two fingers', { touches: 2 }, null],
  ['starts at left edge (back gesture)', { startX: 10, dx: 150 }, null],
  ['starts at right edge (forward gesture)', { startX: 380 }, null],
  ['starts on a carousel or input', { blocked: true }, null],
  ['text selected', { selection: true }, null],
  ['instagram story', { path: '/stories/friend/123/' }, null],
  ['instagram reel', { path: '/reel/AAA/' }, null],
  ['instagram reels id', { path: '/reels/AAA/' }, null],
  ['username reel', { path: '/friend/reel/AAA/' }, null],
  ['youtube subscriptions', { path: '/feed/subscriptions' }, 'next'],
  ['youtube watch page', { path: '/watch', dx: 130, startX: 80 }, 'prev'],
  ['profile page', { path: '/friend/' }, 'next'],
];

let failed = 0;
for (const [name, over, want] of cases) {
  try {
    assert.equal(d(over), want);
    console.log(`ok   ${name}`);
  } catch {
    failed++;
    console.log(`FAIL ${name}: got ${d(over)}, want ${want}`);
  }
}
if (failed) {
  console.log(`${failed} of ${cases.length} failed`);
  process.exit(1);
}
console.log(`all ${cases.length} passed`);
