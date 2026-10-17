import RFB from '@novnc/novnc';
import { passwordDesktop, fastDesktop } from './desktop.mjs';
import { elapsed, toggle, startOnPedaling, formatDuration } from './session.mjs';
import { createAPI } from './api.mjs';
import { energyState, accumulateEnergy, calories, calorieGoal } from './energy.mjs';
const PasswordDesktop = passwordDesktop(RFB);
const FastDesktop = fastDesktop(RFB);
const $ = id => document.getElementById(id);
let rfb, status = {}, voiceActive = false, eventSocket, noticeTimer, pendingText = '', finishing = false, lastTranscript = 0, previewPhrase = 0, desktopConnected = false;
let voicePreferenceLoaded=false, companionReady=false;
let timer = { elapsed: Number(localStorage.getItem('elapsed') || 0), running: false, started: 0, manualPause: localStorage.getItem('sessionPaused')==='true' };
let energy = energyState(localStorage.getItem('energyJoules')), goal = calorieGoal(localStorage.getItem('calorieGoal'));
let fastMode = localStorage.getItem('desktopMode') !== 'exact';
const origin = location.origin, wsOrigin = origin.replace(/^http/, 'ws');
function notice(message) { $('notice').textContent=message; $('notice').hidden=false; clearTimeout(noticeTimer); noticeTimer=setTimeout(()=>$('notice').hidden=true,6500); }
const api=createAPI();
async function authenticate() {
  const token = window.DeskDevice?.connectionToken() || new URLSearchParams(location.hash.slice(1)).get('token');
  if (token) { await api('auth',{token}); history.replaceState(null,'','/'); }
}
function openDesktop() {
  if (desktopConnected) return;
  if (!status.vncAvailable) { notice('Activez le partage d’écran sur le Mac.'); return; }
  if (rfb) { rfb.removeEventListener('disconnect', disconnected); rfb.disconnect(); }
  const Desktop = fastMode ? FastDesktop : PasswordDesktop;
  rfb = new Desktop($('desktop'),wsOrigin+'/vnc'+(fastMode?'?mode=fast':''));
  rfb.scaleViewport=true; rfb.resizeSession=false; rfb.showDotCursor=true; rfb.qualityLevel=7; rfb.compressionLevel=2;
  rfb.addEventListener('credentialsrequired',()=>{ if(!$('password-dialog').open)$('password-dialog').showModal(); $('password').focus(); });
  rfb.addEventListener('connect',()=>{ desktopConnected=true; $('welcome').hidden=true; $('password-dialog').close(); notice('Bureau connecté. Touchez un champ pour écrire.'); });
  rfb.addEventListener('securityfailure',()=>notice('Mot de passe refusé. Vérifiez le mot de passe du partage d’écran.'));
  rfb.addEventListener('disconnect',disconnected);
}
function disconnected(){ desktopConnected=false; $('password-dialog').close(); $('welcome').hidden=false; $('connection-detail').textContent='La connexion au bureau est interrompue.'; $('connect').hidden=false; stopVoice(); }
$('password-form').addEventListener('submit',e=>{ e.preventDefault(); rfb?.sendCredentials({password:$('password').value}); $('password').value=''; $('password-dialog').close(); });
$('password-cancel').onclick=()=>{ $('password-dialog').close(); rfb?.disconnect(); };
$('connect').onclick=openDesktop;
function sessionState(){ $('session-icon').textContent=timer.running?'Ⅱ':'▶'; $('session').setAttribute('aria-label',timer.running?'Mettre la session en pause':'Démarrer la session');localStorage.setItem('sessionPaused',String(timer.manualPause)); }
$('session').onclick=()=>{timer=toggle(timer,performance.now());energy={...energy,previous:null};sessionState();};
setInterval(()=>{ const ms=elapsed(timer,performance.now()); $('duration').textContent=formatDuration(ms); localStorage.setItem('elapsed',Math.round(ms)); },500);
$('settings').onclick=()=>$('settings-dialog').showModal();
function modeLabel(){ $('desktop-mode').textContent=fastMode?'Bureau fluide · passer en image exacte':'Image exacte · passer en bureau fluide'; }
modeLabel();
$('desktop-mode').onclick=()=>{fastMode=!fastMode;localStorage.setItem('desktopMode',fastMode?'fast':'exact');modeLabel();notice('Mode choisi. Touchez « Reconnecter le bureau » pour l’appliquer.');};
$('close-settings').onclick=()=>$('settings-dialog').close();
$('reconnect').onclick=()=>{ $('settings-dialog').close(); stopVoice(); desktopConnected=false; openDesktop(); };
$('reset-timer').onclick=()=>{timer={elapsed:0,running:false,started:0,manualPause:false};energy=energyState();sessionState();renderEnergy();$('duration').textContent='00:00';localStorage.setItem('elapsed','0');localStorage.setItem('energyJoules','0');$('settings-dialog').close();};
function renderEnergy(){
  const kcal=calories(energy.joules), reached=kcal>=goal;
  $('calories').textContent=Math.floor(kcal);$('calorie-target').textContent=goal;
  $('calorie-progress').max=goal;$('calorie-progress').value=Math.min(kcal,goal);
  $('calorie-progress').setAttribute('aria-label',`${Math.floor(kcal)} sur ${goal} kcal estimées${reached?', objectif atteint':''}`);
  $('calorie-label').textContent=reached?'OBJECTIF ATTEINT':'KCAL EST.';
  $('calorie-metric').classList.toggle('goal-reached',reached);
}
$('calorie-goal').value=goal;
$('calorie-goal').onchange=()=>{goal=calorieGoal($('calorie-goal').value);$('calorie-goal').value=goal;localStorage.setItem('calorieGoal',String(goal));renderEnergy();};
renderEnergy();
$('insert-pending').onclick=()=>{
  if(!rfb || !$('welcome').hidden){notice('Connectez le bureau et sélectionnez un champ de texte.');return;}
  for(const character of pendingText.replace(/[\r\n\t]/g,' ')){
    const point=character.codePointAt(0);if(point>=32)rfb.sendKey(point<=255?point:0x01000000+point);
  }
  pendingText='';$('insert-pending').hidden=true;$('settings-dialog').close();
};
async function stopVoice(){if(!voiceActive&&!finishing)return;try{await api('voice/stop',{source:'bike'});}catch{} voiceState(false);}
function voiceState(active,phase){voiceActive=active;$('send-return').disabled=active||phase==='finishing'||phase==='starting';finishing=phase==='finishing'||phase==='starting';$('voice').disabled=finishing;$('voice').setAttribute('aria-pressed',String(active));$('voice-label').textContent=phase==='starting'?'Préparation…':finishing?'Transcription…':active?'À l’écoute':'Dictée';}
$('voice').onclick=async()=>{try{if(voiceActive){$('voice').disabled=true;await api('voice/finish',{});return;}if($('welcome').hidden===false){notice('Connectez le bureau, puis touchez un champ de texte.');return;}$('voice').disabled=true;await api('voice/start',{sendReturn:$('send-return').checked});}catch(e){$('voice').disabled=false;notice(e.message);}};
function voiceEvents(){
  lastTranscript=0;
  eventSocket=new WebSocket(wsOrigin+'/events');
  eventSocket.onmessage=e=>{
    const data=JSON.parse(e.data);
    if(data.type==='voice-state'){
      voiceState(data.active,data.phase);
      if(typeof data.sendReturn==='boolean')$('send-return').checked=data.sendReturn;
      if(data.phase==='idle')$('live-transcript').hidden=true;
    }
    // Routine dictation stages and successful pastes stay quiet on the Bike.
    if(data.type==='error'||data.type==='notice')notice(data.message);
    if(data.type==='transcription-preview'){
      previewPhrase=data.phraseId;$('live-text').textContent=data.text;
      $('live-transcript').hidden=false;$('live-text').scrollTop=$('live-text').scrollHeight;
    }
    if(data.type==='transcription-ignored'&&data.phraseId>=previewPhrase)$('live-transcript').hidden=true;
    if(data.type==='transcription'&&data.id>lastTranscript){
      if(data.phraseId>=previewPhrase)$('live-transcript').hidden=true;
      lastTranscript=data.id;if(data.replayed)return;
      if(!data.inserted&&data.text){
        pendingText += (pendingText?' ':'')+data.text;$('insert-pending').hidden=false;
        notice('Dictée conservée : sélectionnez le champ puis « Insérer la dictée en attente » dans ···.');
      }
    }
  };
  eventSocket.onclose=()=>{voiceState(false);setTimeout(voiceEvents,3000);};
}
function metrics(){
  try{
    const m=JSON.parse(window.DeskDevice?.metrics()||'{"available":false,"detail":"Capteurs disponibles sur le Bike."}');
    const nextTimer=startOnPedaling(timer,m.available?m.cadence:undefined,performance.now());
    if(nextTimer!==timer){timer=nextTimer;sessionState();}
    energy=accumulateEnergy(energy,m.power,performance.now(),timer.running&&m.available);
    localStorage.setItem('energyJoules',String(energy.joules));renderEnergy();
    for(const key of ['speed','resistance','power','cadence'])$(key).textContent=m.available&&Number.isFinite(m[key])?(key==='speed'?m[key].toFixed(1):Math.round(m[key])):'—';
    $('sensor-status').textContent=m.available?'Capteurs connectés · vitesse estimée à partir de la puissance.':m.detail||'En attente des capteurs.';
    // Numeric diagnostics only: lets the Mac distinguish live sensors from a stale UI.
    window.DeskDevice?.reportMetrics?.(m.available?m.cadence:-1,m.available?m.power:-1,elapsed(timer,performance.now()),timer.running,timer.manualPause);
    window.DeskDevice?.reportEnergy?.(energy.joules,calories(energy.joules),goal);
  }catch{energy={...energy,previous:null};$('sensor-status').textContent='Capteurs indisponibles.';}
}
$('send-return').onchange=()=>localStorage.setItem('sendReturn',String($('send-return').checked));
async function refreshStatus(throwOnError=false){
  try{status=await api('status');if(!voicePreferenceLoaded){$('send-return').checked=localStorage.getItem('sendReturn')===null?status.voiceAutoSend:localStorage.getItem('sendReturn')==='true';voicePreferenceLoaded=true;}$('voice-status').textContent=status.voiceDetail;$('connect').hidden=!status.vncAvailable;
    if(!$('welcome').hidden)$('connection-detail').textContent=status.vncAvailable?'Votre Mac est prêt.':'Sur le Mac : Réglages Système → Général → Partage → Partage d’écran. Activez l’accès VNC avec un mot de passe dédié.';
  }catch(e){status.vncAvailable=false;$('connection-detail').textContent=e.message;$('connect').hidden=true;if(throwOnError)throw e;}
}
async function connectCompanion(){
  try{await authenticate();await refreshStatus(true);companionReady=true;voiceEvents();if(window.DeskDevice?.shouldOpenDesktop())openDesktop();}
  catch(e){$('connection-detail').textContent=e.message;if(e.retryable)setTimeout(connectCompanion,2000);}
}
function main(){connectCompanion();metrics();setInterval(metrics,500);setInterval(()=>{if(companionReady)refreshStatus();},5000);}
document.addEventListener('visibilitychange',()=>{if(document.hidden)stopVoice();});
window.DeskPause=stopVoice;
window.DeskOpenDesktop=async()=>{if(desktopConnected)return;await refreshStatus();openDesktop();};
main();
