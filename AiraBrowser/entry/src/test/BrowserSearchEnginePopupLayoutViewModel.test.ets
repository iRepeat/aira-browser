import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserSearchEnginePopupLayoutViewModel
} from '../main/ets/core/browser/BrowserSearchEnginePopupLayoutViewModel';

const ROW_HEIGHT: number = 48;
const CONTENT_PADDING: number = 6;
const ANCHOR_GAP: number = 8;

function resolveLayout(
  viewModel: BrowserSearchEnginePopupLayoutViewModel,
  anchorTopVp: number,
  topSafeInsetVp: number,
  preferredRowCount: number
) {
  return viewModel.resolve({
    anchorTopVp: anchorTopVp,
    topSafeInsetVp: topSafeInsetVp,
    rowHeightVp: ROW_HEIGHT,
    contentPaddingVp: CONTENT_PADDING,
    preferredRowCount: preferredRowCount,
    anchorGapVp: ANCHOR_GAP
  });
}

export default function browserSearchEnginePopupLayoutViewModelTest(): void {
  describe('BrowserSearchEnginePopupLayoutViewModel', () => {
    it('keeps every preferred row when they fit above the anchor', 0, () => {
      const layout = resolveLayout(new BrowserSearchEnginePopupLayoutViewModel(), 600, 37, 5);

      expect(layout.visibleRowCount).assertEqual(5);
      expect(layout.heightVp).assertEqual(5 * ROW_HEIGHT + CONTENT_PADDING * 2);
    });

    /**
     * The reported short-viewport case: a 707vp-tall window lifts the toolbar to ~290vp, leaving
     * ~253vp above it. The full 252vp menu plus its 8vp gap does not fit, and before the cap the
     * framework flipped the popup downwards onto the keyboard.
     */
    it('caps rows so the menu still fits where a full-height menu would be flipped', 0, () => {
      const layout = resolveLayout(new BrowserSearchEnginePopupLayoutViewModel(), 290, 37, 5);

      expect(layout.visibleRowCount).assertEqual(4);
      const menuHeight = layout.heightVp;
      expect(menuHeight <= 290 - 37 - ANCHOR_GAP).assertTrue();
      expect(menuHeight).assertEqual(4 * ROW_HEIGHT + CONTENT_PADDING * 2);
    });

    it('falls back to a single row when almost no space remains', 0, () => {
      const layout = resolveLayout(new BrowserSearchEnginePopupLayoutViewModel(), 90, 37, 5);

      expect(layout.visibleRowCount).assertEqual(1);
      expect(layout.heightVp).assertEqual(ROW_HEIGHT + CONTENT_PADDING * 2);
    });

    it('never exceeds the preferred row count even with room to spare', 0, () => {
      const layout = resolveLayout(new BrowserSearchEnginePopupLayoutViewModel(), 900, 0, 3);

      expect(layout.visibleRowCount).assertEqual(3);
    });

    it('keeps the full menu before the host has measured the anchor', 0, () => {
      const layout = resolveLayout(new BrowserSearchEnginePopupLayoutViewModel(), 0, 37, 5);

      expect(layout.visibleRowCount).assertEqual(5);
    });

    it('subtracts the top safe inset from the available height', 0, () => {
      const viewModel = new BrowserSearchEnginePopupLayoutViewModel();

      expect(resolveLayout(viewModel, 290, 37, 5).visibleRowCount)
        .assertEqual(resolveLayout(viewModel, 253, 0, 5).visibleRowCount);
    });
  });
}
