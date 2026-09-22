export type CrossDeviceTabsEmptyKind =
  'none' |
  'sign_in' |
  'pro_required' |
  'pro_expired' |
  'link_disabled' |
  'no_devices' |
  'connect_personal_server' |
  'error';

export type CrossDeviceTabsEmptyAction =
  'none' |
  'sign_in' |
  'open_pro' |
  'enable_link' |
  'open_setup' |
  'open_sync_settings' |
  'open_guide' |
  'refresh';

export interface CrossDeviceTabsEmptyPresentation {
  kind: CrossDeviceTabsEmptyKind;
  title: string;
  message: string;
  primaryAction: CrossDeviceTabsEmptyAction;
  primaryLabel: string;
  secondaryAction: CrossDeviceTabsEmptyAction;
  secondaryLabel: string;
}

export const CROSS_DEVICE_TABS_EMPTY_NONE: CrossDeviceTabsEmptyPresentation = {
  kind: 'none',
  title: '',
  message: '',
  primaryAction: 'none',
  primaryLabel: '',
  secondaryAction: 'none',
  secondaryLabel: ''
};

/**
 * Copy and actions for the cross-device tab's in-place empty page.
 * The presence owner decides which kind applies; this function only names it.
 */
export function buildCrossDeviceTabsEmptyPresentation(
  kind: CrossDeviceTabsEmptyKind,
  detail: string = ''
): CrossDeviceTabsEmptyPresentation {
  if (kind === 'sign_in') {
    return {
      kind: kind,
      title: '登录后查看跨设备标签页',
      message: '使用华为账号登录，即可看到电脑上打开的网页。',
      primaryAction: 'sign_in',
      primaryLabel: '登录华为账号',
      secondaryAction: 'none',
      secondaryLabel: ''
    };
  }
  if (kind === 'pro_required') {
    return {
      kind: kind,
      title: '跨设备标签页需要 Aira Pro',
      message: '开通后可以查看并打开其他在线设备的标签页。连接自己的私有化部署则不必开通。',
      primaryAction: 'open_pro',
      primaryLabel: '了解 Aira Pro',
      secondaryAction: 'open_guide',
      secondaryLabel: '使用私有化部署'
    };
  }
  if (kind === 'pro_expired') {
    return {
      kind: kind,
      title: 'Aira Pro 已过期',
      message: '续费后即可恢复跨设备标签页。连接自己的私有化部署则不必开通。',
      primaryAction: 'open_pro',
      primaryLabel: '了解 Aira Pro',
      secondaryAction: 'open_guide',
      secondaryLabel: '使用私有化部署'
    };
  }
  if (kind === 'link_disabled') {
    return {
      kind: kind,
      title: '跨设备互联未开启',
      message: '开启后即可看到电脑上的标签页，和数据同步无关。',
      primaryAction: 'enable_link',
      primaryLabel: '开启跨设备互联',
      secondaryAction: 'none',
      secondaryLabel: ''
    };
  }
  if (kind === 'no_devices') {
    return {
      kind: kind,
      title: '当前没有在线电脑',
      message: '在电脑上打开 Aira 并登录同一账号，这台电脑就会出现在这里。',
      primaryAction: 'open_setup',
      primaryLabel: '查看连接方法',
      secondaryAction: 'refresh',
      secondaryLabel: '刷新'
    };
  }
  if (kind === 'connect_personal_server') {
    const credentials = detail === 'credentials';
    return {
      kind: kind,
      title: '请先连接私有化部署',
      message: credentials
        ? '跨设备标签页需要有效的私有化部署设备凭据。'
        : '跨设备标签页支持通过你自己部署的私有化部署使用，请先在同步设置中完成连接。',
      primaryAction: 'open_sync_settings',
      primaryLabel: '去同步设置',
      secondaryAction: 'none',
      secondaryLabel: ''
    };
  }
  if (kind === 'error') {
    const message = detail.trim().length > 0 ? detail.trim() : '跨设备标签页暂时不可用。';
    return {
      kind: kind,
      title: '跨设备标签页暂时不可用',
      message: message,
      primaryAction: 'refresh',
      primaryLabel: '刷新',
      secondaryAction: 'none',
      secondaryLabel: ''
    };
  }
  return CROSS_DEVICE_TABS_EMPTY_NONE;
}
