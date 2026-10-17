import RFB from '@novnc/novnc';
import { passwordDesktop, fastDesktop } from './desktop.mjs';
import { elapsed, toggle, formatDuration } from './session.mjs';
const PasswordDesktop = passwordDesktop(RFB);
const FastDesktop = fastDesktop(RFB);
const $ = id => document.getElementById(id);
let rfb, status = {}, voiceActive = false, eventSocket, noticeTimer, pendingText = '', finishing = false, lastTranscript = 0, previewPhrase = 0, desktopConnected = false;
let timer = { elapsed: Number(localStorage.getItem('elapsed') || 0), running: false, started: 0 };
let fastMode = localStorage.getItem('desktopMode') !== 'exact';
const origin = location.origin, wsOrigin = origin.replace(/^http/, 'ws');
function notice(message) { $('notice').textContent=message; $('notice').hidden=false; clearTimeout(noticeTimer); noticeTimer=setTimeout(()=>$('notice').hidden=true,6500); }
async function api(path, body) {
  const response = await fetch('/api/'+path, { method: body === undefined ? 'GET':'POST', headers:{'Content-Type':'application/json'}, body:body === undefined?undefined:JSON.stringify(body) });
  const data = await response.json(); if (!response.ok) throw new Error(data.error || 'Connexion interrompue.'); return data;
}
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
$('session').onclick=()=>{ timer=toggle(timer,performance.now()); $('session-icon').textContent=timer.running?'Ⅱ':'▶'; $('session').setAttribute('aria-label',timer.running?'Mettre la session en pause':'Démarrer la session'); };
setInterval(()=>{ const ms=elapsed(timer,performance.now()); $('duration').textContent=formatDuration(ms); localStorage.setItem('elapsed',Math.round(ms)); },500);
$('settings').onclick=()=>$('settings-dialog').showModal();
function modeLabel(){ $('desktop-mode').textContent=fastMode?'Bureau fluide · passer en image exacte':'Image exacte · passer en bureau fluide'; }
modeLabel();
$('desktop-mode').onclick=()=>{fastMode=!fastMode;localStorage.setItem('desktopMode',fastMode?'fast':'exact');modeLabel();notice('Mode choisi. Touchez « Reconnecter le bureau » pour l’appliquer.');};
$('close-settings').onclick=()=>$('settings-dialog').close();
$('reconnect').onclick=()=>{ $('settings-dialog').close(); stopVoice(); desktopConnected=false; openDesktop(); };
$('reset-timer').onclick=()=>{timer={elapsed:0,running:false,started:0};$('session-icon').textContent='▶';$('session').setAttribute('aria-label','Démarrer la session');$('duration').textContent='00:00';localStorage.setItem('elapsed','0');$('settings-dialog').close();};
$('insert-pending').onclick=()=>{
  if(!rfb || !$('welcome').hidden){notice('Connectez le bureau et sélectionnez un champ de texte.');return;}
  for(const character of pendingText.replace(/[\r\n\t]/g,' ')){
    const point=character.codePointAt(0);if(point>=32)rfb.sendKey(point<=255?point:0x01000000+point);
  }
  pendingText='';$('insert-pending').hidden=true;$('settings-dialog').close();
};
async function stopVoice(){if(!voiceActive&&!finishing)return;try{await api('voice/stop',{source:'bike'});}catch{} voiceState(false);}
function voiceState(active,phase){voiceActive=active;finishing=phase==='finishing'||phase==='starting';$('voice').disabled=finishing;$('voice').setAttribute('aria-pressed',String(active));$('voice-label').textContent=phase==='starting'?'Préparation…':finishing?'Transcription…':active?'À l’écoute':'Dictée';}
$('voice').onclick=async()=>{try{if(voiceActive){$('voice').disabled=true;await api('voice/finish',{});return;}if($('welcome').hidden===false){notice('Connectez le bureau, puis touchez un champ de texte.');return;}$('voice').disabled=true;await api('voice/start',{});notice('Démarrage du micro…');}catch(e){$('voice').disabled=false;notice(e.message);}};
function voiceEvents(){
  lastTranscript=0;
  eventSocket=new WebSocket(wsOrigin+'/events');
  eventSocket.onmessage=e=>{const data=JSON.parse(e.data);if(data.type==='voice-state')voiceState(data.active,data.phase);if(data.type==='error'||data.type==='notice'||data.type==='voice-stage')notice(data.message);if(data.type==='transcription-preview'){previewPhrase=data.phraseId;$('live-text').textContent=data.text;$('live-transcript').hidden=false;$('live-text').scrollTop=$('live-text').scrollHeight;}if(data.type==='voice-state'&&data.phase==='idle')$('live-transcript').hidden=true;if(data.type==='transcription'&&data.id>lastTranscript){if(data.phraseId>=previewPhrase)$('live-transcript').hidden=true;lastTranscript=data.id;if(data.replayed)return;if(!data.inserted&&data.text){pendingText += (pendingText?' ':'')+data.text;$('insert-pending').hidden=false;notice('Champ modifié : dictée conservée. Touchez le bon champ puis choisissez « Insérer la dictée en attente » dans ···.');}else notice(data.message||'Phrase vide : aucun texte inséré.');}};
  eventSocket.onclose=()=>{voiceState(false);setTimeout(voiceEvents,3000);};
}
function metrics(){
  try{
    const m=JSON.parse(window.DeskDevice?.metrics()||'{"available":false,"detail":"Capteurs disponibles sur le Bike."}');
    for(const key of ['speed','resistance','cadence'])$(key).textContent=m.available&&Number.isFinite(m[key])?(key==='speed'?m[key].toFixed(1):Math.round(m[key])):'—';
    $('sensor-status').textContent=m.available?'Capteurs connectés · vitesse estimée à partir de la puissance.':m.detail||'En attente des capteurs.';
  }catch{$('sensor-status').textContent='Capteurs indisponibles.';}
}
async function refreshStatus(){
  try{status=await api('status');$('voice-status').textContent=status.voiceDetail;$('connect').hidden=!status.vncAvailable;
    if(!$('welcome').hidden)$('connection-detail').textContent=status.vncAvailable?'Votre Mac est prêt.':'Sur le Mac : Réglages Système → Général → Partage → Partage d’écran. Activez l’accès VNC avec un mot de passe dédié.';
  }catch(e){status.vncAvailable=false;$('connection-detail').textContent=e.message;$('connect').hidden=true;}
}
async function main(){try{await authenticate();await refreshStatus();voiceEvents();if(window.DeskDevice?.shouldOpenDesktop())openDesktop();}catch(e){$('connection-detail').textContent=e.message;}metrics();setInterval(metrics,500);setInterval(refreshStatus,5000);}
document.addEventListener('visibilitychange',()=>{if(document.hidden)stopVoice();});
window.DeskPause=stopVoice;
window.DeskOpenDesktop=async()=>{if(desktopConnected)return;await refreshStatus();openDesktop();};
main();
