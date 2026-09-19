import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { AIRA_ENABLE_SYNC_DIAGNOSTICS } from '../config/AiraSyncDiagnostics';
import { sharedBrowsingActivitySignal } from '../activity/BrowsingActivitySignal';

const DOMAIN: number = 0x0000;
const TAG: string = 'SyncJankProbe';
const PREFIX: string = '[DEBUG-sync-perf-a31f]';
const SAMPLE_MS: number = 50;
const LATE_MS: number = 32;
const CAPTURE_MS: number = 180000;
const EVENTS_PER_SECOND: number = 48;

interface SyncProbeSpan {
  id: number;
  run: number;
  name: string;
  startedAt: number;
}

interface SyncProbeEvent {
  capture: number;
  run: number;
  event: string;
  t: number;
  wall: number;
  durationMs: number;
  browsing: boolean;
  detail: string;
}

// Temporary diagnostic build only. Timer lateness is event-loop delay, NOT an FPS measurement
// or proof that an overlapping async stage caused the stall. Completed spans retain their start
// and end in the log, so a blocked callback can still be matched after that stage has returned.
export class AiraSyncJankProbe {
  private static active: boolean = false;
  private static capture: number = 0;
  private static captureStartedAt: number = 0;
  private static timer: number = -1;
  private static expectedAt: number = 0;
  private static sequence: number = 0;
  private static run: number = 0;
  private static spans: SyncProbeSpan[] = [];
  private static bucketAt: number = 0;
  private static emitted: number = 0;
  private static suppressed: number = 0;
  private static maxLag: number = 0;
  private static samples: number = 0;
  private static useWallClock: boolean = false;
  private static wallAnchor: number = 0;
  private static uptimeAnchor: number = 0;

  static startCapture(reason: string): void {
    if (!AIRA_ENABLE_SYNC_DIAGNOSTICS || AiraSyncJankProbe.active) {
      return;
    }
    try {
      AiraSyncJankProbe.uptimeAnchor = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE);
      AiraSyncJankProbe.wallAnchor = Date.now();
      AiraSyncJankProbe.useWallClock = false;
    } catch (_error) {
      AiraSyncJankProbe.wallAnchor = Date.now();
      AiraSyncJankProbe.uptimeAnchor = 0;
      AiraSyncJankProbe.useWallClock = true;
    }
    AiraSyncJankProbe.active = true;
    AiraSyncJankProbe.capture = Date.now();
    AiraSyncJankProbe.captureStartedAt = AiraSyncJankProbe.now();
    AiraSyncJankProbe.bucketAt = AiraSyncJankProbe.captureStartedAt;
    AiraSyncJankProbe.emitted = 0;
    AiraSyncJankProbe.suppressed = 0;
    AiraSyncJankProbe.maxLag = 0;
    AiraSyncJankProbe.samples = 0;
    AiraSyncJankProbe.emit('capture_start', 0,
      `reason=${reason} clock=${AiraSyncJankProbe.useWallClock ? 'wall' : 'active_uptime'} limitMs=${CAPTURE_MS}`, true);
    AiraSyncJankProbe.schedule();
  }

  static stopCapture(reason: string): void {
    if (!AiraSyncJankProbe.active) {
      return;
    }
    AiraSyncJankProbe.emit('capture_end', 0,
      `reason=${reason} suppressed=${AiraSyncJankProbe.suppressed} open=${AiraSyncJankProbe.spans.length}`, true);
    AiraSyncJankProbe.active = false;
    clearTimeout(AiraSyncJankProbe.timer);
    AiraSyncJankProbe.timer = -1;
    AiraSyncJankProbe.spans = [];
    AiraSyncJankProbe.run = 0;
  }

  static beginRun(source: string, provider: string, mode: string): number {
    if (!AIRA_ENABLE_SYNC_DIAGNOSTICS) {
      return 0;
    }
    AiraSyncJankProbe.startCapture(source);
    AiraSyncJankProbe.run = ++AiraSyncJankProbe.sequence;
    AiraSyncJankProbe.emit('run_start', 0, `source=${source} provider=${provider} mode=${mode}`, true);
    return AiraSyncJankProbe.run;
  }

  static endRun(id: number): void {
    if (!AiraSyncJankProbe.active || id === 0 || AiraSyncJankProbe.run !== id) {
      return;
    }
    AiraSyncJankProbe.emit('run_end', 0, '', true);
    AiraSyncJankProbe.run = 0;
    // Keep sampling the post-sync tail: the delayed timer may not fire until after run_end.
  }

  static beginStage(name: string): number {
    if (!AiraSyncJankProbe.active || AiraSyncJankProbe.spans.length >= 64) {
      return 0;
    }
    const span: SyncProbeSpan = {
      id: ++AiraSyncJankProbe.sequence,
      run: AiraSyncJankProbe.run,
      name,
      startedAt: AiraSyncJankProbe.now()
    };
    AiraSyncJankProbe.spans.push(span);
    AiraSyncJankProbe.emit(`${name}_start`, 0, `span=${span.id}`);
    return span.id;
  }

  static endStage(id: number): void {
    if (!AiraSyncJankProbe.active || id === 0) {
      return;
    }
    const index = AiraSyncJankProbe.spans.findIndex((span: SyncProbeSpan): boolean => span.id === id);
    if (index < 0) {
      return;
    }
    const span = AiraSyncJankProbe.spans[index];
    AiraSyncJankProbe.spans.splice(index, 1);
    AiraSyncJankProbe.emit(span.name, AiraSyncJankProbe.now() - span.startedAt, `span=${id}`, false, span.run);
  }

  static async measure<T>(name: string, operation: () => Promise<T>): Promise<T> {
    const span = AiraSyncJankProbe.beginStage(name);
    try {
      return await operation();
    } finally {
      AiraSyncJankProbe.endStage(span);
    }
  }

  static mark(event: string): void {
    AiraSyncJankProbe.markExtra(event, '');
  }

  static markExtra(event: string, extra: string): void {
    AiraSyncJankProbe.emit(event, 0, extra);
  }

  static end(event: string, startedAt: number): void {
    AiraSyncJankProbe.endExtra(event, startedAt, '');
  }

  static endExtra(event: string, startedAt: number, extra: string): void {
    if (!AiraSyncJankProbe.active) {
      return;
    }
    const duration = Math.max(0, Date.now() - startedAt);
    // Existing per-record probes can fire thousands of times. Keep only slow ones.
    if (event === 'history_change' && duration < 8) {
      return;
    }
    AiraSyncJankProbe.emit(event, duration, extra);
  }

  private static schedule(): void {
    AiraSyncJankProbe.expectedAt = AiraSyncJankProbe.now() + SAMPLE_MS;
    AiraSyncJankProbe.timer = setTimeout((): void => AiraSyncJankProbe.sample(), SAMPLE_MS);
  }

  private static sample(): void {
    if (!AiraSyncJankProbe.active) {
      return;
    }
    const now = AiraSyncJankProbe.now();
    const late = Math.max(0, now - AiraSyncJankProbe.expectedAt);
    AiraSyncJankProbe.maxLag = Math.max(AiraSyncJankProbe.maxLag, late);
    AiraSyncJankProbe.samples++;
    if (late >= LATE_MS) {
      AiraSyncJankProbe.emit('main_thread_lag', late,
        `active=${AiraSyncJankProbe.activeStages()}`, true);
    }
    if (now - AiraSyncJankProbe.bucketAt >= 1000) {
      AiraSyncJankProbe.emit('heartbeat', 0,
        `maxLagMs=${AiraSyncJankProbe.maxLag} samples=${AiraSyncJankProbe.samples}` +
          ` suppressed=${AiraSyncJankProbe.suppressed} active=${AiraSyncJankProbe.activeStages()}`, true);
      AiraSyncJankProbe.bucketAt = now;
      AiraSyncJankProbe.emitted = 0;
      AiraSyncJankProbe.suppressed = 0;
      AiraSyncJankProbe.maxLag = 0;
      AiraSyncJankProbe.samples = 0;
    }
    if (now - AiraSyncJankProbe.captureStartedAt >= CAPTURE_MS) {
      AiraSyncJankProbe.stopCapture('time_limit');
      return;
    }
    AiraSyncJankProbe.schedule();
  }

  private static activeStages(): string {
    return AiraSyncJankProbe.spans.slice(-4).map((span: SyncProbeSpan): string => span.name).join(',') || 'none';
  }

  private static now(): number {
    if (!AiraSyncJankProbe.useWallClock) {
      try {
        return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE);
      } catch (_error) {
        AiraSyncJankProbe.useWallClock = true;
      }
    }
    return AiraSyncJankProbe.uptimeAnchor + Date.now() - AiraSyncJankProbe.wallAnchor;
  }

  private static safeDetail(extra: string): string {
    // Never persist arbitrary error text, URLs, titles, uid, device ids, commits or payloads.
    return extra.split(' ').filter((part: string): boolean =>
      /^(?:(?:span|limitMs|maxLagMs|samples|suppressed|open|count|items|folders|rows|bytes|applied|uploaded|queued|code|ok|write|apply|dirty|upsert|deleted|taskpool|error|reused|yields|sleptMs|computeMs|mainThreadMs|requestBytes|chunks|matched|hit|skip|automatic|enrolled|outbox|tombstones|bookmarks|personalization|history|unpackMs|decodeMs|mergeMs|compareMs|projectionMs|encodeMs|totalMs|visits|packed|lite|cached|skipped|headMatches|replicaReady|localWork|eligible)=-?\d+(?:\.\d+)?|(?:source|provider|mode|reason|kind|type|path|plan|clock|active|outcome|tables)=[a-z_0-9,\-]{1,160})$/.test(part)
    ).slice(0, 16).join(' ');
  }

  private static emit(event: string, durationMs: number, extra: string, always: boolean = false,
    run: number = AiraSyncJankProbe.run): void {
    if (!AiraSyncJankProbe.active) {
      return;
    }
    if (!always && AiraSyncJankProbe.emitted >= EVENTS_PER_SECOND) {
      AiraSyncJankProbe.suppressed++;
      return;
    }
    AiraSyncJankProbe.emitted++;
    try {
      const record: SyncProbeEvent = {
        capture: AiraSyncJankProbe.capture,
        run,
        event,
        t: AiraSyncJankProbe.now() - AiraSyncJankProbe.captureStartedAt,
        wall: Date.now(),
        durationMs: Math.round(durationMs),
        browsing: sharedBrowsingActivitySignal.isBrowsingRecently(),
        detail: AiraSyncJankProbe.safeDetail(extra)
      };
      hilog.info(DOMAIN, TAG, '%{public}s %{public}s', PREFIX, JSON.stringify(record));
    } catch (_error) {
      // Diagnostics must not turn a completed write into a sync retry.
    }
  }
}
