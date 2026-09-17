import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'LoadScrollJank';
const EVENT_PREFIX: string = '[DEBUG-load-scroll-jank-7c4d]';

/**
 * Frame gap that counts as a dropped frame. 60Hz gives ~16.7ms, so anything at or beyond two
 * refresh intervals is a visible hitch on any current device.
 */
const JANK_FRAME_GAP_MS: number = 33;

/**
 * Period of the UI-thread occupancy timer. Short enough that a multi-frame block is detected with
 * useful resolution, long enough that the probe itself stays negligible next to the work it
 * measures.
 */
const OCCUPANCY_TICK_MS: number = 8;

/** One baseline occupancy line per this many ticks (~0.5s at 8ms). */
const OCCUPANCY_SAMPLE_TICKS: number = 64;

/**
 * Timeout-detection / sampling interval for `MAIN_THREAD_JANK`, in milliseconds (documented range
 * 50-500, default 150). The blocks being investigated are 40-50ms, so this sits at the documented
 * floor to make them eligible.
 */
const MAIN_THREAD_JANK_SAMPLE_INTERVAL_MS: number = 50;

/** Stacks collected per timeout; the documented cap is `2500 / sampleInterval - 4` = 46 here. */
const MAIN_THREAD_JANK_SAMPLE_COUNT: number = 10;

/**
 * The configurable main-thread jank event. `hiappevent_event.h` defines it as
 * `EVENT_MAIN_THREAD_JANK_V2 "MAIN_THREAD_JANK_V2"`; the SDK's JS/ETS surface only exposes the
 * non-configurable `MAIN_THREAD_JANK` constant, so the name is written out here.
 */
const MAIN_THREAD_JANK_V2_EVENT_NAME: string = 'MAIN_THREAD_JANK_V2';

/** `log_type` value that collects only the call stack (2 would collect only a trace). */
const MAIN_THREAD_JANK_LOG_TYPE_STACK: number = 1;

/** `ignore_startup_time` in seconds; documented minimum is 3, default 10. */
const MAIN_THREAD_JANK_IGNORE_STARTUP_SECONDS: number = 3;

/** `report_times_per_app`: sampling reports per app pid per lifecycle; documented max 180. */
const MAIN_THREAD_JANK_REPORT_TIMES: number = 20;

/** Only `code`/`message` are read from a caught rejection; a BusinessError has no enumerable fields. */
interface BusinessErrorLike {
  code?: number;
  message?: string;
}

/** A bracketed stretch of our own synchronous ArkTS work on the UI thread. */
interface UiTaskSpan {
  name: string;
  startMs: number;
  endMs: number;
}

/** How many recent ui_task spans to keep for attribution against a later dropped frame. */
const UI_TASK_SPAN_LIMIT: number = 256;

/** Spans shorter than this are not worth a log line of their own. */
const UI_TASK_LOG_MIN_MS: number = 4;

/**
 * Quiet period that ends a tile render-key pass. A build resolves every tile's key within the same
 * pass, so waiting for this much silence after the last resolution collects the whole set instead of
 * logging 17 partial snapshots.
 */
const TILE_KEY_FLUSH_DEBOUNCE_MS: number = 60;

/** Tile ids listed individually when a snapshot changes, so the log stays one readable line. */
const TILE_KEY_CHANGED_SAMPLE_LIMIT: number = 6;

/**
 * Temporary probes for "page finished loading, then the first swipe stutters".
 *
 * Three independent measurements, because they answer different questions:
 * - the platform watchers report whether the dropped frames are ArkWeb *fling* jank (page/render
 *   process) or app main-thread jank, with the platform's own frame timing;
 * - the frame-cadence probe chains `postFrameCallback` on the UI thread, which measures real VSync
 *   delivery gaps;
 * - the occupancy probe runs a self-rescheduling short timer and records how late it fires.
 *
 * The cadence probe alone cannot tell "the UI thread was busy" from "the UI thread was idle but
 * frames were not delivered": a VSync gap looks identical either way. The occupancy timer
 * separates them. Timers are dispatched on the same UI thread, so if ArkTS is blocked the timer
 * fires late by roughly the blocked duration (`occupancyMs` close to the gap); if ArkTS is idle
 * while the render pipeline drops frames, the timer keeps firing on time (`occupancyMs` small).
 * Read `occupancyMs` and `gap` together on one `frame_gap` line to attribute a hitch.
 *
 * Grep [DEBUG-load-scroll-jank-7c4d] to remove.
 */
class AiraLoadScrollJankFrameCallback extends FrameCallback {
  private readonly onFrameTick: (frameTimeInNano: number) => void;

  constructor(onFrameTick: (frameTimeInNano: number) => void) {
    super();
    this.onFrameTick = onFrameTick;
  }

  onFrame(frameTimeInNano: number): void {
    this.onFrameTick(frameTimeInNano);
  }

  onIdle(_timeLeftInNano: number): void {
  }
}

export class AiraLoadScrollJankProbe {
  private static watchersInstalled: boolean = false;
  private static cadenceActive: boolean = false;
  private static cadenceStartedAt: number = 0;
  private static cadenceFirstFrameMs: number = 0;
  private static cadenceLastFrameMs: number = 0;
  private static cadenceLastFrameWallMs: number = 0;
  private static cadenceFrameCount: number = 0;
  private static cadenceMaxGapMs: number = 0;
  private static cadenceGapsOverThreshold: number = 0;
  private static cadenceJankWindows: string[] = [];
  private static loadFinishedAt: number = 0;
  private static occupancyActive: boolean = false;
  private static occupancyGeneration: number = 0;
  private static occupancyExpectedAt: number = 0;
  private static occupancyMaxSinceFrameMs: number = 0;
  private static occupancyMaxMs: number = 0;
  private static occupancySampleMaxMs: number = 0;
  private static occupancyTicks: number = 0;
  private static uiTaskSpans: UiTaskSpan[] = [];
  private static tileKeyCurrent: Map<string, string> = new Map<string, string>();
  private static tileKeyLogged: Map<string, string> = new Map<string, string>();
  private static tileKeyLastSignature: string = '';
  private static tileKeyThemeMode: string = '';
  private static tileKeyLastLoggedThemeMode: string = '';
  private static tileKeyShowNames: boolean = false;
  private static tileKeyFlushPending: boolean = false;

  /**
   * Subscribes to the platform's own scroll and main-thread jank events. These carry the frame
   * timing the system measured, so they can separate "the Web render process dropped frames while
   * flinging" from "the ArkTS main thread was blocked".
   */
  static installPlatformJankWatchers(): void {
    if (AiraLoadScrollJankProbe.watchersInstalled) {
      return;
    }
    AiraLoadScrollJankProbe.watchersInstalled = true;
    AiraLoadScrollJankProbe.configureMainThreadJankPolicy();
    AiraLoadScrollJankProbe.subscribe([
      hiAppEvent.event.SCROLL_ARKWEB_FLING_JANK,
      hiAppEvent.event.SCROLL_JANK,
      hiAppEvent.event.MAIN_THREAD_JANK,
      // The configurable variant, which the policy above applies to. It is a distinct event name, so
      // subscribing to only `MAIN_THREAD_JANK` would leave the collected stacks unreported.
      MAIN_THREAD_JANK_V2_EVENT_NAME
    ]);
  }

  /**
   * Turns on call-stack collection for main-thread jank with a threshold we control.
   *
   * Subscribing alone was not enough: the default policy only samples when the main thread times out
   * twice in a row inside 150-450ms and ignores the first 10s after thread start, while the blocks
   * under investigation are 40-50ms. The event therefore never fired (zero `platform name=` lines in
   * every capture).
   *
   * The configurable variant is a *different event*: `hiappevent_event.h` defines
   * `EVENT_MAIN_THREAD_JANK_V2 "MAIN_THREAD_JANK_V2"`, and `hiappevent_param.h` defines its parameters
   * in snake_case (`log_type`, `sample_interval`, `ignore_startup_time`, `sample_count`,
   * `report_times_per_app`, `auto_stop_sampling`), all `@since 22`. The structured
   * `configEventPolicy(MainThreadJankPolicy)` path rejected on this device, and
   * `setEventConfig` is the API whose own doc comment says it currently supports MAIN_THREAD_JANK.
   *
   * `log_type: 1` collects only the call stack, at the threshold given by `sample_interval`
   * (documented range 50-500ms, default 150), so 50 makes our 40-50ms blocks eligible.
   *
   * This is per-process in-app configuration; it needs no developer-options switch.
   */
  /**
   * Probes which (event name, value type) combination the platform accepts for the main-thread jank
   * config, because the surface is inconsistent across the docs and the device:
   *
   * - `@ohos.hiviewdfx.hiAppEvent.d.ts` types the config as `Record<string, ParamType>` (number,
   *   string, boolean accepted) and says only `MAIN_THREAD_JANK` is supported;
   * - `hiappevent_param.h` defines the same parameters for `MAIN_THREAD_JANK_V2` in snake_case;
   * - the native `OH_HiAppEvent_SetConfigItem(config, itemName, itemValue)` takes the value as
   *   `const char*`, i.e. a string.
   *
   * Every numeric value was rejected with 401 "Invalid param value for event config.", so this runs
   * the combinations and logs the outcome of each instead of assuming one of them works.
   */
  private static applyMainThreadJankConfig(): void {
    AiraLoadScrollJankProbe.applyJankConfigStep('MAIN_THREAD_JANK', 'log_type', MAIN_THREAD_JANK_LOG_TYPE_STACK);
    AiraLoadScrollJankProbe.applyJankConfigStep('MAIN_THREAD_JANK', 'log_type', `${MAIN_THREAD_JANK_LOG_TYPE_STACK}`);
    AiraLoadScrollJankProbe.applyJankConfigStep(MAIN_THREAD_JANK_V2_EVENT_NAME, 'log_type',
      `${MAIN_THREAD_JANK_LOG_TYPE_STACK}`);
    AiraLoadScrollJankProbe.applyJankConfigStep(MAIN_THREAD_JANK_V2_EVENT_NAME, 'sample_interval',
      `${MAIN_THREAD_JANK_SAMPLE_INTERVAL_MS}`);
  }

  private static applyJankConfigStep(eventName: string, key: string, value: hiAppEvent.ParamType): void {
    const config: Record<string, hiAppEvent.ParamType> = {};
    config[key] = value;
    const label = `${eventName}/${key}=${value}(${typeof value})`;
    try {
      hiAppEvent.setEventConfig(eventName, config)
        .then((): void => {
          hilog.info(DOMAIN, TAG, '%{public}s jank_policy_step ok %{public}s', EVENT_PREFIX, label);
        })
        .catch((error: Error): void => {
          hilog.warn(DOMAIN, TAG, '%{public}s jank_policy_step rejected %{public}s %{public}s',
            EVENT_PREFIX, label, AiraLoadScrollJankProbe.describeError(error));
        });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '%{public}s jank_policy_step threw %{public}s %{public}s',
        EVENT_PREFIX, label, AiraLoadScrollJankProbe.describeError(error));
    }
  }

  private static configureMainThreadJankPolicy(): void {
    AiraLoadScrollJankProbe.applyMainThreadJankConfig();
  }

  /**
   * Reads `code`/`message` off a caught rejection without assuming it is a well-formed Error.
   *
   * Two logging attempts failed before this one: `JSON.stringify(error)` printed `err=null` (a
   * `BusinessError` has no enumerable fields), and reading `.code` directly then threw *inside* the
   * catch handler, so neither `then` nor `catch` logged anything at all. Guard the field reads.
   */
  private static describeError(error: Error): string {
    try {
      const like = error as BusinessErrorLike;
      const code = like.code;
      const message = like.message;
      return `code=${code === undefined ? 'none' : code} message=${message === undefined ? 'none' : message}`;
    } catch (_error) {
      return 'unreadable';
    }
  }

  private static subscribe(eventNames: string[]): void {
    try {
      hiAppEvent.addWatcher({
        name: 'aira_load_scroll_jank_watcher',
        appEventFilters: [
          {
            domain: hiAppEvent.domain.OS,
            names: eventNames
          }
        ],
        onReceive: (_domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>): void => {
          AiraLoadScrollJankProbe.logEventGroups(appEventGroups);
        }
      });
      hilog.info(DOMAIN, TAG, '%{public}s watcher installed names=%{public}s',
        EVENT_PREFIX, eventNames.join(','));
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '%{public}s watcher failed err=%{public}s',
        EVENT_PREFIX, JSON.stringify(error));
    }
  }

  private static logEventGroups(appEventGroups: Array<hiAppEvent.AppEventGroup>): void {
    for (const group of appEventGroups) {
      const events = group.appEventInfos;
      for (const info of events) {
        AiraLoadScrollJankProbe.logEventParams(info.name, info.params);
      }
    }
  }

  private static logEventParams(name: string, rawParams: object): void {
    const params = rawParams as Record<string, hiAppEvent.ParamType>;
    const keys = Object.keys(params);
    for (const key of keys) {
      const value = params[key];
      if (Array.isArray(value)) {
        hilog.info(DOMAIN, TAG, '%{public}s platform name=%{public}s %{public}s=%{public}s',
          EVENT_PREFIX, name, key, JSON.stringify(value));
        continue;
      }
      hilog.info(DOMAIN, TAG, '%{public}s platform name=%{public}s %{public}s=%{public}s',
        EVENT_PREFIX, name, key, String(value));
    }
  }

  /**
   * Starts a bounded UI-thread frame cadence probe. Call it when a page reports load-finished so the
   * window covers the first swipe that follows the page appearing.
   */
  static startFrameCadence(uiContext: UIContext, windowMs: number = 6000): void {
    if (AiraLoadScrollJankProbe.cadenceActive) {
      return;
    }
    AiraLoadScrollJankProbe.cadenceActive = true;
    AiraLoadScrollJankProbe.cadenceStartedAt = Date.now();
    AiraLoadScrollJankProbe.cadenceLastFrameMs = 0;
    AiraLoadScrollJankProbe.cadenceLastFrameWallMs = 0;
    AiraLoadScrollJankProbe.cadenceFrameCount = 0;
    AiraLoadScrollJankProbe.cadenceMaxGapMs = 0;
    AiraLoadScrollJankProbe.cadenceGapsOverThreshold = 0;
    AiraLoadScrollJankProbe.cadenceJankWindows = [];
    AiraLoadScrollJankProbe.startOccupancyProbe();
    hilog.info(DOMAIN, TAG, '%{public}s cadence_start windowMs=%{public}d',
      EVENT_PREFIX, Math.round(windowMs));
    AiraLoadScrollJankProbe.postCadenceFrame(uiContext, windowMs);
  }

  /**
   * Runs a self-rescheduling timer and keeps the worst lateness seen. Rescheduling from the actual
   * fire time (rather than a fixed interval from start) keeps a single late tick from biasing every
   * later measurement.
   */
  private static startOccupancyProbe(): void {
    if (AiraLoadScrollJankProbe.occupancyActive) {
      return;
    }
    AiraLoadScrollJankProbe.occupancyActive = true;
    AiraLoadScrollJankProbe.occupancyExpectedAt = Date.now() + OCCUPANCY_TICK_MS;
    AiraLoadScrollJankProbe.occupancyMaxSinceFrameMs = 0;
    AiraLoadScrollJankProbe.occupancyMaxMs = 0;
    AiraLoadScrollJankProbe.occupancySampleMaxMs = 0;
    AiraLoadScrollJankProbe.occupancyTicks = 0;
    AiraLoadScrollJankProbe.scheduleOccupancyTick();
  }

  private static scheduleOccupancyTick(): void {
    const generation = AiraLoadScrollJankProbe.occupancyGeneration;
    setTimeout((): void => {
      if (!AiraLoadScrollJankProbe.occupancyActive ||
        generation !== AiraLoadScrollJankProbe.occupancyGeneration) {
        return;
      }
      const now = Date.now();
      const latenessMs = now - AiraLoadScrollJankProbe.occupancyExpectedAt;
      if (latenessMs > AiraLoadScrollJankProbe.occupancyMaxSinceFrameMs) {
        AiraLoadScrollJankProbe.occupancyMaxSinceFrameMs = latenessMs;
      }
      if (latenessMs > AiraLoadScrollJankProbe.occupancyMaxMs) {
        AiraLoadScrollJankProbe.occupancyMaxMs = latenessMs;
      }
      if (latenessMs > AiraLoadScrollJankProbe.occupancySampleMaxMs) {
        AiraLoadScrollJankProbe.occupancySampleMaxMs = latenessMs;
      }
      AiraLoadScrollJankProbe.occupancyTicks += 1;
      // Periodic baseline so a large lateness during a hitch can be compared against what this
      // thread normally reports while scrolling smoothly. Without it a single big number proves
      // nothing.
      if (AiraLoadScrollJankProbe.occupancyTicks % OCCUPANCY_SAMPLE_TICKS === 0) {
        hilog.info(DOMAIN, TAG,
          '%{public}s occupancy_sample maxMs=%{public}d sinceLoadFinished=%{public}d',
          EVENT_PREFIX,
          Math.round(AiraLoadScrollJankProbe.occupancyMaxSinceSampleMs()),
          AiraLoadScrollJankProbe.msSinceLoadFinished());
      }
      AiraLoadScrollJankProbe.occupancyExpectedAt = now + OCCUPANCY_TICK_MS;
      AiraLoadScrollJankProbe.scheduleOccupancyTick();
    }, OCCUPANCY_TICK_MS);
  }

  private static occupancyMaxSinceSampleMs(): number {
    const worst = AiraLoadScrollJankProbe.occupancySampleMaxMs;
    AiraLoadScrollJankProbe.occupancySampleMaxMs = 0;
    return worst;
  }

  private static stopOccupancyProbe(): void {
    // Bumping the generation makes any callback already queued a no-op, so a cadence restart cannot
    // end up with two chains racing over the same `occupancyExpectedAt` field.
    AiraLoadScrollJankProbe.occupancyActive = false;
    AiraLoadScrollJankProbe.occupancyGeneration += 1;
  }

  /**
   * Worst occupancy lateness accumulated during the interval that just ended, then reset.
   *
   * The reset happens for every frame (see `recordCadenceFrame`), not only when a gap is reported.
   * Resetting only on a reported gap would leave the window unbounded, and the value attributed to a
   * gap could then span far more wall time than that gap did, making it uninterpretable.
   */
  private static takeOccupancySinceFrame(): number {
    const worst = AiraLoadScrollJankProbe.occupancyMaxSinceFrameMs;
    AiraLoadScrollJankProbe.occupancyMaxSinceFrameMs = 0;
    return Math.round(worst);
  }

  private static postCadenceFrame(uiContext: UIContext, windowMs: number): void {
    try {
      uiContext.postFrameCallback(new AiraLoadScrollJankFrameCallback((frameTimeInNano: number): void => {
        const frameMs = AiraLoadScrollJankProbe.toMilliseconds(frameTimeInNano);
        AiraLoadScrollJankProbe.recordCadenceFrame(frameMs);
        if (Date.now() - AiraLoadScrollJankProbe.cadenceStartedAt >= windowMs) {
          AiraLoadScrollJankProbe.finishFrameCadence();
          return;
        }
        AiraLoadScrollJankProbe.postCadenceFrame(uiContext, windowMs);
      }));
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '%{public}s cadence_post_failed err=%{public}s',
        EVENT_PREFIX, JSON.stringify(error));
      AiraLoadScrollJankProbe.finishFrameCadence();
    }
  }

  private static recordCadenceFrame(frameMs: number): void {
    AiraLoadScrollJankProbe.cadenceFrameCount += 1;
    // Occupancy is sampled per frame, so the value reported with a gap covers exactly that gap.
    const occupancyMs = AiraLoadScrollJankProbe.takeOccupancySinceFrame();
    const wallMs = Date.now();
    const wallGapMs = AiraLoadScrollJankProbe.cadenceLastFrameWallMs > 0
      ? wallMs - AiraLoadScrollJankProbe.cadenceLastFrameWallMs
      : 0;
    AiraLoadScrollJankProbe.cadenceLastFrameWallMs = wallMs;
    if (AiraLoadScrollJankProbe.cadenceLastFrameMs <= 0) {
      AiraLoadScrollJankProbe.cadenceLastFrameMs = frameMs;
      AiraLoadScrollJankProbe.cadenceFirstFrameMs = frameMs;
      return;
    }
    const gapMs = frameMs - AiraLoadScrollJankProbe.cadenceLastFrameMs;
    AiraLoadScrollJankProbe.cadenceLastFrameMs = frameMs;
    if (gapMs <= JANK_FRAME_GAP_MS) {
      return;
    }
    AiraLoadScrollJankProbe.cadenceGapsOverThreshold += 1;
    AiraLoadScrollJankProbe.cadenceMaxGapMs = Math.max(AiraLoadScrollJankProbe.cadenceMaxGapMs, gapMs);
    // Keep only the widest few windows: the log buffer is small and the outliers are what matters.
    AiraLoadScrollJankProbe.cadenceJankWindows.push([
      't+', Math.round(frameMs - AiraLoadScrollJankProbe.cadenceFirstFrameMs), 'ms gap=', Math.round(gapMs)
    ].join(''));
    if (AiraLoadScrollJankProbe.cadenceJankWindows.length > 12) {
      AiraLoadScrollJankProbe.cadenceJankWindows.shift();
    }
    // `gap` is derived from VSync timestamps while `occupancyMs` is wall clock, so they are not
    // directly comparable; `wallGapMs` is the same interval measured on the wall clock. Attribute a
    // hitch by comparing `occupancyMs` against `wallGapMs`, not against `gap`.
    const windowStartWallMs = wallMs - wallGapMs;
    hilog.info(DOMAIN, TAG,
      '%{public}s frame_gap t+%{public}dms gap=%{public}dms wallGapMs=%{public}d ' +
      'occupancyMs=%{public}d sinceLoadFinished=%{public}dms uiTasks=%{public}s',
      EVENT_PREFIX,
      Math.round(frameMs - AiraLoadScrollJankProbe.cadenceFirstFrameMs),
      Math.round(gapMs),
      Math.round(wallGapMs),
      occupancyMs,
      AiraLoadScrollJankProbe.msSinceLoadFinished(),
      AiraLoadScrollJankProbe.describeUiTasksInWindow(windowStartWallMs, wallMs));
  }

  private static toMilliseconds(frameTimeInNano: number): number {
    if (!Number.isFinite(frameTimeInNano)) {
      return 0;
    }
    // The callback reports nanoseconds; the millisecond scale this probe logs is 1e6 below it.
    return frameTimeInNano / 1e6;
  }

  private static finishFrameCadence(): void {
    if (!AiraLoadScrollJankProbe.cadenceActive) {
      return;
    }
    AiraLoadScrollJankProbe.cadenceActive = false;
    AiraLoadScrollJankProbe.stopOccupancyProbe();
    hilog.info(DOMAIN, TAG,
      '%{public}s cadence_end frames=%{public}d maxGap=%{public}dms gapsOver%{public}d=%{public}d maxOccupancyMs=%{public}d ticks=%{public}d windows=%{public}s',
      EVENT_PREFIX,
      AiraLoadScrollJankProbe.cadenceFrameCount,
      Math.round(AiraLoadScrollJankProbe.cadenceMaxGapMs),
      JANK_FRAME_GAP_MS,
      AiraLoadScrollJankProbe.cadenceGapsOverThreshold,
      Math.round(AiraLoadScrollJankProbe.occupancyMaxMs),
      AiraLoadScrollJankProbe.occupancyTicks,
      AiraLoadScrollJankProbe.cadenceJankWindows.join('|'));
  }

  static markPageEnd(): void {
    hilog.info(DOMAIN, TAG, '%{public}s timeline page_end', EVENT_PREFIX);
  }

  static markLoadFinished(): void {
    AiraLoadScrollJankProbe.loadFinishedAt = Date.now();
    AiraLoadScrollJankProbe.cadenceFirstFrameMs = 0;
    hilog.info(DOMAIN, TAG, '%{public}s timeline load_finished', EVENT_PREFIX);
  }

  private static msSinceLoadFinished(): number {
    if (AiraLoadScrollJankProbe.loadFinishedAt <= 0) {
      return -1;
    }
    return Date.now() - AiraLoadScrollJankProbe.loadFinishedAt;
  }

  /** Bracket for a block of ArkTS work that runs on the UI thread. */
  static startTimed(): number {
    return Date.now();
  }

  static endTimed(event: string, startedAt: number, extra: string = ''): void {
    hilog.info(DOMAIN, TAG, '%{public}s task %{public}s durationMs=%{public}d sinceLoadFinished=%{public}d %{public}s',
      EVENT_PREFIX,
      event,
      Date.now() - startedAt,
      AiraLoadScrollJankProbe.msSinceLoadFinished(),
      extra);
  }

  /**
   * Bracket for a stretch of our own synchronous UI-thread code.
   *
   * `startTimed`/`endTimed` report a duration but leave it to the reader to decide whether it landed
   * on a bad frame. These spans are retained, so a later `frame_gap` can name which of our handlers
   * (if any) actually overlapped that specific window. That is the difference between "the UI thread
   * was busy" and "our code made it busy", and only the second one is ours to fix.
   */
  static beginUiTask(name: string): number {
    return Date.now();
  }

  static endUiTask(name: string, startedAt: number): void {
    const endedAt = Date.now();
    const span: UiTaskSpan = { name: name, startMs: startedAt, endMs: endedAt };
    AiraLoadScrollJankProbe.uiTaskSpans.push(span);
    if (AiraLoadScrollJankProbe.uiTaskSpans.length > UI_TASK_SPAN_LIMIT) {
      AiraLoadScrollJankProbe.uiTaskSpans.shift();
    }
    const durationMs = endedAt - startedAt;
    if (durationMs < UI_TASK_LOG_MIN_MS) {
      return;
    }
    hilog.info(DOMAIN, TAG, '%{public}s ui_task %{public}s durationMs=%{public}d sinceLoadFinished=%{public}d',
      EVENT_PREFIX,
      name,
      durationMs,
      AiraLoadScrollJankProbe.msSinceLoadFinished());
  }

  /** Names and offsets of our own UI-thread spans that overlap `[fromWallMs, toWallMs]`. */
  private static describeUiTasksInWindow(fromWallMs: number, toWallMs: number): string {
    if (fromWallMs <= 0) {
      return 'none';
    }
    const parts: string[] = [];
    for (const span of AiraLoadScrollJankProbe.uiTaskSpans) {
      if (span.endMs < fromWallMs || span.startMs > toWallMs) {
        continue;
      }
      parts.push(`${span.name}@+${span.startMs - fromWallMs}ms/${span.endMs - span.startMs}ms`);
    }
    return parts.length === 0 ? 'none' : parts.join(',');
  }

  /**
   * Records one tile's render key for the current build pass.
   *
   * Question it answers: when a page opens, does the whole grid get new keys at once? The per-tile
   * key is `` `${iconKey}:${themeMode}:${names|icons}` ``, so a change in the resolved theme mode
   * alone would flip all 17 keys and rebuild all 17 tiles in one frame. That is our own state, and
   * `uiTasks=none` cannot see it: the `@StorageProp` write is fast, while the rebuild it triggers
   * runs inside ArkUI's own frame pass, outside our `beginUiTask`/`endUiTask` brackets.
   *
   * The snapshot is logged with `sinceLoadFinished`, so a flip can be put next to a dropped frame.
   */
  static noteShortcutRenderKey(
    shortcutId: string,
    renderKey: string,
    themeMode: string,
    showNames: boolean
  ): void {
    AiraLoadScrollJankProbe.tileKeyCurrent.set(shortcutId, renderKey);
    AiraLoadScrollJankProbe.tileKeyThemeMode = themeMode;
    AiraLoadScrollJankProbe.tileKeyShowNames = showNames;
    if (AiraLoadScrollJankProbe.tileKeyFlushPending) {
      return;
    }
    AiraLoadScrollJankProbe.tileKeyFlushPending = true;
    setTimeout((): void => {
      AiraLoadScrollJankProbe.flushShortcutRenderKeys();
    }, TILE_KEY_FLUSH_DEBOUNCE_MS);
  }

  private static flushShortcutRenderKeys(): void {
    AiraLoadScrollJankProbe.tileKeyFlushPending = false;
    const ids: string[] = Array.from(AiraLoadScrollJankProbe.tileKeyCurrent.keys()).sort();
    const parts: string[] = [];
    for (const id of ids) {
      parts.push(`${id}=${AiraLoadScrollJankProbe.tileKeyCurrent.get(id) ?? ''}`);
    }
    const signature = parts.join('|');
    if (signature === AiraLoadScrollJankProbe.tileKeyLastSignature) {
      return;
    }
    const changed: string[] = [];
    for (const id of ids) {
      if (AiraLoadScrollJankProbe.tileKeyLogged.get(id) !== AiraLoadScrollJankProbe.tileKeyCurrent.get(id)) {
        changed.push(id);
      }
    }
    let vanished = 0;
    for (const id of Array.from(AiraLoadScrollJankProbe.tileKeyLogged.keys())) {
      if (!AiraLoadScrollJankProbe.tileKeyCurrent.has(id)) {
        vanished += 1;
      }
    }
    const previousThemeMode = AiraLoadScrollJankProbe.tileKeyLastLoggedThemeMode;
    AiraLoadScrollJankProbe.tileKeyLastSignature = signature;
    AiraLoadScrollJankProbe.tileKeyLastLoggedThemeMode = AiraLoadScrollJankProbe.tileKeyThemeMode;
    const nextLogged = new Map<string, string>();
    for (const id of ids) {
      nextLogged.set(id, AiraLoadScrollJankProbe.tileKeyCurrent.get(id) ?? '');
    }
    AiraLoadScrollJankProbe.tileKeyLogged = nextLogged;
    const sample = changed.slice(0, TILE_KEY_CHANGED_SAMPLE_LIMIT).join(',');
    hilog.info(DOMAIN, TAG,
      '%{public}s tile_keys total=%{public}d changed=%{public}d vanished=%{public}d ' +
      'allChanged=%{public}s themeMode=%{public}s previousThemeMode=%{public}s showNames=%{public}s ' +
      'changedIds=%{public}s sinceLoadFinished=%{public}d',
      EVENT_PREFIX,
      ids.length,
      changed.length,
      vanished,
      ids.length > 0 && changed.length === ids.length ? 'yes' : 'no',
      AiraLoadScrollJankProbe.tileKeyThemeMode,
      previousThemeMode.length === 0 ? 'none' : previousThemeMode,
      AiraLoadScrollJankProbe.tileKeyShowNames ? 'yes' : 'no',
      sample.length === 0 ? 'none' : sample,
      AiraLoadScrollJankProbe.msSinceLoadFinished());
  }

  private static tileBuildCount: number = 0;
  private static tileBuildMissingPixelMap: number = 0;
  private static tileBuildLastLoggedAt: number = 0;

  /**
   * Aggregated, throttled count of home shortcut tile builds.
   *
   * Question it answers: at the moment of a dropped frame, is the off-screen home grid rebuilding,
   * and are its tiles being built without a cached pixel map (which makes `SiteIconView` fall back
   * to `Image(<file>)` and decode the icon again at full resolution)? A per-tile log would flood
   * during scrolling, so the counters are summed and emitted at most four times a second.
   */
  static noteShortcutTileBuild(hasPixelMap: boolean): void {
    AiraLoadScrollJankProbe.tileBuildCount += 1;
    if (!hasPixelMap) {
      AiraLoadScrollJankProbe.tileBuildMissingPixelMap += 1;
    }
    const now = Date.now();
    const sinceLastLog = now - AiraLoadScrollJankProbe.tileBuildLastLoggedAt;
    if (AiraLoadScrollJankProbe.tileBuildLastLoggedAt !== 0 && sinceLastLog < 250) {
      return;
    }
    const tiles = AiraLoadScrollJankProbe.tileBuildCount;
    const missing = AiraLoadScrollJankProbe.tileBuildMissingPixelMap;
    AiraLoadScrollJankProbe.tileBuildCount = 0;
    AiraLoadScrollJankProbe.tileBuildMissingPixelMap = 0;
    AiraLoadScrollJankProbe.tileBuildLastLoggedAt = now;
    hilog.info(DOMAIN, TAG,
      '%{public}s home_tile_build tiles=%{public}d missingPixelMap=%{public}d sinceLoadFinished=%{public}d',
      EVENT_PREFIX,
      tiles,
      missing,
      AiraLoadScrollJankProbe.msSinceLoadFinished());
  }
}
