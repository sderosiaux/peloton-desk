// Personal estimate, not Peloton's calorie algorithm. Mechanical work (joules)
// divided by an assumed 24% efficiency and 4,184 J/kcal.
const EFFICIENCY = 0.24;
const MAX_SAMPLE_GAP_MS = 2500;
export function energyState(savedJoules = 0) {
  const joules = Number(savedJoules);
  return { joules: Number.isFinite(joules) && joules >= 0 ? joules : 0, previous: null };
}
export function accumulateEnergy(state, power, now, active) {
  if (!active || !Number.isFinite(power) || power < 0 || power >= 3000 || !Number.isFinite(now))
    return { ...state, previous: null };
  const previous = state.previous, dt = previous ? now - previous.at : 0;
  // Do not invent work during suspension, disconnection or a manual pause.
  const added = previous && dt > 0 && dt <= MAX_SAMPLE_GAP_MS
    ? (previous.power + power) / 2 * dt / 1000 : 0;
  return { joules: state.joules + added, previous: { at: now, power } };
}
export function calories(joules) { return joules / (4184 * EFFICIENCY); }
export function calorieGoal(value) {
  const goal = Number(value);
  return Number.isFinite(goal) && goal >= 1 && goal <= 10000 ? Math.round(goal) : 200;
}
