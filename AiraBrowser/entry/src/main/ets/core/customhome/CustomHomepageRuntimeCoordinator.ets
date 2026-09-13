import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  BrowserThemeMode,
  BrowserResolvedThemeMode,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { CustomHomepageSettings } from '../../common/models/CustomHomepageModels';
import { CUSTOM_HOMEPAGE_SETTINGS_ROUTE } from '../../app/router/AppRoutes';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import { DEFAULT_BROWSER_APPEARANCE_SETTINGS } from '../../data/preferences/PreferencesRepository';
import { BrowserAddressSubmissionCoordinator } from '../navigation/BrowserAddressSubmissionCoordinator';
import { WebNetworkAvailabilityService } from '../../services/web/WebNetworkAvailabilityService';
import {
  WebLoadErrorPresentation,
  WebLoadErrorPresentationService
} from '../../services/web/WebLoadErrorPresentationService';
import { buildBrowserTabWebComponentSnapshotId } from '../../services/web/BrowserTabPreviewCaptureService';
import {
  CustomHomepageBridgeService,
  CustomHomepageHoldingHandStatus,
  CustomHomepageMotionState,
  CustomHomepagePrivacyState,
  CustomHomepageShortcutIconItem,
  CustomHomepageThemeState
} from '../../services/customhome/CustomHomepageBridgeService';
import {
  CustomHomepageThemePaletteProjectionService,
  CustomHomepageThemePreferenceSnapshot
} from '../../services/customhome/CustomHomepageThemePaletteProjectionService';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import { BrowserSmartGripState } from '../browser/BrowserSmartGripCoordinator';
import { BrowserAppUrlOpenCoordinator } from '../browser/BrowserAppUrlOpenCoordinator';
import { BrowserWindowOpenApplicationCoordinator } from '../browser/BrowserWindowOpenApplicationCoordinator';
import { CustomHomepageNativeBridge } from '../browser/BrowserShellBridgeAdapters';
import { HomeShortcutStateCoordinator } from '../shortcuts/HomeShortcutStateCoordinator';
import { BrowserCreateTabOptions } from '../tabs/TabManager';
import {
  SearchEngineSelectionCoordinator,
  SearchEngineSelectionSnapshot
} from '../search/SearchEngineSelectionCoordinator';
import { WebRuntimeBridge } from '../web/WebRuntimeBridge';
import { buildWebAppearanceDocumentStartScriptItem } from '../web/WebAppearancePolicy';
import {
  CustomHomepageBridgeCoordinator,
  CustomHomepageBridgeShellAction,
  CustomHomepageBridgeShellExecutor,
  CustomHomepageBridgeSyncKind,
  CustomHomepageBridgeSyncSnapshot
} from './CustomHomepageBridgeCoordinator';
import {
  createCustomHomepageHostedWebGeneration,
  CustomHomepageHostedWebConfig,
  CustomHomepageHostedWebGeneration,
  CustomHomepageHostedWebDocumentSignal,
  CustomHomepageHostedWebNodeController
} from './CustomHomepageHostedWebNode';
import {
  CustomHomepagePresentationState,
  CustomHomepagePresentationViewModel
} from './CustomHomepagePresentationViewModel';

const CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN: number = 0x0000;
const CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG: string = 'CustomHomeRuntime';
const CUSTOM_HOMEPAGE_LOAD_TIMEOUT_MS: number = 8000;
// Upper bound on how long the cold-start cover may wait for the reloaded document
// to report that it painted; a slow or hanging subresource must not pin it.
const CUSTOM_HOMEPAGE_DOCUMENT_SETTLE_FALLBACK_MS: number = 3000;
// Homepages often paint a light default body background before their own dark
// theme applies, and often keep loading images after `loadFinished`. The reveal
// probe re-reads the page at this cadence until the theme matches AND the
// images already on screen have decoded, bounded so a stubborn page still reveals.
const CUSTOM_HOMEPAGE_SETTLE_PROBE_INTERVAL_MS: number = 100;
const CUSTOM_HOMEPAGE_SETTLE_PROBE_MAX_ATTEMPTS: number = 18;
// Consecutive identical confident reads required before revealing. One read is not
// enough: the page can be themed and image-complete in the render process a beat
// before it is composited to the screen.
const CUSTOM_HOMEPAGE_SETTLE_PROBE_STABLE_READS: number = 2;
// Returns 'dark' or 'light' once the page is painted, 'pending' while the
// document or a visible image is still coming in, or 'unknown'. Background tone
// alone was not enough: it can match the theme while visible images are still
// blank, which showed as a flash the moment the cold-start cover lifted.
const CUSTOM_HOMEPAGE_SETTLE_PROBE_SCRIPT: string =
  '(function(){try{' +
  'if(document.readyState!=="complete"){return "pending";}' +
  'function tone(el){if(!el){return null;}var m=getComputedStyle(el).backgroundColor.match(/rgba?\\(([^)]+)\\)/);' +
  'if(!m){return null;}var p=m[1].split(\',\').map(function(s){return parseFloat(s);});' +
  'var a=p.length>=4?p[3]:1;if(!(a>0.01)){return null;}return p;}' +
  'var p=tone(document.body);if(!p){p=tone(document.documentElement);}' +
  'if(!p){return "pending";}' +
  'var vw=window.innerWidth||document.documentElement.clientWidth||0;' +
  'var vh=window.innerHeight||document.documentElement.clientHeight||0;' +
  'var imgs=document.images||[];' +
  'for(var i=0;i<imgs.length;i++){var im=imgs[i];var r=im.getBoundingClientRect();' +
  'if(r.bottom>0&&r.top<vh&&r.right>0&&r.left<vw){' +
  'if(!im.complete){return "pending";}}}' +
  'var lum=(0.2126*p[0]+0.7152*p[1]+0.0722*p[2])/255;' +
  'return lum<0.5?"dark":"light";}catch(e){return "unknown";}})()';
export const CUSTOM_HOMEPAGE_PREVIEW_TAB_ID: string = 'custom-homepage';

const UNKNOWN_CUSTOM_HOMEPAGE_HOLDING_HAND_STATUS: CustomHomepageHoldingHandStatus = 16;

type CustomHomepageFailureAction = 'retry' | 'edit_homepage';

export type CustomHomepageSurfaceAction =
  'retry' |
  'edit_homepage' |
  'open_tabs' |
  'open_bookmarks' |
  'open_history' |
  'open_homepage_settings' |
  'open_settings_center';

export interface CustomHomepageLoadFailureState {
  visible: boolean;
  url: string;
  presentation: WebLoadErrorPresentation;
}

const HIDDEN_CUSTOM_HOMEPAGE_LOAD_FAILURE_STATE: CustomHomepageLoadFailureState = {
  visible: false,
  url: '',
  presentation: {
    title: '',
    summary: '',
    host: '',
    primaryActionLabel: '再试一次',
    secondaryActionLabel: '编辑主页',
    tertiaryActionLabel: '',
    detailLabel: '错误详情',
    detailText: '',
    hints: []
  }
};

export type CustomHomepageRuntimeActivityState =
  'unbound' |
  'staging' |
  'active' |
  'inactive_resident';

export interface CustomHomepageRuntimeShellFacts {
  uiContext: UIContext;
  shellVisible: boolean;
  showHomePage: boolean;
  runtimeAllowed: boolean;
  theme: CustomHomepageRuntimeThemeFacts;
  privacy: CustomHomepagePrivacyState;
  dataScope: BrowserDataScope;
  createOptions: BrowserCreateTabOptions;
  homeBackgroundColor: string;
  forceEnableWebZoom: boolean;
  shortcuts: ShortcutRecord[];
  shortcutIcons: CustomHomepageShortcutIconItem[];
}

export interface CustomHomepageRuntimeThemeFacts {
  mode: BrowserThemeMode;
  effectiveMode: BrowserResolvedThemeMode;
}

export interface CustomHomepageRuntimeShellState {
  settings: CustomHomepageSettings;
  presentation: CustomHomepagePresentationState;
  loadFailureState: CustomHomepageLoadFailureState;
  presentationRevision: number;
  hostedNodeRevision: number;
  documentCommitted: boolean;
  activityState: CustomHomepageRuntimeActivityState;
  surfaceVisible: boolean;
  transientBackHandlerActive: boolean;
  // Identity of the currently presented document plus its resolved theme. The
  // shell validates the persisted cold-start launch snapshot against these.
  renderKey: string;
  themeMode: BrowserResolvedThemeMode;
  // True once the committed document has finished loading. The launch-snapshot
  // cover stays up until the real content has actually painted.
  documentSettled: boolean;
}

interface CustomHomepageApplySearchEngineSnapshotEffect {
  type: 'apply_search_engine_snapshot';
  snapshot: SearchEngineSelectionSnapshot;
}

interface CustomHomepageOpenSearchEffect {
  type: 'open_search';
  documentGeneration: number;
}

interface CustomHomepageOpenToolbarEffect {
  type: 'open_toolbar';
  documentGeneration: number;
}

interface CustomHomepageOpenNovelBookshelfEffect {
  type: 'open_novel_bookshelf';
  documentGeneration: number;
}

interface CustomHomepageTogglePrivateModeEffect {
  type: 'toggle_private_mode';
  documentGeneration: number;
}

interface CustomHomepageScanQrEffect {
  type: 'scan_qr';
}

interface CustomHomepageShowMessageEffect {
  type: 'show_message';
  message: string;
}

interface CustomHomepageHandleScrollEffect {
  type: 'handle_scroll';
  event: OnScrollEvent;
}

export type CustomHomepageRuntimeShellEffect =
  CustomHomepageApplySearchEngineSnapshotEffect |
  CustomHomepageOpenSearchEffect |
  CustomHomepageOpenToolbarEffect |
  CustomHomepageOpenNovelBookshelfEffect |
  CustomHomepageTogglePrivateModeEffect |
  CustomHomepageScanQrEffect |
  CustomHomepageShowMessageEffect |
  CustomHomepageHandleScrollEffect;

export interface CustomHomepageRuntimeShellHost {
  resolveFacts: () => CustomHomepageRuntimeShellFacts;
  publishState: (state: CustomHomepageRuntimeShellState) => void;
  notifyDocumentCommitted: () => void;
  // The homepage edited its own content/layout through the bridge, so the
  // cold-start cover for this identity is now out of date.
  notifyContentChanged: () => void;
  executeEffect: (effect: CustomHomepageRuntimeShellEffect) => void;
}

export interface CustomHomepageRuntimeDependencies {
  repository: CustomHomepageRepository;
  selectionCoordinator: SearchEngineSelectionCoordinator;
  addressSubmissionCoordinator: BrowserAddressSubmissionCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  routeCoordinator: BrowserShellRouteCoordinator;
  shortcutStateCoordinator: HomeShortcutStateCoordinator;
  windowOpenApplicationCoordinator: BrowserWindowOpenApplicationCoordinator;
  webRuntimeBridge: WebRuntimeBridge;
}

interface CustomHomepageRuntimeTimeoutRequest {
  generation: number;
  documentGeneration: number;
  url: string;
}

interface CustomHomepageRuntimeCancelTimeoutEffect {
  type: 'cancel_timeout';
}

interface CustomHomepageRuntimeMaterializeEffect {
  type: 'materialize_document';
  generation: number;
}

interface CustomHomepageRuntimeScheduleTimeoutEffect {
  type: 'schedule_timeout';
  request: CustomHomepageRuntimeTimeoutRequest;
  delayMs: number;
}

interface CustomHomepageRuntimeSyncBridgeEffect {
  type: 'sync_bridge';
  generation: number;
}

interface CustomHomepageRuntimeShowToastEffect {
  type: 'show_toast';
  message: string;
}

interface CustomHomepageRuntimeRefreshPresentationEffect {
  type: 'refresh_presentation';
}

interface CustomHomepageRuntimeOpenHomepageSettingsEffect {
  type: 'open_homepage_settings';
}

interface CustomHomepageRuntimeOpenUrlEffect {
  type: 'open_url';
  url: string;
}

type CustomHomepageRuntimeEffect =
  CustomHomepageRuntimeCancelTimeoutEffect |
  CustomHomepageRuntimeMaterializeEffect |
  CustomHomepageRuntimeScheduleTimeoutEffect |
  CustomHomepageRuntimeSyncBridgeEffect |
  CustomHomepageRuntimeShowToastEffect |
  CustomHomepageRuntimeRefreshPresentationEffect |
  CustomHomepageRuntimeOpenHomepageSettingsEffect |
  CustomHomepageRuntimeOpenUrlEffect;

interface CustomHomepageRuntimeTransition {
  effects: CustomHomepageRuntimeEffect[];
}

interface CustomHomepageRuntimeRefreshInput {
  homeVisible: boolean;
  runtimeAllowed: boolean;
  shouldRenderCustomHtml: boolean;
  webUrl: string;
  renderKey: string;
  renderKeyChanged: boolean;
  forceReload: boolean;
}

interface CustomHomepageRuntimeControllerAttachedInput {
  generation: number;
}

interface CustomHomepageRuntimePageBeginInput {
  url: string;
  generation: number;
}

interface CustomHomepageRuntimePageEndInput {
  url: string;
  generation: number;
}

interface CustomHomepageRuntimeVisibilityInput {
  homeVisible: boolean;
  runtimeAllowed: boolean;
  shouldRenderCustomHtml: boolean;
}

interface CustomHomepageRuntimeErrorInput {
  requestUrl: string;
  generation: number;
  isMainFrame: boolean;
  errorMessage: string;
}

interface CustomHomepageRuntimeNavigationInput {
  generation: number;
  url: string;
  isMainFrame: boolean;
  isRequestGesture: boolean;
  isRemoteUrlHomepage: boolean;
  isHttpOrHttpsUrl: boolean;
}

interface CustomHomepageRuntimeNavigationPlan {
  shouldIntercept: boolean;
  transition?: CustomHomepageRuntimeTransition;
}

export class CustomHomepageRuntimeCoordinator {
  private dependencies: CustomHomepageRuntimeDependencies;
  private shellHost: CustomHomepageRuntimeShellHost;
  private repository: CustomHomepageRepository;
  private presentationViewModel: CustomHomepagePresentationViewModel = new CustomHomepagePresentationViewModel();
  private settings: CustomHomepageSettings;
  private presentationState: CustomHomepagePresentationState;
  private presentationRenderKey: string;
  private presentationThemeMode: BrowserResolvedThemeMode = 'light';
  private presentationRevision: number = 0;
  private hostedNodeRevision: number = 0;
  private settingsListenerKey: string = '';
  private loadTimeoutTimer: number = -1;
  private documentSettleFallbackTimer: number = -1;
  private documentSettleProbeTimer: number = -1;
  private documentSettleProbeAttempts: number = 0;
  private documentSettleProbeGeneration: number = 0;
  private documentSettleProbeLastSample: string = '';
  private documentSettleProbeStableMatches: number = 0;
  private loadErrorPresentationService: WebLoadErrorPresentationService = new WebLoadErrorPresentationService();
  private loadFailureState: CustomHomepageLoadFailureState = HIDDEN_CUSTOM_HOMEPAGE_LOAD_FAILURE_STATE;
  private loadingUrl: string = '';
  private diagnosticLoadStartedAt: number = 0;
  private failedUrl: string = '';
  private loadGeneration: number = 0;
  private transientBackHandlerActive: boolean = false;
  private controllerAttached: boolean = false;
  private desiredGeneration: number = 0;
  private activeGeneration: number = 0;
  private committedGeneration: number = 0;
  private settledGeneration: number = 0;
  private desiredUrl: string = '';
  private desiredRenderKey: string = '';
  private activeRenderKey: string = '';
  private documentCommitted: boolean = false;
  private bridgeAuthorityActive: boolean = false;
  private activityState: CustomHomepageRuntimeActivityState = 'unbound';
  private homeVisible: boolean = false;
  private runtimeAllowed: boolean = false;
  private shouldRenderCustomHtml: boolean = false;
  private hostedWebGeneration: CustomHomepageHostedWebGeneration | undefined = undefined;
  private networkAvailabilityService: WebNetworkAvailabilityService;
  private bridgeService: CustomHomepageBridgeService;
  private themePaletteProjectionService: CustomHomepageThemePaletteProjectionService;
  private themePreferences: CustomHomepageThemePreferenceSnapshot = {
    themePaletteId: DEFAULT_BROWSER_APPEARANCE_SETTINGS.themePaletteId
  };
  private bridgeCoordinator: CustomHomepageBridgeCoordinator;
  private holdingHandStatus: CustomHomepageHoldingHandStatus = UNKNOWN_CUSTOM_HOMEPAGE_HOLDING_HAND_STATUS;
  private bridgeShellExecutor: CustomHomepageBridgeShellExecutor = {
    execute: (action: CustomHomepageBridgeShellAction): void => this.executeBridgeShellAction(action)
  };

  constructor(
    dependencies: CustomHomepageRuntimeDependencies,
    shellHost: CustomHomepageRuntimeShellHost,
    networkAvailabilityService: WebNetworkAvailabilityService = new WebNetworkAvailabilityService(),
    bridgeService: CustomHomepageBridgeService = new CustomHomepageBridgeService(),
    themePaletteProjectionService: CustomHomepageThemePaletteProjectionService =
      new CustomHomepageThemePaletteProjectionService()
  ) {
    this.dependencies = dependencies;
    this.shellHost = shellHost;
    this.repository = dependencies.repository;
    this.networkAvailabilityService = networkAvailabilityService;
    this.bridgeService = bridgeService;
    this.themePaletteProjectionService = themePaletteProjectionService;
    this.settings = this.repository.getSettings();
    this.presentationState = this.presentationViewModel.buildState(this.settings);
    this.presentationRenderKey = this.presentationViewModel.buildRenderKey(this.settings);
    this.bridgeCoordinator = new CustomHomepageBridgeCoordinator({
      selectionCoordinator: dependencies.selectionCoordinator,
      bridgeService: this.bridgeService,
      routeCoordinator: dependencies.routeCoordinator,
      shortcutStateCoordinator: dependencies.shortcutStateCoordinator,
      shellExecutor: this.bridgeShellExecutor
    });
    dependencies.shortcutStateCoordinator.bindCustomHomepageRuntime(this);
  }

  getShellState(): CustomHomepageRuntimeShellState {
    return {
      settings: this.settings,
      presentation: this.presentationState,
      loadFailureState: this.loadFailureState,
      presentationRevision: this.presentationRevision,
      hostedNodeRevision: this.hostedNodeRevision,
      documentCommitted: this.documentCommitted,
      activityState: this.activityState,
      surfaceVisible: this.isSurfaceVisible(),
      transientBackHandlerActive: this.transientBackHandlerActive,
      renderKey: this.presentationRenderKey,
      themeMode: this.presentationThemeMode,
      documentSettled: this.documentCommitted &&
        this.committedGeneration > 0 &&
        this.settledGeneration === this.committedGeneration
    };
  }

  start(forceReload: boolean): void {
    this.bindSettingsUpdates();
    this.refresh(forceReload);
  }

  stop(): void {
    this.unbindSettingsUpdates();
    this.applyLoadTimeout();
  }

  refresh(forceReload: boolean, homeVisibleOverride?: boolean): void {
    const facts = this.shellHost.resolveFacts();
    const previousUrl = this.presentationState.webUrl;
    const previousRenderKey = this.presentationRenderKey;
    this.settings = this.repository.getSettings();
    const refreshPlan = this.presentationViewModel.buildRefreshPlan({
      forceReload: forceReload,
      previousUrl: previousUrl,
      previousRenderKey: previousRenderKey,
      settings: this.settings,
      resolvedThemeMode: facts.theme.effectiveMode
    });
    this.presentationState = refreshPlan.state;
    this.presentationRenderKey = refreshPlan.renderKey;
    this.presentationThemeMode = facts.theme.effectiveMode;
    this.presentationRevision += 1;
    this.applyTransition(this.handlePresentationRefresh({
      homeVisible: homeVisibleOverride ?? facts.showHomePage,
      runtimeAllowed: facts.runtimeAllowed,
      shouldRenderCustomHtml: refreshPlan.state.shouldRenderCustomHtml,
      webUrl: refreshPlan.state.webUrl,
      renderKey: refreshPlan.renderKey,
      renderKeyChanged: refreshPlan.renderKeyChanged,
      forceReload: forceReload
    }));
  }

  syncVisibility(): void {
    const facts = this.shellHost.resolveFacts();
    const wasBridgeAuthorityActive = this.bridgeAuthorityActive;
    this.applyTransition(this.handleVisibilityChanged({
      homeVisible: facts.shellVisible && facts.showHomePage,
      runtimeAllowed: facts.runtimeAllowed,
      shouldRenderCustomHtml: this.presentationState.shouldRenderCustomHtml
    }));
    if (!wasBridgeAuthorityActive && this.bridgeAuthorityActive) {
      this.syncBridge('holding_hand');
    }
  }

  syncBridge(kind: CustomHomepageBridgeSyncKind, documentGeneration?: number): void {
    const facts = this.shellHost.resolveFacts();
    this.bridgeCoordinator.sync(kind, this.buildBridgeSyncSnapshot(facts, documentGeneration));
  }

  syncPrivacyBoundaryBridge(documentGeneration?: number): void {
    const facts = this.shellHost.resolveFacts();
    const snapshot = this.buildBridgeSyncSnapshot(facts, documentGeneration);
    this.bridgeCoordinator.sync('privacy', snapshot);
    this.bridgeCoordinator.sync('theme', snapshot);
  }

  updateThemePreferences(preferences: CustomHomepageThemePreferenceSnapshot): void {
    this.themePreferences = {
      themePaletteId: preferences.themePaletteId
    };
  }

  updateSmartGripState(state: BrowserSmartGripState): void {
    const next = this.resolveHoldingHandStatus(state);
    if (this.holdingHandStatus === next) {
      return;
    }
    this.holdingHandStatus = next;
    if (this.bridgeAuthorityActive && this.isMotionBridgeAllowed()) {
      this.syncBridge('holding_hand');
    }
  }

  private buildBridgeSyncSnapshot(
    facts: CustomHomepageRuntimeShellFacts,
    documentGeneration?: number
  ): CustomHomepageBridgeSyncSnapshot {
    return {
      shouldSync: this.shouldRenderCustomHomepage(),
      documentGeneration: documentGeneration ?? this.committedGeneration,
      dataScope: facts.dataScope,
      shortcuts: facts.shortcuts,
      icons: facts.shortcutIcons,
      theme: this.buildBridgeThemeState(facts),
      privacy: facts.privacy,
      motionAllowed: this.isMotionBridgeAllowed(),
      holdingHandStatus: this.resolvePublishedHoldingHandStatus()
    };
  }

  handleFailureAction(action: CustomHomepageFailureAction): void {
    this.applyTransition(this.buildFailureActionTransition(action));
  }

  handleSurfaceAction(action: CustomHomepageSurfaceAction): void {
    if (action === 'retry' || action === 'edit_homepage') {
      this.handleFailureAction(action);
      return;
    }
    if (action === 'open_homepage_settings') {
      this.dependencies.routeCoordinator.openSimpleRoute(
        CUSTOM_HOMEPAGE_SETTINGS_ROUTE,
        '打开自定义主页设置失败'
      );
      return;
    }
    if (action === 'open_tabs') {
      this.dependencies.routeCoordinator.openHomeSystemEntry('tabs');
      return;
    }
    if (action === 'open_bookmarks') {
      this.dependencies.routeCoordinator.openHomeSystemEntry('bookmarks');
      return;
    }
    if (action === 'open_history') {
      this.dependencies.routeCoordinator.openHomeSystemEntry('history');
      return;
    }
    this.dependencies.routeCoordinator.openHomeSystemEntry('settings');
  }

  private applyTransition(transition: CustomHomepageRuntimeTransition): void {
    this.publishShellState();
    for (const effect of transition.effects) {
      this.applyRuntimeEffect(effect);
    }
  }

  private applyRuntimeEffect(effect: CustomHomepageRuntimeEffect): void {
    switch (effect.type) {
      case 'cancel_timeout':
        this.applyLoadTimeout();
        return;
      case 'materialize_document':
        this.materializeHostedWebGeneration(effect.generation);
        return;
      case 'schedule_timeout':
        this.applyLoadTimeout(effect.request, effect.delayMs);
        return;
      case 'sync_bridge':
        this.syncBridge('document_ready', effect.generation);
        return;
      case 'show_toast':
        this.executeShellEffect({ type: 'show_message', message: effect.message });
        return;
      case 'refresh_presentation':
        this.refresh(true, true);
        return;
      case 'open_homepage_settings':
        this.dependencies.routeCoordinator.openSimpleRoute(
          CUSTOM_HOMEPAGE_SETTINGS_ROUTE,
          '打开自定义主页设置失败'
        );
        return;
      case 'open_url':
        this.openUrl(effect.url);
        return;
    }
  }

  private applyLoadTimeout(
    request?: CustomHomepageRuntimeTimeoutRequest,
    delayMs: number = 0
  ): void {
    if (this.loadTimeoutTimer >= 0) {
      clearTimeout(this.loadTimeoutTimer);
      this.loadTimeoutTimer = -1;
    }
    if (request === undefined) {
      return;
    }
    this.loadTimeoutTimer = setTimeout((): void => {
      this.loadTimeoutTimer = -1;
      this.applyTransition(this.handleLoadTimeout(request));
    }, delayMs);
  }

  private materializeHostedWebGeneration(generation: number): void {
    const facts = this.shellHost.resolveFacts();
    const created = createCustomHomepageHostedWebGeneration(
      facts.uiContext,
      this.buildHostedWebConfig(generation, facts)
    );
    this.applyTransition(this.bindHostedWebGeneration(created));
  }

  private buildHostedWebConfig(
    generation: number,
    facts: CustomHomepageRuntimeShellFacts
  ): CustomHomepageHostedWebConfig {
    const theme = this.buildBridgeThemeState(facts);
    const motion = this.buildPublishedMotionState();
    const appearancePolicy = this.presentationViewModel.buildWebAppearancePolicy({
      state: this.presentationState,
      resolvedThemeMode: facts.theme.effectiveMode,
      backgroundColor: facts.homeBackgroundColor
    });
    return {
      documentGeneration: generation,
      componentSnapshotId: `${buildBrowserTabWebComponentSnapshotId(CUSTOM_HOMEPAGE_PREVIEW_TAB_ID)}-${generation}`,
      appearancePolicy: appearancePolicy,
      forceEnableWebZoom: facts.forceEnableWebZoom,
      nativeBridge: new CustomHomepageNativeBridge(
        generation,
        (bridgeGeneration: number, action: string, value: string): string =>
          this.handleBridgeRequest(bridgeGeneration, action, value)
      ),
      documentStartScripts: [
        buildWebAppearanceDocumentStartScriptItem(appearancePolicy),
        this.bridgeService.buildDocumentStartScriptItem({
          theme: theme,
          privacy: facts.privacy,
          motion: motion
        })
      ],
      callbacks: {
        onControllerAttached: (attachedGeneration: number): void => {
          this.applyTransition(this.handleControllerAttached({ generation: attachedGeneration }));
        },
        onOverrideUrlLoading: (request: WebResourceRequest, requestGeneration: number): boolean =>
          this.handleOverrideUrlLoading(request, requestGeneration),
        onLoadIntercept: (event: OnLoadInterceptEvent, requestGeneration: number): boolean =>
          this.handleLoadIntercept(event, requestGeneration),
        onPageBegin: (event: OnPageBeginEvent, eventGeneration: number): void =>
          this.handlePageBeginEvent(event, eventGeneration),
        onPageEnd: (event: OnPageEndEvent, signal: CustomHomepageHostedWebDocumentSignal): void =>
          this.handlePageEndEvent(event, signal),
        onFirstMeaningfulPaint: (signal: CustomHomepageHostedWebDocumentSignal): void =>
          this.applyTransition(this.handleFirstMeaningfulPaint(signal)),
        onScroll: (event: OnScrollEvent, eventGeneration: number): void =>
          this.handleScrollEvent(event, eventGeneration),
        onLoadFinished: (signal: CustomHomepageHostedWebDocumentSignal): void =>
          this.applyTransition(this.handleLoadFinished(signal)),
        onWindowNew: (event: OnWindowNewEvent, eventGeneration: number): void =>
          this.handleWindowNewEvent(event, eventGeneration),
        onErrorReceive: (event: OnErrorReceiveEvent, eventGeneration: number): void =>
          this.handleErrorReceiveEvent(event, eventGeneration)
      }
    };
  }

  private buildBridgeThemeState(facts: CustomHomepageRuntimeShellFacts): CustomHomepageThemeState {
    return this.themePaletteProjectionService.build({
      preferences: this.themePreferences,
      mode: facts.theme.mode,
      effectiveMode: facts.theme.effectiveMode
    });
  }

  private handleOverrideUrlLoading(request: WebResourceRequest, generation: number): boolean {
    try {
      return this.handleNavigationEvent(
        request.getRequestUrl(),
        request.isMainFrame(),
        request.isRequestGesture(),
        generation
      );
    } catch (_error) {
      return false;
    }
  }

  private handleLoadIntercept(event: OnLoadInterceptEvent, generation: number): boolean {
    try {
      const request = event.data;
      return this.handleNavigationEvent(
        request.getRequestUrl(),
        request.isMainFrame(),
        request.isRequestGesture(),
        generation
      );
    } catch (_error) {
      return false;
    }
  }

  private handlePageBeginEvent(event: OnPageBeginEvent, generation: number): void {
    try {
      this.applyTransition(this.handlePageBegin({ url: event.url, generation: generation }));
    } catch (_error) {
    }
  }

  private handlePageEndEvent(
    event: OnPageEndEvent,
    signal: CustomHomepageHostedWebDocumentSignal
  ): void {
    try {
      this.applyTransition(this.handlePageEnd({
        url: event.url.trim(),
        generation: signal.generation
      }));
    } catch (_error) {
    }
  }

  private handleScrollEvent(event: OnScrollEvent, generation: number): void {
    if (!this.authorizeActiveDocumentEvent(generation, 'scroll')) {
      return;
    }
    this.executeShellEffect({ type: 'handle_scroll', event: event });
  }

  private handleWindowNewEvent(event: OnWindowNewEvent, generation: number): void {
    if (!this.authorizeActiveDocumentEvent(generation, 'window_new')) {
      this.dependencies.windowOpenApplicationCoordinator.rejectImmediateEvent(event);
      return;
    }
    try {
      this.dependencies.windowOpenApplicationCoordinator.rejectImmediateEvent(event);
      this.openUrl(event.targetUrl);
    } catch (_error) {
      this.dependencies.windowOpenApplicationCoordinator.rejectImmediateEvent(event);
    }
  }

  private handleErrorReceiveEvent(event: OnErrorReceiveEvent, generation: number): void {
    try {
      const requestUrl = event.request.getRequestUrl();
      const isMainFrame = event.request.isMainFrame();
      const errorCode = event.error.getErrorCode();
      const errorInfo = event.error.getErrorInfo();
      hilog.warn(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        'custom homepage web error main=%{public}s url=%{public}s code=%{public}d info=%{public}s',
        `${isMainFrame}`,
        requestUrl,
        errorCode,
        errorInfo
      );
      this.applyTransition(this.handleError({
        requestUrl: requestUrl,
        generation: generation,
        isMainFrame: isMainFrame,
        errorMessage: errorInfo.length > 0 ? errorInfo : `errorCode=${errorCode}`
      }));
    } catch (_error) {
    }
  }

  private handleNavigationEvent(
    url: string,
    isMainFrame: boolean,
    isRequestGesture: boolean,
    generation: number
  ): boolean {
    const normalizedUrl = url.trim();
    const normalizedScheme = this.dependencies.webRuntimeBridge.getUrlScheme(normalizedUrl);
    const navigationPlan = this.handleNavigationRequest({
      generation: generation,
      url: normalizedUrl,
      isMainFrame: isMainFrame,
      isRequestGesture: isRequestGesture,
      isRemoteUrlHomepage: this.presentationState.isRemoteUrlHomepage,
      isHttpOrHttpsUrl: normalizedScheme === 'http' || normalizedScheme === 'https'
    });
    if (navigationPlan.transition !== undefined) {
      this.applyTransition(navigationPlan.transition);
    }
    return navigationPlan.shouldIntercept;
  }

  private handleBridgeRequest(generation: number, action: string, value: string): string {
    const facts = this.shellHost.resolveFacts();
    const bridgeAuthorityActive = this.authorizeBridgeRequest(generation, action);
    const response = this.bridgeCoordinator.handleRequest({
      documentGeneration: generation,
      action: action,
      value: value,
      dataScope: facts.dataScope,
      bridgeAuthorityActive: bridgeAuthorityActive,
      installedHomepageId: this.settings.mode === 'custom_html' ? this.settings.selectedItemId : '',
      shortcuts: facts.shortcuts
    });
    if (response.length > 0 && bridgeAuthorityActive && this.isContentMutatingBridgeAction(action)) {
      this.shellHost.notifyContentChanged();
    }
    return response;
  }

  // A homepage customizes itself by writing storage and reordering/removing its own
  // shortcuts; these are the actions whose result changes what the homepage looks
  // like, so the persisted cover must be refreshed after them. Read-only and
  // native-to-web sync actions are excluded to avoid capturing on every request.
  private isContentMutatingBridgeAction(rawAction: string): boolean {
    switch (rawAction.trim().toLowerCase()) {
      case 'storageset':
      case 'storageremove':
      case 'storageclear':
      case 'reordershortcuts':
      case 'removeshortcut':
      case 'deleteshortcut':
      case 'confirmdeleteshortcut':
      case 'moveshortcutup':
      case 'moveshortcutdown':
      case 'moveshortcuttotop':
      case 'moveshortcuttobottom':
        return true;
      default:
        return false;
    }
  }

  private handleAiraUrl(url: string): boolean {
    const request = this.bridgeService.parseAiraUrl(url);
    if (request === undefined) {
      return false;
    }
    return this.handleBridgeRequest(
      this.committedGeneration,
      request.action,
      request.value
    ).length > 0;
  }

  private openUrl(url: string): void {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return;
    }
    const scheme = this.dependencies.webRuntimeBridge.getUrlScheme(normalizedUrl);
    if (scheme === 'aira' && this.handleAiraUrl(normalizedUrl)) {
      return;
    }
    if (scheme === 'http' || scheme === 'https' || scheme === 'file' || scheme === 'data' || scheme === 'about') {
      this.dependencies.appUrlOpenCoordinator.openCurrentAppUi(
        normalizedUrl,
        '正在从主页打开链接',
        this.shellHost.resolveFacts().createOptions
      );
      return;
    }
    this.executeShellEffect({ type: 'show_message', message: '暂不支持从主页打开此链接。' });
  }

  private executeBridgeShellAction(action: CustomHomepageBridgeShellAction): void {
    switch (action.type) {
      case 'apply_search_engine_snapshot':
        this.executeShellEffect({ type: 'apply_search_engine_snapshot', snapshot: action.snapshot });
        return;
      case 'execute_script':
        this.executeScript(action.documentGeneration, action.script, 'sync custom homepage bridge state');
        return;
      case 'open_tabs_overview':
        this.dependencies.routeCoordinator.openHomeSystemEntry('tabs');
        return;
      case 'open_search':
        this.executeShellEffect({ type: 'open_search', documentGeneration: action.documentGeneration });
        return;
      case 'open_toolbar':
        if (!this.authorizeActiveDocumentEvent(action.documentGeneration, 'openToolbar')) {
          return;
        }
        this.executeShellEffect({ type: 'open_toolbar', documentGeneration: action.documentGeneration });
        return;
      case 'open_novel_bookshelf':
        if (!this.authorizeActiveDocumentEvent(action.documentGeneration, 'openNovelBookshelf')) {
          return;
        }
        this.executeShellEffect({ type: 'open_novel_bookshelf', documentGeneration: action.documentGeneration });
        return;
      case 'toggle_private_mode':
        if (!this.authorizeActiveDocumentEvent(action.documentGeneration, 'togglePrivateMode')) {
          return;
        }
        this.executeShellEffect({ type: 'toggle_private_mode', documentGeneration: action.documentGeneration });
        return;
      case 'scan_qr':
        this.executeShellEffect({ type: 'scan_qr' });
        return;
      case 'sync_theme':
        this.syncBridge('theme', action.documentGeneration);
        return;
      case 'sync_privacy':
        this.syncBridge('privacy', action.documentGeneration);
        return;
      case 'set_back_handler_active':
        this.setTransientBackHandlerActive(action.active);
        this.publishShellState();
        return;
      case 'open_url':
        this.openUrl(action.url);
        return;
      case 'submit_search':
        void this.dependencies.addressSubmissionCoordinator.submitAddress(
          action.rawInput,
          action.searchEngineId,
          action.routingMode,
          900
        );
        return;
      case 'sync_shortcuts':
        this.syncBridge('shortcuts', action.documentGeneration);
        return;
      case 'open_shortcut_picker':
        this.dependencies.shortcutStateCoordinator.openSelectionSession();
        return;
      case 'show_message':
        this.executeShellEffect({ type: 'show_message', message: action.message });
        return;
    }
  }

  private bindSettingsUpdates(): void {
    if (this.settingsListenerKey.length > 0) {
      return;
    }
    this.settingsListenerKey = this.repository.subscribe((): void => {
      this.refresh(false);
    });
  }

  private unbindSettingsUpdates(): void {
    if (this.settingsListenerKey.length <= 0) {
      return;
    }
    this.repository.unsubscribe(this.settingsListenerKey);
    this.settingsListenerKey = '';
  }

  private publishShellState(): void {
    this.shellHost.publishState(this.getShellState());
  }

  private executeShellEffect(effect: CustomHomepageRuntimeShellEffect): void {
    this.shellHost.executeEffect(effect);
  }

  private bindHostedWebGeneration(runtime: CustomHomepageHostedWebGeneration): CustomHomepageRuntimeTransition {
    const generation = runtime.getGeneration();
    if (generation <= 0 || generation !== this.desiredGeneration) {
      runtime.dispose();
      this.recordContractViolation('stale_generation_materialized', `${generation}:${this.desiredGeneration}`);
      return this.buildTransition([]);
    }
    if (this.isHostedGeneration(generation)) {
      runtime.dispose();
      this.recordContractViolation('duplicate_generation_materialized', `${generation}`);
      return this.buildTransition([]);
    }
    this.releaseHostedWebGeneration();
    this.hostedWebGeneration = runtime;
    this.hostedNodeRevision += 1;
    const hostedWebNode = runtime.getNodeController();
    if (this.shouldAttachHostedSurfaceDuringStaging() && hostedWebNode.attachSurface() !== true) {
      this.recordContractViolation('prepared_surface_attach_failed', `${generation}`);
      this.markLoadFailure(this.desiredUrl, '主页渲染失败，请重试。');
      this.releaseHostedWebGeneration();
      return this.buildTransition([]);
    }
    this.controllerAttached = runtime.getNodeController().isWebControllerAttached();
    this.syncHostedActivity();
    const effects: CustomHomepageRuntimeEffect[] = [];
    if (this.shouldLoadDesiredDocument(this.runtimeAllowed, this.shouldRenderCustomHtml)) {
      effects.push(...this.startDesiredDocumentLoad(generation));
    }
    return this.buildTransition(effects);
  }

  getHostedWebNodeController(): CustomHomepageHostedWebNodeController | undefined {
    return this.hostedWebGeneration?.getNodeController();
  }

  /**
   * The controller of the currently committed document, for callers that need a
   * Web-level snapshot (`webPageSnapshot`). Component snapshot of a Surface that
   * only wraps a NodeContainer does not reliably include Web pixels, so the
   * cold-start cover must be captured through the controller itself. Returns
   * undefined unless the current document is committed and active.
   */
  getCommittedWebController(): webview.WebviewController | undefined {
    if (!this.documentCommitted || this.committedGeneration <= 0 || this.activityState !== 'active') {
      return undefined;
    }
    return this.resolveHostedWebController(this.committedGeneration);
  }

  /**
   * Component id of the committed Web node, for `webPageSnapshot`.
   *
   * `webPageSnapshot` targets the id set on the Web component itself. The page
   * also puts a container id on the wrapping Stack, and passing that container id
   * made every capture fail with 17100001 — so the cold-start cover never
   * refreshed and stayed a stale frame, which showed up as a content flash at the
   * handoff. The id must match `buildHostedWebConfig` exactly, generation suffix
   * included.
   */
  getCommittedWebComponentSnapshotId(): string {
    if (!this.documentCommitted || this.committedGeneration <= 0) {
      return '';
    }
    return `${buildBrowserTabWebComponentSnapshotId(CUSTOM_HOMEPAGE_PREVIEW_TAB_ID)}-${this.committedGeneration}`;
  }

  private executeScript(generation: number, script: string, action: string): void {
    try {
      const execution = this.resolveHostedWebController(generation)?.runJavaScript(script);
      if (execution === undefined) {
        return;
      }
      void execution.catch((error: Error): void => {
        hilog.warn(
          CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
          CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
          '%{public}s failed: %{public}s',
          action,
          error.message
        );
      });
    } catch (error) {
      hilog.warn(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        '%{public}s threw: %{public}s',
        action,
        JSON.stringify(error)
      );
    }
  }

  private resolveHostedWebController(generation: number): webview.WebviewController | undefined {
    const runtime = this.hostedWebGeneration;
    const normalizedGeneration = Math.max(0, Math.floor(generation));
    if (runtime === undefined || runtime.getGeneration() !== normalizedGeneration) {
      return undefined;
    }
    return runtime.getController();
  }

  private authorizeBridgeRequest(generation: number, action: string): boolean {
    const normalizedGeneration = Math.max(0, Math.floor(generation));
    if (this.bridgeAuthorityActive &&
      normalizedGeneration === this.committedGeneration &&
      normalizedGeneration === this.desiredGeneration) {
      return true;
    }
    const normalizedAction = action.trim().toLowerCase();
    if (this.activityState === 'staging' &&
      normalizedGeneration === this.activeGeneration &&
      normalizedGeneration === this.desiredGeneration &&
      this.isStagingBootstrapBridgeAction(normalizedAction)) {
      return true;
    }
    this.recordContractViolation(
      'invalid_bridge_authority',
      `${normalizedAction}:${normalizedGeneration}:${this.committedGeneration}`
    );
    return false;
  }

  authorizeActiveDocumentEvent(generation: number, eventName: string): boolean {
    const normalizedGeneration = Math.max(0, Math.floor(generation));
    if (!this.isHostedGeneration(normalizedGeneration) ||
      normalizedGeneration !== this.desiredGeneration) {
      this.recordContractViolation(
        'stale_generation_interaction',
        `${eventName}:${normalizedGeneration}:${this.desiredGeneration}`
      );
      return false;
    }
    return this.bridgeAuthorityActive &&
      this.documentCommitted &&
      normalizedGeneration === this.committedGeneration;
  }

  private handlePresentationRefresh(input: CustomHomepageRuntimeRefreshInput): CustomHomepageRuntimeTransition {
    this.homeVisible = input.homeVisible;
    this.runtimeAllowed = input.runtimeAllowed;
    this.shouldRenderCustomHtml = input.shouldRenderCustomHtml;
    this.updateDesiredDocument(input.shouldRenderCustomHtml, input.webUrl, input.renderKey, input.renderKeyChanged,
      input.forceReload);
    if (!input.homeVisible || !input.runtimeAllowed || !input.shouldRenderCustomHtml) {
      this.transientBackHandlerActive = false;
    }
    const normalizedFailureUrl = this.stripFragmentAndQuery(this.loadFailureState.url);
    if (normalizedFailureUrl.length > 0 &&
      (!input.shouldRenderCustomHtml || normalizedFailureUrl !== this.stripFragmentAndQuery(input.webUrl))) {
      this.clearLoadFailure();
    }
    if (!input.runtimeAllowed) {
      this.invalidateUnavailableHostedGeneration();
    } else if (!input.shouldRenderCustomHtml) {
      this.releaseHostedWebGeneration();
    }
    const shouldMaterializeDocument = this.shouldMaterializeDesiredDocument(
      input.runtimeAllowed,
      input.shouldRenderCustomHtml
    );
    const shouldLoadDocument = this.shouldLoadDesiredDocument(input.runtimeAllowed, input.shouldRenderCustomHtml);
    this.syncHostedActivity();
    const effects: CustomHomepageRuntimeEffect[] = [];
    if (!input.runtimeAllowed || !input.shouldRenderCustomHtml) {
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
    } else if (shouldMaterializeDocument) {
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
      effects.push(this.buildGenerationEffect('materialize_document', this.desiredGeneration));
    } else if (shouldLoadDocument) {
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
      effects.push(...this.startDesiredDocumentLoad(this.desiredGeneration));
    } else if (this.shouldSyncReadyDocument(input.homeVisible, input.runtimeAllowed,
      input.shouldRenderCustomHtml, shouldLoadDocument)) {
      effects.push(this.buildGenerationEffect('sync_bridge', this.committedGeneration));
    }
    return this.buildTransition(effects);
  }

  private handleControllerAttached(
    input: CustomHomepageRuntimeControllerAttachedInput
  ): CustomHomepageRuntimeTransition {
    if (!this.isHostedGeneration(input.generation)) {
      this.recordContractViolation(
        'stale_controller_attached',
        `${input.generation}:${this.desiredGeneration}`
      );
      return this.buildTransition([]);
    }
    this.controllerAttached = true;
    const shouldLoadDocument = this.shouldLoadDesiredDocument(this.runtimeAllowed, this.shouldRenderCustomHtml);
    this.syncHostedActivity();
    const effects: CustomHomepageRuntimeEffect[] = [];
    if (!this.runtimeAllowed || !this.shouldRenderCustomHtml) {
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
    } else if (shouldLoadDocument) {
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
      effects.push(...this.startDesiredDocumentLoad(input.generation));
    } else if (this.shouldSyncReadyDocument(this.homeVisible, this.runtimeAllowed,
      this.shouldRenderCustomHtml, shouldLoadDocument)) {
      effects.push(this.buildGenerationEffect('sync_bridge', this.committedGeneration));
    }
    return this.buildTransition(effects);
  }

  private handleLoadTimeout(request: CustomHomepageRuntimeTimeoutRequest): CustomHomepageRuntimeTransition {
    if (request.generation !== this.loadGeneration ||
      request.documentGeneration !== this.desiredGeneration ||
      !this.isHostedGeneration(request.documentGeneration)) {
      return this.buildTransition([]);
    }
    if (!this.homeVisible || !this.shouldRenderCustomHtml || this.loadFailureState.visible ||
      this.failedUrl.trim().length > 0 ||
      this.stripFragmentAndQuery(this.loadingUrl) !== this.stripFragmentAndQuery(request.url)) {
      return this.buildTransition([]);
    }
    const normalizedUrl = request.url.trim();
    this.failedUrl = normalizedUrl;
    const message = this.networkAvailabilityService.shouldFastFailNavigation(normalizedUrl)
      ? this.networkAvailabilityService.buildOfflineMessage()
      : '加载失败：主页长时间没有响应。';
    this.markLoadFailure(normalizedUrl, message);
    this.cancelLoadTimeout();
    return this.buildTransition([this.buildCancelTimeoutEffect()]);
  }

  private handlePageBegin(input: CustomHomepageRuntimePageBeginInput): CustomHomepageRuntimeTransition {
    const pageUrl = input.url.trim();
    if (!this.isCurrentGeneration(input.generation, 'page_begin') ||
      !this.isDesiredDocumentUrl(pageUrl)) {
      return this.buildTransition([]);
    }
    this.transientBackHandlerActive = false;
    this.loadingUrl = pageUrl;
    this.failedUrl = '';
    if (this.stripFragmentAndQuery(this.loadFailureState.url).length > 0 &&
      this.stripFragmentAndQuery(this.loadFailureState.url) === this.stripFragmentAndQuery(pageUrl)) {
      this.clearLoadFailure();
    }
    return this.buildTransition([]);
  }

  private handlePageEnd(input: CustomHomepageRuntimePageEndInput): CustomHomepageRuntimeTransition {
    const pageUrl = input.url.trim();
    if (!this.isCurrentGeneration(input.generation, 'page_end') ||
      !this.isDesiredDocumentUrl(pageUrl)) {
      return this.buildTransition([]);
    }
    if (this.loadFailureState.visible || this.failedUrl.length > 0) {
      return this.buildTransition([]);
    }
    const wasCommitted = this.documentCommitted && this.committedGeneration === input.generation;
    const effects: CustomHomepageRuntimeEffect[] = this.acceptNativeDocumentReadiness(
      'page_end',
      input.generation
    );
    if (wasCommitted) {
      effects.push(this.buildGenerationEffect('sync_bridge', input.generation));
    }
    return this.buildTransition(effects);
  }

  private handleLoadFinished(signal: CustomHomepageHostedWebDocumentSignal): CustomHomepageRuntimeTransition {
    if (!this.isCurrentGeneration(signal.generation, signal.kind)) {
      return this.buildTransition([]);
    }
    // `onLoadFinished` means the document and its subresources have finished. Do
    // not release the cold-start cover yet: many homepages ship a light default
    // body background and only apply their dark theme a moment later, so reveal
    // is gated on the page background actually matching the current theme.
    if (!this.loadFailureState.visible && this.failedUrl.length <= 0) {
      this.beginDocumentSettleProbe(Math.max(0, Math.floor(signal.generation)));
    }
    return this.buildTransition(this.acceptNativeDocumentReadiness(
      signal.kind,
      signal.generation
    ));
  }

  // Reads the page's effective canvas background and returns whether it reads as
  // dark or light, so the reveal gate can wait out a not-yet-themed (white) page.
  private beginDocumentSettleProbe(generation: number): void {
    this.cancelDocumentSettleProbe();
    this.documentSettleProbeGeneration = generation;
    this.documentSettleProbeAttempts = 0;
    this.documentSettleProbeLastSample = '';
    this.documentSettleProbeStableMatches = 0;
    this.runDocumentSettleProbe();
  }

  private runDocumentSettleProbe(): void {
    const generation = this.documentSettleProbeGeneration;
    if (generation <= 0 || !this.documentCommitted || this.committedGeneration !== generation) {
      return;
    }
    const controller = this.resolveHostedWebController(generation);
    if (controller === undefined) {
      this.completeDocumentSettle(generation, 'no-controller');
      return;
    }
    let execution: Promise<string> | undefined = undefined;
    try {
      execution = controller.runJavaScript(CUSTOM_HOMEPAGE_SETTLE_PROBE_SCRIPT);
    } catch (_error) {
      this.completeDocumentSettle(generation, 'probe-threw');
      return;
    }
    if (execution === undefined) {
      this.completeDocumentSettle(generation, 'no-execution');
      return;
    }
    void execution.then((value: string): void => {
      if (this.documentSettleProbeGeneration !== generation) {
        return;
      }
      const sampled = this.normalizeProbeResult(value);
      // A single confident read is not proof the page has painted: the render
      // process can report a themed, image-complete document a frame or two before
      // those pixels reach the screen. Require the same confident answer twice in a
      // row so the reveal waits out that compositor lag instead of exposing a page
      // that is themed in JS but still blank on screen.
      if (sampled === this.documentSettleProbeLastSample &&
        (sampled === this.presentationThemeMode || sampled === 'unknown')) {
        this.documentSettleProbeStableMatches += 1;
      } else {
        this.documentSettleProbeStableMatches =
          (sampled === this.presentationThemeMode || sampled === 'unknown') ? 1 : 0;
      }
      this.documentSettleProbeLastSample = sampled;
      if (this.documentSettleProbeStableMatches >= CUSTOM_HOMEPAGE_SETTLE_PROBE_STABLE_READS) {
        this.completeDocumentSettle(generation, `matched-${sampled}`);
        return;
      }
      this.documentSettleProbeAttempts += 1;
      if (this.documentSettleProbeAttempts >= CUSTOM_HOMEPAGE_SETTLE_PROBE_MAX_ATTEMPTS) {
        this.completeDocumentSettle(generation, `timeout-${sampled}`);
        return;
      }
      this.documentSettleProbeTimer = setTimeout((): void => {
        this.documentSettleProbeTimer = -1;
        this.runDocumentSettleProbe();
      }, CUSTOM_HOMEPAGE_SETTLE_PROBE_INTERVAL_MS);
    }).catch((): void => {
      if (this.documentSettleProbeGeneration === generation) {
        this.completeDocumentSettle(generation, 'probe-failed');
      }
    });
  }

  // ArkWeb returns the script result JSON-encoded, so a JS string arrives with
  // surrounding quotes (`"dark"`). Normalizing here keeps the theme comparison
  // exact instead of always missing and burning the retry budget.
  private normalizeProbeResult(value: string): string {
    const trimmed = String(value).trim();
    if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  private completeDocumentSettle(generation: number, reason: string): void {
    if (!this.documentCommitted || this.committedGeneration !== generation) {
      return;
    }
    this.cancelDocumentSettleProbe();
    this.settledGeneration = generation;
    hilog.info(CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN, CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
      'document_settled generation=%{public}d reason=%{public}s', generation, reason);
    this.publishShellState();
  }

  private cancelDocumentSettleProbe(): void {
    if (this.documentSettleProbeTimer >= 0) {
      clearTimeout(this.documentSettleProbeTimer);
      this.documentSettleProbeTimer = -1;
    }
    this.documentSettleProbeAttempts = 0;
    this.documentSettleProbeLastSample = '';
    this.documentSettleProbeStableMatches = 0;
    this.documentSettleProbeGeneration = 0;
  }

  private handleFirstMeaningfulPaint(signal: CustomHomepageHostedWebDocumentSignal): CustomHomepageRuntimeTransition {
    if (!this.isCurrentGeneration(signal.generation, signal.kind) ||
      this.loadFailureState.visible || this.failedUrl.length > 0) {
      return this.buildTransition([]);
    }
    // Deliberately NOT a settle signal. A homepage can paint its first frame
    // before its theme/JS initialization finishes, so lifting the cold-start cover
    // on first paint revealed a briefly light page (the dark-mode flash). Only
    // `loadFinished`, after subresources, releases the cover.
    return this.buildTransition(this.acceptNativeDocumentReadiness(
      signal.kind,
      signal.generation
    ));
  }

  private handleVisibilityChanged(input: CustomHomepageRuntimeVisibilityInput): CustomHomepageRuntimeTransition {
    this.homeVisible = input.homeVisible;
    this.runtimeAllowed = input.runtimeAllowed;
    this.shouldRenderCustomHtml = input.shouldRenderCustomHtml;
    if (!this.homeVisible || !this.runtimeAllowed || !this.shouldRenderCustomHtml) {
      this.transientBackHandlerActive = false;
    }
    const effects: CustomHomepageRuntimeEffect[] = [];
    if (!this.runtimeAllowed || !this.shouldRenderCustomHtml) {
      if (!this.runtimeAllowed) {
        this.invalidateUnavailableHostedGeneration();
      }
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
    }
    this.syncHostedActivity();
    return this.buildTransition(effects);
  }

  private handleError(input: CustomHomepageRuntimeErrorInput): CustomHomepageRuntimeTransition {
    const requestUrl = input.requestUrl.trim();
    if (!this.isCurrentGeneration(input.generation, 'error_receive') ||
      !input.isMainFrame ||
      !this.isDesiredDocumentUrl(requestUrl) ||
      this.failedUrl === requestUrl ||
      !this.isLoadingUrl(requestUrl)) {
      return this.buildTransition([]);
    }
    this.markLoadFailure(requestUrl, input.errorMessage);
    this.cancelLoadTimeout();
    return this.buildTransition([this.buildCancelTimeoutEffect()]);
  }

  private buildFailureActionTransition(action: CustomHomepageFailureAction): CustomHomepageRuntimeTransition {
    const effects: CustomHomepageRuntimeEffect[] = [];
    if (action === 'retry') {
      effects.push(this.buildShowToastEffect('正在重新加载主页'));
      this.desiredGeneration += 1;
      this.releaseHostedWebGeneration();
      this.clearLoadFailure();
      this.loadingUrl = '';
      this.failedUrl = '';
      this.activeRenderKey = '';
      this.activeGeneration = 0;
      this.invalidateCommittedDocument();
      this.cancelLoadTimeout();
      effects.push(this.buildCancelTimeoutEffect());
      effects.push(this.buildRefreshPresentationEffect());
    }
    if (action === 'edit_homepage') {
      effects.push(this.buildOpenHomepageSettingsEffect());
    }
    return this.buildTransition(effects);
  }

  private handleNavigationRequest(input: CustomHomepageRuntimeNavigationInput): CustomHomepageRuntimeNavigationPlan {
    const normalizedUrl = input.url.trim();
    if (!this.isHostedGeneration(input.generation) ||
      input.generation !== this.activeGeneration ||
      input.generation !== this.desiredGeneration) {
      this.recordContractViolation(
        'stale_navigation_event',
        `${input.generation}:${this.desiredGeneration}:${this.activeGeneration}`
      );
      return {
        shouldIntercept: true
      };
    }
    if (normalizedUrl.length === 0 || this.isDesiredDocumentUrl(normalizedUrl) || !input.isMainFrame) {
      return {
        shouldIntercept: false
      };
    }
    if (input.isRemoteUrlHomepage && !input.isRequestGesture && input.isHttpOrHttpsUrl) {
      const transition = this.beginRedirectGeneration(normalizedUrl);
      return {
        shouldIntercept: true,
        transition: transition
      };
    }
    if (!this.bridgeAuthorityActive) {
      return {
        shouldIntercept: true
      };
    }
    return {
      shouldIntercept: true,
      transition: this.buildTransition([this.buildOpenUrlEffect(normalizedUrl)])
    };
  }

  private setTransientBackHandlerActive(active: boolean): void {
    this.transientBackHandlerActive = active && this.isSurfaceVisible();
  }

  private shouldRenderCustomHomepage(): boolean {
    return this.runtimeAllowed && this.shouldRenderCustomHtml;
  }

  private isMotionBridgeAllowed(): boolean {
    if (this.settings.mode !== 'custom_html' || this.settings.selectedItemId.length <= 0) {
      return false;
    }
    const selectedItem = this.settings.items.find((item): boolean => item.id === this.settings.selectedItemId);
    return selectedItem?.kind === 'zip_package';
  }

  private buildPublishedMotionState(): CustomHomepageMotionState {
    const allowed = this.isMotionBridgeAllowed();
    return {
      allowed: allowed,
      holdingHandStatus: allowed ? this.holdingHandStatus : UNKNOWN_CUSTOM_HOMEPAGE_HOLDING_HAND_STATUS
    };
  }

  private resolvePublishedHoldingHandStatus(): CustomHomepageHoldingHandStatus {
    return this.isMotionBridgeAllowed() ?
      this.holdingHandStatus : UNKNOWN_CUSTOM_HOMEPAGE_HOLDING_HAND_STATUS;
  }

  private resolveHoldingHandStatus(state: BrowserSmartGripState): CustomHomepageHoldingHandStatus {
    if (!state.enabled || !state.supported) {
      return UNKNOWN_CUSTOM_HOMEPAGE_HOLDING_HAND_STATUS;
    }
    if (state.hand === 'not_held') {
      return 0;
    }
    if (state.hand === 'left') {
      return 1;
    }
    if (state.hand === 'right') {
      return 2;
    }
    if (state.hand === 'both') {
      return 3;
    }
    return UNKNOWN_CUSTOM_HOMEPAGE_HOLDING_HAND_STATUS;
  }

  private isSurfaceVisible(): boolean {
    return this.shouldRenderCustomHomepage() &&
      this.documentCommitted &&
      !this.loadFailureState.visible;
  }

  dispatchTransientBack(): boolean {
    if (!this.transientBackHandlerActive) {
      return false;
    }
    this.transientBackHandlerActive = false;
    this.publishShellState();
    try {
      const controller = this.resolveHostedWebController(this.committedGeneration);
      if (!this.documentCommitted || this.committedGeneration <= 0 || controller === undefined) {
        return false;
      }
      const execution = controller.runJavaScript(this.bridgeService.buildBackRequestScript());
      void execution.catch((error: Error): void => {
        this.setTransientBackHandlerActive(true);
        this.publishShellState();
        hilog.warn(
          CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
          CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
          'dispatch custom homepage back failed: %{public}s',
          error.message
        );
      });
    } catch (error) {
      this.setTransientBackHandlerActive(true);
      this.publishShellState();
      hilog.warn(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        'dispatch custom homepage back threw: %{public}s',
        JSON.stringify(error)
      );
    }
    return true;
  }

  private startDesiredDocumentLoad(generation: number): CustomHomepageRuntimeEffect[] {
    const url = this.desiredUrl.trim();
    const renderKey = this.desiredRenderKey.trim();
    if (url.length <= 0 || renderKey.length <= 0 ||
      !this.isHostedGeneration(generation) || !this.controllerAttached ||
      generation !== this.desiredGeneration) {
      this.recordContractViolation(
        'load_without_current_generation',
        `${generation}:${this.desiredGeneration}:${this.controllerAttached}`
      );
      this.cancelLoadTimeout();
      return [this.buildCancelTimeoutEffect()];
    }
    this.transientBackHandlerActive = false;
    this.activeRenderKey = renderKey;
    this.activeGeneration = generation;
    this.invalidateCommittedDocument();
    this.syncHostedActivity();
    if (this.networkAvailabilityService.shouldFastFailNavigation(url)) {
      this.loadingUrl = url;
      const errorMessage = this.networkAvailabilityService.buildOfflineMessage();
      this.markLoadFailure(url, errorMessage);
      this.cancelLoadTimeout();
      return [this.buildCancelTimeoutEffect()];
    }
    this.loadingUrl = url;
    this.failedUrl = '';
    const controller = this.resolveHostedWebController(generation);
    if (controller === undefined) {
      this.cancelLoadTimeout();
      return [this.buildCancelTimeoutEffect()];
    }
    try {
      this.diagnosticLoadStartedAt = Date.now();
      hilog.info(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        '[DEBUG-FAVICON-COLDSTART] web_load_start generation=%{public}d remoteHomepage=%{public}s',
        generation,
        `${this.presentationState.isRemoteUrlHomepage}`
      );
      hilog.info(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        'load custom homepage url=%{public}s',
        url
      );
      controller.loadUrl(url);
      return [this.buildScheduleTimeoutEffect(this.buildTimeoutRequest(url))];
    } catch (error) {
      hilog.warn(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        'load custom homepage failed: %{public}s',
        JSON.stringify(error)
      );
      this.cancelLoadTimeout();
      this.markLoadFailure(url, JSON.stringify(error));
      return [this.buildCancelTimeoutEffect()];
    }
  }

  private isDesiredDocumentUrl(url: string): boolean {
    const normalizedUrl = url.trim();
    return normalizedUrl.length > 0 && this.desiredUrl.length > 0 &&
      this.stripFragmentAndQuery(normalizedUrl) === this.stripFragmentAndQuery(this.desiredUrl);
  }

  private buildTimeoutRequest(url: string): CustomHomepageRuntimeTimeoutRequest {
    this.loadingUrl = url.trim();
    this.cancelLoadTimeout();
    this.loadGeneration += 1;
    return {
      generation: this.loadGeneration,
      documentGeneration: this.activeGeneration,
      url: this.loadingUrl
    };
  }

  private cancelLoadTimeout(): void {
    this.loadGeneration += 1;
    this.cancelDocumentSettleFallback();
  }

  private beginRedirectGeneration(url: string): CustomHomepageRuntimeTransition {
    this.desiredGeneration += 1;
    this.desiredUrl = url.trim();
    this.transientBackHandlerActive = false;
    this.activeGeneration = 0;
    this.activeRenderKey = '';
    this.loadingUrl = '';
    this.failedUrl = '';
    this.clearLoadFailure();
    this.invalidateCommittedDocument();
    this.releaseHostedWebGeneration();
    this.cancelLoadTimeout();
    return this.buildTransition([
      this.buildCancelTimeoutEffect(),
      this.buildGenerationEffect('materialize_document', this.desiredGeneration)
    ]);
  }

  private buildTransition(effects: CustomHomepageRuntimeEffect[]): CustomHomepageRuntimeTransition {
    return {
      effects: effects
    };
  }

  private buildCancelTimeoutEffect(): CustomHomepageRuntimeCancelTimeoutEffect {
    return {
      type: 'cancel_timeout'
    };
  }

  private buildGenerationEffect(
    type: 'materialize_document' | 'sync_bridge',
    generation: number
  ): CustomHomepageRuntimeMaterializeEffect | CustomHomepageRuntimeSyncBridgeEffect {
    return {
      type: type,
      generation: Math.max(0, Math.floor(generation))
    };
  }

  private buildScheduleTimeoutEffect(
    request: CustomHomepageRuntimeTimeoutRequest
  ): CustomHomepageRuntimeScheduleTimeoutEffect {
    return {
      type: 'schedule_timeout',
      request: request,
      delayMs: CUSTOM_HOMEPAGE_LOAD_TIMEOUT_MS
    };
  }

  private buildShowToastEffect(message: string): CustomHomepageRuntimeShowToastEffect {
    return {
      type: 'show_toast',
      message: message.trim()
    };
  }

  private buildRefreshPresentationEffect(): CustomHomepageRuntimeRefreshPresentationEffect {
    return {
      type: 'refresh_presentation'
    };
  }

  private buildOpenHomepageSettingsEffect(): CustomHomepageRuntimeOpenHomepageSettingsEffect {
    return {
      type: 'open_homepage_settings'
    };
  }

  private buildOpenUrlEffect(url: string): CustomHomepageRuntimeOpenUrlEffect {
    return {
      type: 'open_url',
      url: url.trim()
    };
  }

  private markLoadFailure(url: string, errorMessage: string): void {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length <= 0) {
      return;
    }
    this.loadFailureState = {
      visible: true,
      url: normalizedUrl,
      presentation: this.loadErrorPresentationService.build({
        url: normalizedUrl,
        pendingUrl: normalizedUrl,
        title: '',
        errorMessage: errorMessage.trim(),
        runtimeDegradedMessage: '',
        crashed: false,
        context: 'custom_homepage'
      })
    };
    this.failedUrl = normalizedUrl;
    this.invalidateCommittedDocument();
    this.syncHostedActivity();
  }

  private clearLoadFailure(): void {
    if (!this.loadFailureState.visible) {
      return;
    }
    this.loadFailureState = HIDDEN_CUSTOM_HOMEPAGE_LOAD_FAILURE_STATE;
  }

  private isLoadingUrl(url: string): boolean {
    return this.stripFragmentAndQuery(url) === this.stripFragmentAndQuery(this.loadingUrl);
  }

  private updateDesiredDocument(
    shouldRenderCustomHtml: boolean,
    webUrl: string,
    renderKey: string,
    renderKeyChanged: boolean,
    forceReload: boolean
  ): void {
    if (!shouldRenderCustomHtml || webUrl.trim().length <= 0) {
      if (this.desiredRenderKey.length > 0 || this.activeRenderKey.length > 0 || this.documentCommitted) {
        this.desiredGeneration += 1;
      }
      this.desiredUrl = '';
      this.desiredRenderKey = '';
      this.activeRenderKey = '';
      this.activeGeneration = 0;
      this.invalidateCommittedDocument();
      this.releaseHostedWebGeneration();
      return;
    }
    const normalizedWebUrl = webUrl.trim();
    const normalizedRenderKey = renderKey.trim();
    const shouldCreateGeneration = forceReload || this.desiredRenderKey !== normalizedRenderKey;
    if (shouldCreateGeneration) {
      this.desiredGeneration += 1;
      this.desiredUrl = normalizedWebUrl;
      this.desiredRenderKey = normalizedRenderKey;
      this.activeRenderKey = '';
      this.activeGeneration = 0;
      this.invalidateCommittedDocument();
      this.releaseHostedWebGeneration();
      return;
    }
    if (this.desiredUrl.length <= 0) {
      this.desiredUrl = normalizedWebUrl;
    }
    if (renderKeyChanged && this.desiredRenderKey === normalizedRenderKey) {
      this.recordContractViolation('render_key_change_without_generation', normalizedRenderKey);
    }
  }

  private shouldLoadDesiredDocument(runtimeAllowed: boolean, shouldRenderCustomHtml: boolean): boolean {
    return runtimeAllowed &&
      shouldRenderCustomHtml &&
      this.controllerAttached &&
      this.desiredRenderKey.length > 0 &&
      this.activeRenderKey !== this.desiredRenderKey;
  }

  private shouldMaterializeDesiredDocument(
    runtimeAllowed: boolean,
    shouldRenderCustomHtml: boolean
  ): boolean {
    return runtimeAllowed &&
      shouldRenderCustomHtml &&
      this.desiredGeneration > 0 &&
      this.desiredRenderKey.length > 0 &&
      !this.isHostedGeneration(this.desiredGeneration);
  }

  private shouldSyncReadyDocument(
    homeVisible: boolean,
    runtimeAllowed: boolean,
    shouldRenderCustomHtml: boolean,
    shouldLoadDocument: boolean
  ): boolean {
    return homeVisible &&
      runtimeAllowed &&
      shouldRenderCustomHtml &&
      this.controllerAttached &&
      !shouldLoadDocument &&
      this.documentCommitted &&
      this.activeRenderKey.length > 0 &&
      this.activeRenderKey === this.desiredRenderKey;
  }

  private invalidateCommittedDocument(): void {
    this.documentCommitted = false;
    this.committedGeneration = 0;
    this.settledGeneration = 0;
    this.bridgeAuthorityActive = false;
    const hostedWebNode = this.hostedWebGeneration?.getNodeController();
    hostedWebNode?.setInteractionAllowed(false);
    if (this.presentationState.isRemoteUrlHomepage) {
      hostedWebNode?.detachSurface();
    }
  }

  private isHostedGeneration(generation: number): boolean {
    const runtime = this.hostedWebGeneration;
    return runtime !== undefined &&
      runtime.getGeneration() === Math.max(0, Math.floor(generation));
  }

  private releaseHostedWebGeneration(): void {
    this.cancelDocumentSettleFallback();
    this.cancelDocumentSettleProbe();
    const runtime = this.hostedWebGeneration;
    if (runtime === undefined) {
      this.controllerAttached = false;
      return;
    }
    runtime.getNodeController().setInteractionAllowed(false);
    runtime.dispose();
    this.hostedWebGeneration = undefined;
    this.hostedNodeRevision += 1;
    this.controllerAttached = false;
    this.bridgeAuthorityActive = false;
    this.activityState = 'unbound';
  }

  private invalidateUnavailableHostedGeneration(): void {
    if (this.hostedWebGeneration === undefined) {
      return;
    }
    this.desiredGeneration += 1;
    this.activeGeneration = 0;
    this.activeRenderKey = '';
    this.invalidateCommittedDocument();
    this.releaseHostedWebGeneration();
  }

  private acceptNativeDocumentReadiness(
    reason: string,
    generation: number
  ): CustomHomepageRuntimeEffect[] {
    if (this.loadFailureState.visible || this.failedUrl.length > 0) {
      return [];
    }
    const wasCommitted = this.documentCommitted;
    this.loadingUrl = '';
    this.failedUrl = '';
    this.cancelLoadTimeout();
    this.clearLoadFailure();
    this.commitStagedDocument(reason, generation);
    const loadDuration = this.diagnosticLoadStartedAt > 0
      ? Date.now() - this.diagnosticLoadStartedAt
      : -1;
    this.diagnosticLoadStartedAt = 0;
    hilog.info(
      CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
      CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
      '[DEBUG-FAVICON-COLDSTART] web_ready reason=%{public}s generation=%{public}d durationMs=%{public}d',
      reason,
      generation,
      loadDuration
    );
    const effects: CustomHomepageRuntimeEffect[] = [this.buildCancelTimeoutEffect()];
    if (!wasCommitted && this.documentCommitted) {
      hilog.info(
        CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
        CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
        'document_readiness_accepted reason=%{public}s generation=%{public}d',
        reason,
        generation
      );
      effects.push(this.buildGenerationEffect('sync_bridge', generation));
    }
    return effects;
  }

  private commitStagedDocument(reason: string, generation: number): void {
    if (!this.isCurrentGeneration(generation, reason)) {
      return;
    }
    if (this.documentCommitted ||
      !this.runtimeAllowed ||
      !this.shouldRenderCustomHtml ||
      !this.controllerAttached ||
      this.loadFailureState.visible ||
      this.failedUrl.length > 0 ||
      this.activeRenderKey.length <= 0 ||
      this.activeRenderKey !== this.desiredRenderKey) {
      return;
    }
    const hostedWebNode = this.hostedWebGeneration?.getNodeController();
    if (!this.isHostedGeneration(generation) || hostedWebNode === undefined) {
      this.recordContractViolation('staged_surface_attach_failed', reason);
      this.markLoadFailure(this.desiredUrl, '主页渲染失败，请重试。');
      return;
    }
    if (!hostedWebNode.isSurfaceAttached() && hostedWebNode.attachSurface() !== true) {
      this.recordContractViolation('staged_surface_attach_failed', reason);
      this.markLoadFailure(this.desiredUrl, '主页渲染失败，请重试。');
      return;
    }
    this.documentCommitted = true;
    this.committedGeneration = generation;
    this.syncHostedActivity();
    this.scheduleDocumentSettleFallback(generation);
    this.shellHost.notifyDocumentCommitted();
  }

  // A homepage whose document never reports load completion must still release the
  // cold-start cover, or the cover would sit over the real page indefinitely.
  private scheduleDocumentSettleFallback(generation: number): void {
    this.cancelDocumentSettleFallback();
    this.documentSettleFallbackTimer = setTimeout((): void => {
      this.documentSettleFallbackTimer = -1;
      if (!this.documentCommitted || this.committedGeneration !== generation ||
        this.settledGeneration === generation) {
        return;
      }
      this.settledGeneration = generation;
      this.cancelDocumentSettleProbe();
      this.publishShellState();
    }, CUSTOM_HOMEPAGE_DOCUMENT_SETTLE_FALLBACK_MS);
  }

  private cancelDocumentSettleFallback(): void {
    if (this.documentSettleFallbackTimer < 0) {
      return;
    }
    clearTimeout(this.documentSettleFallbackTimer);
    this.documentSettleFallbackTimer = -1;
  }

  private shouldAttachHostedSurfaceDuringStaging(): boolean {
    return !this.presentationState.isRemoteUrlHomepage;
  }

  private isCurrentGeneration(generation: number, eventName: string): boolean {
    const normalizedGeneration = Math.max(0, Math.floor(generation));
    if (normalizedGeneration > 0 &&
      normalizedGeneration === this.desiredGeneration &&
      normalizedGeneration === this.activeGeneration) {
      return true;
    }
    this.recordContractViolation(
      'stale_generation_event',
      `${eventName}:${normalizedGeneration}:${this.desiredGeneration}:${this.activeGeneration}`
    );
    return false;
  }

  private isStagingBootstrapBridgeAction(action: string): boolean {
    return action === 'shortcuts' || action === 'theme' || action === 'privacy' || action === 'searchengines' ||
      action === 'storageget';
  }

  private recordContractViolation(reason: string, detail: string): void {
    hilog.error(
      CUSTOM_HOMEPAGE_RUNTIME_LOG_DOMAIN,
      CUSTOM_HOMEPAGE_RUNTIME_LOG_TAG,
      'policy_home_document_contract_violation reason=%{public}s detail=%{public}s renderKey=%{public}s',
      reason,
      detail,
      `${this.activeRenderKey}|desired=${this.desiredGeneration}|active=${this.activeGeneration}|committed=${this.committedGeneration}`
    );
  }

  private syncHostedActivity(): void {
    const hostedWebNode = this.hostedWebGeneration?.getNodeController();
    if (hostedWebNode === undefined || !this.controllerAttached) {
      this.bridgeAuthorityActive = false;
      this.activityState = 'unbound';
      return;
    }
    if (!this.runtimeAllowed || !this.shouldRenderCustomHtml) {
      hostedWebNode.deactivate();
      this.bridgeAuthorityActive = false;
      this.activityState = 'inactive_resident';
    } else if (this.loadFailureState.visible || this.failedUrl.length > 0) {
      hostedWebNode.deactivate();
      this.bridgeAuthorityActive = false;
      this.activityState = 'inactive_resident';
    } else if (!this.documentCommitted) {
      hostedWebNode.activate();
      this.bridgeAuthorityActive = false;
      this.activityState = 'staging';
    } else if (this.homeVisible) {
      hostedWebNode.activate();
      this.bridgeAuthorityActive = true;
      this.activityState = 'active';
    } else {
      hostedWebNode.deactivate();
      this.bridgeAuthorityActive = false;
      this.activityState = 'inactive_resident';
    }
    hostedWebNode.setInteractionAllowed(this.bridgeAuthorityActive);
    this.validateContractState('sync_hosted_activity');
  }

  private validateContractState(reason: string): void {
    const hostedRuntime = this.hostedWebGeneration;
    const hostedWebNode = hostedRuntime?.getNodeController();
    if (hostedRuntime !== undefined && hostedRuntime.getGeneration() !== this.desiredGeneration) {
      this.recordContractViolation('hosted_generation_mismatch', reason);
    }
    if (this.documentCommitted &&
      (this.committedGeneration <= 0 ||
        this.committedGeneration !== this.activeGeneration ||
        this.committedGeneration !== this.desiredGeneration)) {
      this.recordContractViolation('committed_generation_mismatch', reason);
    }
    if (this.bridgeAuthorityActive &&
      (!this.documentCommitted || !this.homeVisible || this.activityState !== 'active')) {
      this.recordContractViolation('invalid_active_authority', reason);
      this.bridgeAuthorityActive = false;
      hostedWebNode?.setInteractionAllowed(false);
    }
    if (!this.documentCommitted && hostedWebNode?.isSurfaceAttached() === true &&
      !this.shouldAttachHostedSurfaceDuringStaging()) {
      this.recordContractViolation('uncommitted_surface_attached', reason);
      hostedWebNode.detachSurface();
    }
    if (hostedWebNode !== undefined && hostedWebNode.isInteractionAllowed() !== this.bridgeAuthorityActive) {
      this.recordContractViolation('interaction_authority_mismatch', reason);
      hostedWebNode.setInteractionAllowed(this.bridgeAuthorityActive);
    }
  }

  private stripFragmentAndQuery(url: string): string {
    return url.trim().split('#')[0].split('?')[0];
  }
}
