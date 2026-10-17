import test from 'node:test';
import assert from 'node:assert/strict';
import { energyState, accumulateEnergy, calories } from '../energy.mjs';

test('100 W for ten minutes accumulates 60 kJ, about 59.75 estimated kcal', () => {
  let s = energyState();
  for (let now = 0; now <= 600000; now += 500) s = accumulateEnergy(s, 100, now, true);
  assert.equal(s.joules, 60000);
  assert.ok(Math.abs(calories(s.joules) - 59.751434) < 0.00001);
  s = accumulateEnergy(s, 200, 601000, true);
  assert.equal(s.joules, 60150);
});
test('pauses, missing sensors and long gaps do not add unobserved work', () => {
  let s = accumulateEnergy(energyState(), 100, 0, true);
  s = accumulateEnergy(s, 100, 1000, true);
  s = accumulateEnergy(s, 100, 2000, false);
  s = accumulateEnergy(s, 100, 10000, true);
  assert.equal(s.joules, 100);
  s = accumulateEnergy(s, 100, 11000, true);
  s = accumulateEnergy(s, NaN, 12000, true);
  s = accumulateEnergy(s, 100, 13000, true);
  s = accumulateEnergy(s, 100, 90000, true);
  assert.equal(s.joules, 200);
  s = accumulateEnergy(s, 100, 89000, true);
  assert.equal(s.joules, 200);
  for (const invalid of [-1, Infinity, undefined, 3000]) {
    s = accumulateEnergy(s, invalid, 91000, true);
    assert.equal(s.previous, null);
    assert.equal(s.joules, 200);
  }
});
test('zero power stays flat; restore preserves total without bridging sessions', () => {
  let s = energyState('5000');
  s = accumulateEnergy(s, 0, 0, true);
  s = accumulateEnergy(s, 0, 1000, true);
  assert.equal(s.joules, 5000);
  s = energyState(s.joules);
  s = accumulateEnergy(s, 200, 500000, true);
  assert.equal(s.joules, 5000);
  for (const saved of ['bad', -1, Infinity]) assert.equal(energyState(saved).joules, 0);
  assert.equal(energyState().joules, 0);
});
