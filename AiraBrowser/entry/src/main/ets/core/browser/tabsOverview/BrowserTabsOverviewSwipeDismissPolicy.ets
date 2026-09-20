export type BrowserTabsOverviewSwipeAxis = 'horizontal' | 'upward';

export interface BrowserTabsOverviewSwipeReleaseInput {
  mode: BrowserTabsOverviewSwipeAxis;
  /** Signed travel along the gesture axis, in vp. */
  offsetVp: number;
  /** Signed release speed along the gesture axis, in vp per second. */
  velocityVpPerSecond: number;
  thresholdVp: number;
}

/**
 * Half of the card, along the axis the dismiss gesture actually moves on.
 *
 * Clamped, because "half the card" alone is not usable at the extremes: a three-column desktop
 * card is wide enough that half of it is a long drag, and the shortest grid cards would start
 * dismissing on a nudge. The bounds keep every window in a range that feels like a deliberate
 * swipe without ever being a chore.
 */
export const BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_EXTENT_RATIO: number = 0.5;
export const BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MIN_THRESHOLD_VP: number = 64;
export const BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MAX_THRESHOLD_VP: number = 128;
/**
 * A release at or above this speed is a fling and dismisses without waiting for the full
 * threshold. Distance-only dismissal is what made the gesture feel heavy: a quick flick was
 * discarded unless the finger had also travelled far enough.
 */
export const BROWSER_TABS_OVERVIEW_SWIPE_FLING_VELOCITY_VP_PER_SECOND: number = 600;
/** A fling still needs this much travel, so a twitch on a tap cannot dismiss a card. */
export const BROWSER_TABS_OVERVIEW_SWIPE_FLING_MIN_DISTANCE_VP: number = 20;

/**
 * The dismissed card keeps the speed the gesture ended with.
 *
 * The flight is `travel / speed`: a quick flick is gone in a blink and a slow drag drifts away, so
 * the card leaves under the finger's own momentum instead of playing a fixed animation that has
 * nothing to do with the gesture. Both ends are bounded — a lazy release would otherwise hold the
 * card on screen for seconds waiting out its own travel, and a violent flick would be over before
 * the fade reads.
 */
export const BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS: number = 170;
export const BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS: number = 620;

/**
 * How far a tab card must travel before releasing it closes the tab.
 *
 * The gesture reports absolute vp, so a single fixed number cannot be right everywhere: the
 * same distance is a fifth of a three-column desktop card and two thirds of a two-column phone
 * card, which is exactly the "different threshold on different screens" complaint. Deriving the
 * threshold from the card keeps the perceived effort identical across window sizes.
 */
export class BrowserTabsOverviewSwipeDismissPolicy {
  /**
   * `cardExtentVp` is the card's width for a horizontal swipe and its full height (identity
   * header plus preview) for an upward one.
   */
  resolveThresholdVp(cardExtentVp: number): number {
    const extent = Number.isFinite(cardExtentVp) ? Math.max(0, cardExtentVp) : 0;
    const desired = extent * BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_EXTENT_RATIO;
    return Math.min(
      BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MAX_THRESHOLD_VP,
      Math.max(BROWSER_TABS_OVERVIEW_SWIPE_DISMISS_MIN_THRESHOLD_VP, desired)
    );
  }

  /**
   * An upward dismiss only ever travels negative; a horizontal one accepts either direction.
   * A travel that crossed the threshold always commits, and a fast enough fling commits early
   * as long as it is heading the dismiss way.
   */
  shouldDismissOnRelease(input: BrowserTabsOverviewSwipeReleaseInput): boolean {
    const offset = Number.isFinite(input.offsetVp) ? input.offsetVp : 0;
    const velocity = Number.isFinite(input.velocityVpPerSecond) ? input.velocityVpPerSecond : 0;
    const threshold = Math.max(1, Number.isFinite(input.thresholdVp) ? input.thresholdVp : 1);
    if (input.mode === 'upward') {
      return offset <= -threshold || this.isDismissingFling(-offset, -velocity);
    }
    if (Math.abs(offset) >= threshold) {
      return true;
    }
    return this.isDismissingFling(Math.abs(offset), Math.abs(velocity)) && velocity * offset > 0;
  }

  private isDismissingFling(distance: number, speed: number): boolean {
    return speed >= BROWSER_TABS_OVERVIEW_SWIPE_FLING_VELOCITY_VP_PER_SECOND &&
      distance >= BROWSER_TABS_OVERVIEW_SWIPE_FLING_MIN_DISTANCE_VP;
  }

  /**
   * How long the dismissed card takes to cover the rest of its way out.
   *
   * `travelVp` is the distance still to cover when the finger let go and `velocityVpPerSecond` is the
   * speed it was moving at, both measured along the dismiss axis. The card is given exactly that
   * speed, so a flick leaves quickly and a slow release drifts; the bounds only clamp the extremes,
   * where a literal `travel / speed` would hang the card on screen or leave nothing to see.
   */
  resolveFlyoutDurationMs(travelVp: number, velocityVpPerSecond: number): number {
    const travel = Number.isFinite(travelVp) ? Math.max(0, travelVp) : 0;
    if (travel <= 0) {
      return BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS;
    }
    const speed = Math.abs(Number.isFinite(velocityVpPerSecond) ? velocityVpPerSecond : 0);
    if (speed <= 0) {
      return BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS;
    }
    return Math.min(
      BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS,
      Math.max(BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS, (travel / speed) * 1000)
    );
  }
}
