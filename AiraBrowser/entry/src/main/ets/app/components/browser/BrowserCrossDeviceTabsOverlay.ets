import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import router from '@ohos.router';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  CrossDeviceTabPresenceDevice,
  CrossDeviceTabPresencePanelState,
  CrossDeviceTabPresenceTab
} from '../../../core/deviceTabs/CrossDeviceTabPresenceModels';
import {
  buildCrossDeviceTabsEmptyPresentation,
  CROSS_DEVICE_TABS_EMPTY_NONE,
  CrossDeviceTabsEmptyAction,
  CrossDeviceTabsEmptyPresentation
} from '../../../core/deviceTabs/CrossDeviceTabsEmptyPresentation';
import { SyncSettingsRefreshSignal } from '../../../core/sync/SyncSettingsRefreshSignal';
import { sharedHuaweiAccountMutationCoordinator } from '../../bootstrap/BrowserAppRuntime';
import { HuaweiLoginSheetContent } from '../account/HuaweiLoginSheetContent';
import {
  CROSS_DEVICE_LINK_SETUP_ROUTE,
  SETTINGS_LEGAL_WEB_DOCUMENT_ROUTE,
  SETTINGS_PRIVACY_STATEMENT_ROUTE,
  SYNC_DESKTOP_BOOKMARK_GUIDE_ROUTE,
  SYNC_SETTINGS_ROUTE,
  AIRA_PRO_ROUTE
} from '../../router/AppRoutes';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import {
  sharedCrossDeviceTabPresenceCoordinator
} from '../../../core/deviceTabs/CrossDeviceTabPresenceCoordinator';
import { AiraIcon } from '../common/AiraIcon';
import {
  RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
  RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_HORIZONTAL_INSET,
  RECORD_LIST_ROW_RADIUS
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';

const EMPTY_PANEL_STATE: CrossDeviceTabPresencePanelState = {
  status: 'loading',
  enabled: false,
  deviceName: '',
  devices: [],
  message: '',
  serverTime: 0,
  onlineWindowMs: 120000,
  empty: CROSS_DEVICE_TABS_EMPTY_NONE
};
const EMPTY_ACTION_BUTTON_HEIGHT: number = 40;

interface CrossDeviceTabsRouteParams {
  dataScope: string;
  privacyMode: string;
  boundarySource: string;
  kind: string;
}

@Component
export struct BrowserCrossDeviceTabsSheet {
  private readonly siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;

  @State private panelState: CrossDeviceTabPresencePanelState = EMPTY_PANEL_STATE;
  @State private loginSheetVisible: boolean = false;
  @State private siteIconStates: SiteIconListRenderState[] = [];
  @State private pressedTabId: string = '';
  @State private loading: boolean = false;

  onOpenRemoteTab: (url: string, title: string) => void = (_url: string, _title: string) => {};
  /**
   * Hosts that already know how to open Pro, sync settings, or the setup page return true.
   * A false result falls back to the routed pages, so every entry of this list shares the
   * empty pages even when the host does not wire them.
   */
  onNavigate: (action: CrossDeviceTabsEmptyAction) => boolean =
    (_action: CrossDeviceTabsEmptyAction): boolean => false;
  @Prop dataScope: string = 'profile_persistent';
  @Prop privacyMode: string = 'regular';
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential
      ): void => {
        this.handleHuaweiLoginResult(error, response);
      });
  /**
   * Optional: show one computer only. Empty means every online computer, which is what
   * the tab manager wants; a caller that already listed the computers passes its id.
   */
  @Prop deviceIdFilter: string = '';
  /**
   * Insets owned by the host, not by this component.
   *
   * As a bottom sheet this component owns a small inner margin because the sheet chrome is
   * already inset. As a full tabs-overview page it must instead clear the status bar at the
   * top and the floating bottom chrome at the bottom, and both of those are the host's live
   * geometry, so the host passes them in rather than this component guessing.
   *
   * They are applied as *content* offsets on the list, not as container padding: padding
   * would shrink the scrollport and clip the list, while a content offset lets the rows
   * scroll edge to edge under the immersive chrome and still come to rest clear of it.
   */
  @Prop contentTopInset: number = 8;
  @Prop contentBottomInset: number = 18;

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
    void this.refresh();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    Column() {
      this.buildRemoteDeviceContent()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .bindSheet($$this.loginSheetVisible, this.buildHuaweiLoginSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      preferType: SheetType.BOTTOM
    })
  }

  @Builder
  private buildHuaweiLoginSheet() {
    HuaweiLoginSheetContent({
      controller: this.huaweiLoginButtonController,
      onOpenUserAgreement: (): void => {
        this.openLegalDocument(SETTINGS_LEGAL_WEB_DOCUMENT_ROUTE, 'user_service_agreement');
      },
      onOpenPrivacyPolicy: (): void => {
        this.openLegalDocument(SETTINGS_PRIVACY_STATEMENT_ROUTE, '');
      }
    })
  }

  private resolveContentTopInset(): number {
    return Number.isFinite(this.contentTopInset) ? Math.max(0, this.contentTopInset) : 0;
  }

  private resolveContentBottomInset(): number {
    return Number.isFinite(this.contentBottomInset) ? Math.max(0, this.contentBottomInset) : 0;
  }

  private resolveVisibleDevices(): CrossDeviceTabPresenceDevice[] {
    const filter = this.deviceIdFilter.trim();
    if (filter.length === 0) {
      return this.panelState.devices;
    }
    return this.panelState.devices.filter((device: CrossDeviceTabPresenceDevice): boolean => {
      return device.deviceId === filter;
    });
  }

  @Builder
  private buildRemoteDeviceContent() {
    Column() {
      if (this.loading) {
        this.buildMessageState('正在读取在线电脑...', true)
      } else if (this.panelState.empty.kind !== 'none') {
        this.buildEmptyPresentation(this.panelState.empty)
      } else if (this.resolveVisibleDevices().length === 0) {
        this.buildEmptyPresentation(buildCrossDeviceTabsEmptyPresentation('no_devices'))
      } else {
        List({ space: 12 }) {
          ForEach(this.resolveVisibleDevices(), (device: CrossDeviceTabPresenceDevice) => {
            ListItem() {
              this.buildDeviceGroup(device)
            }
            .width('100%')
          }, (device: CrossDeviceTabPresenceDevice): string => device.deviceId)
        }
        .width('100%')
        .height('100%')
        // Content offsets, not container padding: the list keeps its full immersive
        // height and the first/last rows stop where the chrome does.
        .contentStartOffset(this.resolveContentTopInset())
        .contentEndOffset(this.resolveContentBottomInset())
        .alignListItem(ListItemAlign.Start)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .clip(true)
  }

  @Builder
  private buildMessageState(message: string, showLoading: boolean) {
    Column({ space: 12 }) {
      if (showLoading) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.storedAccentColor)
      } else {
        AiraIcon({
          airaIconId: 'settings.themeMode.system',
          iconSize: 26,
          iconColor: this.storedSecondaryTextColor
        })
      }

      Text(message)
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(3)
    }
    .width('100%')
    .height('100%')
    // The centred message state clears the same chrome the list does, so switching between
    // "正在读取" and the list never shifts the vertical centre.
    .padding({
      left: 24,
      right: 24,
      top: this.resolveContentTopInset(),
      bottom: this.resolveContentBottomInset()
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildEmptyPresentation(presentation: CrossDeviceTabsEmptyPresentation) {
    Column({ space: 12 }) {
      AiraIcon({
        airaIconId: 'settings.themeMode.system',
        iconSize: 36,
        iconColor: this.storedSecondaryTextColor
      })

      Text(presentation.title)
        .width('100%')
        .constraintSize({ maxWidth: 300 })
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(2)

      Text(presentation.message)
        .width('100%')
        .constraintSize({ maxWidth: 300 })
        .fontSize(14)
        .lineHeight(21)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(4)

      if (presentation.primaryAction !== 'none' && presentation.primaryLabel.length > 0) {
        Button(presentation.primaryLabel)
          .type(ButtonType.Normal)
          .height(EMPTY_ACTION_BUTTON_HEIGHT)
          .padding({ left: 20, right: 20 })
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor(this.storedAccentColor)
          .borderRadius(EMPTY_ACTION_BUTTON_HEIGHT / 2)
          .margin({ top: 8 })
          .onClick((): void => {
            this.handleEmptyAction(presentation.primaryAction);
          })
      }

      if (presentation.secondaryAction !== 'none' && presentation.secondaryLabel.length > 0) {
        Text(presentation.secondaryLabel)
          .fontSize(14)
          .fontColor(this.storedAccentColor)
          .margin({ top: 4 })
          .onClick((): void => {
            this.handleEmptyAction(presentation.secondaryAction);
          })
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 24,
      right: 24,
      top: this.resolveContentTopInset(),
      bottom: this.resolveContentBottomInset()
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDeviceGroup(device: CrossDeviceTabPresenceDevice) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(this.resolveDeviceTitle(device))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })

        Text(`${device.tabCount} 个`)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
      }
      .width('100%')
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      if (device.tabs.length > 0) {
        Column({ space: 8 }) {
          ForEach(device.tabs, (tab: CrossDeviceTabPresenceTab, index: number) => {
            this.buildRemoteTabRow(device, tab, index)
          }, (tab: CrossDeviceTabPresenceTab, index: number): string => this.buildRemoteTabId(device, tab, index))
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private buildRemoteTabRow(
    device: CrossDeviceTabPresenceDevice,
    tab: CrossDeviceTabPresenceTab,
    index: number
  ) {
    WebsiteRecordRow({
      iconUri: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.path ?? '',
      iconPixelMap: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.pixelMap,
      fallbackLabel: resolveSiteIconFallbackLabel(tab.title, tab.url),
      title: tab.title.trim().length > 0 ? tab.title : tab.url,
      subtitle: tab.url,
      pressed: this.pressedTabId === this.buildRemoteTabId(device, tab, index),
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rowHeight: RECORD_LIST_ROW_HEIGHT,
      rowBorderRadius: RECORD_LIST_ROW_RADIUS,
      iconSize: RECORD_LIST_ROW_FAVICON_SIZE,
      iconSlotSize: RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
      iconContentRatio: RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
      iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      fallbackFontSize: RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
      preferPixelMap: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.pixelMap !== undefined,
      sourceRevision: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.sourceRevision ?? 0,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.handleSiteIconLoadError(device, tab, index, iconUri, sourceRevision);
      },
      onTouchAction: (type: TouchType) => {
        this.updatePressedTab(this.buildRemoteTabId(device, tab, index), type);
      },
      onRowClick: () => {
        this.onOpenRemoteTab(tab.url, tab.title);
      }
    })
    .width('100%')
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(RECORD_LIST_ROW_RADIUS)
    .clip(true)
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      const state = await sharedCrossDeviceTabPresenceCoordinator.loadPanelState();
      this.panelState = state;
      this.syncSiteIcons();
    } finally {
      this.loading = false;
    }
  }

  private handleEmptyAction(action: CrossDeviceTabsEmptyAction): void {
    if (action === 'none') {
      return;
    }
    if (action === 'refresh') {
      void this.refresh();
      return;
    }
    if (action === 'enable_link') {
      void this.enableLink();
      return;
    }
    if (action === 'sign_in') {
      this.beginSignIn();
      return;
    }
    if (this.onNavigate(action)) {
      return;
    }
    this.navigateByRoute(action);
  }

  private async enableLink(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      await sharedCrossDeviceTabPresenceCoordinator.setCrossDeviceLinkEnabled(true);
      this.panelState = await sharedCrossDeviceTabPresenceCoordinator.loadPanelState();
      this.syncSiteIcons();
    } finally {
      this.loading = false;
    }
  }

  private beginSignIn(): void {
    const boundary = this.buildBoundaryInput();
    if (!sharedHuaweiAccountMutationCoordinator.canSignIn(boundary)) {
      this.showToast('请回到普通会话后登录华为账号。');
      return;
    }
    this.loginSheetVisible = true;
  }

  private handleHuaweiLoginResult(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential
  ): void {
    if (error !== undefined) {
      if (error.code !== 1001502012) {
        this.showToast(error.message.length > 0 ? error.message : '华为账号登录失败');
      }
      return;
    }
    if (response.authorizationCode.trim().length <= 0 && response.openID.trim().length <= 0) {
      this.showToast('华为账号登录未完成');
      return;
    }
    this.loginSheetVisible = false;
    sharedHuaweiAccountMutationCoordinator.signIn(this.buildBoundaryInput())
      .then((result): void => {
        if (result.type === 'failed') {
          this.showToast(result.message.length > 0 ? result.message : result.title);
          return;
        }
        new SyncSettingsRefreshSignal().bump();
        void this.refresh();
      })
      .catch((): void => {
        this.showToast('华为账号登录失败');
      });
  }

  private navigateByRoute(action: CrossDeviceTabsEmptyAction): void {
    if (action === 'open_pro') {
      this.pushRoute(AIRA_PRO_ROUTE);
      return;
    }
    if (action === 'open_sync_settings') {
      this.pushRoute(SYNC_SETTINGS_ROUTE);
      return;
    }
    if (action === 'open_setup') {
      this.pushRoute(CROSS_DEVICE_LINK_SETUP_ROUTE);
      return;
    }
    if (action === 'open_guide') {
      this.pushRoute(SYNC_DESKTOP_BOOKMARK_GUIDE_ROUTE);
    }
  }

  private openLegalDocument(url: string, kind: string): void {
    this.loginSheetVisible = false;
    const params: CrossDeviceTabsRouteParams = {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: 'cross_device_tabs',
      kind: kind
    };
    router.pushUrl({ url: url, params: params }).catch((): void => {
      this.showToast('暂时无法打开该页面');
    });
  }

  private pushRoute(url: string): void {
    const params: CrossDeviceTabsRouteParams = {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: 'cross_device_tabs',
      kind: ''
    };
    router.pushUrl({ url: url, params: params }).catch((): void => {
      this.showToast('暂时无法打开该页面');
    });
  }

  private buildBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }

  private resolveDeviceTitle(device: CrossDeviceTabPresenceDevice): string {
    const browserName = device.browserName.trim();
    const platform = device.platform.trim();
    if (browserName.length > 0 && platform.length > 0) {
      return `${browserName} ${platform}`;
    }
    return browserName || platform || device.deviceName.trim() || device.model.trim() || '电脑';
  }

  private syncSiteIcons(): void {
    const targets = this.buildSiteIconTargets();
    this.siteIconStates = this.siteIconStates.filter((state: SiteIconListRenderState): boolean => {
      return targets.some((target: SiteIconListTarget): boolean => target.id === state.id);
    });
    this.siteIconListPresenter.resolveTargets(
      targets,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }

  private buildSiteIconTargets(): SiteIconListTarget[] {
    const targets: SiteIconListTarget[] = [];
    this.panelState.devices.forEach((device: CrossDeviceTabPresenceDevice): void => {
      device.tabs.forEach((tab: CrossDeviceTabPresenceTab, index: number): void => {
        targets.push({
          id: this.buildRemoteTabId(device, tab, index),
          url: tab.url
        });
      });
    });
    return targets;
  }

  private applyResolvedSiteIcon(result: SiteIconListResolvedIcon): void {
    this.siteIconStates = this.siteIconListPresenter.applyResolvedIcon(this.siteIconStates, result);
  }

  private handleSiteIconLoadError(
    device: CrossDeviceTabPresenceDevice,
    tab: CrossDeviceTabPresenceTab,
    index: number,
    currentUri: string,
    sourceRevision: number
  ): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      {
        id: this.buildRemoteTabId(device, tab, index),
        url: tab.url
      },
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }

  private resolveSiteIconState(tabId: string): SiteIconListRenderState | undefined {
    return this.siteIconStates.find((state: SiteIconListRenderState): boolean => state.id === tabId);
  }

  private updatePressedTab(tabId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedTabId = tabId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedTabId = '';
    }
  }

  private buildRemoteTabId(
    device: CrossDeviceTabPresenceDevice,
    tab: CrossDeviceTabPresenceTab,
    index: number
  ): string {
    return `${device.deviceId}:${tab.windowOrder}:${tab.tabOrder}:${index}:${tab.url}`;
  }
}
