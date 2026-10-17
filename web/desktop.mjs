// noVNC 1.7.0 follows the server's security preference. macOS advertises ARD
// (account username + password) before VNCAuth (the dedicated sharing password).
// This app intentionally supports the dedicated VNC password only. Never accept
// unauthenticated access. The private hook is pinned to the noVNC version above.
export function passwordDesktop(BaseRFB) {
  return class PasswordDesktop extends BaseRFB {
    _isSupportedSecurityType(type) { return type === 2; }
  };
}
