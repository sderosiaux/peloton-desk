import test from 'node:test';
import assert from 'node:assert/strict';
import {elapsed,toggle,formatDuration} from '../session.mjs';
test('a paused session does not count time between rides',()=>{
  let s={elapsed:0,running:false,started:0};
  s=toggle(s,1000);s=toggle(s,61000);assert.equal(elapsed(s,999000),60000);
  s=toggle(s,999000);assert.equal(elapsed(s,1000000),61000);
});
test('duration does not wrap after one hour',()=>assert.equal(formatDuration(3661000),'1:01:01'));
