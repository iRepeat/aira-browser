import {
  BrowserAppUrlOpenIntent,
  BrowserAppUrlOpenSource
} from '../browser/BrowserAppUrlOpenCoordinator';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';

export interface BrowserPendingNavigationRequest {
  url: string;
  title: string;
  intent: BrowserAppUrlOpenIntent;
  source: BrowserAppUrlOpenSource;
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  createdAt: number;
  requestId: string;
  /**
   * The route token this request was staged with, when it was delivered through both the in-memory queue
   * and the shell route params. Empty for requests that only use the in-memory queue.
   */
  routeToken?: string;
}

export interface BrowserNavigationBoundaryOptions {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

interface BrowserNormalizedNavigationBoundary {
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
}

export interface BrowserNavigationRouteParams {
  openUrl?: string;
  openTitle?: string;
  openIntent?: string;
  openSource?: string;
  openToken?: string;
  openProfileId?: string;
  openPrivacyMode?: string;
  openDataScope?: string;
}

export interface BrowserRouteNavigationRequestResult {
  request: BrowserPendingNavigationRequest;
  token: string;
}

export type BrowserPendingShellIntent = 'none' | 'open_tabs_overview' | 'return_home';

export type BrowserPendingNavigationConsumeOrigin =
  'memory' |
  'route_params' |
  'duplicate_route' |
  'empty';

export interface BrowserPendingNavigationConsumeResult {
  request: BrowserPendingNavigationRequest;
  origin: BrowserPendingNavigationConsumeOrigin;
  routeToken: string;
}

const EMPTY_PENDING_BROWSER_REQUEST: BrowserPendingNavigationRequest = {
  url: '',
  title: '',
  intent: 'current_tab',
  source: 'app_ui',
  createdAt: 0,
  requestId: '',
  routeToken: ''
};

let pendingBrowserRequest: BrowserPendingNavigationRequest = EMPTY_PENDING_BROWSER_REQUEST;
let pendingShellIntent: BrowserPendingShellIntent = 'none';

export function requestBrowserShellIntent(intent: BrowserPendingShellIntent): void {
  pendingShellIntent = intent;
}

export function consumePendingBrowserShellIntent(): BrowserPendingShellIntent {
  const intent = pendingShellIntent;
  pendingShellIntent = 'none';
  return intent;
}

export function requestOpenBrowserUrl(
  url: string,
  intent: BrowserAppUrlOpenIntent = 'current_tab',
  title: string = '',
  source: BrowserAppUrlOpenSource = 'app_ui',
  boundary: BrowserNavigationBoundaryOptions = {},
  routeToken: string = ''
): void {
  const normalizedSource = normalizeBrowserNavigationSource(source);
  const normalizedBoundary = normalizeBrowserNavigationBoundary(boundary);
  const normalizedRouteToken = routeToken.trim();
  pendingBrowserRequest = {
    url: url,
    title: title,
    intent: intent,
    source: normalizedSource,
    profileId: normalizedBoundary.profileId,
    privacyMode: normalizedBoundary.privacyMode,
    dataScope: normalizedBoundary.dataScope,
    createdAt: Date.now(),
    requestId: normalizedRouteToken.length > 0
      ? normalizedRouteToken
      : createBrowserNavigationRequestId(normalizedSource, 'memory'),
    routeToken: normalizedRouteToken
  };
}

export function requestOpenBrowserUrlWithRouteParams(
  url: string,
  intent: BrowserAppUrlOpenIntent = 'current_tab',
  title: string = '',
  source: BrowserAppUrlOpenSource = 'app_ui',
  boundary: BrowserNavigationBoundaryOptions = {}
): BrowserNavigationRouteParams {
  // One request, two delivery paths: the in-memory queue (read by the shell's consume pass) and the route
  // params this caller passes to `router.back`. Both must carry the same token, because the consume side
  // only records the route token it was handed. Without that, the in-memory copy is consumed first and the
  // still-readable route param is consumed again on every later page-show, re-opening this URL and
  // replacing whatever page the tab has since navigated to.
  const routeParams = buildBrowserNavigationRouteParams(url, intent, title, source, boundary);
  requestOpenBrowserUrl(url, intent, title, source, boundary, routeParams.openToken);
  return routeParams;
}

/**
 * Builds the route params and stages the matching in-memory request under the same token.
 */
export function buildBrowserNavigationRouteParams(
  url: string,
  intent: BrowserAppUrlOpenIntent = 'current_tab',
  title: string = '',
  source: BrowserAppUrlOpenSource = 'app_ui',
  boundary: BrowserNavigationBoundaryOptions = {}
): BrowserNavigationRouteParams {
  const normalizedBoundary = normalizeBrowserNavigationBoundary(boundary);
  return {
    openUrl: url,
    openTitle: title,
    openIntent: normalizeBrowserNavigationIntent(intent),
    openSource: normalizeBrowserNavigationSource(source),
    openToken: `${Date.now()}-${normalizeBrowserNavigationSource(source)}`,
    openProfileId: normalizedBoundary.profileId,
    openPrivacyMode: normalizedBoundary.privacyMode,
    openDataScope: normalizedBoundary.dataScope
  };
}

export function consumePendingBrowserNavigationRequest(): BrowserPendingNavigationRequest {
  const request = pendingBrowserRequest;
  pendingBrowserRequest = EMPTY_PENDING_BROWSER_REQUEST;
  return request;
}

export function consumePendingBrowserNavigationRequestWithRouteFallback(
  params: BrowserNavigationRouteParams | undefined,
  consumedToken: string
): BrowserPendingNavigationConsumeResult {
  const memoryRequest = consumePendingBrowserNavigationRequest();
  if (memoryRequest.url.trim().length > 0) {
    return {
      request: memoryRequest,
      origin: 'memory',
      // The in-memory request and the route params it was staged with are the same request. Reporting the
      // shared token here lets the consume side retire the route copy too, so a later page-show cannot
      // deliver it a second time.
      routeToken: memoryRequest.routeToken ?? ''
    };
  }
  const routeResult = readPendingBrowserNavigationRequestFromRouteParams(params, consumedToken);
  if (routeResult.request.url.trim().length > 0) {
    return {
      request: routeResult.request,
      origin: 'route_params',
      routeToken: routeResult.token
    };
  }
  if (routeResult.token.length > 0 && routeResult.token === consumedToken) {
    return {
      request: EMPTY_PENDING_BROWSER_REQUEST,
      origin: 'duplicate_route',
      routeToken: routeResult.token
    };
  }
  return {
    request: EMPTY_PENDING_BROWSER_REQUEST,
    origin: 'empty',
    routeToken: routeResult.token
  };
}

export function readPendingBrowserNavigationRequestFromRouteParams(
  params: BrowserNavigationRouteParams | undefined,
  consumedToken: string
): BrowserRouteNavigationRequestResult {
  const token = String(params?.openToken ?? '').trim();
  if (token.length > 0 && token === consumedToken) {
    return {
      request: EMPTY_PENDING_BROWSER_REQUEST,
      token: token
    };
  }
  const url = String(params?.openUrl ?? '').trim();
  if (url.length === 0) {
    return {
      request: EMPTY_PENDING_BROWSER_REQUEST,
      token: token
    };
  }
  const normalizedBoundary = normalizeBrowserNavigationRouteBoundary(params);
  return {
    request: {
      url: url,
      title: String(params?.openTitle ?? ''),
      intent: normalizeBrowserNavigationIntent(String(params?.openIntent ?? '')),
      source: normalizeBrowserNavigationSource(String(params?.openSource ?? '')),
      profileId: normalizedBoundary.profileId,
      privacyMode: normalizedBoundary.privacyMode,
      dataScope: normalizedBoundary.dataScope,
      createdAt: Date.now(),
      requestId: token.length > 0 ? token : createBrowserNavigationRequestId(
        normalizeBrowserNavigationSource(String(params?.openSource ?? '')),
        'route'
      ),
      routeToken: token
    },
    token: token
  };
}

export function consumePendingBrowserUrl(): string {
  return consumePendingBrowserNavigationRequest().url;
}

function normalizeBrowserNavigationIntent(intent: string): BrowserAppUrlOpenIntent {
  if (intent === 'new_tab' || intent === 'background_tab') {
    return intent;
  }
  return 'current_tab';
}

function normalizeBrowserNavigationSource(source: string): BrowserAppUrlOpenSource {
  if (source === 'bookmark' ||
    source === 'history' ||
    source === 'offline' ||
    source === 'home_shortcut' ||
    source === 'web_context_menu' ||
    source === 'userscript_install') {
    return source;
  }
  return 'app_ui';
}

function normalizeBrowserNavigationBoundary(boundary: BrowserNavigationBoundaryOptions): BrowserNormalizedNavigationBoundary {
  return normalizeBrowserNavigationBoundaryValues(boundary.profileId, boundary.privacyMode, boundary.dataScope);
}

function normalizeBrowserNavigationRouteBoundary(
  params: BrowserNavigationRouteParams | undefined
): BrowserNormalizedNavigationBoundary {
  return normalizeBrowserNavigationBoundaryValues(
    params?.openProfileId,
    params?.openPrivacyMode,
    params?.openDataScope
  );
}

function normalizeBrowserNavigationBoundaryValues(
  rawProfileId: BrowserProfileId | string | undefined,
  rawPrivacyMode: BrowserSessionPrivacyMode | string | undefined,
  rawDataScope: BrowserDataScope | string | undefined
): BrowserNormalizedNavigationBoundary {
  const hasBoundary = String(rawProfileId ?? '').trim().length > 0 ||
    String(rawPrivacyMode ?? '').trim().length > 0 ||
    String(rawDataScope ?? '').trim().length > 0;
  if (!hasBoundary) {
    return {};
  }
  const privacyMode = normalizeBrowserSessionPrivacyMode(rawPrivacyMode);
  return {
    profileId: normalizeBrowserProfileId(rawProfileId),
    privacyMode: privacyMode,
    dataScope: normalizeBrowserDataScope(rawDataScope, privacyMode)
  };
}

function createBrowserNavigationRequestId(source: BrowserAppUrlOpenSource, origin: string): string {
  return `native-open-${source}-${origin}-${Date.now()}`;
}
