import { describe, expect, it } from '@ohos/hypium';
import {
  CENTERED_DIALOG_MAX_WIDTH_VP,
  CenteredDialogWidthViewModel
} from '../main/ets/core/browser/CenteredDialogWidthViewModel';
import { DesktopDialogWidthViewModel } from '../main/ets/core/browser/DesktopDialogWidthViewModel';
import { resolveSystemSheetDialogTier } from '../main/ets/core/browser/DesktopDialogSheetPolicy';
import { DESKTOP_DIALOG_CORNER_RADIUS_VP } from '../main/ets/core/browser/BrowserDialogPresentationTokens';

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

  describe('DesktopDialogWidthViewModel', () => {
    it('resolves each declared tier on a wide window', 0, () => {
      const viewModel = new DesktopDialogWidthViewModel();

      expect(viewModel.resolve('xs', 1440, 900).widthVp).assertEqual(360);
      expect(viewModel.resolve('s', 1440, 900).widthVp).assertEqual(420);
      expect(viewModel.resolve('m', 1440, 900).widthVp).assertEqual(520);
      expect(viewModel.resolve('l', 1440, 900).widthVp).assertEqual(640);
      expect(viewModel.resolve('xl', 1440, 900).widthVp).assertEqual(720);
      expect(viewModel.resolve('m', 1440, 900).cornerRadiusVp).assertEqual(DESKTOP_DIALOG_CORNER_RADIUS_VP);
    });

    it('uses the full usable width below 600vp and tightens the radius', 0, () => {
      const viewModel = new DesktopDialogWidthViewModel();

      const narrow = viewModel.resolve('m', 560, 800);

      expect(narrow.widthVp).assertEqual(512);
      expect(narrow.fullWidth).assertTrue();
      expect(narrow.cornerRadiusVp).assertEqual(20);
    });

    it('steps L and XL down one tier below 1000vp', 0, () => {
      const viewModel = new DesktopDialogWidthViewModel();

      expect(viewModel.resolve('l', 900, 700).widthVp).assertEqual(520);
      expect(viewModel.resolve('xl', 900, 700).widthVp).assertEqual(640);
      expect(viewModel.resolve('m', 900, 700).widthVp).assertEqual(520);
    });

    it('stacks three actions and a pair that would wrap', 0, () => {
      const viewModel = new DesktopDialogWidthViewModel();

      expect(viewModel.resolveActionLayout(['取消', '保存', '删除'], 360, 1280)).assertEqual('stack');
      expect(viewModel.resolveActionLayout(['取消', '保存'], 312, 1280)).assertEqual('row');
      expect(viewModel.resolveActionLayout(['仅在使用期间允许', '不允许'], 200, 1280)).assertEqual('stack');
      expect(viewModel.resolveActionLayout(['取消', '保存'], 312, 420)).assertEqual('stack');
    });

    it('keeps the phone alert width owner unchanged', 0, () => {
      const phone = new CenteredDialogWidthViewModel().resolve(390);
      const desktop = new DesktopDialogWidthViewModel().resolve('xs', 1280, 800);

      expect(phone.percentBased).assertTrue();
      expect(desktop.widthVp).assertEqual(360);
      expect(CENTERED_DIALOG_MAX_WIDTH_VP).assertEqual(420);
    });
  });

  describe('DesktopDialogSheetPolicy', () => {
    it('maps system sheets onto content-shaped tiers', 0, () => {
      expect(resolveSystemSheetDialogTier('releaseNotice')).assertEqual('l');
      expect(resolveSystemSheetDialogTier('desktopLoginConfirm')).assertEqual('s');
      expect(resolveSystemSheetDialogTier('novelCatalog')).assertEqual('m');
      expect(resolveSystemSheetDialogTier('readerSettings')).assertEqual('l');
      expect(resolveSystemSheetDialogTier('webPageTools')).assertEqual('m');
    });
  });
}
