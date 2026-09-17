import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ToolbarPopupReopen';
const PREFIX: string = '[DEBUG-toolbar-popup-reopen-a91f]';

/**
 * Temporary probe for the bottom-toolbar popup that re-opens shortly after an interactive
 * dismiss (tap outside, then scroll the page).
 *
 * Two surfaces can own that popup, so both are traced through one prefix:
 *  - the toolbar system Sheet (`BrowserBottomAddressPanel.openToolbarSystemSheet`), whose every
 *    open path records the reason it was called, and whose dismissal records the owning instance
 *    token so a remount can be told apart from a real user dismissal;
 *  - the search-engine popup (`BrowserBottomChromeRenderer.bindPopup`), whose every visibility
 *    write records the value and the trigger.
 *
 * Every line is `event key=value ...` so a single `hdc hilog | grep a91f` capture shows the exact
 * call chain that re-opened the surface.
 */
export function logToolbarPopupReopen(event: string, fields: string): void {
  hilog.info(DOMAIN, TAG, '%{public}s %{public}s %{public}s', PREFIX, event, fields);
}
