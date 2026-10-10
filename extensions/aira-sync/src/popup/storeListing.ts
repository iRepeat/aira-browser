import {
  readInstalledHistoryBrowser,
  type HistoryBrowserKind,
} from '@/features/history-takeover/historyTakeoverPolicy';

// Verified public listings. The Gecko listing is addressed by its AMO slug; the
// Chromium detail pages below are built from the running extension's store ID.
const FIREFOX_STORE_LISTING_URL = 'https://addons.mozilla.org/firefox/addon/aira-focused-webdav-new-tab/';
const CHROME_WEB_STORE_LISTING_URL = 'https://chromewebstore.google.com/detail/hgifgplkfbfmkogjdpcjkgbgkikcjpni';
// The manual-install packages keep their own fixed IDs, which no store serves;
// those installs fall back to the public Chrome Web Store listing.
const MANUAL_INSTALL_EXTENSION_IDS = new Set([
  'plnjjlkaaonbccmjpfljbbbbaahfklem',
  'efehgppkhnkjamcpbipclfmmofdildji',
]);
const FIREFOX_BROWSER_KINDS = new Set<HistoryBrowserKind>([
  'zen',
  'floorp',
  'librewolf',
  'waterfox',
  'firefox',
]);

function readRuntimeExtensionId(): string {
  const runtime = globalThis.chrome?.runtime as { id?: string } | undefined;
  return String(runtime?.id || '').trim();
}

export function resolveStoreListingUrl(browserKind: HistoryBrowserKind): string {
  if (FIREFOX_BROWSER_KINDS.has(browserKind)) {
    return FIREFOX_STORE_LISTING_URL;
  }
  // A store install carries the store-assigned extension ID, so the detail page
  // built from the runtime ID always points at the store this copy came from.
  const extensionId = readRuntimeExtensionId();
  if (extensionId && !MANUAL_INSTALL_EXTENSION_IDS.has(extensionId)) {
    return browserKind === 'edge'
      ? `https://microsoftedge.microsoft.com/addons/detail/${extensionId}`
      : `https://chromewebstore.google.com/detail/${extensionId}`;
  }
  return CHROME_WEB_STORE_LISTING_URL;
}

export async function readStoreListingUrl(): Promise<string> {
  return resolveStoreListingUrl(await readInstalledHistoryBrowser());
}
