import { describe, expect, it } from '@ohos/hypium';
import {
  CENTERED_DIALOG_MAX_WIDTH_VP,
  CenteredDialogWidthViewModel
} from '../main/ets/core/browser/CenteredDialogWidthViewModel';

export default function centeredDialogWidthViewModelTest(): void {
  describe('CenteredDialogWidthViewModel', () => {
    it('keeps the phone-proportional percentage while it fits the maximum', 0, () => {
      const viewModel = new CenteredDialogWidthViewModel();

      const phoneWidth = viewModel.resolve(360);
      const tabletWidth = viewModel.resolve(466);

      expect(phoneWidth.percentBased).assertTrue();
      expect(phoneWidth.widthVp).assertEqual(0);
      expect(tabletWidth.percentBased).assertTrue();
    });

    it('pins to the shared maximum once the window is a PC/large-screen size', 0, () => {
      const viewModel = new CenteredDialogWidthViewModel();

      const desktopWidth = viewModel.resolve(1280);

      expect(desktopWidth.percentBased).assertFalse();
      expect(desktopWidth.widthVp).assertEqual(CENTERED_DIALOG_MAX_WIDTH_VP);
    });

    it('switches to the maximum exactly when the percentage would overshoot it', 0, () => {
      const viewModel = new CenteredDialogWidthViewModel();

      const atThreshold = viewModel.resolve(467);

      expect(atThreshold.percentBased).assertFalse();
      expect(atThreshold.widthVp).assertEqual(CENTERED_DIALOG_MAX_WIDTH_VP);
    });

    it('keeps the phone percentage when the window width is unknown', 0, () => {
      const viewModel = new CenteredDialogWidthViewModel();

      const unknownWidth = viewModel.resolve(0);

      expect(unknownWidth.percentBased).assertTrue();
    });
  });
}
