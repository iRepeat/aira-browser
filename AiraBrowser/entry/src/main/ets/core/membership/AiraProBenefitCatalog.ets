/**
 * The Aira Pro benefit list, shared by the membership page and the renewal
 * sheet. Both surfaces make the same promise to the user, so they must not
 * carry independent copies of it: a benefit added to one is then advertised by
 * the other automatically.
 *
 * Titles are kept short because the renewal sheet renders them as a compact
 * checklist; the membership page uses the longer description.
 */
export interface AiraProBenefitDefinition {
  id: string;
  title: string;
  description: string;
  tutorialText: string;
}

export const AIRA_PRO_BENEFITS: AiraProBenefitDefinition[] = [
  {
    id: 'cross_system_bookmark_sync',
    title: 'Aira 云书签同步',
    description: '使用 Aira 官方托管服务，在手机与电脑之间同步书签',
    tutorialText: ''
  },
  {
    id: 'page_handoff',
    title: 'Aira 云网页接力',
    description: '通过 Aira 官方托管服务，将当前网页推送至其他设备',
    tutorialText: '查看教程'
  },
  {
    id: 'cross_device_tabs',
    title: 'Aira 云跨设备标签页',
    description: '通过 Aira 官方托管服务查看并打开其他在线设备的标签页',
    tutorialText: '查看教程'
  },
  {
    id: 'aira_cloud_history',
    title: 'Aira 云历史同步',
    description: '使用 Aira 官方托管服务，在手机与电脑之间同步浏览历史',
    tutorialText: ''
  }
];
