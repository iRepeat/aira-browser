import { common } from '@kit.AbilityKit';
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
  CrossDeviceLinkActionId,
  CrossDeviceLinkDeviceFact,
  CrossDeviceLinkProviderKind,
  CrossDeviceLinkViewState,
  CrossDeviceLinkViewModel
} from '../../../core/sync/CrossDeviceLinkViewModel';
import {
  SyncExperienceGoalOption,
  SyncExperienceViewState
} from '../../../core/sync/SyncExperienceViewModel';
import { CrossDeviceTabPresenceDevice } from '../../../core/deviceTabs/CrossDeviceTabPresenceModels';
import { sharedCrossDeviceTabPresenceCoordinator } from '../../../core/deviceTabs/CrossDeviceTabPresenceCoordinator';
import { sharedSyncExperienceCoordinator, sharedAiraSyncConfigStore } from '../../bootstrap/BrowserAppRuntime';
import { SYNC_SETTINGS_REFRESH_REVISION_KEY } from '../../../core/sync/SyncSettingsRefreshSignal';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { BrowserCrossDeviceTabsSheet } from '../browser/BrowserCrossDeviceTabsOverlay';
import { DesktopLoginConfirmSheetContent } from '../settings/DesktopLoginConfirmSheetContent';
import { CrossDeviceLinkScreen } from './CrossDeviceLinkScreen';
import { CrossDeviceLinkSetupScreen } from './CrossDeviceLinkSetupScreen';

const DEVICE_TABS_SHEET_TITLE: string = '跨设备标签页';
const CROSS_DEVICE_LINK_LOG_DOMAIN: number = 0x0A1A;
const CROSS_DEVICE_LINK_LOG_TAG: string = 'CrossDeviceLink';

@Component
export struct CrossDeviceLinkHost {
  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('handleSyncSettingsSignal')
  private syncSettingsRefreshRevision: number = 0;
  @Prop @Watch('handlePageShowRefresh') refreshToken: number = 0;
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
  @State private isAddingDevice: boolean = false;
  /** Large-screen workspace shows the install/pairing recipe inline instead of routing. */
  @State private showSetupInline: boolean = false;
  /** Remembered so the install sub-page can show the right recipe. */
  @State private providerKind: CrossDeviceLinkProviderKind = 'none';
  @State private confirmSheetVisible: boolean = false;
  @State private deviceTabsSheetVisible: boolean = false;
  /** Empty shows every online computer; a device row narrows the sheet to that one. */
  @State private deviceTabsFilter: string = '';
  @State private qrScanSnapshot: BrowserQrScanSessionSnapshot = DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT;
  @State private boundary: BrowserBoundaryRouteState = INITIAL_BOUNDARY;
  private readonly viewModel: CrossDeviceLinkViewModel = new CrossDeviceLinkViewModel();
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
      // Only the desktop-login handshake is in scope on this page; an account
      // redirect leaves the page, and any other result opens as a page.
      if (target === 'account_settings') {
        this.navigationCoordinator.openSettingsDetail('aira_pro', this.boundary);
        return;
      }
      this.openUrlInBrowser(value);
    },
    setSurfaceVisible: (surface: BrowserQrScanSurface, visible: boolean): void => {
      if (surface !== 'desktop_login_confirm') {
        return;
      }
      this.confirmSheetVisible = visible;
    }
  };
  private readonly qrScanCoordinator: BrowserQrScanCoordinator =
    new BrowserQrScanCoordinator(sharedAiraSyncConfigStore, this.qrScanShell);

  aboutToAppear(): void {
    this.boundary = readBrowserBoundaryRouteState();
    void this.refresh();
  }

  private handlePageShowRefresh(): void {
    void this.refresh();
  }

  build() {
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
          isAddingDevice: this.isAddingDevice,
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
          onHelp: (): void => {
            this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.boundary);
          },
          onAddDevice: (): void => {
            this.addDevice();
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
          onAction: (action: CrossDeviceLinkActionId): void => {
            this.handleAction(action);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.confirmSheetVisible, this.buildDesktopLoginConfirmSheet(), {
      preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: !this.desktopPresentation,
      showClose: false,
      onDisappear: (): void => {
        this.handleConfirmSheetDisappear();
      }
    })
    .bindSheet($$this.deviceTabsSheetVisible, this.buildDeviceTabsSheet(), {
      preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.LARGE,
      title: { title: DEVICE_TABS_SHEET_TITLE },
      dragBar: !this.desktopPresentation,
      showClose: true
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
      onOpenRemoteTab: (url: string, _title: string): void => {
        this.deviceTabsSheetVisible = false;
        this.openUrlInBrowser(url);
      }
    })
      .width('100%')
      .height('100%')
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
      devices: devices
    });
    lastPublishedViewState = nextViewState;
    this.viewState = nextViewState;
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
    devices: []
  });
}

/**
 * Kept across visits for the same reason: walking back into the page should not
 * repaint it from a guess.
 */
let lastPublishedViewState: CrossDeviceLinkViewState | undefined = undefined;
