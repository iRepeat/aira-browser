import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserShellFamilyAvailability,
  BrowserWindowPresentationProfileCoordinator
} from '../main/ets/core/browser/BrowserWindowPresentationProfile';
import { BrowserTabletInterfaceModePolicy } from '../main/ets/core/browser/BrowserTabletInterfaceModePolicy';

export default function browserTabletInterfaceModePolicyTest(): void {
  describe('BrowserTabletInterfaceModePolicy', () => {
    it('lets phones expose interface mode and choose desktop UI explicitly', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const autoDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false
      });
      const desktopDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'desktop',
        pointerAvailable: false
      });
      const pointerAutoDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: true
      });

      expect(autoDecision.settingVisible).assertTrue();
      expect(autoDecision.shellFamily).assertEqual('phone');
      expect(pointerAutoDecision.settingVisible).assertTrue();
      expect(pointerAutoDecision.shellFamily).assertEqual('phone');
      expect(pointerAutoDecision.decisionReason).assertEqual('phone-auto-touch');
      expect(desktopDecision.settingVisible).assertTrue();
      expect(desktopDecision.shellFamily).assertEqual('large_screen');
      expect(desktopDecision.decisionReason).assertEqual('phone-desktop-override');
    });

    it('keeps computer-class devices locked to desktop UI without a setting entry', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const pcDecision = policy.resolve({
        detectedFormFactor: 'pc',
        selectedMode: 'touch',
        pointerAvailable: false
      });
      const twoInOneDecision = policy.resolve({
        detectedFormFactor: 'two_in_one',
        selectedMode: 'touch',
        pointerAvailable: false
      });

      expect(pcDecision.settingVisible).assertFalse();
      expect(pcDecision.shellFamily).assertEqual('large_screen');
      expect(twoInOneDecision.settingVisible).assertFalse();
      expect(twoInOneDecision.shellFamily).assertEqual('large_screen');
    });

    it('preserves tablet automatic pointer behavior', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const touchDecision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: false
      });
      const pointerDecision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: true
      });

      expect(touchDecision.settingVisible).assertTrue();
      expect(touchDecision.shellFamily).assertEqual('phone');
      expect(pointerDecision.settingVisible).assertTrue();
      expect(pointerDecision.shellFamily).assertEqual('large_screen');
    });

    it('marks phone presentation as switchable when desktop mode is selected', 0, () => {
      const coordinator = new BrowserWindowPresentationProfileCoordinator();
      const availability: BrowserShellFamilyAvailability = {
        phoneShellAvailable: true,
        largeScreenShellAvailable: true
      };

      const profile = coordinator.reconcile({
        platformDeviceType: 'phone',
        windowWidthVp: 420,
        windowHeightVp: 860,
        pointerAvailable: false,
        tabletInterfaceMode: 'desktop'
      }, availability, 1);

      expect(profile.shellFamily).assertEqual('large_screen');
      expect(profile.familyLocked).assertFalse();
      expect(profile.decisionReason).assertEqual('phone-desktop-override');
    });

    it('uses stable fold state only for automatic phone presentation', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const expandedDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded'
      });
      const foldedDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: true,
        foldState: 'folded'
      });
      const explicitTouchDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'touch',
        pointerAvailable: false,
        foldState: 'expanded'
      });

      expect(expandedDecision.shellFamily).assertEqual('large_screen');
      expect(expandedDecision.decisionReason).assertEqual('fold-expanded-auto-desktop');
      expect(foldedDecision.shellFamily).assertEqual('phone');
      expect(foldedDecision.decisionReason).assertEqual('folded-auto-touch');
      expect(explicitTouchDecision.shellFamily).assertEqual('phone');
      expect(explicitTouchDecision.decisionReason).assertEqual('phone-touch-override');
    });

    it('keeps the previous automatic heuristic when fold state is unknown', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const decision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: true,
        foldState: 'unknown'
      });

      expect(decision.shellFamily).assertEqual('large_screen');
      expect(decision.decisionReason).assertEqual('tablet-auto-pointer');
    });

    it('keeps a known pocket foldable on the touch shell when unfolded', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const puraX = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: true,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Pura X',
        deviceProductModel: 'VDE-AL00'
      });
      const pocket2 = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Pocket 2',
        deviceProductModel: 'LEM-AL00'
      });
      const novaFlip = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI nova Flip',
        deviceProductModel: 'PSD-AL00'
      });

      expect(puraX.shellFamily).assertEqual('phone');
      expect(puraX.decisionReason).assertEqual('small-fold-expanded-auto-touch');
      expect(puraX.settingVisible).assertTrue();
      expect(pocket2.shellFamily).assertEqual('phone');
      expect(novaFlip.shellFamily).assertEqual('phone');
    });

    it('never demotes a large foldable whose name extends a pocket one', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      // "HUAWEI Pura X" is a prefix of "HUAWEI Pura X Max", so a substring
      // match would wrongly send this 7.7 inch book fold to the touch shell.
      // Its aspect ratio (1.41) also sits above the ratio band that works for
      // Pura X, which is why identity and not geometry is the signal here.
      const puraXMax = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Pura X Max',
        deviceProductModel: 'HOP-AL00'
      });
      const mateXT = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Mate XT ULTIMATE DESIGN',
        deviceProductModel: 'GRL-AL10'
      });

      expect(puraXMax.shellFamily).assertEqual('large_screen');
      expect(puraXMax.decisionReason).assertEqual('fold-expanded-auto-desktop');
      expect(mateXT.shellFamily).assertEqual('large_screen');
    });

    it('never demotes an unknown foldable to touch merely for being unlisted', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const mateX6 = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Mate X6',
        deviceProductModel: 'ICL-AL10'
      });
      const unnamed = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'auto',
        pointerAvailable: false,
        foldState: 'expanded'
      });

      expect(mateX6.shellFamily).assertEqual('large_screen');
      expect(unnamed.shellFamily).assertEqual('large_screen');
    });

    it('still lets a pocket foldable opt into the desktop shell by hand', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      const desktopDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'desktop',
        pointerAvailable: false,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Pura X',
        deviceProductModel: 'VDE-AL00'
      });
      const touchDecision = policy.resolve({
        detectedFormFactor: 'phone',
        selectedMode: 'touch',
        pointerAvailable: true,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Mate X6',
        deviceProductModel: 'ICL-AL10'
      });

      expect(desktopDecision.shellFamily).assertEqual('large_screen');
      expect(desktopDecision.decisionReason).assertEqual('phone-desktop-override');
      expect(touchDecision.shellFamily).assertEqual('phone');
      expect(touchDecision.decisionReason).assertEqual('phone-touch-override');
    });

    it('recognises a pocket foldable from either identifier', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      // Market name alone, as on a device that reports no SKU.
      expect(policy.isKnownSmallFoldable('HUAWEI Pura X', '')).assertTrue();
      // SKU alone, as on a build whose marketing name is unset or generic.
      expect(policy.isKnownSmallFoldable('', 'VDE-AL00')).assertTrue();
      // Case, spacing and brand prefix are all normalised away.
      expect(policy.isKnownSmallFoldable('  huawei   pocket  s ', 'BAL-AL60')).assertTrue();
      expect(policy.isKnownSmallFoldable('HUAWEI nova Flip S', 'PSD-AL80')).assertTrue();
      // A device that omits the brand, or spells it in Chinese, still matches:
      // both sides are normalised, so the catalog may keep the brand spelled out.
      expect(policy.isKnownSmallFoldable('Pura X', '')).assertTrue();
      expect(policy.isKnownSmallFoldable('华为 Pura X', '')).assertTrue();
      // Large foldables and their SKUs must not match.
      expect(policy.isKnownSmallFoldable('', 'ICL-AL10')).assertFalse();
      expect(policy.isKnownSmallFoldable('HUAWEI Mate X5', 'ALT-AL10')).assertFalse();
      // Unset or generic identifiers are "unknown", never a match.
      expect(policy.isKnownSmallFoldable('', '')).assertFalse();
      expect(policy.isKnownSmallFoldable('OpenHarmony', 'ohos')).assertFalse();
      expect(policy.isKnownSmallFoldable('HUAWEI', '')).assertFalse();
    });

    it('does not exempt a tablet that reports a pocket foldable identity', 0, () => {
      const policy = new BrowserTabletInterfaceModePolicy();

      // Phone-class only: a tablet keeps its own path even when the reported
      // identity matches a pocket foldable.
      const decision = policy.resolve({
        detectedFormFactor: 'tablet',
        selectedMode: 'auto',
        pointerAvailable: true,
        foldState: 'expanded',
        deviceMarketName: 'HUAWEI Pura X',
        deviceProductModel: 'VDE-AL00'
      });

      expect(decision.shellFamily).assertEqual('large_screen');
      expect(decision.decisionReason).assertEqual('fold-expanded-auto-desktop');
    });
  });
}
