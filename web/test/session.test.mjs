import test from 'node:test';
import assert from 'node:assert/strict';
import {elapsed,toggle,startOnPedaling,formatDuration} from '../session.mjs';
test('a paused session does not count time between rides',()=>{
  let s={elapsed:0,running:false,started:0};
  s=toggle(s,1000);s=toggle(s,61000);assert.equal(elapsed(s,999000),60000);
  s=toggle(s,999000);assert.equal(elapsed(s,1000000),61000);
});
test('duration does not wrap after one hour',()=>assert.equal(formatDuration(3661000),'1:01:01'));
test('pedaling starts the timer once and preserves a manual pause',()=>{
  let s={elapsed:0,running:false,started:0,manualPause:false};
  for(const cadence of [0,undefined,NaN,-1])assert.equal(startOnPedaling(s,cadence,1000),s);
  s=startOnPedaling(s,65,1000);
  assert.equal(elapsed(s,6000),5000);
  assert.equal(startOnPedaling(s,70,6000),s);
  s=toggle(s,6000);
  assert.equal(startOnPedaling(s,70,999000),s);
  assert.equal(elapsed(s,999000),5000);
  s=toggle(s,999000);
  assert.equal(elapsed(s,1000000),6000);
});
