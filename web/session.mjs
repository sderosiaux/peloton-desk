export function elapsed(state, now) {
  return Math.max(0, state.elapsed + (state.running ? Math.max(0, now - state.started) : 0));
}
export function toggle(state, now) {
  return { ...state, elapsed: elapsed(state, now), running: !state.running, started: now, manualPause: state.running };
}
export function startOnPedaling(state, cadence, now) {
  if (state.running || state.manualPause || !Number.isFinite(cadence) || cadence <= 0) return state;
  return { ...state, running: true, started: now };
}
export function formatDuration(ms) {
  const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
  return (h ? `${h}:` : '') + `${m}`.padStart(2, '0') + ':' + `${s % 60}`.padStart(2, '0');
}
