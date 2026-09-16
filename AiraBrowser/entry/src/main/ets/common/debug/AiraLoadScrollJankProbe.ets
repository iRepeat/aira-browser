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
 * Temporary probes for "page finished loading, then the first swipe stutters".
 *
 * Two independent measurements, because they answer different questions:
 * - the platform watchers report whether the dropped frames are ArkWeb *fling* jank (page/render
 *   process) or app main-thread jank, with the platform's own frame timing;
 * - the frame-cadence probe chains `postFrameCallback` on the UI thread, which measures real VSync
 *   delivery gaps. Unlike a `setInterval` heartbeat, a late callback here cannot be explained by
 *   timer throttling or queueing, so a gap is evidence the UI thread was actually busy.
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
  private static cadenceFrameCount: number = 0;
  private static cadenceMaxGapMs: number = 0;
  private static cadenceGapsOverThreshold: number = 0;
  private static cadenceJankWindows: string[] = [];
  private static loadFinishedAt: number = 0;

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
    AiraLoadScrollJankProbe.subscribe([
      hiAppEvent.event.SCROLL_ARKWEB_FLING_JANK,
      hiAppEvent.event.SCROLL_JANK,
      hiAppEvent.event.MAIN_THREAD_JANK
    ]);
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
    AiraLoadScrollJankProbe.cadenceFrameCount = 0;
    AiraLoadScrollJankProbe.cadenceMaxGapMs = 0;
    AiraLoadScrollJankProbe.cadenceGapsOverThreshold = 0;
    AiraLoadScrollJankProbe.cadenceJankWindows = [];
    hilog.info(DOMAIN, TAG, '%{public}s cadence_start windowMs=%{public}d',
      EVENT_PREFIX, Math.round(windowMs));
    AiraLoadScrollJankProbe.postCadenceFrame(uiContext, windowMs);
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
    hilog.info(DOMAIN, TAG,
      '%{public}s frame_gap t+%{public}dms gap=%{public}dms sinceLoadFinished=%{public}dms',
      EVENT_PREFIX,
      Math.round(frameMs - AiraLoadScrollJankProbe.cadenceFirstFrameMs),
      Math.round(gapMs),
      AiraLoadScrollJankProbe.msSinceLoadFinished());
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
    hilog.info(DOMAIN, TAG,
      '%{public}s cadence_end frames=%{public}d maxGap=%{public}dms gapsOver%{public}d=%{public}d windows=%{public}s',
      EVENT_PREFIX,
      AiraLoadScrollJankProbe.cadenceFrameCount,
      Math.round(AiraLoadScrollJankProbe.cadenceMaxGapMs),
      JANK_FRAME_GAP_MS,
      AiraLoadScrollJankProbe.cadenceGapsOverThreshold,
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
