import { AiraSyncProviderKind } from '../../common/models/AiraSyncModels';
import { CrossDeviceTabPresencePanelStatus } from '../deviceTabs/CrossDeviceTabPresenceModels';

/**
 * What a row on the 跨设备互联 page does when tapped. The page is a read-only
 * projection plus these jumps; it never owns sync state itself.
 */
export type CrossDeviceLinkActionId =
  'open_sync_settings' |
  'open_personal_server' |
  'open_help' |
  'open_device_tabs' |
  'add_device' |
  'refresh_devices' |
  'none';

/**
 * The page answers one question: can the phone reach a desktop with the sync mode
 * the user actually chose? `none` means no mode is active yet.
 */
export type CrossDeviceLinkProviderKind = AiraSyncProviderKind | 'none';

export interface CrossDeviceLinkCapabilityRowState {
  id: string;
  title: string;
  /** Whether this mode can deliver the capability at all. */
  available: boolean;
  /** The user's own on/off switch; always true for capabilities with no switch. */
  enabled: boolean;
  statusLabel: string;
  action: CrossDeviceLinkActionId;
}

export interface CrossDeviceLinkDeviceRowState {
  deviceId: string;
  title: string;
  subtitle: string;
}

export interface CrossDeviceLinkViewState {
  connectionTitle: string;
  connectionMessage: string;
  /** One sentence about what the chosen mode can and cannot do; empty when it can do everything. */
  providerNotice: string;
  primaryActionVisible: boolean;
  primaryActionLabel: string;
  primaryActionHint: string;
  primaryAction: CrossDeviceLinkActionId;
  capabilities: CrossDeviceLinkCapabilityRowState[];
  /** The three-step recipe for the mode that is actually available here. */
  steps: string[];
  devices: CrossDeviceLinkDeviceRowState[];
  devicesPlaceholderTitle: string;
  devicesPlaceholderDetail: string;
  devicesPlaceholderAction: CrossDeviceLinkActionId;
  selfHostedTitle: string;
  selfHostedSectionTitle: string;
  selfHostedFooter: string;
  selfHostedAction: CrossDeviceLinkActionId;
}

export interface CrossDeviceLinkDeviceFact {
  deviceId: string;
  deviceName: string;
  platform: string;
  browserName: string;
  tabCount: number;
  ageMs: number;
}

export interface CrossDeviceLinkFacts {
  /** Whether this distribution carries the Aira Cloud capability the extension pairs with. */
  desktopLinkAvailable: boolean;
  providerKind: CrossDeviceLinkProviderKind;
  bookmarkSyncEnabled: boolean;
  historySyncEnabled: boolean;
  /** False for a mode that cannot carry history to the desktop, such as WebDAV. */
  historySyncSupported: boolean;
  deviceStatus: CrossDeviceTabPresencePanelStatus;
  deviceMessage: string;
  devices: CrossDeviceLinkDeviceFact[];
}

const CONNECTION_TITLE: string = '跨设备互联';
const CONNECTION_MESSAGE: string = 'Windows · macOS 上的 Chrome、Edge、Firefox';
const ADD_DEVICE_HINT: string = '用手机扫一扫电脑上的二维码，确认后电脑端就用当前账号登录，不必在电脑上输密码。';
const PAIR_HINT: string = '在电脑端扩展里填同一个服务器地址和配对码，两边对上就通了。';

const WEBDAV_NOTICE: string = 'WebDAV 只能同步书签，没有网页接力和跨设备标签页。';
const HUAWEI_SPACE_NOTICE: string = '华为云空间在华为设备之间同步，没有电脑浏览器端。';
const NO_PROVIDER_NOTICE: string = '还没开启同步，先选一种同步方式，再回来和电脑连。';
const NO_PROVIDER_NOTICE_COMMUNITY: string = '还没配置同步，先配置私有化部署，就能和电脑连上。';

const SELF_HOSTED_SECTION_TITLE: string = '不想登录账号';
const SELF_HOSTED_SECTION_TITLE_COMMUNITY: string = '推荐方式';
const SELF_HOSTED_FOOTER: string =
  '用私有化部署：书签、历史记录、网页接力、跨设备标签页全都能用，免账号、免会员。';
const SELF_HOSTED_FOOTER_COMMUNITY: string =
  '私有化部署用的是你自己的服务器，不需要登录账号，书签、历史记录、网页接力和跨设备标签页都能用。';

const STEPS_CLOUD: string[] = [
  '在电脑上安装 Aira-sync 扩展',
  '点扩展图标，选「使用账号登录」',
  '用「扫一扫」扫电脑上的二维码'
];
const STEPS_SELF_HOSTED: string[] = [
  '在电脑上安装 Aira-sync 扩展',
  '在手机这里点「去配对」，填服务器地址和配对码',
  '在电脑端扩展里填同一个地址和配对码'
];
const STEPS_LIMITED: string[] = [
  '在电脑上安装 Aira-sync 扩展',
  '换一种能和电脑连上的同步方式',
  '按提示在手机和电脑两端填同一份地址'
];

const ENABLED_LABEL: string = '已开启';
const DISABLED_LABEL: string = '未开启';
const UNAVAILABLE_LABEL: string = '不可用';
const SELF_HOSTED_TITLE: string = '私有化部署';

const DEVICES_EMPTY_TITLE: string = '当前没有在线电脑';
const DEVICES_EMPTY_DETAIL: string = '连接后在手机上就能看到电脑打开的网页';
const DEVICES_LOADING_TITLE: string = '正在读取在线电脑…';
const DEVICES_ERROR_TITLE: string = '暂时读不到在线电脑';
const DEVICES_ERROR_DETAIL: string = '稍后再看，或确认电脑端是否还开着浏览器';
const DEVICES_SIGNED_OUT_TITLE: string = '登录账号后查看';
const DEVICES_SIGNED_OUT_DETAIL: string = '电脑端登录后，这里会显示它打开的网页';

const BOOKMARK_ROW_TITLE: string = '书签同步';
const HISTORY_ROW_TITLE: string = '历史记录同步';
const PAGE_PUSH_ROW_TITLE: string = '网页接力';
const DEVICE_TABS_ROW_TITLE: string = '跨设备标签页';

const MINUTE_MS: number = 60 * 1000;
const HOUR_MS: number = 60 * MINUTE_MS;

/**
 * The three-step recipe for a mode. Pure, so the install sub-page can derive it from
 * the mode the overview already knows instead of loading sync state again.
 */
export function buildCrossDeviceLinkSteps(
  providerKind: CrossDeviceLinkProviderKind,
  desktopLinkAvailable: boolean
): string[] {
  const fullDesktopLink = desktopLinkAvailable
    ? providerKind === 'aira_cloud' || providerKind === 'self_hosted'
    : providerKind === 'self_hosted';
  if (fullDesktopLink) {
    return providerKind === 'aira_cloud' ? STEPS_CLOUD : STEPS_SELF_HOSTED;
  }
  return desktopLinkAvailable ? STEPS_CLOUD : STEPS_LIMITED;
}

export class CrossDeviceLinkViewModel {
  buildState(facts: CrossDeviceLinkFacts): CrossDeviceLinkViewState {
    const fullDesktopLink = this.hasFullDesktopLink(facts);
    const primary = this.resolvePrimaryAction(facts, fullDesktopLink);
    return {
      connectionTitle: CONNECTION_TITLE,
      connectionMessage: CONNECTION_MESSAGE,
      providerNotice: this.resolveProviderNotice(facts, fullDesktopLink),
      primaryActionVisible: primary.visible,
      primaryActionLabel: primary.label,
      primaryActionHint: primary.hint,
      primaryAction: primary.action,
      capabilities: this.buildCapabilities(facts, fullDesktopLink),
      steps: this.resolveSteps(facts),
      devices: this.buildDevices(facts.devices),
      devicesPlaceholderTitle: this.resolveDevicesPlaceholderTitle(facts),
      devicesPlaceholderDetail: this.resolveDevicesPlaceholderDetail(facts),
      devicesPlaceholderAction: this.resolveDevicesPlaceholderAction(facts),
      selfHostedTitle: SELF_HOSTED_TITLE,
      selfHostedSectionTitle: facts.desktopLinkAvailable
        ? SELF_HOSTED_SECTION_TITLE
        : SELF_HOSTED_SECTION_TITLE_COMMUNITY,
      selfHostedFooter: facts.desktopLinkAvailable ? SELF_HOSTED_FOOTER : SELF_HOSTED_FOOTER_COMMUNITY,
      selfHostedAction: 'open_personal_server'
    };
  }

  /**
   * Only Aira Cloud and a self-hosted server give the extension the account or
   * server it needs for page push and cross-device tabs. WebDAV carries bookmarks
   * only, and Huawei Space has no desktop browser side at all.
   */
  private hasFullDesktopLink(facts: CrossDeviceLinkFacts): boolean {
    if (!facts.desktopLinkAvailable) {
      return facts.providerKind === 'self_hosted';
    }
    return facts.providerKind === 'aira_cloud' || facts.providerKind === 'self_hosted';
  }

  /**
   * A build without Aira Cloud never names it: there is no account to sign in with,
   * so the only way this page can work there is the user's own server.
   */
  private resolveProviderNotice(facts: CrossDeviceLinkFacts, fullDesktopLink: boolean): string {
    if (fullDesktopLink) {
      return '';
    }
    if (facts.providerKind === 'webdav') {
      return WEBDAV_NOTICE;
    }
    if (facts.providerKind === 'huawei_space') {
      return HUAWEI_SPACE_NOTICE;
    }
    return facts.desktopLinkAvailable ? NO_PROVIDER_NOTICE : NO_PROVIDER_NOTICE_COMMUNITY;
  }

  private resolveSteps(facts: CrossDeviceLinkFacts): string[] {
    return buildCrossDeviceLinkSteps(facts.providerKind, facts.desktopLinkAvailable);
  }

  /**
   * One action per state, and it is always the action that changes the state: pair
   * the chosen mode, or go pick a mode that can reach a desktop.
   */
  private resolvePrimaryAction(
    facts: CrossDeviceLinkFacts,
    fullDesktopLink: boolean
  ): CrossDeviceLinkPrimaryAction {
    if (fullDesktopLink && facts.providerKind === 'aira_cloud') {
      return {
        visible: true,
        label: '添加设备',
        hint: ADD_DEVICE_HINT,
        action: 'add_device'
      };
    }
    if (fullDesktopLink) {
      return {
        visible: true,
        label: '去配对',
        hint: PAIR_HINT,
        action: 'open_personal_server'
      };
    }
    if (!facts.desktopLinkAvailable) {
      // No account to pair with here, so the only route to a desktop is the
      // self-hosted server: send the user straight at configuring it.
      return {
        visible: true,
        label: '去配置私有化部署',
        hint: PAIR_HINT,
        action: 'open_personal_server'
      };
    }
    return {
      visible: true,
      label: facts.providerKind === 'none' ? '去开启同步' : '更换同步方式',
      hint: '',
      action: 'open_sync_settings'
    };
  }

  private buildCapabilities(
    facts: CrossDeviceLinkFacts,
    fullDesktopLink: boolean
  ): CrossDeviceLinkCapabilityRowState[] {
    return [
      this.buildCapabilityRow('bookmark_sync', BOOKMARK_ROW_TITLE, true, facts.bookmarkSyncEnabled,
        'open_sync_settings'),
      this.buildCapabilityRow('history_sync', HISTORY_ROW_TITLE, facts.historySyncSupported, facts.historySyncEnabled,
        'open_sync_settings'),
      this.buildCapabilityRow('page_push', PAGE_PUSH_ROW_TITLE, fullDesktopLink, fullDesktopLink, 'open_help'),
      this.buildCapabilityRow('device_tabs', DEVICE_TABS_ROW_TITLE, fullDesktopLink, fullDesktopLink,
        'open_device_tabs')
    ];
  }

  private buildCapabilityRow(
    id: string,
    title: string,
    available: boolean,
    enabled: boolean,
    action: CrossDeviceLinkActionId
  ): CrossDeviceLinkCapabilityRowState {
    return {
      id: id,
      title: title,
      available: available,
      enabled: enabled,
      statusLabel: available ? (enabled ? ENABLED_LABEL : DISABLED_LABEL) : UNAVAILABLE_LABEL,
      action: action
    };
  }

  private buildDevices(devices: CrossDeviceLinkDeviceFact[]): CrossDeviceLinkDeviceRowState[] {
    const rows: CrossDeviceLinkDeviceRowState[] = [];
    devices.forEach((device: CrossDeviceLinkDeviceFact): void => {
      rows.push({
        deviceId: device.deviceId,
        title: this.resolveDeviceTitle(device),
        subtitle: `${this.resolveDeviceAgeLabel(device.ageMs)} · ${device.tabCount} 个标签页`
      });
    });
    return rows;
  }

  private resolveDeviceTitle(device: CrossDeviceLinkDeviceFact): string {
    const platform = device.platform.trim();
    const browserName = device.browserName.trim();
    if (platform.length > 0 && browserName.length > 0) {
      return `${platform} · ${browserName}`;
    }
    if (platform.length > 0) {
      return platform;
    }
    if (device.deviceName.trim().length > 0) {
      return device.deviceName.trim();
    }
    return browserName;
  }

  private resolveDeviceAgeLabel(ageMs: number): string {
    if (!Number.isFinite(ageMs) || ageMs < MINUTE_MS) {
      return '刚在线';
    }
    if (ageMs < HOUR_MS) {
      return `${Math.floor(ageMs / MINUTE_MS)} 分钟前`;
    }
    if (ageMs < HOUR_MS * 24) {
      return `${Math.floor(ageMs / HOUR_MS)} 小时前`;
    }
    return '刚刚离线';
  }

  /**
   * The presence owner already explains why it has nothing to show; its own
   * message wins over the generic one.
   */
  private resolveDevicesPlaceholderTitle(facts: CrossDeviceLinkFacts): string {
    if (facts.deviceStatus === 'ready') {
      return DEVICES_EMPTY_TITLE;
    }
    if (facts.deviceMessage.trim().length > 0 && facts.deviceStatus !== 'loading') {
      return facts.deviceMessage.trim();
    }
    if (facts.deviceStatus === 'loading') {
      return DEVICES_LOADING_TITLE;
    }
    if (facts.deviceStatus === 'signed_out') {
      return DEVICES_SIGNED_OUT_TITLE;
    }
    if (facts.deviceStatus === 'error') {
      return DEVICES_ERROR_TITLE;
    }
    return DEVICES_EMPTY_TITLE;
  }

  /** The empty row is a shortcut to whatever fixes it, hence a real action. */
  private resolveDevicesPlaceholderAction(facts: CrossDeviceLinkFacts): CrossDeviceLinkActionId {
    if (facts.deviceStatus === 'loading') {
      return 'none';
    }
    if (facts.deviceStatus === 'error') {
      return 'refresh_devices';
    }
    if (facts.deviceStatus === 'signed_out' || facts.deviceStatus === 'disabled') {
      return 'open_sync_settings';
    }
    return 'add_device';
  }

  private resolveDevicesPlaceholderDetail(facts: CrossDeviceLinkFacts): string {
    if (facts.deviceStatus === 'ready') {
      return DEVICES_EMPTY_DETAIL;
    }
    if (facts.deviceStatus === 'signed_out') {
      return DEVICES_SIGNED_OUT_DETAIL;
    }
    if (facts.deviceStatus === 'error') {
      return DEVICES_ERROR_DETAIL;
    }
    return '';
  }
}

interface CrossDeviceLinkPrimaryAction {
  visible: boolean;
  label: string;
  hint: string;
  action: CrossDeviceLinkActionId;
}
