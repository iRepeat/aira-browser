import { describe, expect, it } from '@ohos/hypium';
import {
  BROWSER_FONT_SCALE_PINNED,
  BrowserShellFontScalePolicy
} from '../main/ets/core/browser/BrowserShellFontScalePolicy';

export default function browserShellFontScalePolicyTest(): void {
  describe('BrowserShellFontScalePolicy', () => {
    it('follows the system font scale on the phone shell', 0, () => {
      const policy = new BrowserShellFontScalePolicy();

      expect(policy.followsSystemFontScale('phone')).assertTrue();
      expect(policy.resolveAppUiScale(1.75, 'phone')).assertEqual(1.75);
      expect(policy.resolveContentScale(1.75, 'phone')).assertEqual(1.75);
    });

    it('pins both UI and content text on the PC shell', 0, () => {
      const policy = new BrowserShellFontScalePolicy();

      expect(policy.followsSystemFontScale('large_screen')).assertFalse();
      expect(policy.resolveAppUiScale(3.2, 'large_screen')).assertEqual(BROWSER_FONT_SCALE_PINNED);
      expect(policy.resolveContentScale(3.2, 'large_screen')).assertEqual(BROWSER_FONT_SCALE_PINNED);
      expect(policy.resolveContentScale(0.5, 'large_screen')).assertEqual(BROWSER_FONT_SCALE_PINNED);
      expect(BROWSER_FONT_SCALE_PINNED).assertEqual(1);
    });

    it('falls back to the app default for an unusable system scale', 0, () => {
      const policy = new BrowserShellFontScalePolicy();

      expect(policy.resolveAppUiScale(0, 'phone')).assertEqual(BROWSER_FONT_SCALE_PINNED);
      expect(policy.resolveContentScale(Number.NaN, 'phone')).assertEqual(BROWSER_FONT_SCALE_PINNED);
    });
  });
}
