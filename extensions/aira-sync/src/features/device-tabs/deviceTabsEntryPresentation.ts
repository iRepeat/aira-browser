export type DeviceTabsEntryKind =
  | 'ready'
  | 'sign_in'
  | 'pro_required'
  | 'pro_expired'
  | 'link_disabled'
  | 'connect_personal_server'
  | 'membership_unavailable'
  | 'server_unsupported';

export type DeviceTabsEntryAction =
  | 'none'
  | 'sign_in'
  | 'open_personal_server'
  | 'enable_link'
  | 'retry_membership';

export type DeviceTabsEntryCopy = {
  titleKey: string;
  title: string;
  messageKey: string;
  message: string;
  primaryAction: DeviceTabsEntryAction;
  primaryLabelKey: string;
  primaryLabel: string;
  secondaryAction: DeviceTabsEntryAction;
  secondaryLabelKey: string;
  secondaryLabel: string;
};

export type DeviceTabsEntryInput = {
  airaCloudAvailable: boolean;
  selectedSyncSource: string | null | undefined;
  personalServerReady: boolean;
  personalServerTabsCapable: boolean;
  signedIn: boolean;
  membershipPlan: string;
  membershipStatus: string;
  membershipExpiresAt: number;
  membershipDegraded: boolean;
  linkEnabled: boolean;
  now?: number;
};

const EMPTY_ACTION = {
  primaryAction: 'none' as const,
  primaryLabelKey: '',
  primaryLabel: '',
  secondaryAction: 'none' as const,
  secondaryLabelKey: '',
  secondaryLabel: '',
};

export function resolveDeviceTabsEntry(input: DeviceTabsEntryInput): DeviceTabsEntryKind {
  if (input.selectedSyncSource === 'personal-server') {
    if (!input.personalServerReady) return 'connect_personal_server';
    if (!input.personalServerTabsCapable) return 'server_unsupported';
    return input.linkEnabled ? 'ready' : 'link_disabled';
  }
  if (!input.airaCloudAvailable) return 'connect_personal_server';
  if (!input.signedIn) return 'sign_in';
  if (!isActivePro(input)) {
    if (input.membershipDegraded) return 'membership_unavailable';
    return isExpiredMembership(input) ? 'pro_expired' : 'pro_required';
  }
  return input.linkEnabled ? 'ready' : 'link_disabled';
}

export function buildDeviceTabsEntryCopy(kind: Exclude<DeviceTabsEntryKind, 'ready'>): DeviceTabsEntryCopy {
  if (kind === 'sign_in') {
    return {
      titleKey: 'deviceTabs.entry.signInTitle',
      title: '登录后查看手机标签页',
      messageKey: 'deviceTabs.entry.signInMessage',
      message: '登录后可以查看手机上打开的网页。也可以改用自己的私有化部署。',
      primaryAction: 'sign_in',
      primaryLabelKey: 'deviceTabs.entry.signIn',
      primaryLabel: '登录',
      secondaryAction: 'open_personal_server',
      secondaryLabelKey: 'deviceTabs.entry.usePersonalServer',
      secondaryLabel: '使用私有化部署',
    };
  }
  if (kind === 'pro_required') {
    return {
      titleKey: 'deviceTabs.entry.proRequiredTitle',
      title: '手机标签页需要 Aira Pro',
      messageKey: 'deviceTabs.entry.proRequiredMessage',
      message: '请在手机 Aira 中开通。连接自己的私有化部署则不必开通。',
      primaryAction: 'open_personal_server',
      primaryLabelKey: 'deviceTabs.entry.usePersonalServer',
      primaryLabel: '使用私有化部署',
      secondaryAction: 'none',
      secondaryLabelKey: '',
      secondaryLabel: '',
    };
  }
  if (kind === 'pro_expired') {
    return {
      titleKey: 'deviceTabs.entry.proExpiredTitle',
      title: 'Aira Pro 已过期',
      messageKey: 'deviceTabs.entry.proExpiredMessage',
      message: '请在手机 Aira 中续费。连接自己的私有化部署则不必开通。',
      primaryAction: 'open_personal_server',
      primaryLabelKey: 'deviceTabs.entry.usePersonalServer',
      primaryLabel: '使用私有化部署',
      secondaryAction: 'none',
      secondaryLabelKey: '',
      secondaryLabel: '',
    };
  }
  if (kind === 'link_disabled') {
    return {
      titleKey: 'deviceTabs.entry.linkDisabledTitle',
      title: '跨设备标签页尚未开启',
      messageKey: 'deviceTabs.entry.linkDisabledMessage',
      message: '开启后即可看到手机上的标签页。',
      primaryAction: 'enable_link',
      primaryLabelKey: 'deviceTabs.entry.enableLink',
      primaryLabel: '开启跨设备标签页',
      secondaryAction: 'none',
      secondaryLabelKey: '',
      secondaryLabel: '',
    };
  }
  if (kind === 'connect_personal_server') {
    return {
      titleKey: 'deviceTabs.entry.connectPersonalServerTitle',
      title: '请先连接私有化部署',
      messageKey: 'deviceTabs.entry.connectPersonalServerMessage',
      message: '跨设备标签页需要使用你自己的私有化部署。',
      primaryAction: 'open_personal_server',
      primaryLabelKey: 'deviceTabs.entry.connectPersonalServer',
      primaryLabel: '连接私有化部署',
      secondaryAction: 'none',
      secondaryLabelKey: '',
      secondaryLabel: '',
    };
  }
  if (kind === 'membership_unavailable') {
    return {
      titleKey: 'deviceTabs.entry.membershipUnavailableTitle',
      title: '会员状态暂时无法确认',
      messageKey: 'deviceTabs.entry.membershipUnavailableMessage',
      message: '请稍后再试。',
      primaryAction: 'retry_membership',
      primaryLabelKey: 'deviceTabs.entry.retry',
      primaryLabel: '重试',
      secondaryAction: 'none',
      secondaryLabelKey: '',
      secondaryLabel: '',
    };
  }
  return {
    titleKey: 'deviceTabs.entry.serverUnsupportedTitle',
    title: '当前服务器不支持跨设备标签页',
    messageKey: 'deviceTabs.entry.serverUnsupportedMessage',
    message: '这台私有化部署没有提供跨设备标签页。',
    ...EMPTY_ACTION,
  };
}

function isActivePro(input: DeviceTabsEntryInput): boolean {
  if (input.membershipPlan.trim().toLowerCase() !== 'pro') return false;
  const expiresAt = Number(input.membershipExpiresAt || 0);
  return expiresAt === 0 || expiresAt > (input.now ?? Date.now());
}

function isExpiredMembership(input: DeviceTabsEntryInput): boolean {
  const status = input.membershipStatus.trim().toLowerCase();
  if (status === 'expired' || status === 'lapsed') return true;
  const expiresAt = Number(input.membershipExpiresAt || 0);
  return input.membershipPlan.trim().toLowerCase() === 'pro'
    && expiresAt > 0
    && expiresAt <= (input.now ?? Date.now());
}
