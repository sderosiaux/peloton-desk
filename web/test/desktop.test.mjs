import test from 'node:test';
import assert from 'node:assert/strict';
import { passwordDesktop, fastDesktop } from '../desktop.mjs';

const Desktop = passwordDesktop(class {});
const client = new Desktop();
// Security types captured from the actual macOS server. noVNC negotiates in
// server order; ARD first caused our password-only dialog to prompt forever.
test('macOS negotiation chooses the dedicated sharing password', () => {
  const offered = [30, 33, 36, 2, 35];
  assert.equal(offered.find(type => client._isSupportedSecurityType(type)), 2);
});
test('a missing VNC password mode cannot fall back to unauthenticated access', () => {
  assert.equal([30, 1].find(type => client._isSupportedSecurityType(type)), undefined);
});

test('fast mode negotiates only formats understood by the Mac converter', () => {
  let advertised;
  class Base { static messages = { clientEncodings: (_, list) => { advertised = list; } }; }
  const Fast = fastDesktop(Base), client = new Fast();
  client._sendEncodings();
  assert.equal(advertised.find(value => value !== 1), 6);
  assert.ok(advertised.includes(-239)); // Keep the local cursor.
  assert.ok(!advertised.includes(16)); // ZRLE must not reach this converter.
  assert.ok(!advertised.includes(21)); // Only the gateway emits JPEG.
  assert.equal([30, 1, 2].find(type => client._isSupportedSecurityType(type)), 2);
});

function frameClient() {
  const requests=[];
  class Base {
    static messages={fbUpdateRequest:(_, ...args)=>requests.push(args)};
    _normalMsg(){this.otherMessages=(this.otherMessages||0)+1;return true;}
    _framebufferUpdate(){return this.decode();}
  }
  const client=new (fastDesktop(Base))();
  Object.assign(client,{
    _FBU:{rects:0},_fbWidth:1920,_fbHeight:1080,
    _sock:{rQpeek8:()=>0,rQskipBytes:()=>{},rQlen:()=>3},
    _display:{pending:()=>false,flush:()=>Promise.resolve()},
    _handleMessage:()=>{},
    decode:()=>true,
  });
  return {client,requests};
}
test('request overlaps frame reception without duplicating fragmented updates',()=>{
  const {client,requests}=frameClient();
  client.decode=()=>{assert.equal(requests.length,1);client._FBU.rects=2;return false;};
  assert.equal(client._normalMsg(),false);
  assert.equal(client._normalMsg(),false);
  client.decode=()=>{client._FBU.rects=0;return true;};
  assert.equal(client._normalMsg(),true);
  assert.equal(requests.length,1);
  client._normalMsg();
  assert.equal(requests.length,2);
  assert.deepEqual(requests[0],[true,0,0,1920,1080]);
});
test('incomplete headers and pending image decodes do not build a request queue',async()=>{
  const {client,requests}=frameClient();
  client._sock.rQlen=()=>2;
  client.decode=()=>false;
  client._normalMsg();assert.equal(requests.length,0);
  client._sock.rQlen=()=>3;
  client._display.pending=()=>true;
  client.decode=()=>assert.fail('Decoded header before previous image finished');
  client._normalMsg();assert.equal(requests.length,0);
  assert.equal(client._FBU.rects,0);
  await Promise.resolve();
  client._display.pending=()=>false;
  client.decode=()=>{client._FBU.rects=0;return true;};
  client._normalMsg();assert.equal(requests.length,1);
});
test('empty update resumes after image decoding instead of stalling the desktop',async()=>{
  const {client,requests}=frameClient();
  let pending=true,read=0,resume;
  client._sock.rQskipBytes=()=>read++;
  client._display={pending:()=>pending,flush:()=>new Promise(resolve=>{resume=resolve;})};
  client._handleMessage=()=>client._normalMsg();
  client.decode=()=>true; // zero rectangles
  assert.equal(client._normalMsg(),false);
  assert.equal(read,0);assert.equal(requests.length,0);
  pending=false;resume();await Promise.resolve();
  assert.equal(read,1);assert.equal(requests.length,1);assert.equal(client._flushing,false);
});
test('resize refreshes the new bounds and other server messages use noVNC',()=>{
  const {client,requests}=frameClient();
  client.decode=()=>{client._fbWidth=1280;client._fbHeight=800;return true;};
  client._normalMsg();
  assert.deepEqual(requests,[[true,0,0,1920,1080],[false,0,0,1280,800]]);
  client._sock.rQpeek8=()=>2;client._normalMsg();
  assert.equal(client.otherMessages,1);assert.equal(requests.length,2);
});
test('focus drains in-flight desktop frames and resumes with a full refresh',()=>{
  const {client,requests}=frameClient();
  client.setFocusPaused(true);
  client._normalMsg();client._normalMsg();
  assert.equal(requests.length,0);
  client.setFocusPaused(false);
  assert.deepEqual(requests,[[false,0,0,1920,1080]]);
  client.setFocusPaused(false);
  assert.equal(requests.length,1);
  client._normalMsg();assert.equal(requests.length,2);
});
