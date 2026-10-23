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
    _requestFrame(incremental = true) {
      if (this._focusPaused) return;
      BaseRFB.messages.fbUpdateRequest(this._sock, incremental, 0, 0, this._fbWidth, this._fbHeight);
    }
    setFocusPaused(paused) {
      if (this._focusPaused === paused) return;
      const wasPaused = this._focusPaused;
      this._focusPaused = paused;
      if (!paused && wasPaused) { this._requestedAhead = null; this._requestFrame(false); }
    }
    _normalMsg() {
      // noVNC normally polls only after receiving a whole frame. Ask once as
      // soon as a frame starts, overlapping Wi-Fi transit with Mac capture.
      // Preserve its rendering backpressure: never request ahead of a pending
      // display flush, and never request twice for fragmented frame payloads.
      const continuing = this._FBU.rects > 0;
      if (!continuing && this._sock.rQpeek8() !== 0) return super._normalMsg();
      if (!continuing && this._display.pending()) {
        // Leave the header unread until the previous image has rendered. In
        // particular, an empty update must not be consumed and then stranded
        // waiting for more bytes while no further request is outstanding.
        this._flushing = true;
        this._display.flush().then(() => {
          this._flushing = false;
          if (this._sock.rQlen() > 0) this._handleMessage();
        });
        return false;
      }
      if (!continuing) this._sock.rQskipBytes(1);
      if (!this._requestedAhead && (continuing || this._sock.rQlen() >= 3) && !this._display.pending()) {
        this._requestFrame();
        this._requestedAhead = [this._fbWidth, this._fbHeight];
      }
      const finished = super._framebufferUpdate();
      if (finished) {
        if (!this._requestedAhead) this._requestFrame();
        else if (this._requestedAhead[0] !== this._fbWidth || this._requestedAhead[1] !== this._fbHeight) {
          // A request sent before DesktopSize used the old bounds. Refresh all
          // new pixels once; ordinary updates still have just one request ahead.
          this._requestFrame(false);
        }
        this._requestedAhead = null;
      }
      return finished;
    }
  };
}
