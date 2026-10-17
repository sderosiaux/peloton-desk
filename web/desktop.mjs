// noVNC 1.7.0 follows the server's security preference. macOS advertises ARD
// (account username + password) before VNCAuth (the dedicated sharing password).
// This app intentionally supports the dedicated VNC password only. Never accept
// unauthenticated access. The private hook is pinned to the noVNC version above.
export function passwordDesktop(BaseRFB) {
  return class PasswordDesktop extends BaseRFB {
    _isSupportedSecurityType(type) { return type === 2; }
  };
}

// Fast mode is paired with macos/vnc.py. The Mac-side gateway converts zlib
// pixels to JPEG; noVNC renders them with the browser's native image decoder.
// Keep the pixel format at noVNC's default 32-bit RGBX (24-bit depth). This list
// selects source formats on macOS; the gateway emits JPEG/TightPNG for noVNC's
// already-registered decoders, without asking macOS to emit those formats.
export function fastDesktop(BaseRFB) {
  return class FastDesktop extends passwordDesktop(BaseRFB) {
    _sendEncodings() {
      BaseRFB.messages.clientEncodings(this._sock, [1, 6, 0, -223, -224, -239]);
    }
  };
}
