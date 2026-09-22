import { TabRecord } from '../../common/models/BrowserModels';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AiraLapsedProView, AiraMembershipState, buildEmptyLapsedProView } from '../../common/models/MembershipModels';
import {
  AiraPersonalServerConfig,
  AiraSyncSettings
} from '../../common/models/AiraSyncModels';
import {
  sharedCrossDeviceTabPresencePreferencesRepository,
  CrossDeviceTabPresencePreferencesRepository
} from '../../data/deviceTabs/CrossDeviceTabPresencePreferencesRepository';
import {
  CrossDeviceTabPresenceApiError,
  CrossDeviceTabPresenceApiService
} from '../../services/deviceTabs/CrossDeviceTabPresenceApiService';
import {
  HuaweiAccountSyncAuthService,
  HuaweiAccountSyncIdentity
} from '../../services/sync/HuaweiAccountSyncAuthService';
import { AIRA_PERSONAL_SERVER_INSTANCE_SERVICE } from '../../services/sync/AiraPersonalServerInstanceService';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import {
  BrowserWindowSessionLifetimeListener,
  sharedBrowserWindowSessionLifetimeSignal
} from '../browser/BrowserWindowSessionLifetimeSignal';
import {
  CrossDeviceTabPresenceDevice,
  CrossDeviceTabPresenceLocalDevice,
  CrossDeviceTabPresencePanelState,
  CrossDeviceTabPresencePanelStatus,
  CrossDeviceTabPresenceTab
} from './CrossDeviceTabPresenceModels';
import {
  buildCrossDeviceTabsEmptyPresentation,
  CROSS_DEVICE_TABS_EMPTY_NONE,
  CrossDeviceTabsEmptyKind,
  CrossDeviceTabsEmptyPresentation
} from './CrossDeviceTabsEmptyPresentation';

const PUBLISH_DEBOUNCE_MS: number = 750;
const HEARTBEAT_INTERVAL_MS: number = 60000;
const MAX_PUBLISHED_TABS: number = 100;

interface CrossDeviceTabPresenceProviderContext {
  kind: 'aira_cloud' | 'self_hosted';
  preferenceScope: string;
  device: CrossDeviceTabPresenceLocalDevice;
  uid: string;
  personalServer?: AiraPersonalServerConfig;
}

export class CrossDeviceTabPresenceCoordinator {
  private readonly preferencesRepository: CrossDeviceTabPresencePreferencesRepository;
  private readonly apiService: CrossDeviceTabPresenceApiService;
  private readonly authService: HuaweiAccountSyncAuthService;
  private syncConfigStore?: AiraSyncConfigStore;
  private membershipStateReader?: () => AiraMembershipState;
  private lapsedProReader?: () => AiraLapsedProView;
  private readonly tabsByWindowId: Record<string, CrossDeviceTabPresenceTab[] | undefined> = {};
  private readonly foregroundByWindowId: Record<string, boolean | undefined> = {};
  private readonly lifetimeListeners: Record<string, BrowserWindowSessionLifetimeListener | undefined> = {};
  private readonly windowOrder: string[] = [];
  private publishTimer: number = -1;
  private heartbeatTimer: number = -1;
  private publishPromise?: Promise<void>;
  private entitlementBlocked: boolean = false;

  constructor(
    preferencesRepository?: CrossDeviceTabPresencePreferencesRepository,
    apiService?: CrossDeviceTabPresenceApiService,
    authService?: HuaweiAccountSyncAuthService
  ) {
    this.preferencesRepository = preferencesRepository ?? sharedCrossDeviceTabPresencePreferencesRepository;
    this.apiService = apiService ?? new CrossDeviceTabPresenceApiService();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  configureSyncConfigStore(syncConfigStore: AiraSyncConfigStore): void {
    this.syncConfigStore = syncConfigStore;
  }

  /** Membership facts stay with their owner. The panel only reads them to choose an empty page. */
  configureMembershipFacts(
    stateReader: () => AiraMembershipState,
    lapsedReader: () => AiraLapsedProView
  ): void {
    this.membershipStateReader = stateReader;
    this.lapsedProReader = lapsedReader;
  }

  reconcileWindowRecords(windowId: string, records: TabRecord[]): void {
    const normalizedWindowId = windowId.trim();
    if (normalizedWindowId.length === 0) {
      return;
    }
    if (!this.windowOrder.includes(normalizedWindowId)) {
      this.windowOrder.push(normalizedWindowId);
    }
    this.tabsByWindowId[normalizedWindowId] = this.projectRecords(records);
    this.ensureWindowLifetimeSubscription(normalizedWindowId);
    if (this.hasForegroundWindow()) {
      this.schedulePublish();
    }
  }

  async loadPanelState(): Promise<CrossDeviceTabPresencePanelState> {
    try {
      const settings = await this.requireSyncConfigStore().initialize();
      const localDevice = await this.preferencesRepository.readLocalDevice();
      if (settings.remoteKind === 'self_hosted') {
        const context = await this.resolveProviderContext(settings, localDevice)
          .catch((): undefined => undefined);
        if (context === undefined) {
          return this.buildPanelState(
            'disabled',
            false,
            localDevice.deviceName,
            [],
            '请先连接私有化部署',
            buildCrossDeviceTabsEmptyPresentation('connect_personal_server', 'credentials')
          );
        }
        return this.loadEnabledPanel(context);
      }
      if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity() ||
        !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
        const unavailable = !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity();
        return this.buildPanelState(
          'disabled',
          false,
          localDevice.deviceName,
          [],
          unavailable ? '跨设备互联不可用' : '请先连接私有化部署',
          buildCrossDeviceTabsEmptyPresentation('connect_personal_server', unavailable ? 'unavailable' : 'community')
        );
      }
      const context = await this.resolveProviderContext(settings, localDevice);
      if (context === undefined) {
        return this.buildPanelState(
          'signed_out',
          false,
          localDevice.deviceName,
          [],
          '请先使用华为账号登录。',
          buildCrossDeviceTabsEmptyPresentation('sign_in')
        );
      }
      const proKind = this.resolveCloudProEmptyKind(context.uid);
      if (proKind !== 'none') {
        return this.buildPanelState(
          'disabled',
          false,
          context.device.deviceName,
          [],
          '',
          buildCrossDeviceTabsEmptyPresentation(proKind)
        );
      }
      return this.loadEnabledPanel(context);
    } catch (error) {
      const device = await this.preferencesRepository.readLocalDevice();
      const proRequired = this.isProRequired(error);
      const message = this.resolveErrorMessage(error);
      return this.buildPanelState(
        proRequired ? 'disabled' : 'error',
        false,
        device.deviceName,
        [],
        proRequired ? '' : message,
        buildCrossDeviceTabsEmptyPresentation(proRequired ? 'pro_required' : 'error', proRequired ? '' : message)
      );
    }
  }

  async reconcileMembershipState(state: AiraMembershipState): Promise<void> {
    const settings = await this.requireSyncConfigStore().initialize();
    if (settings.remoteKind === 'self_hosted') {
      try {
        const localDevice = await this.preferencesRepository.readLocalDevice();
        const context = await this.resolveProviderContext(settings, localDevice);
        if (context === undefined) {
          throw new Error('私有化部署尚未连接。');
        }
        await this.enableProviderByDefault(context);
      } catch (_error) {
        this.entitlementBlocked = true;
        this.clearPublishTimer();
        this.stopHeartbeat();
      }
      return;
    }
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      this.entitlementBlocked = true;
      this.clearPublishTimer();
      this.stopHeartbeat();
      return;
    }
    const identity = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      this.entitlementBlocked = true;
      this.clearPublishTimer();
      this.stopHeartbeat();
      return;
    }
    const uid = identity.uid.trim();
    const enabledPreference = await this.preferencesRepository.readEnabledPreference(uid);
    if (!this.isActiveProState(state, uid)) {
      this.entitlementBlocked = true;
      this.clearPublishTimer();
      this.stopHeartbeat();
      if (enabledPreference === true) {
        const device = await this.preferencesRepository.readLocalDevice();
        await this.apiService.clear(uid, device.deviceId).catch((_error: Error): void => {
        });
      }
      return;
    }
    this.entitlementBlocked = false;
    if (enabledPreference !== true) {
      await this.preferencesRepository.setEnabled(uid, true);
    }
    if (this.hasForegroundWindow()) {
      this.startHeartbeat();
      this.schedulePublish();
    }
  }

  async clearCurrentAccountSnapshot(): Promise<void> {
    const settings = await this.requireSyncConfigStore().initialize();
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return;
    }
    const identity = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      return;
    }
    // Personal Server keeps publishing on its own credential. Signing out only withdraws
    // the account snapshot, and must not stop that other channel's heartbeat.
    if (settings.remoteKind !== 'self_hosted') {
      this.clearPublishTimer();
      this.stopHeartbeat();
    }
    const device = await this.preferencesRepository.readLocalDevice();
    await this.apiService.clear(identity.uid, device.deviceId);
  }

  /**
   * The cross-device switch is this owner's own preference, separate from the data-sync master
   * switch: a user who pauses bookmarks and history may still want tab handoff and page push.
   * Turning it off stops publishing and the heartbeat and withdraws our own snapshot, so the
   * other side stops seeing this phone; it never touches sync state.
   */
  async setCrossDeviceLinkEnabled(enabled: boolean): Promise<void> {
    const settings = await this.requireSyncConfigStore().initialize();
    const localDevice = await this.preferencesRepository.readLocalDevice();
    const context = await this.resolveProviderContext(settings, localDevice).catch((): undefined => undefined);
    if (context === undefined) {
      return;
    }
    await this.preferencesRepository.setEnabled(context.preferenceScope, enabled);
    if (enabled) {
      this.entitlementBlocked = false;
      if (this.hasForegroundWindow()) {
        this.startHeartbeat();
        this.schedulePublish();
      }
      return;
    }
    this.clearPublishTimer();
    this.stopHeartbeat();
    await this.withdrawSnapshot(context);
  }

  /** The preference is scoped to the paired account or server instance, like the panel itself. */
  async isCrossDeviceLinkEnabled(): Promise<boolean> {
    const settings = await this.requireSyncConfigStore().initialize();
    const localDevice = await this.preferencesRepository.readLocalDevice();
    const context = await this.resolveProviderContext(settings, localDevice).catch((): undefined => undefined);
    if (context === undefined) {
      return false;
    }
    return await this.preferencesRepository.isEnabled(context.preferenceScope);
  }

  private async withdrawSnapshot(context: CrossDeviceTabPresenceProviderContext): Promise<void> {
    try {
      if (context.kind === 'self_hosted' && context.personalServer !== undefined) {
        await this.apiService.clearPersonalServer(
          context.personalServer.baseUrl,
          context.personalServer.deviceToken
        );
        return;
      }
      await this.apiService.clear(context.uid, context.device.deviceId);
    } catch (_error) {
      // Withdrawing is best effort: the snapshot expires on its own within the online window.
    }
  }

  private ensureWindowLifetimeSubscription(windowId: string): void {
    let listener = this.lifetimeListeners[windowId];
    if (listener === undefined) {
      listener = (foreground: boolean): void => {
        this.handleWindowLifetimeChanged(windowId, foreground);
      };
      this.lifetimeListeners[windowId] = listener;
    }
    sharedBrowserWindowSessionLifetimeSignal.subscribe(windowId, listener);
  }

  private handleWindowLifetimeChanged(windowId: string, foreground: boolean): void {
    this.foregroundByWindowId[windowId] = foreground;
    if (!this.hasForegroundWindow()) {
      this.clearPublishTimer();
      this.stopHeartbeat();
      return;
    }
    this.startHeartbeat();
    this.schedulePublish();
  }

  private hasForegroundWindow(): boolean {
    return Object.keys(this.foregroundByWindowId).some((windowId: string): boolean => {
      return this.foregroundByWindowId[windowId] === true;
    });
  }

  private schedulePublish(): void {
    this.clearPublishTimer();
    this.publishTimer = setTimeout((): void => {
      this.publishTimer = -1;
      void this.publishNow().catch((_error: Error): void => {
      });
    }, PUBLISH_DEBOUNCE_MS);
  }

  private clearPublishTimer(): void {
    if (this.publishTimer < 0) {
      return;
    }
    clearTimeout(this.publishTimer);
    this.publishTimer = -1;
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer >= 0 || !this.hasForegroundWindow() || this.entitlementBlocked) {
      return;
    }
    this.heartbeatTimer = setInterval((): void => {
      void this.publishNow().catch((_error: Error): void => {
      });
    }, HEARTBEAT_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer < 0) {
      return;
    }
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = -1;
  }

  private async publishNow(): Promise<void> {
    if (this.publishPromise !== undefined) {
      return this.publishPromise;
    }
    this.publishPromise = this.publishCurrentSnapshot();
    try {
      await this.publishPromise;
    } finally {
      this.publishPromise = undefined;
    }
  }

  private async publishCurrentSnapshot(): Promise<void> {
    if (!this.hasForegroundWindow()) {
      return;
    }
    const settings = await this.requireSyncConfigStore().initialize();
    if (!this.isSupportedProvider(settings)) {
      this.stopHeartbeat();
      return;
    }
    const localDevice = await this.preferencesRepository.readLocalDevice();
    const context = await this.resolveProviderContext(settings, localDevice);
    if (context === undefined) {
      this.stopHeartbeat();
      return;
    }
    if (context.kind === 'aira_cloud' && this.entitlementBlocked) {
      return;
    }
    if (context.kind === 'self_hosted' && this.entitlementBlocked) {
      this.entitlementBlocked = false;
      this.startHeartbeat();
    }
    if (!await this.preferencesRepository.isEnabled(context.preferenceScope)) {
      this.stopHeartbeat();
      return;
    }
    try {
      if (context.kind === 'self_hosted' && context.personalServer !== undefined) {
        await this.apiService.publishPersonalServer(
          context.personalServer.baseUrl,
          context.personalServer.deviceToken,
          context.device,
          this.collectPublishedTabs()
        );
      } else {
        await this.apiService.publish(context.uid, context.device, this.collectPublishedTabs());
      }
    } catch (error) {
      const detail = error as Error;
      if (this.isProRequired(detail)) {
        this.entitlementBlocked = true;
        this.stopHeartbeat();
      }
      throw detail;
    }
  }

  private collectPublishedTabs(): CrossDeviceTabPresenceTab[] {
    const result: CrossDeviceTabPresenceTab[] = [];
    this.windowOrder.forEach((windowId: string, windowOrder: number): void => {
      const tabs = this.tabsByWindowId[windowId] ?? [];
      tabs.forEach((tab: CrossDeviceTabPresenceTab): void => {
        if (result.length >= MAX_PUBLISHED_TABS) {
          return;
        }
        result.push({
          title: tab.title,
          url: tab.url,
          active: tab.active,
          lastActiveAt: tab.lastActiveAt,
          windowOrder: windowOrder,
          tabOrder: tab.tabOrder
        });
      });
    });
    return result;
  }

  private projectRecords(records: TabRecord[]): CrossDeviceTabPresenceTab[] {
    const result: CrossDeviceTabPresenceTab[] = [];
    records.forEach((record: TabRecord, index: number): void => {
      if (result.length >= MAX_PUBLISHED_TABS || record.isHome === true || record.privacyMode === 'private' ||
        record.dataScope === 'session_ephemeral' || record.runtimeState === 'error') {
        return;
      }
      const url = this.normalizeHttpUrl(record.url);
      if (url.length === 0) {
        return;
      }
      result.push({
        title: record.title.trim().slice(0, 512),
        url: url,
        active: record.isActive === true,
        lastActiveAt: this.normalizeTimestamp(record.lastActiveAt),
        windowOrder: 0,
        tabOrder: this.normalizeOrder(record.tabOrder, index)
      });
    });
    return result;
  }

  private normalizeHttpUrl(value: string): string {
    const url = value.trim();
    const lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return '';
    }
    const authorityStart = url.indexOf('://') + 3;
    let authorityEnd = url.length;
    const separators: string[] = ['/', '?', '#'];
    separators.forEach((separator: string): void => {
      const index = url.indexOf(separator, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    });
    const authority = url.slice(authorityStart, authorityEnd);
    return authority.length > 0 && !authority.includes('@') ? url : '';
  }

  private normalizeTimestamp(value: number): number {
    return Number.isSafeInteger(value) && value > 0 ? value : 0;
  }

  private normalizeOrder(value: number | undefined, fallback: number): number {
    return value !== undefined && Number.isSafeInteger(value) && value >= 0 ? value : fallback;
  }

  private async loadEnabledPanel(
    context: CrossDeviceTabPresenceProviderContext
  ): Promise<CrossDeviceTabPresencePanelState> {
    const enabled = await this.preferencesRepository.isEnabled(context.preferenceScope);
    if (!enabled) {
      return this.buildPanelState(
        'disabled',
        false,
        context.device.deviceName,
        [],
        '',
        buildCrossDeviceTabsEmptyPresentation('link_disabled')
      );
    }
    const result = context.kind === 'self_hosted' && context.personalServer !== undefined
      ? await this.apiService.listPersonalServer(
        context.personalServer.baseUrl,
        context.personalServer.deviceToken
      )
      : await this.apiService.list(context.uid, context.device.deviceId);
    const empty = result.devices.length === 0
      ? buildCrossDeviceTabsEmptyPresentation('no_devices')
      : CROSS_DEVICE_TABS_EMPTY_NONE;
    return {
      status: 'ready',
      enabled: true,
      deviceName: context.device.deviceName,
      devices: result.devices,
      message: '',
      serverTime: result.serverTime,
      onlineWindowMs: result.onlineWindowMs,
      empty: empty
    };
  }

  /**
   * Pro is checked only after a Huawei identity exists, and only once that identity's
   * membership has been loaded. A missing reader or a not-yet-hydrated account does not
   * pretend to be a paywall; the list call still reports `pro_required` if it is.
   */
  private resolveCloudProEmptyKind(uid: string): CrossDeviceTabsEmptyKind {
    if (this.membershipStateReader === undefined) {
      return 'none';
    }
    const state = this.membershipStateReader();
    if (state.userId.trim() !== uid || this.isActiveProState(state, uid)) {
      return 'none';
    }
    const lapsed = this.lapsedProReader === undefined ? buildEmptyLapsedProView() : this.lapsedProReader();
    if (lapsed.uid === uid && lapsed.expiredAt > 0) {
      return 'pro_expired';
    }
    return 'pro_required';
  }

  private buildPanelState(
    status: CrossDeviceTabPresencePanelStatus,
    enabled: boolean,
    deviceName: string,
    devices: CrossDeviceTabPresenceDevice[],
    message: string,
    empty: CrossDeviceTabsEmptyPresentation = CROSS_DEVICE_TABS_EMPTY_NONE
  ): CrossDeviceTabPresencePanelState {
    return {
      status: status,
      enabled: enabled,
      deviceName: deviceName,
      devices: devices,
      message: message,
      serverTime: Date.now(),
      onlineWindowMs: 120000,
      empty: empty
    };
  }

  private resolveErrorMessage(error: Object): string {
    const detail = error as Error;
    const message = detail.message?.trim() ?? '';
    return message.length > 0 ? message : '跨设备标签页暂时不可用。';
  }

  private isProRequired(error: Object): boolean {
    const detail = error as CrossDeviceTabPresenceApiError;
    return detail.code === 'pro_required';
  }

  private async enableProviderByDefault(context: CrossDeviceTabPresenceProviderContext): Promise<void> {
    const enabledPreference = await this.preferencesRepository.readEnabledPreference(context.preferenceScope);
    if (enabledPreference !== true) {
      await this.preferencesRepository.setEnabled(context.preferenceScope, true);
    }
    this.entitlementBlocked = false;
    if (this.hasForegroundWindow()) {
      this.startHeartbeat();
      this.schedulePublish();
    }
  }

  private requireSyncConfigStore(): AiraSyncConfigStore {
    if (this.syncConfigStore === undefined) {
      throw new Error('同步配置尚未初始化。');
    }
    return this.syncConfigStore;
  }

  /**
   * Account login carries the link by itself. Data sync may be off, WebDAV, or Huawei Space.
   * Personal Server is the other channel, and only when it is the active sync provider.
   */
  private isSupportedProvider(settings: AiraSyncSettings): boolean {
    if (settings.remoteKind === 'self_hosted') {
      return true;
    }
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
  }

  private async resolveProviderContext(
    settings: AiraSyncSettings,
    localDevice: CrossDeviceTabPresenceLocalDevice
  ): Promise<CrossDeviceTabPresenceProviderContext | undefined> {
    if (settings.remoteKind === 'self_hosted') {
      const config = AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(settings);
      const pairedDeviceId = settings.sourceId.trim();
      if (pairedDeviceId.length === 0) {
        throw new Error('私有化部署设备标识不可用，请重新连接。');
      }
      return {
        kind: 'self_hosted',
        preferenceScope: `personal-server:${config.instanceId}`,
        device: {
          deviceId: pairedDeviceId,
          deviceName: config.deviceName.trim().length > 0 ? config.deviceName : localDevice.deviceName,
          platform: localDevice.platform,
          model: localDevice.model,
          browserName: localDevice.browserName,
          browserVersion: localDevice.browserVersion
        },
        uid: '',
        personalServer: config
      };
    }
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return undefined;
    }
    const identity: HuaweiAccountSyncIdentity | undefined = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      return undefined;
    }
    const uid = identity.uid.trim();
    return {
      kind: 'aira_cloud',
      preferenceScope: uid,
      device: localDevice,
      uid: uid
    };
  }

  private isActiveProState(state: AiraMembershipState, uid: string): boolean {
    return state.userId.trim() === uid && state.plan === 'pro' &&
      (state.planExpiresAt === 0 || state.planExpiresAt > Date.now());
  }
}

export const sharedCrossDeviceTabPresenceCoordinator: CrossDeviceTabPresenceCoordinator =
  new CrossDeviceTabPresenceCoordinator();
