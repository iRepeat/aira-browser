export interface BrowserSearchEnginePopupLayoutInput {
  /**
   * Global top of the popup's anchor, in vp. Zero or negative means the host has not measured
   * the anchor yet; the popup then keeps its full menu instead of collapsing to one row.
   */
  anchorTopVp: number;
  /** Window top safe inset, in vp. Keeps the popup clear of the status bar and cutout. */
  topSafeInsetVp: number;
  rowHeightVp: number;
  contentPaddingVp: number;
  /** Rows the menu would like to show; the policy only ever lowers this. */
  preferredRowCount: number;
  /** Gap kept between the popup and the anchor. Matches the popup's own `targetSpace`. */
  anchorGapVp: number;
}

export interface BrowserSearchEnginePopupLayout {
  visibleRowCount: number;
  heightVp: number;
}

/**
 * Caps the search-engine popup to the space that is genuinely free above its anchor.
 *
 * `Placement.Top` alone is not enough. ArkUI flips a popup to the opposite side when the
 * requested side cannot show it "completely", and it judges that against the *window*. This
 * window is never resized for the soft keyboard - the shell runs `KeyboardAvoidMode.NONE` and
 * lifts its own toolbar by the keyboard inset - so the keyboard's half of the screen still
 * counts as free. A 252vp menu anchored near the bottom of a short viewport therefore gets
 * flipped downwards and lands underneath the keyboard, where only its top edge stays visible.
 *
 * The host measures the anchor instead and asks this policy how many rows fit above it. A popup
 * that already fits is never flipped, so the menu can no longer open onto the keyboard.
 */
export class BrowserSearchEnginePopupLayoutViewModel {
  resolve(input: BrowserSearchEnginePopupLayoutInput): BrowserSearchEnginePopupLayout {
    const rowHeight = Math.max(1, this.normalizePositive(input.rowHeightVp, 1));
    const contentPadding = Math.max(0, this.normalizePositive(input.contentPaddingVp, 0));
    const preferredRowCount = Math.max(1, Math.floor(this.normalizePositive(input.preferredRowCount, 1)));
    const anchorTop = this.normalizePositive(input.anchorTopVp, 0);
    if (anchorTop <= 0) {
      return this.buildLayout(preferredRowCount, rowHeight, contentPadding);
    }
    const availableHeight = anchorTop -
      Math.max(0, this.normalizePositive(input.topSafeInsetVp, 0)) -
      Math.max(0, this.normalizePositive(input.anchorGapVp, 0));
    const affordableRows = Math.floor(
      (availableHeight - contentPadding * 2) / rowHeight
    );
    return this.buildLayout(
      Math.max(1, Math.min(preferredRowCount, affordableRows)),
      rowHeight,
      contentPadding
    );
  }

  private buildLayout(rowCount: number, rowHeight: number, contentPadding: number): BrowserSearchEnginePopupLayout {
    return {
      visibleRowCount: rowCount,
      heightVp: rowCount * rowHeight + contentPadding * 2
    };
  }

  private normalizePositive(value: number, fallback: number): number {
    return Number.isFinite(value) ? value : fallback;
  }
}
