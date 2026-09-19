import { describe, expect, it } from '@ohos/hypium';
import {
  CrossDeviceLinkDeviceFact,
  CrossDeviceLinkFacts,
  CrossDeviceLinkProviderKind,
  CrossDeviceLinkViewState,
  CrossDeviceLinkViewModel
} from '../main/ets/core/sync/CrossDeviceLinkViewModel';

const DEVICE_TAB_ROW_TITLE: string = '跨设备标签页';
const PAGE_PUSH_ROW_TITLE: string = '网页接力';
const BOOKMARK_ROW_TITLE: string = '书签同步';
const HISTORY_ROW_TITLE: string = '历史记录同步';

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
    devices: []
  };
}

function buildState(facts: CrossDeviceLinkFacts): CrossDeviceLinkViewState {
  return new CrossDeviceLinkViewModel().buildState(facts);
}

function findRow(state: CrossDeviceLinkViewState, title: string) {
  let row = state.capabilities[0];
  state.capabilities.forEach((candidate): void => {
    if (candidate.title === title) {
      row = candidate;
    }
  });
  return row;
}

export default function crossDeviceLinkViewModelTest(): void {
  describe('CrossDeviceLinkViewModel', () => {
    it('keeps every capability row so the page layout never collapses', 0, () => {
      const state = buildState(buildFacts('aira_cloud'));

      expect(state.capabilities.length).assertEqual(4);
      expect(state.capabilities[0].title).assertEqual(BOOKMARK_ROW_TITLE);
      expect(state.capabilities[1].title).assertEqual(HISTORY_ROW_TITLE);
      expect(state.capabilities[2].title).assertEqual(PAGE_PUSH_ROW_TITLE);
      expect(state.capabilities[3].title).assertEqual(DEVICE_TAB_ROW_TITLE);
    });

    it('pairs a phone with a computer over Aira Cloud', 0, () => {
      const state = buildState(buildFacts('aira_cloud'));

      expect(state.primaryActionVisible).assertTrue();
      expect(state.primaryActionLabel).assertEqual('添加设备');
      expect(state.primaryAction).assertEqual('add_device');
      expect(state.providerNotice.length).assertEqual(0);
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).available).assertTrue();
      expect(findRow(state, DEVICE_TAB_ROW_TITLE).statusLabel).assertEqual('已开启');
    });

    it('pairs a self-hosted server with its own code instead of a scan', 0, () => {
      const state = buildState(buildFacts('self_hosted'));

      expect(state.primaryActionLabel).assertEqual('去配对');
      expect(state.primaryAction).assertEqual('open_personal_server');
      expect(state.providerNotice.length).assertEqual(0);
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).available).assertTrue();
    });

    it('reports WebDAV as bookmark-only and points at switching the mode', 0, () => {
      const state = buildState(buildFacts('webdav'));

      expect(state.primaryActionLabel).assertEqual('更换同步方式');
      expect(state.primaryAction).assertEqual('open_sync_settings');
      expect(state.providerNotice.length > 0).assertTrue();
      expect(findRow(state, HISTORY_ROW_TITLE).available).assertFalse();
      expect(findRow(state, HISTORY_ROW_TITLE).statusLabel).assertEqual('不可用');
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).statusLabel).assertEqual('不可用');
      expect(findRow(state, DEVICE_TAB_ROW_TITLE).statusLabel).assertEqual('不可用');
      expect(findRow(state, BOOKMARK_ROW_TITLE).available).assertTrue();
    });

    it('reports Huawei Space as having no desktop browser side', 0, () => {
      const state = buildState(buildFacts('huawei_space'));

      expect(state.primaryActionLabel).assertEqual('更换同步方式');
      expect(findRow(state, HISTORY_ROW_TITLE).available).assertTrue();
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).available).assertFalse();
      expect(findRow(state, DEVICE_TAB_ROW_TITLE).available).assertFalse();
    });

    it('asks for a sync mode first when none is active', 0, () => {
      const state = buildState(buildFacts('none'));

      expect(state.primaryActionLabel).assertEqual('去开启同步');
      expect(state.primaryAction).assertEqual('open_sync_settings');
      expect(state.providerNotice.length > 0).assertTrue();
    });

    it('is a self-hosted-only page on a build without Aira Cloud', 0, () => {
      const facts = buildFacts('self_hosted');
      facts.desktopLinkAvailable = false;
      const state = buildState(facts);

      expect(state.primaryActionLabel).assertEqual('去配对');
      expect(state.primaryAction).assertEqual('open_personal_server');
      expect(state.providerNotice.length).assertEqual(0);
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).available).assertTrue();
      expect(state.selfHostedSectionTitle).assertEqual('推荐方式');
      expect(state.steps[1].indexOf('账号') < 0).assertTrue();
    });

    it('sends a build without Aira Cloud straight at the self-hosted server', 0, () => {
      const facts = buildFacts('webdav');
      facts.desktopLinkAvailable = false;
      const state = buildState(facts);

      expect(state.primaryActionLabel).assertEqual('去配置私有化部署');
      expect(state.primaryAction).assertEqual('open_personal_server');
      expect(state.providerNotice.indexOf('Aira 云') < 0).assertTrue();
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).available).assertFalse();
    });

    it('never mentions Aira Cloud anywhere on a build that cannot sign in', 0, () => {
      const facts = buildFacts('none');
      facts.desktopLinkAvailable = false;
      const state = buildState(facts);

      expect(state.providerNotice.indexOf('Aira 云') < 0).assertTrue();
      // The community footer may say an account is not needed; what it must never do is
      // promise Aira Cloud on a build that cannot sign in to it.
      expect(state.selfHostedFooter.indexOf('Aira 云') < 0).assertTrue();
      expect(state.primaryAction).assertEqual('open_personal_server');
    });

    it('keeps the account wording on a build that can sign in', 0, () => {
      const state = buildState(buildFacts('aira_cloud'));

      expect(state.selfHostedSectionTitle).assertEqual('不想登录账号');
      expect(state.steps[1].indexOf('账号') >= 0).assertTrue();
    });

    it('mirrors the bookmark and history switches', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.bookmarkSyncEnabled = false;
      facts.historySyncEnabled = false;
      const state = buildState(facts);

      expect(findRow(state, BOOKMARK_ROW_TITLE).statusLabel).assertEqual('未开启');
      expect(findRow(state, HISTORY_ROW_TITLE).statusLabel).assertEqual('未开启');
      expect(findRow(state, PAGE_PUSH_ROW_TITLE).statusLabel).assertEqual('已开启');
    });

    it('describes online computers with their browser and tab count', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.devices = [
        buildDevice('desktop-1', 'macOS', 'Chrome', 12, 5000),
        buildDevice('desktop-2', 'Windows', 'Edge', 3, 5 * 60 * 1000)
      ];
      const state = buildState(facts);

      expect(state.devices.length).assertEqual(2);
      expect(state.devices[0].title).assertEqual('macOS · Chrome');
      expect(state.devices[0].subtitle).assertEqual('刚在线 · 12 个标签页');
      expect(state.devices[1].title).assertEqual('Windows · Edge');
      expect(state.devices[1].subtitle).assertEqual('5 分钟前 · 3 个标签页');
    });

    it('falls back to the device name when the computer reports no platform', 0, () => {
      const facts = buildFacts('aira_cloud');
      facts.devices = [buildDevice('我的台式机', '', '', 1, 0)];

      expect(buildState(facts).devices[0].title).assertEqual('我的台式机');
    });

    it('keeps the device list shape when nothing is online', 0, () => {
      const emptyState = buildState(buildFacts('aira_cloud'));
      expect(emptyState.devicesPlaceholderTitle).assertEqual('当前没有在线电脑');
      expect(emptyState.devicesPlaceholderDetail.length > 0).assertTrue();
      expect(emptyState.devicesPlaceholderAction).assertEqual('add_device');

      const signedOutFacts = buildFacts('aira_cloud');
      signedOutFacts.deviceStatus = 'signed_out';
      expect(buildState(signedOutFacts).devicesPlaceholderTitle).assertEqual('登录账号后查看');
      expect(buildState(signedOutFacts).devicesPlaceholderAction).assertEqual('open_sync_settings');

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
  });
}
