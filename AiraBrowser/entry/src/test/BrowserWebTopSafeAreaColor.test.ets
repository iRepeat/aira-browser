import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserChromeRuntimeCoordinator,
  BrowserChromeRuntimeState
} from '../main/ets/core/browser/BrowserChromeRuntimeCoordinator';

const ACTIVE_TAB_ID: string = 'tab-1';

function buildThemeState(): BrowserChromeRuntimeState {
  const coordinator = new BrowserChromeRuntimeCoordinator();
  return coordinator.applyPageChromeTheme(coordinator.createState(), ACTIVE_TAB_ID, {
    themeColor: '#1A73E8',
    pageBackgroundColor: '#FFFFFF',
    prefersDarkScheme: false,
    supportsDarkAppearance: false
  });
}

export default function browserWebTopSafeAreaColorTest(): void {
  describe('BrowserChromeRuntimeCoordinator top safe area color', () => {
    it('keeps following the page color while scroll immersion only reserves the strip', 0, () => {
      const coordinator = new BrowserChromeRuntimeCoordinator();

      expect(coordinator.resolveWebTopSafeAreaBackdropColor({
        state: buildThemeState(),
        activeTabId: ACTIVE_TAB_ID,
        webPageVisible: true,
        pageDrawnUnderTopSafeArea: false,
        resolvedThemeMode: 'light'
      })).assertEqual('#1A73E8');
    });

    it('drops the separate strip color once the page draws under the top safe area', 0, () => {
      const coordinator = new BrowserChromeRuntimeCoordinator();

      expect(coordinator.resolveWebTopSafeAreaBackdropColor({
        state: buildThemeState(),
        activeTabId: ACTIVE_TAB_ID,
        webPageVisible: true,
        pageDrawnUnderTopSafeArea: true,
        resolvedThemeMode: 'light'
      })).assertEqual('');
    });

    it('drops the strip color when no web page is visible', 0, () => {
      const coordinator = new BrowserChromeRuntimeCoordinator();

      expect(coordinator.resolveWebTopSafeAreaBackdropColor({
        state: buildThemeState(),
        activeTabId: ACTIVE_TAB_ID,
        webPageVisible: false,
        pageDrawnUnderTopSafeArea: false,
        resolvedThemeMode: 'light'
      })).assertEqual('');
    });
  });
}
