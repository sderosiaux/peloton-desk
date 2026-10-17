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
