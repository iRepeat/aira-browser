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

/**
 * Official-cloud entitlement for this page's own switch. Private deployment does not use it.
 * `not_required` is a build or mode that never asks for Pro.
 */
export type CrossDeviceLinkCloudEntitlement =
  'not_required' |
  'signed_out' |
  'pro_required' |
  'pro_expired' |
  'active';

export interface CrossDeviceLinkDeviceRowState {
  deviceId: string;
  title: string;
  subtitle: string;
}

export interface CrossDeviceLinkViewState {
  /** The signed-in nickname, or the signed-out wording. Headline of the page header. */
  accountTitle: string;
  /** The account id under the nickname; a signed-out header guides instead. */
  accountSubtitle: string;
  /** The account's own avatar; empty means the header draws its placeholder glyph. */
  accountAvatarUri: string;
  accountSignedIn: boolean;
  /** Drives the computer glyph and its connector: it lights up only against a live desktop. */
  onlineComputerCount: number;
  /** One sentence about what the chosen mode can and cannot do; empty when it can do everything. */
  providerNotice: string;
  /**
   * The cross-device link switch: tab handoff and page push. It is deliberately not the data
   * sync master switch, because a user may pause bookmarks while keeping devices connected.
   */
  linkSwitchTitle: string;
  linkSwitchDescription: string;
  linkEnabled: boolean;
  linkSwitchEnabled: boolean;
  /** The one row that leaves the page for the sync owner; its value names the active mode. */
  syncSettingsValue: string;
  /**
   * This phone, always first and always present: the user is looking at it, so a list that
   * leaves it out is describing the wrong thing.
   */
  localDeviceRow: CrossDeviceLinkDeviceRowState;
  /** The computers the presence owner reports; never includes the phone itself. */
  devices: CrossDeviceLinkDeviceRowState[];
  /** Only the computers can be absent, so this drives the placeholder row alone. */
  devicesPlaceholderVisible: boolean;
  devicesPlaceholderTitle: string;
  devicesPlaceholderDetail: string;
  devicesPlaceholderAction: CrossDeviceLinkActionId;
  /** The always-last row that starts the QR pairing handshake. */
  addDeviceTitle: string;
  addDeviceDetail: string;
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

/**
 * The phone this build runs on. It is always online, so it has no age and no tab count;
 * what it needs is a name and the platform it presents itself as.
 */
export interface CrossDeviceLinkLocalDeviceFact {
  deviceName: string;
  platform: string;
  browserName: string;
}

/**
 * Who the header says this phone belongs to. Empty `uid` means nobody is signed in, and
 * `avatarUri` then only carries whatever local image the user picked for themselves.
 */
export interface CrossDeviceLinkAccountFact {
  displayName: string;
  uid: string;
  avatarUri: string;
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
  account: CrossDeviceLinkAccountFact;
  localDevice: CrossDeviceLinkLocalDeviceFact;
  /** The presence owner's own cross-device preference, never a copy this page keeps. */
  linkEnabled: boolean;
  /** False when there is no paired mode to carry the link at all. */
  linkSwitchEnabled: boolean;
  /**
   * Official-cloud readiness. The saved switch preference is separate: an expired account
   * still keeps that preference, and this only decides whether the switch may be used now.
   */
  cloudEntitlement: CrossDeviceLinkCloudEntitlement;
  /** Only used to name the current mode on the 同步设置 row; this page never writes sync. */
  hasConfiguredSync: boolean;
  goalLabel: string;
}

const SIGNED_OUT_TITLE: string = '未登录';
const SIGNED_OUT_SUBTITLE: string = '登录后即可和电脑互联，数据同步可以另开';
const ACCOUNT_TITLE_FALLBACK: string = '已登录账号';
const ACCOUNT_ID_PREFIX: string = '账号 ID ';
const LOCAL_DEVICE_NAME_FALLBACK: string = '本机';
const LOCAL_DEVICE_VALUE: string = '当前设备';

const WEBDAV_NOTICE: string = 'WebDAV 只能同步书签，没有网页接力和跨设备标签页。';
const HUAWEI_SPACE_NOTICE: string = '华为云空间在华为设备之间同步，没有电脑浏览器端。';
const ACCOUNT_LINK_NOTICE: string = '登录后即可和电脑互联，不必先开启数据同步。';
const PRO_REQUIRED_NOTICE: string = '跨设备互联需要 Aira Pro，也可以改用自己的私有化部署。';
const PRO_EXPIRED_NOTICE: string = 'Aira Pro 已过期，跨设备互联已暂停。续费后会恢复原来的开关。';
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

const DEVICES_EMPTY_TITLE: string = '当前没有在线电脑';
const DEVICES_EMPTY_DETAIL: string = '连接后在手机上就能看到电脑打开的网页';
const DEVICES_LOADING_TITLE: string = '正在读取在线电脑…';
const DEVICES_ERROR_TITLE: string = '暂时读不到在线电脑';
const DEVICES_ERROR_DETAIL: string = '稍后再看，或确认电脑端是否还开着浏览器';
const DEVICES_SIGNED_OUT_TITLE: string = '登录账号后查看';
const DEVICES_SIGNED_OUT_DETAIL: string = '电脑端登录后，这里会显示它打开的网页';

const SELF_HOSTED_TITLE: string = '私有化部署';

const LINK_SWITCH_TITLE: string = '跨设备互联';
const LINK_SWITCH_DETAIL: string = '跨设备标签页和网页推送，和数据同步互不影响。';
const SYNC_SETTINGS_TITLE: string = '同步设置';
const SYNC_SETTINGS_VALUE_UNSET: string = '去开启同步';
const ADD_DEVICE_ROW_TITLE: string = '添加设备';
const ADD_DEVICE_ROW_DETAIL: string = '扫一扫电脑上的二维码';

/**
 * The link switch is usable when this device can actually carry tab handoff. Official
 * cloud needs a signed-in active Pro account; the data-sync provider does not have to
 * be Aira Cloud. Personal Server remains its own channel and does not need that login.
 */
export function canEnableCrossDeviceLinkSwitch(
  desktopLinkAvailable: boolean,
  providerKind: CrossDeviceLinkProviderKind,
  accountUid: string,
  cloudEntitlement: CrossDeviceLinkCloudEntitlement = 'active'
): boolean {
  if (providerKind === 'self_hosted') {
    return true;
  }
  if (!desktopLinkAvailable) {
    return false;
  }
  if (accountUid.trim().length <= 0) {
    return false;
  }
  return cloudEntitlement === 'active';
}

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
    return {
      accountTitle: this.resolveAccountTitle(facts),
      accountSubtitle: this.resolveAccountSubtitle(facts),
      accountAvatarUri: facts.account.avatarUri.trim(),
      accountSignedIn: facts.account.uid.trim().length > 0,
      onlineComputerCount: facts.devices.length,
      providerNotice: this.resolveProviderNotice(facts, fullDesktopLink),
      linkSwitchTitle: LINK_SWITCH_TITLE,
      linkSwitchDescription: LINK_SWITCH_DETAIL,
      // A blocked switch is shown off. The saved preference stays where the presence owner left it.
      linkEnabled: facts.linkEnabled && this.resolveDisplayedLinkSwitchEnabled(facts),
      linkSwitchEnabled: this.resolveDisplayedLinkSwitchEnabled(facts),
      syncSettingsValue: this.resolveSyncSettingsValue(facts),
      localDeviceRow: this.buildLocalDeviceRow(facts.localDevice),
      devices: this.buildDevices(facts.devices),
      devicesPlaceholderVisible: facts.devices.length === 0,
      devicesPlaceholderTitle: this.resolveDevicesPlaceholderTitle(facts),
      devicesPlaceholderDetail: this.resolveDevicesPlaceholderDetail(facts),
      devicesPlaceholderAction: this.resolveDevicesPlaceholderAction(facts),
      addDeviceTitle: ADD_DEVICE_ROW_TITLE,
      addDeviceDetail: ADD_DEVICE_ROW_DETAIL,
      selfHostedTitle: SELF_HOSTED_TITLE,
      selfHostedSectionTitle: facts.desktopLinkAvailable
        ? SELF_HOSTED_SECTION_TITLE
        : SELF_HOSTED_SECTION_TITLE_COMMUNITY,
      selfHostedFooter: facts.desktopLinkAvailable ? SELF_HOSTED_FOOTER : SELF_HOSTED_FOOTER_COMMUNITY,
      selfHostedAction: 'open_personal_server'
    };
  }

  /**
   * The settings row names the mode the switch actually controls, so the value is the sync
   * owner's own goal label rather than this page's guess at a provider name.
   */
  private resolveSyncSettingsValue(facts: CrossDeviceLinkFacts): string {
    if (!facts.hasConfiguredSync) {
      return SYNC_SETTINGS_VALUE_UNSET;
    }
    return facts.goalLabel;
  }

  /**
   * The header names the account, not the page: the nickname the user recognises, or
   * the account's own id when the account never returned a nickname. A device that is
   * connected without an account still says so instead of claiming a login happened.
   */
  private resolveAccountTitle(facts: CrossDeviceLinkFacts): string {
    if (facts.account.uid.trim().length <= 0) {
      return SIGNED_OUT_TITLE;
    }
    const displayName = facts.account.displayName.trim();
    return displayName.length > 0 ? displayName : ACCOUNT_TITLE_FALLBACK;
  }

  /**
   * The id is the one thing that identifies the account on both ends, so it is what the
   * header shows under the nickname; a signed-out header guides instead of showing one.
   */
  private resolveAccountSubtitle(facts: CrossDeviceLinkFacts): string {
    const uid = facts.account.uid.trim();
    if (uid.length <= 0) {
      return SIGNED_OUT_SUBTITLE;
    }
    return `${ACCOUNT_ID_PREFIX}${uid}`;
  }

  /**
   * A signed-in account carries page push and cross-device tabs whatever the data-sync
   * provider is. Personal Server carries them without an account. WebDAV and Huawei
   * Space only fail to do so on a build that cannot sign in.
   */
  private hasFullDesktopLink(facts: CrossDeviceLinkFacts): boolean {
    if (facts.providerKind === 'self_hosted' || facts.providerKind === 'aira_cloud') {
      return true;
    }
    if (!facts.desktopLinkAvailable) {
      return false;
    }
    return facts.account.uid.trim().length > 0;
  }

  /**
   * A build without Aira Cloud never names it: there is no account to sign in with,
   * so the only way this page can work there is the user's own server.
   */
  private resolveDisplayedLinkSwitchEnabled(facts: CrossDeviceLinkFacts): boolean {
    if (!facts.linkSwitchEnabled) {
      return false;
    }
    if (facts.providerKind === 'self_hosted' || !facts.desktopLinkAvailable) {
      return true;
    }
    return facts.cloudEntitlement === 'active';
  }

  private resolveProviderNotice(facts: CrossDeviceLinkFacts, fullDesktopLink: boolean): string {
    if (facts.cloudEntitlement === 'pro_expired') {
      return PRO_EXPIRED_NOTICE;
    }
    if (facts.cloudEntitlement === 'pro_required') {
      return PRO_REQUIRED_NOTICE;
    }
    if (facts.cloudEntitlement === 'signed_out' && facts.desktopLinkAvailable) {
      return ACCOUNT_LINK_NOTICE;
    }
    if (fullDesktopLink) {
      return '';
    }
    if (!facts.desktopLinkAvailable) {
      if (facts.providerKind === 'webdav') {
        return WEBDAV_NOTICE;
      }
      if (facts.providerKind === 'huawei_space') {
        return HUAWEI_SPACE_NOTICE;
      }
      return NO_PROVIDER_NOTICE_COMMUNITY;
    }
    return ACCOUNT_LINK_NOTICE;
  }

  private resolveSteps(facts: CrossDeviceLinkFacts): string[] {
    return buildCrossDeviceLinkSteps(facts.providerKind, facts.desktopLinkAvailable);
  }

  /**
   * The phone names itself, always, and it is always online: the user is holding it. The
   * value says which device the row is instead of an age, so the row answers "am I in this
   * list" before the name is even read.
   */
  private buildLocalDeviceRow(localDevice: CrossDeviceLinkLocalDeviceFact): CrossDeviceLinkDeviceRowState {
    const name = localDevice.deviceName.trim();
    const platform = localDevice.platform.trim();
    return {
      deviceId: '',
      title: name.length > 0 ? name : (platform.length > 0 ? platform : LOCAL_DEVICE_NAME_FALLBACK),
      subtitle: LOCAL_DEVICE_VALUE
    };
  }

  private buildDevices(devices: CrossDeviceLinkDeviceFact[]): CrossDeviceLinkDeviceRowState[] {
    const rows: CrossDeviceLinkDeviceRowState[] = [];
    devices.forEach((device: CrossDeviceLinkDeviceFact): void => {
      rows.push({
        deviceId: device.deviceId,
        title: this.resolveDeviceTitle(device),
        subtitle: ''
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
    // Naming a computer is what the always-last 添加设备 row does, so the empty row sends
    // the user at the sync owner instead of repeating that row's action.
    return 'open_sync_settings';
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
