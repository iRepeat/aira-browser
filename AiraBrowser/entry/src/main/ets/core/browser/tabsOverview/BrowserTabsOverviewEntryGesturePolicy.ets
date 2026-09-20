/**
 * The finger's part of the bottom-bar entry gesture.
 *
 * Dragging up on the middle of the bottom bar opens the tab overview, but not as a finished screen:
 * the finger keeps the page's snapshot, shrinking it towards the deck's card, so the overview is
 * pulled open rather than switched to. This file owns that mapping and nothing else — the panel only
 * recognises the drag, and the overlay only paints what `resolveLayout` returns.
 */

/** Upward travel that claims the drag for the overview. Small, because the response must be instant. */
export const BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_CLAIM_VP: number = 8;
/**
 * Fraction of the sheet height that takes the page all the way down to the deck's card.
 *
 * Shorter would make the shrink jumpy and leave nothing for the finger to control; longer would need
 * most of the screen before the overview reads as open.
 */
/**
 * The travel that takes the page all the way down to the smallest the pull can make the card.
 *
 * Almost the height of the sheet, so the finger has something to do for the whole drag: reaching the
 * deck's card size after a quarter of it left the rest of the pull looking as if it had jammed.
 */
export const BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_REACH_RATIO: number = 0.95;
/** How much of the deck's card the pull can shrink it to, at the very top. */
export const BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_MIN_CARD_RATIO: number = 0.45;
/**
 * Above 1 the pull eases out: every further vp of travel changes the card less than the last one.
 *
 * This is the whole feel of the gesture. A `reach` of a quarter of the screen with a damped tail made
 * the card shrink fastest at the start and then creep, which reads as the pull being wired backwards.
 */
const PULL_EASE: number = 1.8;
/** Sideways travel only nudges the row, so the finger never drags a card out of the overview. */
export const BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_PAN_RATIO: number = 0.34;
/** The most sideways travel can move the row, as a fraction of the sheet width. */
const PAN_LIMIT_RATIO: number = 0.36;

export interface BrowserTabsOverviewEntryGestureInput {
  /** Finger travel since the drag was claimed, in vp. Up is negative */
  offsetX: number;
  offsetY: number;
  viewportWidth: number;
  viewportHeight: number;
}

export interface BrowserTabsOverviewEntryGestureLayout {
  /**
   * How far the pull has taken the card, 0 at the page and 1 at its smallest, already eased.
   *
   * The card's size is `lerp(page, smallest, progress)` and nothing else: the caller must not scale
   * the small end by `progress` as well, or the size becomes quadratic in the travel — accelerating,
   * which is the pull shrinking fastest just before the finger stops instead of slowest.
   */
  progress: number;
  /** Damped pan for the card, in vp. */
  panX: number;
  panY: number;
}

export class BrowserTabsOverviewEntryGesturePolicy {
  /**
   * Whether an upward drag on the middle of the bottom bar belongs to the tab overview.
   *
   * The drag is claimed once, on the way up, so the gesture that opens the overview is the same one
   * that keeps driving it. A drag that has already been claimed stays claimed for its whole life,
   * including a pull back down, which is why the second argument exists rather than the caller
   * re-testing the travel.
   */
  shouldClaim(offsetY: number, alreadyClaimed: boolean): boolean {
    if (alreadyClaimed) {
      return true;
    }
    const travel = Number.isFinite(offsetY) ? offsetY : 0;
    return travel <= -BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_CLAIM_VP;
  }

  resolveLayout(input: BrowserTabsOverviewEntryGestureInput): BrowserTabsOverviewEntryGestureLayout {
    const width = this.positive(input.viewportWidth);
    const height = this.positive(input.viewportHeight);
    const travel = Math.max(0, -this.finite(input.offsetY));
    const reach = Math.max(1, height * BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_REACH_RATIO);

    // One curve for the whole pull, easing out from the first millimetre to the last: the card answers
    // the finger at once and then answers less and less, so every further vp of travel shrinks it less
    // than the one before. The caller turns this into `lerp(page, smallest, progress)` — one
    // interpolation, so the size stays monotonic in the rate it changes by.
    const ratio = Math.min(1, travel / reach);
    const progress = this.clamp(1 - Math.pow(1 - ratio, PULL_EASE), 0, 1);

    const limitX = width * PAN_LIMIT_RATIO;
    return {
      progress: progress,
      panX: this.clamp(this.finite(input.offsetX) * BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_PAN_RATIO,
        -limitX, limitX),
      // The card also drifts with the finger, damped, so the pull reads as movement rather than a
      // pure zoom. Downward travel is damped harder: the page is already the largest it can be.
      panY: this.dampedTravel(this.finite(input.offsetY), height)
    };
  }

  /** Finger travel as the small drift the card is allowed, in vp. */
  private dampedTravel(offsetY: number, height: number): number {
    const limit = height * 0.08;
    const travel = offsetY < 0 ? offsetY * 0.30 : offsetY * 0.18;
    return this.clamp(travel, -limit, limit);
  }

  private positive(value: number): number {
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  private finite(value: number): number {
    return Number.isFinite(value) ? value : 0;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }
}
