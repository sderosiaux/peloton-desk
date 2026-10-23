import test from 'node:test';
import assert from 'node:assert/strict';
import {TREND_WINDOW_MS, sampleTrends, restoreTrends, trendPaths} from '../trends.mjs';

test('frequent telemetry is bounded to fifteen minutes with one sample per five seconds',()=>{
  let history=[];
  for(let now=0;now<=30*60000;now+=500)history=sampleTrends(history,{cadence:60},now);
  assert.equal(history.length,181);
  assert.equal(history[0].at,15*60000);
  assert.equal(history.at(-1).at,30*60000);
});
test('restoration keeps only recent valid measurements, including real zeros',()=>{
  const now=2*TREND_WINDOW_MS;
  const saved=[{at:0,cadence:80},{at:now-10000,cadence:70},{at:now-5000,cadence:-1},{at:now,cadence:0},{at:now+10000,cadence:90}];
  const history=restoreTrends(JSON.stringify(saved),now);
  assert.deepEqual(history.map(point=>point.cadence),[70,null,0]);
  for(const corrupt of [null,'bad','{}','[null,{}]'])assert.deepEqual(restoreTrends(corrupt,now),[]);
  assert.equal(sampleTrends(history,{cadence:50},now-20000).length,1);
});
test('higher readings rise, and a brief history occupies only the right edge',()=>{
  const {line}=trendPaths([{at:0,speed:10},{at:5000,speed:20}],'speed',5000);
  const points=[...line.matchAll(/(?:M|L)([\d.]+),([\d.]+)/g)].map(match=>match.slice(1).map(Number));
  assert.ok(points[0][0]>99);
  assert.equal(points[1][0],100);
  assert.ok(points[1][1]<points[0][1]);
});
test('sensor loss and suspension leave gaps instead of invented interpolation',()=>{
  for(const middle of [[{at:10000,cadence:null}],[]]) {
    const history=[{at:0,cadence:60},{at:5000,cadence:70},...middle,{at:20000,cadence:80},{at:25000,cadence:75}];
    const {line,area}=trendPaths(history,'cadence',25000);
    assert.equal((line.match(/M/g)||[]).length,2);
    assert.equal((area.match(/Z/g)||[]).length,2);
  }
});
test('flat, empty and invalid readings never produce broken SVG coordinates',()=>{
  for(const cadence of [0,60,NaN,Infinity,undefined]) {
    const paths=trendPaths([{at:0,cadence},{at:5000,cadence}],'cadence',5000);
    assert.doesNotMatch(paths.line+paths.area,/NaN|Infinity/);
    if(Number.isFinite(cadence))assert.ok(paths.line);else assert.equal(paths.line,'');
  }
  assert.equal(trendPaths([{at:0,cadence:60}],'cadence',TREND_WINDOW_MS+1).line,'');
});
