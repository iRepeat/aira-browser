import {
  readExtensionStorageRecord,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import {
  BOOKMARK_SYNC_DOMAIN_ENABLED_KEY,
  HISTORY_SYNC_DOMAIN_ENABLED_KEY,
} from './leafTabSyncStorageKeys';

// The domain master switches mirror the App's bookmark/history sync toggles:
// they pause every sync, upload, and capture for that domain on this device
// only, and they never delete local or remote data. An unset key means enabled.
const readDomainEnabled = async (storageKey: string): Promise<boolean> => {
  const record = await readExtensionStorageRecord([storageKey]);
  const value = record[storageKey];
  if (value === undefined || value === null) {
    return true;
  }
  return String(value) === 'true';
};

const writeDomainEnabled = async (storageKey: string, enabled: boolean): Promise<void> => {
  await writeExtensionStorageRecord({
    [storageKey]: String(enabled),
  });
};

export const readBookmarkSyncDomainEnabled = (): Promise<boolean> =>
  readDomainEnabled(BOOKMARK_SYNC_DOMAIN_ENABLED_KEY);

export const writeBookmarkSyncDomainEnabled = (enabled: boolean): Promise<void> =>
  writeDomainEnabled(BOOKMARK_SYNC_DOMAIN_ENABLED_KEY, enabled);

export const readHistorySyncDomainEnabled = (): Promise<boolean> =>
  readDomainEnabled(HISTORY_SYNC_DOMAIN_ENABLED_KEY);

export const writeHistorySyncDomainEnabled = (enabled: boolean): Promise<void> =>
  writeDomainEnabled(HISTORY_SYNC_DOMAIN_ENABLED_KEY, enabled);
