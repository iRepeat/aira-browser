import { describe, expect, test } from 'vitest';
import { resolveCrossDeviceTransportKind } from './crossDeviceTransport';

describe('cross-device transport', () => {
  test('uses the account when sync is off or uses another source, as long as the same account is signed in', () => {
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: null,
      personalServerReady: false,
      accountSignedIn: true,
    })).toBe('account');
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: 'webdav',
      personalServerReady: false,
      accountSignedIn: true,
    })).toBe('account');
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: 'aira-cloud',
      personalServerReady: false,
      accountSignedIn: true,
    })).toBe('account');
  });

  test('does not treat a signed-out account as a link, even if cloud sync was previously selected', () => {
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: 'aira-cloud',
      personalServerReady: false,
      accountSignedIn: false,
    })).toBe('unavailable');
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: 'webdav',
      personalServerReady: true,
      accountSignedIn: false,
    })).toBe('unavailable');
  });

  test('keeps Personal Server as its own channel and does not fall through to the account', () => {
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: 'personal-server',
      personalServerReady: true,
      accountSignedIn: true,
    })).toBe('personal-server');
    expect(resolveCrossDeviceTransportKind({
      selectedSyncSource: 'personal-server',
      personalServerReady: false,
      accountSignedIn: true,
    })).toBe('unavailable');
  });
});
