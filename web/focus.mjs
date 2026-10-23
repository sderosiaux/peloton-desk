import {readMusicFrame, liveSignal, sceneWeights, createFocusPresentation} from './focus-signal.mjs';

export function createFocus({root, toggle, onChange}) {
  const $=selector=>root.querySelector(selector);
  const canvas=$('canvas'),ctx=canvas.getContext('2d',{alpha:false});
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  let enabled=false,socket=null,retryTimer=0,request=0,last=0,frame=null,phase='idle',detail='';
  let width=1,height=1,time=0,turn=0,slowEnergy=0,cadence=null,nextLabel=0;
  const presentation=createFocusPresentation();
  let weights={calm:1,trance:0,mountain:0,build:0};
  let energy=0,bass=0,treble=0,pulse=0;
  const labels={calm:'Respiration',trance:'Rythme soutenu',mountain:'Basses profondes',build:'L’énergie remonte'};
  const colors={calm:[121,221,207],trance:[105,204,255],mountain:[255,168,102],build:[168,153,255]};
  let ink='rgb(121,221,207)',second='rgb(159,157,255)';
  const put=(element,text)=>{if(element.textContent!==text)element.textContent=text;};

  function connection() {
    if(!enabled || document.hidden)return;
    clearTimeout(retryTimer);frame=null;presentation.reset();nextLabel=0;phase='starting';detail='Connexion au son de Spotify…';
    const current=new WebSocket(location.origin.replace(/^http/,'ws')+'/music');socket=current;
    current.onmessage=event=>{
      if(socket!==current)return;
      let data;try{data=JSON.parse(event.data);}catch{return;}
      if(data.type==='music-state'){
        phase=data.phase;detail=typeof data.detail==='string'?data.detail:'';
        if(phase!=='listening' && phase!=='waiting')frame=null;
        $('#focus-retry').hidden=phase!=='error';
      }else{
        const parsed=readMusicFrame(data,performance.now());
        if(parsed){frame=parsed;phase='listening';$('#focus-retry').hidden=true;}
      }
    };
    current.onclose=()=>{
      if(socket!==current)return;
      socket=null;frame=null;
      if(enabled){phase='waiting';detail='Connexion au Mac interrompue…';retryTimer=setTimeout(connection,2000);}
    };
    current.onerror=()=>current.close();
  }
  function disconnect(){
    clearTimeout(retryTimer);const previous=socket;socket=null;previous?.close();frame=null;presentation.reset();
  }
  function resize(){
    if(!enabled)return;
    width=root.clientWidth;height=root.clientHeight;
    const scale=Math.min(devicePixelRatio||1,1.5);
    canvas.width=Math.round(width*scale);canvas.height=Math.round(height*scale);
    ctx?.setTransform(scale,0,0,scale,0,0);
  }
  function setEnabled(value){
    if(value===enabled)return;
    enabled=value;root.hidden=!enabled;
    document.body.classList.toggle('focus-mode',enabled);
    toggle.setAttribute('aria-pressed',String(enabled));
    toggle.setAttribute('aria-label',enabled?'Revenir au bureau':'Ultra focus RPM');
    toggle.title=enabled?'Revenir au bureau':'Ultra focus RPM';
    onChange(enabled);
    if(enabled){resize();connection();last=0;request=requestAnimationFrame(draw);}
    else{disconnect();cancelAnimationFrame(request);}
  }
  toggle.onclick=()=>setEnabled(!enabled);
  $('#focus-exit').onclick=()=>setEnabled(false);
  $('#focus-retry').onclick=()=>{disconnect();connection();};
  new ResizeObserver(resize).observe(root);

  function line(points,color,opacity,thickness=1){
    ctx.strokeStyle=color;ctx.globalAlpha=opacity;ctx.lineWidth=thickness;ctx.beginPath();
    points.forEach((point,index)=>index?ctx.lineTo(...point):ctx.moveTo(...point));ctx.stroke();
  }
  function tunnel(cx,cy,opacity){
    const max=Math.hypot(width/2,height*.65),travel=(time*.22)%1;
    for(let i=0;i<23;i++){
      const z=(i/23+travel)%1,r=48+Math.pow(z,2.4)*max*1.5,points=[];
      for(let n=0;n<=110;n++){
        const a=n/110*Math.PI*2,fold=1+Math.sin(a*6+z*8+time*.25)*.03;
        const radius=r*fold*(1+pulse*.025);
        points.push([cx+Math.cos(a)*radius*(1+.24*z),cy+Math.sin(a)*radius*.8]);
      }
      line(points,i%3?second:ink,(.14+.46*z)*opacity,1+z*.8);
    }
    for(let j=0;j<44;j++){
      const a=j*2.39996,z=((j*.618033)%1+time*.21)%1,r=135+z*z*max*1.2,tail=2+z*z*25;
      const x=cx+Math.cos(a)*r*1.2,y=cy+Math.sin(a)*r*.8;
      line([[x,y],[x+Math.cos(a)*tail,y+Math.sin(a)*tail]],ink,z*.5*opacity,1.4);
    }
  }
  function mountain(cx,cy,opacity){
    for(let row=0;row<28;row++){
      const depth=(row/28+time*.035)%1,p=Math.pow(depth,1.6),base=cy+p*height*.7,points=[];
      for(let j=0;j<=100;j++){
        const x=j/100*width,n=(x-cx)/width;
        const ridge=Math.sin(n*13+depth*8-time*.28)*.44+Math.cos(n*23-depth*5)*.23+Math.sin(n*7+depth*12)*.33;
        const lift=Math.exp(-Math.pow((depth-(time*.2)%1)*5,2))*bass*pulse*45;
        points.push([x,base-ridge*(12+p*100)*(.3+Math.abs(n)*1.8)-lift]);
      }
      line(points,row%4?ink:second,(.1+.5*p)*opacity,1+p*.6);
    }
    for(let i=0;i<9;i++){
      ctx.globalAlpha=(.3-i*.02)*opacity;ctx.strokeStyle=ink;ctx.lineWidth=1;
      const r=140+i*39+pulse*bass*(10+i);
      ctx.beginPath();ctx.ellipse(cx,cy,r,r*.84,0,Math.PI*1.03,Math.PI*1.97);ctx.stroke();
    }
  }
  function calm(cx,cy,opacity){
    for(let j=0;j<14;j++){
      const points=[];
      for(let k=0;k<=95;k++){
        const x=k/95*width,y=cy+Math.sin(x/width*5+time*.2+j*.16)*(40+j*6)+(j-7)*21;
        points.push([x,y]);
      }
      line(points,j%3?ink:second,(.16+Math.sin(j)*.045)*opacity,1.2);
    }
    for(let j=0;j<34;j++){
      ctx.globalAlpha=.35*opacity;ctx.fillStyle=ink;ctx.beginPath();
      ctx.arc(((j*.618+time*.007)%1)*width,((j*.423+time*.008)%1)*height,j%5?1:1.8,0,Math.PI*2);ctx.fill();
    }
  }
  function draw(now){
    if(!enabled)return;
    request=requestAnimationFrame(draw);
    if(document.hidden)return;
    const dt=last?Math.min(.05,(now-last)/1000):0;last=now;
    const signal=liveSignal(frame,now),blend=1-Math.exp(-dt*1.5),fast=1-Math.exp(-dt*12);
    slowEnergy+=(signal.energy-slowEnergy)*(1-Math.exp(-dt*.15));
    const target=sceneWeights(signal,signal.energy-slowEnergy);
    for(const name of Object.keys(weights))weights[name]+=(target[name]-weights[name])*blend;
    energy+=(signal.energy-energy)*fast;bass+=(signal.bass-bass)*fast;treble+=(signal.treble-treble)*fast;
    pulse=signal.pulse>pulse?signal.pulse:pulse*Math.exp(-dt/0.16);
    if(!reduced.matches){time+=dt*(.2+energy*.8);if(signal.bpm&&signal.confidence>.58)turn+=dt*signal.bpm/120*Math.PI*2;}
    const rgb=[0,1,2].map(i=>Math.round(Object.keys(weights).reduce((sum,name)=>sum+colors[name][i]*weights[name],0)));
    ink=`rgb(${rgb.join(',')})`;second=`rgb(${Math.round(155+weights.mountain*90)},${Math.round(147-weights.mountain*35)},${Math.round(255-weights.mountain*100)})`;
    root.style.setProperty('--focus-accent',ink);
    if(now>=nextLabel){
      nextLabel=now+250;
      const {scene,bpm,cue}=presentation.update({frame,now,weights,cadence});
      put($('#focus-scene'),scene?labels[scene]:'À ton rythme');
      const listening=(phase==='listening' || phase==='waiting') && frame && now-frame.received<2000;
      put($('#focus-status'),listening?'Spotify · adaptation automatique':phase==='listening'?'En attente du son de Spotify…':detail);
      put($('#focus-cue'),cue?`Repère · ${cue.rpm} rpm`:'À ton rythme');
      put($('#focus-mapping'),cue?(cue.ratio===.5?'2 temps / tour':cue.ratio===1?'1 temps / tour':'2 tours / temps'):'');
      put($('#focus-bpm'),bpm?`${bpm} BPM`:'');
      $('#focus-beat').style.opacity=String(bpm ? .85 : .2);
    }
    if(!ctx)return;
    const cx=width/2,cy=height*.45;
    ctx.globalAlpha=1;ctx.fillStyle='#070b13';ctx.fillRect(0,0,width,height);
    const halo=ctx.createRadialGradient(cx,cy,10,cx,cy,Math.max(width*.55,height*.7));
    halo.addColorStop(0,`rgba(${rgb.join(',')},${.09+energy*.055+(reduced.matches?0:pulse*.05)})`);halo.addColorStop(1,'rgba(7,11,19,0)');
    ctx.fillStyle=halo;ctx.fillRect(0,0,width,height);
    if(weights.trance+weights.build>.005)tunnel(cx,cy,weights.trance+weights.build);
    if(weights.mountain>.005)mountain(cx,cy,weights.mountain);
    if(weights.calm>.005)calm(cx,cy,weights.calm);
    const radius=Math.min(180,Math.max(125,height*.22));
    const veil=ctx.createRadialGradient(cx,cy,30,cx,cy,radius*1.4);
    veil.addColorStop(0,'#070b13');veil.addColorStop(.48,'#070b13');veil.addColorStop(1,'rgba(7,11,19,0)');
    ctx.globalAlpha=1;ctx.fillStyle=veil;ctx.fillRect(cx-radius*1.4,cy-radius*1.4,radius*2.8,radius*2.8);
    ctx.strokeStyle=ink;ctx.globalAlpha=.15;ctx.lineWidth=1;ctx.beginPath();ctx.arc(cx,cy,radius,0,Math.PI*2);ctx.stroke();
    if(signal.active){
      ctx.globalAlpha=reduced.matches?.25:.2+pulse*.65;ctx.lineWidth=1.5+pulse*2.5;
      ctx.beginPath();ctx.arc(cx,cy,radius+(reduced.matches?0:pulse*8),0,Math.PI*2);ctx.stroke();
      if(signal.confidence>.58){ctx.globalAlpha=.8;ctx.lineWidth=3;ctx.beginPath();ctx.arc(cx,cy,radius,turn-.5,turn);ctx.stroke();}
    }
    ctx.globalAlpha=1;
    $('#focus-beat').style.transform=`scale(${reduced.matches?1:1+pulse*.4})`;
  }
  return {
    get active(){return enabled;},
    exit:()=>setEnabled(false),
    pause:()=>{if(enabled){disconnect();phase='waiting';detail='Focus suspendu';}},
    resume:()=>{if(enabled)connection();},
    metrics(value){cadence=value?.available&&Number.isFinite(value.cadence)?value.cadence:null;put($('#focus-rpm'),cadence===null?'—':String(Math.round(cadence)));}
  };
}
