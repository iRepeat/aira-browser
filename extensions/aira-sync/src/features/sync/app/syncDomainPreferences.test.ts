import { afterEach, describe, expect, test } from 'vitest';
import {
  readBookmarkSyncDomainEnabled,
  readHistorySyncDomainEnabled,
  writeBookmarkSyncDomainEnabled,
  writeHistorySyncDomainEnabled,
} from './syncDomainPreferences';
import {
  BOOKMARK_SYNC_DOMAIN_ENABLED_KEY,
  HISTORY_SYNC_DOMAIN_ENABLED_KEY,
} from './leafTabSyncStorageKeys';

type StorageArea = Record<string, unknown>;

function installChromeStorageMock(): { storage: StorageArea; restore: () => void } {
  const storage: StorageArea = {};
  const previousChrome = globalThis.chrome;
  Object.assign(globalThis, {
    chrome: {
      storage: {
        local: {
          get: async (keys: string[]) => Object.fromEntries(keys.map((key) => [key, storage[key]])),
          set: async (values: Record<string, unknown>) => Object.assign(storage, values),
          remove: async (keys: string[]) => keys.forEach((key) => delete storage[key]),
        },
      },
    },
  });
  return {
    storage,
    restore: () => {
      if (previousChrome === undefined) delete (globalThis as { chrome?: unknown }).chrome;
      else Object.assign(globalThis, { chrome: previousChrome });
    },
  };
}

describe('sync domain preferences', () => {
  const mocks: Array<{ restore: () => void }> = [];

  afterEach(() => {
    mocks.splice(0).forEach((mock) => mock.restore());
  });

  test('unset keys default to enabled for both domains', async () => {
    const mock = installChromeStorageMock();
    mocks.push(mock);
    await expect(readBookmarkSyncDomainEnabled()).resolves.toBe(true);
    await expect(readHistorySyncDomainEnabled()).resolves.toBe(true);
  });

  test('writing a switch persists per-domain and only that domain', async () => {
    const mock = installChromeStorageMock();
    mocks.push(mock);
    await writeBookmarkSyncDomainEnabled(false);
    await expect(readBookmarkSyncDomainEnabled()).resolves.toBe(false);
    await expect(readHistorySyncDomainEnabled()).resolves.toBe(true);
    expect(mock.storage[BOOKMARK_SYNC_DOMAIN_ENABLED_KEY]).toBe('false');

    await writeHistorySyncDomainEnabled(false);
    await expect(readHistorySyncDomainEnabled()).resolves.toBe(false);
    expect(mock.storage[HISTORY_SYNC_DOMAIN_ENABLED_KEY]).toBe('false');

    await writeBookmarkSyncDomainEnabled(true);
    await expect(readBookmarkSyncDomainEnabled()).resolves.toBe(true);
  });
});
