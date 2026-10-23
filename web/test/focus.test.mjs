import test from 'node:test';
import assert from 'node:assert/strict';
import {readMusicFrame,liveSignal,sceneWeights,cadenceCue,createFocusPresentation} from '../focus-signal.mjs';
const event={type:'music-frame',active:true,energy:.85,bass:.4,treble:.4,density:.7,pulse:1,confidence:.85,bpm:168};

test('a stale, missing or invalid music stream cannot invent a beat or target',()=>{
  assert.equal(readMusicFrame({...event,pulse:NaN},0),null);
  assert.equal(readMusicFrame({type:'music-frame'},0),null);
  const frame=readMusicFrame(event,1000);
  for(const now of [999,1800]){
    const signal=liveSignal(frame,now);
    assert.equal(signal.pulse,0);assert.equal(cadenceCue(signal,80),null);
  }
  assert.equal(cadenceCue(liveSignal(null,2000),80),null);
  assert.ok(liveSignal(frame,1100).pulse<frame.pulse);
});
test('quiet passages and uncertain tempo remove the cadence cue',()=>{
  for(const override of [{active:false},{energy:.1},{density:.05},{confidence:.3},{bpm:null}]){
    assert.equal(cadenceCue({...event,...override},84),null);
  }
  assert.deepEqual(cadenceCue(event,80),{rpm:84,ratio:.5});
  assert.deepEqual(cadenceCue({...event,bpm:90},89),{rpm:90,ratio:1});
  assert.deepEqual(cadenceCue({...event,bpm:90},47),{rpm:45,ratio:.5});
});
test('ambience responds to energy and bass even when the tempo is unchanged',()=>{
  const strongest=s=>Object.entries(sceneWeights(s)).sort((a,b)=>b[1]-a[1])[0][0];
  assert.equal(strongest({...event,energy:.1}),'calm');
  assert.equal(strongest({...event,density:.95,bass:.2}),'trance');
  assert.equal(strongest({...event,density:.2,bass:.95}),'mountain');
  for(const s of [event,{...event,energy:0},{...event,bass:1}]){
    assert.ok(Math.abs(Object.values(sceneWeights(s)).reduce((a,b)=>a+b,0)-1)<1e-9);
  }
});

const trance={calm:.05,trance:.8,mountain:.1,build:.05};
const mountain={calm:.05,trance:.1,mountain:.8,build:.05};
function presentationStream(base=event,cadence=82){
  const presentation=createFocusPresentation();
  let now=0;
  return {
    step(override={},weights=trance,rpm=cadence){
      const result=presentation.update({frame:readMusicFrame({...base,...override},now),now,weights,cadence:rpm});
      now+=250;return result;
    },
    missing(){const result=presentation.update({frame:null,now,weights:trance,cadence});now+=250;return result;},
  };
}

test('text survives beat valleys, threshold jitter and competing ambience scores',()=>{
  const stream=presentationStream();
  let settled;
  for(let i=0;i<21;i++)settled=stream.step();
  assert.deepEqual(settled,{scene:'trance',bpm:168,cue:{rpm:84,ratio:.5}});
  for(let i=0;i<48;i++){
    const text=stream.step({active:i%3!==0,confidence:i%2?.57:.59,bpm:i%2?167.8:168.6},
      {calm:.05,trance:i%2?.32:.58,mountain:i%2?.58:.32,build:.05});
    assert.deepEqual(text,settled);
  }
});

test('ambience requires a sustained lead and remains readable for at least eight seconds',()=>{
  const stream=presentationStream();
  let text;
  for(let i=0;i<13;i++)text=stream.step(); // Trance confirmed at 3 s.
  assert.equal(text.scene,'trance');
  for(let i=0;i<31;i++)assert.equal(stream.step({},mountain).scene,'trance');
  assert.equal(stream.step({},mountain).scene,'mountain'); // 11 s.
  for(let i=0;i<32;i++)text=stream.step({},{calm:1,trance:0,mountain:0,build:0});
  assert.equal(text.scene,'calm');
});

test('tempo and RPM change together after a stable estimate, at most once per five seconds',()=>{
  const stream=presentationStream();
  let text;
  for(let i=0;i<16;i++)text=stream.step();
  assert.equal(text.bpm,168);
  for(let i=0;i<10;i++)assert.equal(stream.step({bpm:160}).bpm,168);
  text=stream.step({bpm:160}); // 6.5 s, five seconds after acquiring 168.
  assert.equal(text.bpm,160);assert.deepEqual(text.cue,{rpm:80,ratio:.5});
  for(let i=0;i<20;i++)text=stream.step({bpm:160.8});
  assert.equal(text.bpm,160); // No 160/161 rounding flicker.

  const ambiguous=presentationStream();
  for(let i=0;i<48;i++){
    const uncertain=ambiguous.step({bpm:i%2?84:168});
    assert.equal(uncertain.bpm,null);assert.equal(uncertain.cue,null);
  }
});

test('sustained silence or uncertainty removes cues, and a lost stream clears immediately',()=>{
  for(const override of [{active:false},{confidence:.2},{energy:.05},{density:0}]){
    const stream=presentationStream();
    for(let i=0;i<16;i++)stream.step();
    for(let i=0;i<7;i++)assert.equal(stream.step(override).bpm,168);
    let quiet;
    for(let i=0;i<4;i++)quiet=stream.step(override);
    assert.equal(quiet.bpm,null);assert.equal(quiet.cue,null);
    for(let i=0;i<8;i++)quiet=stream.step();
    assert.equal(quiet.bpm,168);
    assert.deepEqual(stream.missing(),{scene:null,bpm:null,cue:null});
    assert.equal(stream.step().cue,null); // Reconnect must acquire again.
  }
  const presentation=createFocusPresentation();
  for(let now=0;now<=3000;now+=250)presentation.update({frame:readMusicFrame(event,now),now,weights:trance,cadence:82});
  assert.equal(presentation.update({frame:readMusicFrame(event,3000),now:3751,weights:trance,cadence:82}).cue,null);
});

test('pedalling near a subdivision boundary does not flip the musical mapping',()=>{
  const stream=presentationStream({...event,bpm:90},60);
  let text;
  for(let i=0;i<21;i++)text=stream.step();
  assert.deepEqual(text.cue,{rpm:45,ratio:.5});
  for(let i=0;i<40;i++)assert.equal(stream.step({},trance,i%2?66:69).cue.ratio,.5);
  for(let i=0;i<12;i++)assert.equal(stream.step({},trance,90).cue.ratio,.5);
  assert.deepEqual(stream.step({},trance,90).cue,{rpm:90,ratio:1});
});
