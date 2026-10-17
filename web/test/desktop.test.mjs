import test from 'node:test';
import assert from 'node:assert/strict';
import { passwordDesktop } from '../desktop.mjs';

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
