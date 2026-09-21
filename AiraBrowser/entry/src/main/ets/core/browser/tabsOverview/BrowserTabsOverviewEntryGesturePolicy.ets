/**
 * When the middle bar's upward drag belongs to the tab overview.
 *
 * The overview is not pulled open any more: an upward drag on the middle bar is a second trigger for
 * the same open the 标签页 button performs, so the only question left here is whether this drag is the
 * one that asks for it. Everything about how the screen then appears belongs to the overview's own
 * entry, which is the same for both triggers.
 */

/** Upward travel that claims the drag for the overview. Small, because the response must be instant. */
export const BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_CLAIM_VP: number = 8;

export class BrowserTabsOverviewEntryGesturePolicy {
  /**
   * Whether an upward drag on the middle of the bottom bar belongs to the tab overview.
   *
   * The drag is claimed once, on the way up, so a drag that has already been claimed stays claimed
   * for its whole life — including a pull back down — which is why the second argument exists
   * rather than the caller re-testing the travel.
   */
  shouldClaim(offsetY: number, alreadyClaimed: boolean): boolean {
    if (alreadyClaimed) {
      return true;
    }
    const travel = Number.isFinite(offsetY) ? offsetY : 0;
    return travel <= -BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_CLAIM_VP;
  }
}
