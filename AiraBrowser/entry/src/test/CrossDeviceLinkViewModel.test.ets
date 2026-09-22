import { describe, expect, it } from '@ohos/hypium';
import {
  CrossDeviceLinkDeviceFact,
  CrossDeviceLinkFacts,
  CrossDeviceLinkProviderKind,
  CrossDeviceLinkViewState,
  CrossDeviceLinkViewModel,
  canEnableCrossDeviceLinkSwitch
} from '../main/ets/core/sync/CrossDeviceLinkViewModel';

function buildDevice(deviceId: string, platform: string, browserName: string, tabCount: number,
  ageMs: number): CrossDeviceLinkDeviceFact {
  return {
    deviceId: deviceId,
    deviceName: deviceId,
    platform: platform,
    browserName: browserName,
    tabCount: tabCount,
    ageMs: ageMs
  };
}

function buildFacts(providerKind: CrossDeviceLinkProviderKind): CrossDeviceLinkFacts {
  return {
    desktopLinkAvailable: true,
    providerKind: providerKind,
    bookmarkSyncEnabled: true,
    historySyncEnabled: true,
    // WebDAV is the only mode that cannot carry history to a desktop.
    historySyncSupported: providerKind !== 'webdav',
    deviceStatus: 'ready',
    deviceMessage: '',
    devices: [],
    account: { displayName: '', uid: '', avatarUri: '' },
    localDevice: { deviceName: 'Aira 手机', platform: 'HarmonyOS', browserName: 'Aira' },
    linkEnabled: true,
    linkSwitchEnabled: true,
    cloudEntitlement: 'active',
    hasConfiguredSync: true,
    goalLabel: 'Aira 云'
  };
}

function buildState(facts: CrossDeviceLinkFacts): CrossDeviceLinkViewState {
  return new CrossDeviceLinkViewModel().buildState(facts);
}

export default function crossDeviceLinkViewModelTest(): void {
  describe('CrossDeviceLinkViewModel', () => {
    it('carries the cross-device switch and the sync row as two separate things', 0, () => {
      const state = buildState(buildFacts('aira_cloud'));

      // The page owns the link switch; data sync is only a jump to its owner.
      expect(state.linkEnabled).assertTrue();
      expect(state.linkSwitchEnabled).assertTrue();
      expect(state.linkSwitchTitle).assertEqual('跨设备互联');
      expect(state.syncSettingsValue).assertEqual('Aira 云');
      expect(state.addDeviceTitle).assertEqual('添加设备');
      expect(state.addDeviceDetail.length > 0).assertTrue();
    });

    it('mirrors the presence owner link switch instead of keeping its own', 0, () => {
      const off = buildFacts('aira_cloud');
      off.linkEnabled = false;

      expect(buildState(off).linkEnabled).assertFalse();
    });

    it('keeps pausing data sync independent from the cross-device link', 0, () => {
      const facts = buildFacts('aira_cloud');
      // Data sync is off, yet tab handoff and page push stay usable.
      facts.linkEnabled = true;
      facts.hasConfiguredSync = false;
      const state = buildState(facts);

      expect(state.linkEnabled).assertTrue();
      expect(state.syncSettingsValue).assertEqual('去开启同步');
    });

    it('disables the link switch when no mode can carry it', 0, () => {
      const facts = buildFacts('none');
      facts.linkSwitchEnabled = false;

      expect(buildState(facts).linkSwitchEnabled).assertFalse();
    });

    it('explains why a mode cannot carry the whole link', 0, () => {
      expect(buildState(buildFacts('webdav')).providerNotice.length > 0).assertTrue();
      expect(buildState(buildFacts('huawei_space')).providerNotice.length > 0).assertTrue();
      // A mode that carries everything has nothing to explain.
      expect(buildState(buildFacts('aira_cloud')).providerNotice.length).assertEqual(0);
    });

    it('carries the link from account login when data sync is off or uses another provider', 0, () => {
      const signedIn = buildFacts('webdav');
      signedIn.account = { displayName: 'alex', uid: 'uid-1', avatarUri: '' };
      signedIn.hasConfiguredSync = true;

      expect(buildState(signedIn).providerNotice.length).assertEqual(0);
      expect(canEnableCrossDeviceLinkSwitch(true, 'webdav', 'uid-1')).assertTrue();
      expect(canEnableCrossDeviceLinkSwitch(true, 'none', 'uid-1')).assertTrue();
      expect(canEnableCrossDeviceLinkSwitch(true, 'huawei_space', 'uid-1')).assertTrue();
      // Login is the gate. A selected cloud provider is not required, and neither is data sync.
      expect(canEnableCrossDeviceLinkSwitch(true, 'none', '')).assertFalse();
      expect(canEnableCrossDeviceLinkSwitch(true, 'webdav', '  ')).assertFalse();
      expect(buildState(buildFacts('none')).providerNotice.indexOf('数据同步') >= 0).assertTrue();
    });

    it('shows an expired official-cloud switch as off without rewriting the saved preference', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.account = { displayName: 'alex', uid: 'uid-1', avatarUri: '' };
      facts.linkEnabled = true;
      facts.linkSwitchEnabled = false;
      facts.cloudEntitlement = 'pro_expired';
      const state = buildState(facts);

      expect(state.linkEnabled).assertFalse();
      expect(state.linkSwitchEnabled).assertFalse();
      expect(state.providerNotice.indexOf('已过期') >= 0).assertTrue();
      expect(canEnableCrossDeviceLinkSwitch(true, 'aira_cloud', 'uid-1', 'pro_expired')).assertFalse();
      expect(canEnableCrossDeviceLinkSwitch(true, 'aira_cloud', 'uid-1', 'pro_required')).assertFalse();
      expect(canEnableCrossDeviceLinkSwitch(true, 'self_hosted', 'uid-1', 'pro_expired')).assertTrue();
      expect(canEnableCrossDeviceLinkSwitch(false, 'none', '', 'not_required')).assertFalse();
    });

    it('keeps a never-subscribed account distinct from an expired one', 0, () => {
      const facts = buildFacts('webdav');
      facts.account = { displayName: 'alex', uid: 'uid-1', avatarUri: '' };
      facts.cloudEntitlement = 'pro_required';
      const state = buildState(facts);

      expect(state.providerNotice.indexOf('需要 Aira Pro') >= 0).assertTrue();
      expect(state.providerNotice.indexOf('已过期') < 0).assertTrue();
    });

    it('is a self-hosted-only page on a build without Aira Cloud', 0, () => {
      const facts = buildFacts('self_hosted');
      facts.desktopLinkAvailable = false;
      const state = buildState(facts);

      expect(state.providerNotice.length).assertEqual(0);
      expect(state.selfHostedSectionTitle).assertEqual('推荐方式');
      expect(state.steps[1].indexOf('账号') < 0).assertTrue();
    });

    it('never mentions Aira Cloud anywhere on a build that cannot sign in', 0, () => {
      const facts = buildFacts('none');
      facts.desktopLinkAvailable = false;
      const state = buildState(facts);

      expect(state.providerNotice.indexOf('Aira 云') < 0).assertTrue();
      // The community footer may say an account is not needed; what it must never do is
      // promise Aira Cloud on a build that cannot sign in to it.
      expect(state.selfHostedFooter.indexOf('Aira 云') < 0).assertTrue();
      expect(state.syncSettingsValue.length > 0).assertTrue();
    });

    it('keeps the account wording on a build that can sign in', 0, () => {
      const state = buildState(buildFacts('aira_cloud'));

      expect(state.selfHostedSectionTitle).assertEqual('不想登录账号');
      expect(state.steps[1].indexOf('账号') >= 0).assertTrue();
    });

    it('describes online computers by their browser alone', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.devices = [
        buildDevice('desktop-1', 'macOS', 'Chrome', 12, 5000),
        buildDevice('desktop-2', 'Windows', 'Edge', 3, 5 * 60 * 1000)
      ];
      const state = buildState(facts);

      expect(state.devices.length).assertEqual(2);
      expect(state.devices[0].title).assertEqual('macOS · Chrome');
      // The row names a device, not a status readout: an age and a tab count would be noise.
      expect(state.devices[0].subtitle.length).assertEqual(0);
      expect(state.devices[1].title).assertEqual('Windows · Edge');
      expect(state.devices[1].subtitle.length).assertEqual(0);
    });

    it('falls back to the device name when the computer reports no platform', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.devices = [buildDevice('我的台式机', '', '', 1, 0)];

      expect(buildState(facts).devices[0].title).assertEqual('我的台式机');
    });

    it('always offers adding a device, whatever the computer list looks like', 0, () => {
      const emptyState = buildState(buildFacts('aira_cloud'));
      expect(emptyState.devicesPlaceholderVisible).assertTrue();
      expect(emptyState.devicesPlaceholderTitle).assertEqual('当前没有在线电脑');
      expect(emptyState.devicesPlaceholderDetail.length > 0).assertTrue();
      expect(emptyState.addDeviceTitle).assertEqual('添加设备');

      const signedOutFacts = buildFacts('aira_cloud');
      signedOutFacts.deviceStatus = 'signed_out';
      expect(buildState(signedOutFacts).devicesPlaceholderTitle).assertEqual('登录账号后查看');
      expect(buildState(signedOutFacts).devicesPlaceholderAction).assertEqual('open_sync_settings');
      expect(buildState(signedOutFacts).addDeviceTitle).assertEqual('添加设备');

      const disabledFacts = buildFacts('aira_cloud');
      disabledFacts.deviceStatus = 'disabled';
      disabledFacts.deviceMessage = '跨设备标签页需要先完成连接。';
      expect(buildState(disabledFacts).devicesPlaceholderTitle).assertEqual('跨设备标签页需要先完成连接。');

      const errorFacts = buildFacts('aira_cloud');
      errorFacts.deviceStatus = 'error';
      expect(buildState(errorFacts).devicesPlaceholderTitle).assertEqual('暂时读不到在线电脑');
      expect(buildState(errorFacts).devicesPlaceholderAction).assertEqual('refresh_devices');

      const loadingFacts = buildFacts('aira_cloud');
      loadingFacts.deviceStatus = 'loading';
      expect(buildState(loadingFacts).devicesPlaceholderAction).assertEqual('none');
    });

    it('routes the self-hosted row at the self-hosted page', 0, () => {
      const state = buildState(buildFacts('aira_cloud'));

      expect(state.selfHostedTitle).assertEqual('私有化部署');
      expect(state.selfHostedAction).assertEqual('open_personal_server');
    });

    it('names the signed-in account over its own id', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.account = {
        displayName: 'alexsmith6923',
        uid: '4f3c9a17d2e84b60ac51',
        avatarUri: 'file://avatar.png'
      };
      const state = buildState(facts);

      expect(state.accountTitle).assertEqual('alexsmith6923');
      expect(state.accountSubtitle).assertEqual('账号 ID 4f3c9a17d2e84b60ac51');
      expect(state.accountAvatarUri).assertEqual('file://avatar.png');
      expect(state.accountSignedIn).assertTrue();
    });

    it('falls back to a plain account label when no nickname came back', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.account = { displayName: '   ', uid: '4f3c9a17d2e84b60ac51', avatarUri: '' };
      const state = buildState(facts);

      expect(state.accountTitle).assertEqual('已登录账号');
      expect(state.accountSubtitle).assertEqual('账号 ID 4f3c9a17d2e84b60ac51');
      expect(state.accountSignedIn).assertTrue();
    });

    it('keeps a local avatar but never a nickname when nobody is signed in', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.account = { displayName: 'alexsmith6923', uid: '  ', avatarUri: 'file://local.png' };
      const state = buildState(facts);

      expect(state.accountTitle).assertEqual('未登录');
      expect(state.accountSubtitle.indexOf('账号 ID') < 0).assertTrue();
      expect(state.accountSignedIn).assertFalse();
      expect(state.accountAvatarUri).assertEqual('file://local.png');
    });

    it('only lights up the computer side when one is really online', 0, () => {
      const offline = buildState(buildFacts('aira_cloud'));
      expect(offline.onlineComputerCount).assertEqual(0);

      const facts = buildFacts('aira_cloud');
      facts.devices = [buildDevice('desktop-1', 'macOS', 'Chrome', 12, 5000)];
      expect(buildState(facts).onlineComputerCount).assertEqual(1);
    });

    it('always lists this phone as the current device', 0, () => {
      const offline = buildState(buildFacts('aira_cloud'));
      expect(offline.localDeviceRow.title).assertEqual('Aira 手机');
      expect(offline.localDeviceRow.subtitle).assertEqual('当前设备');
      // It is the phone the user is reading the page on, so it is never the missing one.
      expect(offline.devicesPlaceholderVisible).assertTrue();

      const facts = buildFacts('aira_cloud');
      facts.devices = [buildDevice('desktop-1', 'macOS', 'Chrome', 12, 5000)];
      const state = buildState(facts);
      expect(state.localDeviceRow.title).assertEqual('Aira 手机');
      expect(state.devicesPlaceholderVisible).assertFalse();
      // The computers never absorb the phone: the row above them stays one device of its own.
      expect(state.devices.length).assertEqual(1);
    });

    it('falls back when the installation record has no device name yet', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.localDevice = { deviceName: '  ', platform: 'HarmonyOS', browserName: 'Aira' };
      expect(buildState(facts).localDeviceRow.title).assertEqual('HarmonyOS');

      facts.localDevice = { deviceName: '', platform: '', browserName: '' };
      expect(buildState(facts).localDeviceRow.title).assertEqual('本机');
    });
  });
}
