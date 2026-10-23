const unit = n => Math.max(0, Math.min(1, n));
const freshFrame = (frame, now) => frame && now>=frame.received && now-frame.received<=750;
export function readMusicFrame(data, now) {
  if (data?.type !== 'music-frame' || !Number.isFinite(now)) return null;
  for (const key of ['energy','bass','treble','density','pulse','confidence']) {
    if (!Number.isFinite(data[key])) return null;
  }
  return {received:now, active:data.active === true,
    ...Object.fromEntries(['energy','bass','treble','density','pulse','confidence'].map(key=>[key,unit(data[key])])),
    bpm:Number.isFinite(data.bpm)&&data.bpm>=60&&data.bpm<=190?data.bpm:null};
}

export function liveSignal(frame, now) {
  const age = frame ? now-frame.received : Infinity;
  if (!freshFrame(frame,now) || !frame.active) {
    return {active:false,energy:0,bass:0,treble:0,density:0,pulse:0,confidence:0,bpm:null};
  }
  return {...frame,pulse:frame.pulse*Math.exp(-age/150)};
}

export function sceneWeights(signal, rise=0) {
  const motion=unit((signal.energy-.12)/.65);
  const values={
    calm:Math.max(.02,1-motion),
    trance:motion*unit((signal.density-.18)/.45)*(1-signal.bass*.3),
    mountain:motion*signal.bass*signal.bass*(1-signal.density*.55),
    build:motion*Math.max(.06,unit(rise*4))*(1-signal.density*.6),
  };
  const total=Object.values(values).reduce((a,b)=>a+b,0);
  return Object.fromEntries(Object.entries(values).map(([key,value])=>[key,value/total]));
}

// A tempo subdivision is a musical cue, not a measurement of pedal position.
export function cadenceCue(signal, cadence) {
  if (!signal.active || signal.confidence<.58 || !signal.bpm || signal.energy<.2 || signal.density<.12) return null;
  const options=[.5,1,2].map(ratio=>({rpm:Math.round(signal.bpm*ratio),ratio})).filter(x=>x.rpm>=45&&x.rpm<=105);
  if (!options.length) return null;
  const reference=Number.isFinite(cadence)&&cadence>=40?cadence:75;
  return options.sort((a,b)=>Math.abs(a.rpm-reference)-Math.abs(b.rpm-reference))[0];
}

// Text follows musical passages, not individual audio frames. Keep this state
// separate from the fast pulse/energy path used by the canvas.
export function createFocusPresentation() {
  let scene,sceneAt,challenger,challengerAt,samples,sampledAt,bpm,bpmAt,supportedAt,credibleAt,cue,ratio,ratioAt,cueAt;
  function reset() {
    scene='calm';sceneAt=-Infinity;challenger=null;challengerAt=0;
    samples=[];sampledAt=null;bpm=null;bpmAt=-Infinity;supportedAt=-Infinity;credibleAt=-Infinity;
    cue=null;ratio=null;ratioAt=0;cueAt=-Infinity;
  }
  reset();
  return {reset,update({frame,now,weights,cadence}) {
    // A broken stream must never leave an obsolete target on screen.
    if(!freshFrame(frame,now)){reset();return {scene:null,bpm:null,cue:null};}
    const signal=liveSignal(frame,now);
    const strongest=Object.keys(weights).sort((a,b)=>weights[b]-weights[a])[0];
    if(strongest!==scene && weights[strongest]>weights[scene]+.12){
      if(challenger!==strongest){challenger=strongest;challengerAt=now;}
      if(now-challengerAt>=3000 && now-sceneAt>=8000){scene=strongest;sceneAt=now;challenger=null;}
    }else challenger=null;

    samples=samples.filter(sample=>now-sample.at<=3000);
    if(sampledAt!==frame.received){
      sampledAt=frame.received;
      // Acquire with good confidence, then tolerate short dips and beat valleys.
      if(signal.active && signal.bpm && signal.confidence>=(bpm===null?.62:.48) && signal.energy>=.2 && signal.density>=.12){
        samples.push({at:now,bpm:signal.bpm});credibleAt=now;
        if(bpm!==null && Math.abs(signal.bpm-bpm)<=3)supportedAt=now;
      }
    }
    const newest=samples[samples.length-1];
    if(samples.length>=4 && newest.at-samples[0].at>=1500 && now-newest.at<=500){
      const sorted=samples.map(sample=>sample.bpm).sort((a,b)=>a-b);
      const median=sorted[Math.floor(sorted.length/2)];
      // Do not average conflicting half/double-time estimates into a fake tempo.
      if(sorted.filter(value=>Math.abs(value-median)<=2).length/sorted.length>=.75){
        supportedAt=now;
        if(bpm===null || (now-bpmAt>=5000 && Math.abs(median-bpm)>=2)){
          bpm=Math.round(median);bpmAt=now;
        }
      }
    }
    if(now-credibleAt>2000 || now-supportedAt>4000){bpm=null;cue=null;ratio=null;}

    if(bpm!==null){
      const proposed=cadenceCue({active:true,confidence:1,energy:1,density:1,bpm},cadence);
      const current=cue && {ratio:cue.ratio,rpm:Math.round(bpm*cue.ratio)};
      if(!current || current.rpm<45 || current.rpm>105){cue=proposed;cueAt=now;ratio=null;}
      else{
        cue=current;
        const reference=Number.isFinite(cadence)&&cadence>=40?cadence:75;
        if(proposed && proposed.ratio!==current.ratio && Math.abs(proposed.rpm-reference)+8<Math.abs(current.rpm-reference)){
          if(ratio!==proposed.ratio){ratio=proposed.ratio;ratioAt=now;}
          if(now-ratioAt>=3000 && now-cueAt>=8000){cue=proposed;cueAt=now;ratio=null;}
        }else ratio=null;
      }
    }
    return {scene,bpm,cue};
  }};
}
