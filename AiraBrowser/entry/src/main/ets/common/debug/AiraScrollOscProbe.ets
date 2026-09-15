import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ScrollOscProbe';
const HEARTBEAT_MS: number = 50;
const REVERSAL_MIN_PX: number = 2;

// Temporary bottom-panel scroll oscillation probes. Grep [DEBUG-scroll-osc-2a71] to remove.
export class AiraScrollOscProbe {
  private static lastSignBySource: Map<string, number> = new Map();
  private static lastHeartbeatAt: number = 0;

  static markSource(sourceId: string, scrollY: number): void {
    AiraScrollOscProbe.lastSignBySource.set(sourceId, 0);
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-scroll-osc-2a71] source source=%{public}s y=%{public}d',
      sourceId,
      Math.round(scrollY)
    );
  }

  /**
   * Records a Web content-area geometry change. The content height is `hostHeight - topInset`, and
   * the top inset follows status-bar visibility, so this is what decides whether collapsing the
   * chrome actually resizes the Web viewport underneath the user's finger.
   */
  static markViewport(
    statusBarVisible: boolean,
    topInsetPx: number,
    contentHeightPx: number,
    contentTopPx: number,
    hostHeightPx: number
  ): void {
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-scroll-osc-2a71] viewport statusBar=%{public}d inset=%{public}d contentHeight=%{public}d contentTop=%{public}d host=%{public}d',
      statusBarVisible ? 1 : 0,
      Math.round(topInsetPx),
      Math.round(contentHeightPx),
      Math.round(contentTopPx),
      Math.round(hostHeightPx)
    );
  }

  /**
   * Records one scroll sample per source. Panel transitions and direction reversals always log;
   * an ordinary sample only logs on a heartbeat, so a held drag cannot flood the log buffer on a
   * content-heavy page that reports offsets every frame.
   *
   * `interaction` is the resolver's own reason for accepting the sample as user input. It separates
   * a real touch gesture (`touch_active`, `recent_scroll_gesture`) from `scroll_delta_fallback`,
   * which accepts any 2px page movement with no touch at all. Panel presentation changes are gated
   * on the former, so this field is what proves whether an oscillation was finger-driven.
   */
  static markSignal(
    sourceId: string,
    scrollY: number,
    delta: number,
    reason: string,
    interaction: string
  ): void {
    const normalizedDelta = Number.isFinite(delta) ? delta : 0;
    const sign = normalizedDelta > 0 ? 1 : (normalizedDelta < 0 ? -1 : 0);
    const now = Date.now();
    const previousSign = AiraScrollOscProbe.lastSignBySource.get(sourceId) ?? 0;
    if (sign !== 0) {
      AiraScrollOscProbe.lastSignBySource.set(sourceId, sign);
    }
    const isReversal = sign !== 0 && previousSign !== 0 && previousSign !== sign &&
      Math.abs(normalizedDelta) >= REVERSAL_MIN_PX;
    const isTransition = reason.indexOf('scroll_compact') >= 0 || reason.indexOf('scroll_hide') >= 0 ||
      reason.indexOf('scroll_reveal') >= 0;
    if (isTransition) {
      hilog.info(
        DOMAIN,
        TAG,
        '[DEBUG-scroll-osc-2a71] transition source=%{public}s y=%{public}d delta=%{public}d reason=%{public}s interaction=%{public}s',
        sourceId,
        Math.round(scrollY),
        Math.round(normalizedDelta),
        reason,
        interaction
      );
      return;
    }
    if (isReversal) {
      hilog.info(
        DOMAIN,
        TAG,
        '[DEBUG-scroll-osc-2a71] reversal source=%{public}s y=%{public}d delta=%{public}d reason=%{public}s interaction=%{public}s',
        sourceId,
        Math.round(scrollY),
        Math.round(normalizedDelta),
        reason,
        interaction
      );
      return;
    }
    if (now - AiraScrollOscProbe.lastHeartbeatAt >= HEARTBEAT_MS) {
      AiraScrollOscProbe.lastHeartbeatAt = now;
      hilog.info(
        DOMAIN,
        TAG,
        '[DEBUG-scroll-osc-2a71] tick source=%{public}s y=%{public}d delta=%{public}d reason=%{public}s interaction=%{public}s',
        sourceId,
        Math.round(scrollY),
        Math.round(normalizedDelta),
        reason,
        interaction
      );
    }
  }
}
