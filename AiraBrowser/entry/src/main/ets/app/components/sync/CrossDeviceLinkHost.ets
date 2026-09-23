import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserQrScanCoordinator,
  BrowserQrScanNavigationTarget,
  BrowserQrScanSessionSnapshot,
  BrowserQrScanShell,
  BrowserQrScanSurface,
  DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT
} from '../../../core/browser/BrowserQrScanCoordinator';
import {
  CrossDeviceLinkAccountFact,
  CrossDeviceLinkActionId,
  CrossDeviceLinkCloudEntitlement,
  CrossDeviceLinkDeviceFact,
  CrossDeviceLinkLocalDeviceFact,
  CrossDeviceLinkProviderKind,
  CrossDeviceLinkViewState,
  CrossDeviceLinkViewModel,
  canEnableCrossDeviceLinkSwitch
} from '../../../core/sync/CrossDeviceLinkViewModel';
import {
  SyncExperienceGoalOption,
  SyncExperienceViewState
} from '../../../core/sync/SyncExperienceViewModel';
import { CrossDeviceTabPresenceDevice } from '../../../core/deviceTabs/CrossDeviceTabPresenceModels';
import { sharedCrossDeviceTabPresencePreferencesRepository } from '../../../data/deviceTabs/CrossDeviceTabPresencePreferencesRepository';
import { resolveAiraHuaweiAccountIdentity } from '../../../common/models/AiraSyncModels';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { LocalUserAvatarService } from '../../../services/settings/LocalUserAvatarService';
import { sharedCrossDeviceTabPresenceCoordinator } from '../../../core/deviceTabs/CrossDeviceTabPresenceCoordinator';
import {
  sharedSyncExperienceCoordinator,
  sharedAiraSyncConfigStore,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature
} from '../../bootstrap/BrowserAppRuntime';
import {
  SYNC_SETTINGS_REFRESH_REVISION_KEY,
  SyncSettingsRefreshSignal
} from '../../../core/sync/SyncSettingsRefreshSignal';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { BrowserCrossDeviceTabsSheet } from '../browser/BrowserCrossDeviceTabsOverlay';
import { CrossDeviceTabsEmptyAction } from '../../../core/deviceTabs/CrossDeviceTabsEmptyPresentation';
import { DesktopLoginConfirmSheetContent } from '../settings/DesktopLoginConfirmSheetContent';
import { HuaweiLoginSheetContent } from '../account/HuaweiLoginSheetContent';
import { CrossDeviceLinkScreen } from './CrossDeviceLinkScreen';
import { CrossDeviceLinkSetupScreen } from './CrossDeviceLinkSetupScreen';
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';

const DEVICE_TABS_SHEET_TITLE: string = '跨设备标签页';
const CROSS_DEVICE_LINK_LOG_DOMAIN: number = 0x0A1A;
const CROSS_DEVICE_LINK_LOG_TAG: string = 'CrossDeviceLink';

@Component
export struct CrossDeviceLinkHost {
  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('handleSyncSettingsSignal')
  private syncSettingsRefreshRevision: number = 0;
  @Prop @Watch('handlePageShowRefresh') refreshToken: number = 0;
  /** False while the scan UI covers this page, so a returning sheet waits until we are foreground. */
  @Prop @Watch('handlePageVisibility') pageVisible: boolean = true;
  /** Embedded in the large-screen settings workspace instead of its own routed page. */
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop desktopPresentation: boolean = false;
  /** When embedded, back exits the workspace pane instead of popping the router. */
  onExit?: () => void;
  /** Native-tab (PC) shell opens a tapped install link instead of routing back to the shell. */
  onOpenExternalUrl?: (url: string) => void;
  /** PC pane selects the 同步 destination so the centered dialogs are used, not the routed page. */
  onOpenSyncSettings?: () => void;
  @State private viewState: CrossDeviceLinkViewState = lastPublishedViewState ?? buildInitialViewState();
  /** Guard only, so the scan cannot be started twice; nothing renders from it. */
  private isAddingDevice: boolean = false;
  /** The cross-device switch has its own guard, because it is a different owner. */
  @State private isTogglingLink: boolean = false;
  /** Bumped when an attempt settles, so the switch is rebuilt from the owner's real value. */
  @State private syncSwitchRevision: number = 0;
  /** Large-screen workspace shows the install/pairing recipe inline instead of routing. */
  @State private showSetupInline: boolean = false;
  /** Remembered so the install sub-page can show the right recipe. */
  @State private providerKind: CrossDeviceLinkProviderKind = 'none';
  @State private confirmSheetVisible: boolean = false;
  @State private deviceTabsSheetVisible: boolean = false;
  @State private loginSheetVisible: boolean = false;
  /** Empty shows every online computer; a device row narrows the sheet to that one. */
  @State private deviceTabsFilter: string = '';
  @State private qrScanSnapshot: BrowserQrScanSessionSnapshot = DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT;
  @State private boundary: BrowserBoundaryRouteState = INITIAL_BOUNDARY;
  private readonly viewModel: CrossDeviceLinkViewModel = new CrossDeviceLinkViewModel();
  /** The account's own avatar when the account has none; owned here so the refresh reads it once. */
  private readonly localUserAvatarService: LocalUserAvatarService = new LocalUserAvatarService();
  /** The local avatar is read once, because it lives on disk and never changes mid-visit. */
  private cachedLocalAvatarUri: string = '';
  private didLoadLocalAvatar: boolean = false;
  /** This phone names itself the same way on every visit, so it is read once as well. */
  private cachedLocalDevice?: CrossDeviceLinkLocalDeviceFact;
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private readonly appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private readonly themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  private readonly qrScanShell: BrowserQrScanShell = {
    publishSnapshot: (snapshot: BrowserQrScanSessionSnapshot): void => {
      this.qrScanSnapshot = snapshot;
    },
    showToast: (message: string): void => {
      this.showToast(message);
    },
    openNavigation: (target: BrowserQrScanNavigationTarget, value: string): void => {
      // An unsigned scan stays on this page and asks for the account in place.
      if (target === 'account_settings') {
        this.requestHuaweiLoginSheet();
        return;
      }
      this.openUrlInBrowser(value);
    },
    requestAccountSignIn: (): boolean => {
      return this.requestHuaweiLoginSheet();
    },
    setSurfaceVisible: (surface: BrowserQrScanSurface, visible: boolean): void => {
      if (surface !== 'desktop_login_confirm') {
        return;
      }
      if (visible) {
        this.requestForegroundSheet('desktop_login');
        return;
      }
      this.pendingForegroundSheet = 'none';
      this.confirmSheetVisible = false;
    }
  };
  private pendingForegroundSheet: 'none' | 'desktop_login' | 'huawei_login' = 'none';
  private huaweiLoginCompleted: boolean = false;
  private preservePendingDesktopLogin: boolean = false;
  private reopenHuaweiLoginOnShow: boolean = false;
  private readonly huaweiLoginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((error: BusinessError, response: loginComponentManager.HuaweiIDCredential): void => {
        this.handleHuaweiLoginResult(error, response);
      })
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED);
  private readonly qrScanCoordinator: BrowserQrScanCoordinator =
    new BrowserQrScanCoordinator(sharedAiraSyncConfigStore, this.qrScanShell);

  aboutToAppear(): void {
    this.boundary = readBrowserBoundaryRouteState();
    void this.refresh();
  }

  private handlePageShowRefresh(): void {
    void this.refresh();
  }

  private handlePageVisibility(): void {
    if (this.pageVisible && this.reopenHuaweiLoginOnShow) {
      this.reopenHuaweiLoginOnShow = false;
      this.loginSheetVisible = true;
    }
    this.flushPendingForegroundSheet();
  }

  build() {
    Stack() {
    Column() {
      if (this.showSetupInline) {
        CrossDeviceLinkSetupScreen({
          embedded: true,
          desktopPresentation: this.desktopPresentation,
          providerKind: this.providerKind,
          onOpenExternalUrl: this.onOpenExternalUrl,
          onExit: (): void => {
            this.showSetupInline = false;
          }
        })
      } else {
        CrossDeviceLinkScreen({
          state: this.viewState,
          settingsIconBackgrounds: this.theme.settingsIconBackgrounds,
          syncProviderIconBackgrounds: this.theme.syncProviderIconBackgrounds,
          isBusy: this.isTogglingLink,
          switchSettledRevision: this.syncSwitchRevision,
          showBackButton: this.showBackButton,
          showTitleBar: this.showTitleBar,
          useTopSafeInset: this.useTopSafeInset,
          contentKind: this.contentKind,
          desktopPresentation: this.desktopPresentation,
          onBack: (): void => {
            if (this.onExit !== undefined) {
              this.onExit();
              return;
            }
            this.navigationCoordinator.back();
          },
          onOpenSetup: (): void => {
            if (this.desktopPresentation) {
              this.showSetupInline = true;
              return;
            }
            this.navigationCoordinator.openCrossDeviceLinkSetup(this.boundary, this.providerKind);
          },
          onOpenDeviceTabs: (deviceId: string): void => {
            this.openDeviceTabs(deviceId);
          },
          onToggleLink: (enabled: boolean): void => {
            this.toggleLink(enabled);
          },
          onAction: (action: CrossDeviceLinkActionId): void => {
            this.handleAction(action);
          }
        })
      }
    }
    .width('100%')
    .height('100%')

    Column()
      .width(0)
      .height(0)
      .bindSheet($$this.confirmSheetVisible, this.buildDesktopLoginConfirmSheet(), applyDesktopDialogSheetChrome({
        preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
        height: SheetSize.FIT_CONTENT,
        dragBar: !this.desktopPresentation,
        showClose: false,
        onDisappear: (): void => {
          this.handleConfirmSheetDisappear();
        }
      }, 's', this.desktopPresentation))

    Column()
      .width(0)
      .height(0)
      .bindSheet($$this.loginSheetVisible, this.buildHuaweiLoginSheet(), applyDesktopDialogSheetChrome({
        preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
        height: SheetSize.FIT_CONTENT,
        dragBar: !this.desktopPresentation,
        showClose: false,
        onDisappear: (): void => {
          this.handleLoginSheetDisappear();
        }
      }, 'm', this.desktopPresentation))

    Column()
      .width(0)
      .height(0)
      .bindSheet($$this.deviceTabsSheetVisible, this.buildDeviceTabsSheet(), applyDesktopDialogSheetChrome({
        preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
        height: SheetSize.LARGE,
        title: { title: DEVICE_TABS_SHEET_TITLE },
        dragBar: !this.desktopPresentation,
        showClose: true
      }, 'm', this.desktopPresentation))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildHuaweiLoginSheet() {
    HuaweiLoginSheetContent({
      controller: this.huaweiLoginController,
      onOpenUserAgreement: (): void => {
        this.openLoginLegalDocument('user_agreement');
      },
      onOpenPrivacyPolicy: (): void => {
        this.openLoginLegalDocument('privacy');
      }
    })
  }

  @Builder
  private buildDesktopLoginConfirmSheet() {
    DesktopLoginConfirmSheetContent({
      displayName: this.qrScanSnapshot.desktopLoginDisplayName,
      uid: this.qrScanSnapshot.desktopLoginUid,
      avatarUri: this.qrScanSnapshot.desktopLoginAvatarUri,
      confirming: this.qrScanSnapshot.desktopLoginConfirming,
      onAction: (action): void => {
        this.qrScanCoordinator.handleDesktopLoginConfirmAction(action);
      }
    })
  }

  /**
   * The sheet title comes from the host, exactly like the browser shell presents this
   * list, so the header spacing and the close button are the shared sheet's.
   */
  @Builder
  private buildDeviceTabsSheet() {
    BrowserCrossDeviceTabsSheet({
      deviceIdFilter: this.deviceTabsFilter,
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode,
      onNavigate: (action: CrossDeviceTabsEmptyAction): boolean => this.handleDeviceTabsNavigate(action),
      onOpenRemoteTab: (url: string, _title: string): void => {
        this.deviceTabsSheetVisible = false;
        this.openUrlInBrowser(url);
      }
    })
      .width('100%')
      .height('100%')
  }

  private handleDeviceTabsNavigate(action: CrossDeviceTabsEmptyAction): boolean {
    if (action === 'sign_in' || action === 'enable_link' || action === 'refresh' || action === 'none') {
      return false;
    }
    this.deviceTabsSheetVisible = false;
    if (action === 'open_pro') {
      this.navigationCoordinator.openSettingsDetail('aira_pro', this.boundary);
      return true;
    }
    if (action === 'open_sync_settings') {
      if (this.onOpenSyncSettings !== undefined) {
        this.onOpenSyncSettings();
        return true;
      }
      this.navigationCoordinator.openSyncSettings(this.boundary);
      return true;
    }
    if (action === 'open_setup') {
      if (this.desktopPresentation) {
        this.showSetupInline = true;
        return true;
      }
      this.navigationCoordinator.openCrossDeviceLinkSetup(this.boundary, this.providerKind);
      return true;
    }
    if (action === 'open_guide') {
      this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.boundary);
      return true;
    }
    return false;
  }

  private handleSyncSettingsSignal(): void {
    void this.refresh();
  }

  private async refresh(): Promise<void> {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      this.navigationCoordinator.back();
      return;
    }
    // `load()` projects the sync settings that are in memory, and that store only
    // holds the real values once it has been read, so load it first.
    await sharedAiraSyncConfigStore.initialize().catch((): undefined => undefined);
    const syncState = await sharedSyncExperienceCoordinator.load().catch((): undefined => undefined);
    const panelState = await sharedCrossDeviceTabPresenceCoordinator.loadPanelState().catch((): undefined => undefined);
    const providerKind = this.resolveProviderKind(syncState);
    this.providerKind = providerKind;
    // The header names the account, so it is read before the state that carries it.
    const account = await this.refreshAccount();
    const localDevice = await this.resolveLocalDevice();
    const now = Date.now();
    const devices: CrossDeviceLinkDeviceFact[] = [];
    if (panelState !== undefined) {
      panelState.devices.forEach((device: CrossDeviceTabPresenceDevice): void => {
        devices.push({
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          platform: device.platform,
          browserName: device.browserName,
          tabCount: device.tabCount,
          ageMs: device.updatedAt > 0 ? Math.max(0, now - device.updatedAt) : 0
        });
      });
    }
    hilog.info(
      CROSS_DEVICE_LINK_LOG_DOMAIN,
      CROSS_DEVICE_LINK_LOG_TAG,
      'refresh loaded=%{public}s activeProvider=%{public}s bookmark=%{public}s history=%{public}s historySupported=%{public}s devices=%{public}d status=%{public}s',
      syncState !== undefined ? '1' : '0',
      syncState !== undefined && syncState.hasActiveProvider ? syncState.goalLabel : 'none',
      syncState !== undefined && syncState.bookmarkSelected ? '1' : '0',
      syncState !== undefined && syncState.historySelected ? '1' : '0',
      syncState !== undefined && syncState.historySupported ? '1' : '0',
      devices.length,
      panelState !== undefined ? panelState.status : 'unknown'
    );
    const nextViewState = this.viewModel.buildState({
      desktopLinkAvailable: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud'),
      providerKind: providerKind,
      bookmarkSyncEnabled: syncState !== undefined && syncState.bookmarkSelected,
      historySyncEnabled: syncState !== undefined && syncState.historySelected,
      historySyncSupported: syncState !== undefined && syncState.historySupported,
      deviceStatus: panelState !== undefined ? panelState.status : 'error',
      deviceMessage: panelState !== undefined ? panelState.message : '',
      devices: devices,
      account: account,
      localDevice: localDevice,
      hasConfiguredSync: syncState !== undefined && syncState.hasConfiguredSync,
      goalLabel: syncState !== undefined && syncState.hasActiveProvider ? syncState.goalLabel : '',
      linkEnabled: await sharedCrossDeviceTabPresenceCoordinator.isCrossDeviceLinkEnabled()
        .catch((): boolean => false),
      // Account login carries the link. Data sync may be off or use another provider.
      // Membership only decides whether that switch can be used now; the preference is not rewritten.
      cloudEntitlement: this.resolveCloudEntitlement(providerKind, account.uid),
      linkSwitchEnabled: canEnableCrossDeviceLinkSwitch(
        AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud'),
        providerKind,
        account.uid,
        this.resolveCloudEntitlement(providerKind, account.uid)
      )
    });
    lastPublishedViewState = nextViewState;
    this.viewState = nextViewState;
  }

  /**
   * The header names the person using this phone, so the identity comes from the sync
   * owner's own settings and the avatar falls back to the one the user picked locally.
   */
  private async refreshAccount(): Promise<CrossDeviceLinkAccountFact> {
    const settings = sharedAiraSyncConfigStore.getSettings();
    const identity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    if (!this.didLoadLocalAvatar) {
      this.didLoadLocalAvatar = true;
      this.cachedLocalAvatarUri = await this.localUserAvatarService.getAvatarImageUri()
        .catch((): string => '');
    }
    return {
      displayName: identity.displayName,
      uid: identity.uid,
      avatarUri: identity.photoUrl.length > 0 ? identity.photoUrl : this.cachedLocalAvatarUri
    };
  }

  /**
   * This phone is the one device the page can never be wrong about, so its name comes
   * from the presence owner's own installation record instead of a second identity.
   */
  private async resolveLocalDevice(): Promise<CrossDeviceLinkLocalDeviceFact> {
    if (this.cachedLocalDevice !== undefined) {
      return this.cachedLocalDevice;
    }
    const localDevice = await sharedCrossDeviceTabPresencePreferencesRepository.readLocalDevice()
      .catch((): CrossDeviceLinkLocalDeviceFact => ({ deviceName: '', platform: '', browserName: '' }));
    this.cachedLocalDevice = {
      deviceName: localDevice.deviceName,
      platform: localDevice.platform,
      browserName: localDevice.browserName
    };
    return this.cachedLocalDevice;
  }

  /**
   * The active mode comes from the sync owner's own goal options, so this page never
   * guesses which provider is running.
   */
  private resolveProviderKind(syncState: SyncExperienceViewState | undefined): CrossDeviceLinkProviderKind {
    if (syncState === undefined || !syncState.hasActiveProvider) {
      return 'none';
    }
    let active: CrossDeviceLinkProviderKind = 'none';
    syncState.goalOptions.forEach((option: SyncExperienceGoalOption): void => {
      if (option.isSelected) {
        active = option.id;
      }
    });
    return active;
  }

  private handleAction(action: CrossDeviceLinkActionId): void {
    if (action === 'open_help') {
      this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.boundary);
      return;
    }
    if (action === 'open_device_tabs') {
      // The capability row is not about one computer, so it lists all of them.
      this.openDeviceTabs('');
      return;
    }
    if (action === 'open_personal_server') {
      this.navigationCoordinator.openSyncPersonalServerConfig(this.boundary);
      return;
    }
    if (action === 'add_device') {
      this.addDevice();
      return;
    }
    if (action === 'refresh_devices') {
      void this.refresh();
      return;
    }
    // PC hosts sync inside the settings workspace, whose dialogs are centered; pushing the
    // routed sync page there would drop the user back onto the phone presentation.
    if (this.onOpenSyncSettings !== undefined) {
      this.onOpenSyncSettings();
      return;
    }
    this.navigationCoordinator.openSyncSettings(this.boundary);
  }

  /**
   * This page's own switch: tab handoff and page push belong to the presence owner, not to the
   * data sync owner, so flipping it never touches bookmarks, history, or personalization.
   */
  private toggleLink(enabled: boolean): void {
    if (this.isTogglingLink || !this.viewState.linkSwitchEnabled) {
      return;
    }
    this.isTogglingLink = true;
    sharedCrossDeviceTabPresenceCoordinator.setCrossDeviceLinkEnabled(enabled)
      .catch((): undefined => undefined)
      .finally((): void => {
        this.isTogglingLink = false;
        // Rebuild the switch from the owner's own preference, never from the tap.
        void this.refresh().then((): void => {
          this.syncSwitchRevision += 1;
        });
      });
  }

  private openDeviceTabs(deviceId: string): void {
    this.deviceTabsFilter = deviceId;
    this.deviceTabsSheetVisible = true;
  }

  private addDevice(): void {
    if (this.isAddingDevice) {
      return;
    }
    this.isAddingDevice = true;
    void this.qrScanCoordinator.scan(this.getHostContext(), false)
      .catch((): undefined => undefined)
      .then((): void => {
        this.isAddingDevice = false;
      });
  }

  private handleConfirmSheetDisappear(): void {
    if (this.confirmSheetVisible) {
      return;
    }
    if (!this.qrScanSnapshot.desktopLoginConfirming) {
      this.qrScanCoordinator.handleSurfaceDismissed('desktop_login_confirm');
    }
  }

  private handleLoginSheetDisappear(): void {
    if (this.loginSheetVisible) {
      return;
    }
    if (!this.huaweiLoginCompleted && !this.preservePendingDesktopLogin) {
      this.qrScanCoordinator.cancelPendingDesktopLogin();
    }
    this.huaweiLoginCompleted = false;
    this.preservePendingDesktopLogin = false;
  }

  /**
   * A sheet opened by the scanner must wait until this page is foreground again.
   * HarmonyOS drops a bindSheet that is shown while the scan UI still owns the window.
   */
  private requestForegroundSheet(kind: 'desktop_login' | 'huawei_login'): void {
    this.pendingForegroundSheet = kind;
    this.flushPendingForegroundSheet();
  }

  private flushPendingForegroundSheet(): void {
    if (!this.pageVisible || this.pendingForegroundSheet === 'none') {
      return;
    }
    const kind = this.pendingForegroundSheet;
    this.pendingForegroundSheet = 'none';
    if (kind === 'desktop_login') {
      this.confirmSheetVisible = true;
      return;
    }
    this.loginSheetVisible = true;
  }

  private requestHuaweiLoginSheet(): boolean {
    if (!sharedHuaweiAccountMutationCoordinator.canSignIn(this.buildBoundaryInput())) {
      this.showToast('请回到普通会话后登录华为账号。');
      return true;
    }
    this.requestForegroundSheet('huawei_login');
    return true;
  }

  private buildBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode
    };
  }

  private openLoginLegalDocument(kind: string): void {
    this.preservePendingDesktopLogin = true;
    this.reopenHuaweiLoginOnShow = true;
    this.loginSheetVisible = false;
    if (kind === 'privacy') {
      this.navigationCoordinator.openPrivacyStatement(this.boundary);
      return;
    }
    this.navigationCoordinator.openLegalWebDocument('user_service_agreement', this.boundary);
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
    this.huaweiLoginCompleted = true;
    this.loginSheetVisible = false;
    sharedHuaweiAccountMutationCoordinator.signIn(this.buildBoundaryInput())
      .then((result): void => {
        if (result.type === 'failed') {
          this.showToast(result.message.length > 0 ? result.message : result.title);
          this.qrScanCoordinator.cancelPendingDesktopLogin();
          return;
        }
        new SyncSettingsRefreshSignal().bump();
        if (!this.qrScanCoordinator.resumeDesktopLoginAfterSignIn()) {
          void this.refresh();
        }
      })
      .catch((): void => {
        this.showToast('华为账号登录失败');
        this.qrScanCoordinator.cancelPendingDesktopLogin();
      });
  }

  /**
   * Official cloud needs an active Pro account. Private deployment and a community build do not.
   * This only classifies the switch; it never writes the saved preference.
   */
  private resolveCloudEntitlement(
    providerKind: CrossDeviceLinkProviderKind,
    accountUid: string
  ): CrossDeviceLinkCloudEntitlement {
    if (providerKind === 'self_hosted' || !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return 'not_required';
    }
    const uid = accountUid.trim();
    if (uid.length <= 0) {
      return 'signed_out';
    }
    const state = sharedMembershipFeature.getState();
    // A membership record for another account, or one not loaded yet, is not a paywall.
    if (state.userId.trim() !== uid) {
      return 'active';
    }
    if (state.plan === 'pro' && (state.planExpiresAt === 0 || state.planExpiresAt > Date.now())) {
      return 'active';
    }
    const lapsed = sharedMembershipFeature.getLapsedProState();
    if (lapsed.uid === uid && lapsed.expiredAt > 0) {
      return 'pro_expired';
    }
    return 'pro_required';
  }

  /**
   * Leaves this page and opens the url in the browser in front of the user. Staging
   * a launch payload only queues the page for later, which leaves the settings on
   * screen; going back to the shell opens it where the user can see it.
   */
  private openUrlInBrowser(url: string): void {
    if (url.length === 0) {
      return;
    }
    // The PC shell hosts settings in the tab's native route, where router.back cannot bring
    // the page forward; it hands us its own opener so the link really opens.
    if (this.onOpenExternalUrl !== undefined) {
      this.onOpenExternalUrl(url);
      return;
    }
    this.navigationCoordinator.openBrowserUrlFromGuide(url, this.boundary);
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }

  private getHostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }
}

const INITIAL_BOUNDARY: BrowserBoundaryRouteState = {
  dataScope: '',
  privacyMode: '',
  boundarySource: ''
};

/**
 * The first frame has to look like the frame that replaces it, otherwise the card
 * resizes under the user's finger. So it is built for the state this build is most
 * likely to resolve to: a full desktop link, with the device list still loading.
 */
function buildInitialViewState(): CrossDeviceLinkViewState {
  const desktopLinkAvailable = AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
  return new CrossDeviceLinkViewModel().buildState({
    desktopLinkAvailable: desktopLinkAvailable,
    providerKind: desktopLinkAvailable ? 'aira_cloud' : 'self_hosted',
    bookmarkSyncEnabled: true,
    historySyncEnabled: true,
    historySyncSupported: true,
    deviceStatus: 'loading',
    deviceMessage: '',
    devices: [],
    account: { displayName: '', uid: '', avatarUri: '' },
    localDevice: { deviceName: '', platform: '', browserName: '' },
    hasConfiguredSync: true,
    goalLabel: '',
    linkEnabled: true,
    linkSwitchEnabled: true,
    cloudEntitlement: 'active'
  });
}

/**
 * Kept across visits for the same reason: walking back into the page should not
 * repaint it from a guess.
 */
let lastPublishedViewState: CrossDeviceLinkViewState | undefined = undefined;
