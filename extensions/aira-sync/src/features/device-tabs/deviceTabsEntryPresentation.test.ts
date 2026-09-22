import { describe, expect, test } from 'vitest';
import {
  buildDeviceTabsEntryCopy,
  resolveDeviceTabsEntry,
  type DeviceTabsEntryInput,
} from './deviceTabsEntryPresentation';

const NOW = 1_800_000_000_000;

function input(overrides: Partial<DeviceTabsEntryInput> = {}): DeviceTabsEntryInput {
  return {
    airaCloudAvailable: true,
    selectedSyncSource: 'aira-cloud',
    personalServerReady: false,
    personalServerTabsCapable: false,
    signedIn: false,
    membershipPlan: '',
    membershipStatus: '',
    membershipExpiresAt: 0,
    membershipDegraded: false,
    linkEnabled: true,
    now: NOW,
    ...overrides,
  };
}

describe('device tabs entry presentation', () => {
  test('keeps a signed-out official user on the sign-in page', () => {
    expect(resolveDeviceTabsEntry(input())).toBe('sign_in');
    const copy = buildDeviceTabsEntryCopy('sign_in');
    expect(copy.title).toBe('登录后查看手机标签页');
    expect(copy.primaryAction).toBe('sign_in');
    expect(copy.secondaryAction).toBe('open_personal_server');
    expect(copy.secondaryLabel).toBe('使用私有化部署');
  });

  test('separates never-subscribed and expired Pro', () => {
    expect(resolveDeviceTabsEntry(input({
      signedIn: true,
      membershipPlan: 'club',
      membershipStatus: 'missing_plan_default_club',
    }))).toBe('pro_required');
    expect(buildDeviceTabsEntryCopy('pro_required').title).toBe('手机标签页需要 Aira Pro');
    expect(buildDeviceTabsEntryCopy('pro_required').message).toContain('请在手机 Aira 中开通');
    expect(buildDeviceTabsEntryCopy('pro_required').primaryAction).toBe('open_personal_server');

    expect(resolveDeviceTabsEntry(input({
      signedIn: true,
      membershipPlan: 'club',
      membershipStatus: 'expired',
    }))).toBe('pro_expired');
    expect(resolveDeviceTabsEntry(input({
      signedIn: true,
      membershipPlan: 'pro',
      membershipExpiresAt: NOW - 1,
    }))).toBe('pro_expired');
    expect(buildDeviceTabsEntryCopy('pro_expired').title).toBe('Aira Pro 已过期');
  });

  test('does not treat an unconfirmed membership check as a paywall', () => {
    expect(resolveDeviceTabsEntry(input({
      signedIn: true,
      membershipPlan: 'club',
      membershipDegraded: true,
    }))).toBe('membership_unavailable');
  });

  test('does not auto-enable the link for an active Pro user', () => {
    expect(resolveDeviceTabsEntry(input({
      signedIn: true,
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
      linkEnabled: false,
    }))).toBe('link_disabled');
    expect(buildDeviceTabsEntryCopy('link_disabled').primaryAction).toBe('enable_link');
    expect(resolveDeviceTabsEntry(input({
      signedIn: true,
      membershipPlan: 'pro',
      membershipExpiresAt: NOW + 1_000,
      linkEnabled: true,
    }))).toBe('ready');
  });

  test('uses a connected personal server without login or Pro', () => {
    expect(resolveDeviceTabsEntry(input({
      selectedSyncSource: 'personal-server',
      personalServerReady: true,
      personalServerTabsCapable: true,
      linkEnabled: true,
    }))).toBe('ready');
    expect(resolveDeviceTabsEntry(input({
      selectedSyncSource: 'personal-server',
      personalServerReady: false,
      signedIn: true,
      membershipPlan: 'pro',
    }))).toBe('connect_personal_server');
  });

  test('community only guides to private deployment', () => {
    expect(resolveDeviceTabsEntry(input({ airaCloudAvailable: false }))).toBe('connect_personal_server');
    const copy = buildDeviceTabsEntryCopy('connect_personal_server');
    expect(copy.title).toBe('请先连接私有化部署');
    expect(copy.message).not.toContain('Pro');
    expect(copy.primaryLabel).toBe('连接私有化部署');
  });
});
