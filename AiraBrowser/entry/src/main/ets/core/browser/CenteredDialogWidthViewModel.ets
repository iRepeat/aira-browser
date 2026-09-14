/**
 * Width policy for centered alerts.
 *
 * AlertDialog.width accepts a Dimension but exposes no constraintSize, and a
 * percentage value is resolved against the WINDOW. A flat `90%` therefore reads
 * well on a phone but stretches a PC/large-screen alert nearly edge to edge.
 * This owner keeps the phone-proportional percentage only while it still fits
 * inside the shared centered-dialog maximum, and pins the alert to that maximum
 * on wider windows — the same cap every other Aira dialog already uses.
 */

export const CENTERED_DIALOG_MAX_WIDTH_VP: number = 420;
export const CENTERED_DIALOG_ALERT_WIDTH_RATIO: number = 0.9;
export const CENTERED_DIALOG_ALERT_WIDTH_PERCENT: string = '90%';

/** Resolved alert width: either a fixed vp value or the proportional percentage. */
export class CenteredDialogResolvedWidth {
  readonly percentBased: boolean;
  readonly widthVp: number;

  constructor(percentBased: boolean, widthVp: number) {
    this.percentBased = percentBased;
    this.widthVp = widthVp;
  }
}

export class CenteredDialogWidthViewModel {
  /**
   * Resolves the alert width from the window width in vp.
   *
   * A non-positive/unknown width keeps the phone-proportional percentage, so a
   * failed platform read never widens the alert.
   */
  resolve(windowWidthVp: number): CenteredDialogResolvedWidth {
    if (!Number.isFinite(windowWidthVp) || windowWidthVp <= 0 ||
      windowWidthVp * CENTERED_DIALOG_ALERT_WIDTH_RATIO <= CENTERED_DIALOG_MAX_WIDTH_VP) {
      return new CenteredDialogResolvedWidth(true, 0);
    }
    return new CenteredDialogResolvedWidth(false, CENTERED_DIALOG_MAX_WIDTH_VP);
  }
}
