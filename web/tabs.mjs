// Native macOS tab navigation, including Ghostty. Only run on an explicit tap;
// the remote application keeps its focus while the Bike toolbar is used.
export function navigateTab(rfb, direction, connected) {
  if (!rfb || !connected || rfb.viewOnly || !['previous', 'next'].includes(direction)) return false;
  const keys = [[0xffe3, 'ControlLeft']];
  if (direction === 'previous') keys.push([0xffe1, 'ShiftLeft']);
  keys.push([0xff09, 'Tab']);
  // Blur first to release any physical keys tracked by noVNC's keyboard.
  rfb.blur();
  const pressed = [];
  try {
    for (const key of keys) {
      pressed.push(key);
      rfb.sendKey(...key, true);
    }
  } finally {
    // Release every key even if sending one of the events fails.
    for (const key of pressed.reverse()) {
      try { rfb.sendKey(...key, false); } catch { /* Disconnected transport. */ }
    }
  }
  rfb.focus({preventScroll: true});
  return true;
}
