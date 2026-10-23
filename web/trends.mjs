export const TREND_WINDOW_MS = 15 * 60 * 1000;
export const TREND_SAMPLE_MS = 5000;
// Minimum vertical ranges keep tiny changes from looking like large swings.
export const METRIC_SPANS = {speed:5, resistance:10, cadence:20};
const limit = TREND_WINDOW_MS / TREND_SAMPLE_MS + 1;
const clean = value => Number.isFinite(value) && value >= 0 ? value : null;
const values = sample => Object.fromEntries(Object.keys(METRIC_SPANS).map(key => [key, clean(sample[key])]));

export function restoreTrends(saved, now) {
  try {
    const parsed = JSON.parse(saved);
    if (!Array.isArray(parsed)) return [];
    const history = [];
    for (const sample of parsed.slice(-limit)) {
      if (!sample || !Number.isFinite(sample.at) || sample.at > now || sample.at < now - TREND_WINDOW_MS) continue;
      if (history.length && sample.at - history[history.length - 1].at < TREND_SAMPLE_MS) continue;
      history.push({at:sample.at, ...values(sample)});
    }
    return history;
  } catch { return []; }
}

export function sampleTrends(history, sample, now) {
  if (!Number.isFinite(now)) return history;
  const last = history[history.length - 1];
  if (last && now >= last.at && now - last.at < TREND_SAMPLE_MS) return history;
  // A clock correction starts a fresh timeline, never a line drawn backwards.
  const recent = last && now < last.at ? [] : history.filter(point => point.at >= now - TREND_WINDOW_MS);
  return [...recent, {at:now, ...values(sample)}].slice(-limit);
}

export function trendPaths(history, key, now) {
  const visible = history.filter(point => point.at >= now - TREND_WINDOW_MS && point.at <= now);
  const valid = visible.map(point => point[key]).filter(value => clean(value) !== null);
  if (!valid.length) return {line:'', area:''};
  const minimum = Math.min(...valid), maximum = Math.max(...valid);
  const span = Math.max(METRIC_SPANS[key] || 1, maximum - minimum);
  const low = Math.max(0, minimum - (span - (maximum - minimum)) / 2);
  const number = value => value.toFixed(2);
  const groups = [];
  let group = [], previous;
  for (const point of visible) {
    if (clean(point[key]) === null) { group = []; previous = undefined; continue; }
    if (!previous || point.at - previous.at > TREND_SAMPLE_MS * 1.5) {
      group = []; groups.push(group);
    }
    const x = (point.at - (now - TREND_WINDOW_MS)) / TREND_WINDOW_MS * 100;
    const y = 37 - (point[key] - low) / span * 34;
    group.push([number(x), number(y)]);
    previous = point;
  }
  // A single sample has no trend. Missing data leaves a real break in the curve.
  const segments = groups.filter(points => points.length > 1);
  const line = segments.map(points => 'M' + points.map(point => point.join(',')).join(' L')).join(' ');
  const area = segments.map(points => 'M' + points.map(point => point.join(',')).join(' L') +
    ` L${points[points.length - 1][0]},40 L${points[0][0]},40 Z`).join(' ');
  return {line, area};
}

export function mountTrends(document) {
  const charts = Object.keys(METRIC_SPANS).map(key => {
    const metric = document.getElementById(key).closest('.metric');
    metric.insertAdjacentHTML('afterbegin', `<svg class="metric-trend" viewBox="0 0 100 40" preserveAspectRatio="none" aria-hidden="true" focusable="false">
      <defs><linearGradient id="trend-${key}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="currentColor" stop-opacity=".20"/><stop offset="1" stop-color="currentColor" stop-opacity="0"/></linearGradient></defs>
      <path class="trend-area" fill="url(#trend-${key})"/><path class="trend-line" fill="none" stroke="currentColor" stroke-width="1.25" vector-effect="non-scaling-stroke"/>
    </svg>`);
    return {key, line:metric.querySelector('.trend-line'), area:metric.querySelector('.trend-area')};
  });
  return (history, now) => {
    for (const chart of charts) {
      const paths = trendPaths(history, chart.key, now);
      chart.line.setAttribute('d', paths.line);
      chart.area.setAttribute('d', paths.area);
    }
  };
}
