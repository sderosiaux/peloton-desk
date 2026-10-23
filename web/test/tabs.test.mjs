import test from 'node:test';
import assert from 'node:assert/strict';
import {navigateTab} from '../tabs.mjs';

function remote() {
  const events=[];
  return {events, blur:()=>events.push('blur'), focus:()=>events.push('focus'), sendKey:(...args)=>events.push(args)};
}
test('tab buttons send only a complete navigation shortcut with modifiers released',()=>{
  for(const direction of ['previous','next']) {
    const rfb=remote();
    assert.equal(navigateTab(rfb,direction,true),true);
    assert.equal(rfb.events[0],'blur');
    assert.equal(rfb.events.at(-1),'focus');
    const pressed=new Set();
    for(const [symbol,code,down] of rfb.events.filter(Array.isArray)) {
      assert.ok([0xff09,0xffe1,0xffe3].includes(symbol));
      if(code==='Tab' && down) {
        assert.ok(pressed.has('ControlLeft'));
        assert.equal(pressed.has('ShiftLeft'),direction==='previous');
      }
      if(down)pressed.add(code);else pressed.delete(code);
    }
    assert.equal(pressed.size,0);
  }
});
test('disconnected, read-only and invalid navigation cannot send input',()=>{
  const rfb=remote();
  assert.equal(navigateTab(null,'next',true),false);
  assert.equal(navigateTab(rfb,'next',false),false);
  assert.equal(navigateTab(rfb,'close',true),false);
  rfb.viewOnly=true;
  assert.equal(navigateTab(rfb,'previous',true),false);
  assert.deepEqual(rfb.events,[]);
});
test('transport failure still attempts to release every pressed modifier',()=>{
  const rfb=remote(),send=rfb.sendKey;
  rfb.sendKey=(symbol,code,down)=>{send(symbol,code,down);if(code==='Tab')throw new Error('closed');};
  assert.throws(()=>navigateTab(rfb,'previous',true),/closed/);
  assert.deepEqual(rfb.events.slice(-3).map(event=>event.slice(1)),[['Tab',false],['ShiftLeft',false],['ControlLeft',false]]);
});
