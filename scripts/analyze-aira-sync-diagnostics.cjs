#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const PREFIX = '[DEBUG-sync-perf-a31f]';

function parse(text) {
  return text.split('\n').flatMap((line) => {
    const index = line.indexOf(PREFIX);
    if (index < 0) return [];
    try {
      const record = JSON.parse(line.slice(index + PREFIX.length).trim());
      return typeof record.event === 'string' && Number.isFinite(record.t) ? [record] : [];
    } catch { return []; }
  });
}

function analyze(records) {
  const runs = records.filter(r => r.event === 'run_start');
  const stages = records.filter(r => r.durationMs > 0 &&
    !['main_thread_lag', 'heartbeat'].includes(r.event));
  const lags = records.filter(r => r.event === 'main_thread_lag').map(lag => {
    // Include the 50 ms sampling uncertainty, not just the overdue part. A synchronous stage
    // can finish before its delayed timer callback, or before run_end resets the current run.
    const start = lag.t - lag.durationMs - 50;
    const overlapping = stages.filter(s => s.capture === lag.capture &&
      s.t > start && s.t - s.durationMs < lag.t);
    const runIds = new Set(overlapping.map(s => s.run).filter(Boolean));
    if (lag.run) runIds.add(lag.run);
    return { capture: lag.capture, atMs: lag.t, lateMs: lag.durationMs, browsing: lag.browsing,
      active: lag.detail,
      runs: runs.filter(r => r.capture === lag.capture && runIds.has(r.run)).map(r => r.detail),
      overlapping: overlapping.map(s => ({ stage: s.event, durationMs: s.durationMs, run: s.run })) };
  });
  const suppressed = records.filter(r => ['heartbeat', 'capture_end'].includes(r.event))
    .reduce((n, r) => n + Number(/(?:^| )suppressed=(\d+)/.exec(r.detail)?.[1] || 0), 0);
  const captures = records.filter(r => r.event === 'capture_start');
  return {
    captures: captures.length, runs: runs.map(r => ({ run: r.run, detail: r.detail })),
    samplesPresent: records.some(r => r.event === 'heartbeat' || r.event === 'main_thread_lag'),
    endedCaptures: records.filter(r => r.event === 'capture_end').length,
    suppressed, maxLateMs: Math.max(0, ...lags.map(r => r.lateMs)), lags,
    slowestStages: stages.sort((a, b) => b.durationMs - a.durationMs).slice(0, 15)
      .map(r => ({ stage: r.event, durationMs: r.durationMs, run: r.run })),
    interpretation: 'Stage overlap is a candidate, not proof of causation. Async durations include network/yield waits. Timer lateness is not FPS; absent lag does not rule out ArkWeb/GPU jank.'
  };
}

if (require.main === module) {
  const file = process.argv[2];
  if (!file || file.startsWith('--')) {
    console.error('Usage: node scripts/analyze-aira-sync-diagnostics.cjs <log-file> [--assert-responsive]');
    process.exitCode = 2;
  } else {
    const report = analyze(parse(fs.readFileSync(file, 'utf8')));
    console.log(JSON.stringify(report, null, 2));
    if (!report.samplesPresent) process.exitCode = 2;
    else if (process.argv.includes('--assert-responsive') && report.lags.length > 0) process.exitCode = 1;
  }
}
module.exports = { parse, analyze };
