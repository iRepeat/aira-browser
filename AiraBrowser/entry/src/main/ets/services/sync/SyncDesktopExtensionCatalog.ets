import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

/**
 * One place that knows where Aira-sync can be installed from. The browser store
 * entries are Official-only: the Community distribution does not publish to them,
 * so a Community build offers the local package instead and lets the user open
 * the download page in Aira.
 */
export type SyncDesktopExtensionEntryId = 'chrome' | 'edge' | 'firefox' | 'local_package';

/**
 * `copy_link` is for entries that are installed on a computer: the phone cannot
 * open a browser store, so the link is copied and pasted on the desktop.
 * `open_link` is for pages Aira itself can show.
 */
export type SyncDesktopExtensionEntryAction = 'copy_link' | 'open_link';

export interface SyncDesktopExtensionEntry {
  id: SyncDesktopExtensionEntryId;
  title: string;
  url: string;
  action: SyncDesktopExtensionEntryAction;
  /** Present when the target page is locked; copied to the clipboard as the page opens. */
  password: string;
}

export const SYNC_DESKTOP_EXTENSION_CHROME_URL: string =
  'https://chromewebstore.google.com/detail/aira-focused-webdav-new-t/hgifgplkfbfmkogjdpcjkgbgkikcjpni';
export const SYNC_DESKTOP_EXTENSION_EDGE_URL: string =
  'https://microsoftedge.microsoft.com/addons/detail/afliopnmelmcajnmldmiklifmbchgfni';
export const SYNC_DESKTOP_EXTENSION_FIREFOX_URL: string =
  'https://addons.mozilla.org/zh-CN/firefox/addon/aira-focused-webdav-new-tab';
/** The community distribution's download entry, opened inside Aira. */
export const SYNC_DESKTOP_EXTENSION_LOCAL_PACKAGE_URL: string = 'https://wwbgv.lanzoul.com/b00oe0qfcd';
/** The download page is locked, so its password is copied as the page opens. */
export const SYNC_DESKTOP_EXTENSION_LOCAL_PACKAGE_PASSWORD: string = 'aira';

const SYNC_DESKTOP_EXTENSION_STORE_ENTRIES: SyncDesktopExtensionEntry[] = [
  {
    id: 'chrome',
    title: 'Chrome 插件',
    url: SYNC_DESKTOP_EXTENSION_CHROME_URL,
    action: 'copy_link',
    password: ''
  },
  {
    id: 'edge',
    title: 'Edge 插件',
    url: SYNC_DESKTOP_EXTENSION_EDGE_URL,
    action: 'copy_link',
    password: ''
  },
  {
    id: 'firefox',
    title: 'Firefox 插件',
    url: SYNC_DESKTOP_EXTENSION_FIREFOX_URL,
    action: 'copy_link',
    password: ''
  }
];

const SYNC_DESKTOP_EXTENSION_LOCAL_ENTRY: SyncDesktopExtensionEntry = {
  id: 'local_package',
  title: '本地安装包',
  url: SYNC_DESKTOP_EXTENSION_LOCAL_PACKAGE_URL,
  action: 'open_link',
  password: SYNC_DESKTOP_EXTENSION_LOCAL_PACKAGE_PASSWORD
};

export function resolveSyncDesktopExtensionEntries(): SyncDesktopExtensionEntry[] {
  if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
    return SYNC_DESKTOP_EXTENSION_STORE_ENTRIES.concat([SYNC_DESKTOP_EXTENSION_LOCAL_ENTRY]);
  }
  return [SYNC_DESKTOP_EXTENSION_LOCAL_ENTRY];
}

export function resolveSyncDesktopExtensionEntryActionLabel(entry: SyncDesktopExtensionEntry): string {
  return entry.action === 'open_link' ? '查看' : '复制';
}
