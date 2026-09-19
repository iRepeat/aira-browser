import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

export interface BrowserTopImmersionScrollConfig {
  hideDeltaPx: number;
  revealDeltaPx: number;
  visibilitySwitchCooldownMs: number;
}

/**
 * Whether the bottom panel is engaged enough that scroll immersion must keep the status bar visible.
 *
 * Only an expanded panel counts: the address input session and a raised action surface both sit at
 * `middle`. A resting (`low`) or collapsed (`peek`) toolbar does not, because the user is not
 * interacting with it.
 *
 * The resting toolbar must not count. It is the normal state during any scroll, and with the
 * "always show" scroll behavior it never leaves `resting`, so treating "the toolbar is not
 * scroll-collapsed" as engaged would pin the status bar visible and disable immersion entirely.
 */
export function isBottomPanelEngagedForTopImmersion(detent: HomeSearchPanelDetent): boolean {
  return detent === 'middle';
}

export interface BrowserTopImmersionScrollInput {
  tabId: string;
  scrollOffsetY: number;
  webPageVisible: boolean;
  addressFocused: boolean;
  bottomPanelInteractive: boolean;
  bottomChromeRestoredByScroll?: boolean;
  showTabsSheet: boolean;
  scrollImmersionEnabled: boolean;
  currentStatusBarVisible: boolean;
}

export interface BrowserTopImmersionScrollDecision {
  statusBarVisible: boolean;
  changed: boolean;
}

interface BrowserTopImmersionScrollState {
  tabId: string;
  lastScrollOffsetY: number;
  downwardDelta: number;
  upwardDelta: number;
  lastVisibilitySwitchAt: number;
}

const DEFAULT_SCROLL_CONFIG: BrowserTopImmersionScrollConfig = {
  hideDeltaPx: 24,
  revealDeltaPx: 32,
  visibilitySwitchCooldownMs: 360
};

export class BrowserTopImmersionScrollCoordinator {
  private state: BrowserTopImmersionScrollState = {
    tabId: '',
    lastScrollOffsetY: 0,
    downwardDelta: 0,
    upwardDelta: 0,
    lastVisibilitySwitchAt: 0
  };
  private config: BrowserTopImmersionScrollConfig;

  constructor(config: BrowserTopImmersionScrollConfig = DEFAULT_SCROLL_CONFIG) {
    this.config = config;
  }

  handleScroll(input: BrowserTopImmersionScrollInput, now: number = Date.now()): BrowserTopImmersionScrollDecision {
    const normalizedY = Math.max(0, Math.floor(input.scrollOffsetY));
    if (this.shouldForceVisible(input)) {
      this.rememberBaseline(input.tabId, normalizedY);
      return {
        statusBarVisible: true,
        changed: !input.currentStatusBarVisible
      };
    }
    if (this.state.tabId !== input.tabId) {
      this.rememberBaseline(input.tabId, normalizedY);
      return {
        statusBarVisible: input.currentStatusBarVisible,
        changed: false
      };
    }
    const delta = normalizedY - this.state.lastScrollOffsetY;
    this.state.lastScrollOffsetY = normalizedY;
    if (delta > 0) {
      this.state.downwardDelta += delta;
      this.state.upwardDelta = 0;
    } else if (delta < 0) {
      this.state.upwardDelta += Math.abs(delta);
      this.state.downwardDelta = 0;
    }
    if (this.isVisibilitySwitchCoolingDown(now)) {
      return {
        statusBarVisible: input.currentStatusBarVisible,
        changed: false
      };
    }
    if (input.currentStatusBarVisible && normalizedY > 0 && this.state.downwardDelta >= this.config.hideDeltaPx) {
      this.state.downwardDelta = 0;
      this.state.lastVisibilitySwitchAt = Math.max(0, Math.floor(now));
      return {
        statusBarVisible: false,
        changed: true
      };
    }
    if (!input.currentStatusBarVisible && this.state.upwardDelta >= this.config.revealDeltaPx) {
      this.state.upwardDelta = 0;
      this.state.lastVisibilitySwitchAt = Math.max(0, Math.floor(now));
      return {
        statusBarVisible: true,
        changed: true
      };
    }
    return {
      statusBarVisible: input.currentStatusBarVisible,
      changed: false
    };
  }

  reset(tabId: string = '', scrollOffsetY: number = 0): void {
    this.rememberBaseline(tabId, scrollOffsetY);
  }

  private shouldForceVisible(input: BrowserTopImmersionScrollInput): boolean {
    // `bottomChromeRestoredByScroll` is the upward scroll that just brought the toolbar back. Both
    // chromes restore together, so the status bar returns on that same event even when the upward
    // movement alone is below `revealDeltaPx`. It must be an event, not the ambient resting state:
    // a toolbar that is resting because it never scroll-collapses ("always show") would otherwise
    // force the status bar visible on every scroll and cancel immersion.
    return !input.scrollImmersionEnabled ||
      !input.webPageVisible ||
      input.showTabsSheet ||
      input.addressFocused ||
      input.bottomPanelInteractive ||
      input.bottomChromeRestoredByScroll === true;
  }

  private isVisibilitySwitchCoolingDown(now: number): boolean {
    const cooldownMs = Math.max(0, Math.floor(this.config.visibilitySwitchCooldownMs));
    if (cooldownMs <= 0 || this.state.lastVisibilitySwitchAt <= 0) {
      return false;
    }
    return Math.max(0, Math.floor(now)) - this.state.lastVisibilitySwitchAt < cooldownMs;
  }

  private rememberBaseline(tabId: string, scrollOffsetY: number): void {
    this.state = {
      tabId: tabId,
      lastScrollOffsetY: Math.max(0, Math.floor(scrollOffsetY)),
      downwardDelta: 0,
      upwardDelta: 0,
      lastVisibilitySwitchAt: this.state.lastVisibilitySwitchAt
    };
  }
}
