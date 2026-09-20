import { FrameCallback } from '@kit.ArkUI';
import { SiteIconView } from '../common/SiteIconView';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserTabPreviewState } from '../../../core/browser/BrowserTabPreviewCoordinator';
import {
  BrowserTabOverviewIdentityPresentation,
  BrowserTabOverviewItemPresentation,
  BrowserTabsOverviewIdentityIconSnapshot,
  BrowserTabsOverlayRect,
  BrowserTabsOverlayViewModel
} from '../../../core/browser/BrowserTabsOverlayViewModel';
import {
  BrowserTabsOverviewLayoutState,
  BrowserTabsOverviewLayoutViewModel,
  isSameTabsOverviewLayoutState
} from '../../../core/browser/BrowserTabsOverviewLayoutViewModel';
import {
  BrowserTabsOverviewIdentityMotionState,
  BrowserTabsOverlayAnimationViewModel
} from '../../../core/browser/BrowserTabsOverlayAnimationViewModel';
import {
  BrowserTabsSharedSnapshotTransitionCoordinator,
  BrowserTabsSharedSnapshotTransitionState
} from '../../../core/browser/BrowserTabsSharedSnapshotTransitionCoordinator';
import { BrowserTabState } from '../../../core/tabs/TabManager';
import {
  BrowserTabsOverviewLocalRemovalState,
  BrowserTabsOverviewShadowViewModel
} from '../../../core/browser/BrowserTabsOverviewShadowViewModel';
import { BrowserTabsOverviewSection, BrowserTabsOverviewSectionPolicy } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { BrowserTabOverviewCardSelectRect } from './BrowserTabOverviewCard';
import { BrowserTabOverviewItem } from './BrowserTabOverviewItem';
import { BrowserTabsSharedSnapshotOverlay } from './BrowserTabsSharedSnapshotOverlay';
import {
  BrowserTabsOverviewBottomChrome,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT
} from './BrowserTabsOverviewBottomChrome';
import { BrowserTabsOverviewClearButton } from './BrowserTabsOverviewClearButton';
import { BrowserTabsOverviewDeviceButton } from './BrowserTabsOverviewDeviceButton';
import { BrowserTabsOverviewEmptyState } from './BrowserTabsOverviewEmptyState';
import {
  BrowserTabsOverviewBottomChromeState,
  BrowserTabsOverviewBottomChromeViewModel
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewBottomChromeViewModel';
import {
  BrowserTabsOverviewSwipeFeedbackService
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSwipeFeedbackService';
import {
  BrowserTabsOverviewSwipeDismissPolicy
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSwipeDismissPolicy';
import {
  BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_MIN_CARD_RATIO,
  BrowserTabsOverviewEntryGesturePolicy
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewEntryGesturePolicy';
import { BrowserTabsOverviewStackMotion } from '../../../core/browser/tabsOverview/BrowserTabsOverviewStackMotion';
import {
  BrowserTabsOverviewStackCardMetrics,
  BrowserTabsOverviewStackLayoutPolicy
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy';
import {
  BrowserTabsOverviewSelectionDisplacement,
  BrowserTabsOverviewSelectionDisplacementCoordinator
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSelectionDisplacementCoordinator';
import {
  BrowserTabsFloatingEntryTargetCoordinator,
  BrowserTabsFloatingEntryTargetPreparationState,
  BrowserTabsFloatingEntryTargetRectInput,
  BrowserTabsFloatingEntryTargetRecordedRectResult,
  BrowserTabsFloatingEntryTargetReadyAttemptResult,
  BrowserTabsFloatingEntryTargetResolvedRectResult
} from '../../../core/browser/tabsOverview/BrowserTabsFloatingEntryTargetCoordinator';
import {
  BROWSER_TABS_OVERVIEW_IDENTITY_HORIZONTAL_INSET,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_SIZE,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_TEXT_GAP
} from '../../../core/browser/BrowserTabsOverviewVisualTokens';
import {
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY,
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { SiteIconListRenderState } from '../../../core/siteicons/SiteIconListPresenter';

const FLOATING_TABS_HORIZONTAL_PADDING: number = 16;
const FLOATING_TABS_TOP_PADDING: number = 28;
const FLOATING_TABS_GRID_GAP: number = 16;
const FLOATING_TABS_EXIT_DURATION_MS: number = 280;
const FLOATING_TABS_CLOSE_ALL_COMMIT_DELAY_MS: number = 32;
const FLOATING_TABS_BOTTOM_POSITION_DELAY_MS: number = 0;
const FLOATING_TABS_ENTRY_START_DELAY_MS: number = 32;
const FLOATING_TABS_REORDER_DURATION_MS: number = 360;
/** How long the released pull takes to land the row in the deck. */
const ENTRY_GESTURE_SETTLE_DURATION_MS: number = 360;
/** Clear space between the cards the pull shows, in vp. */
const FLOATING_TABS_ENTRY_GESTURE_ROW_GAP: number = 10;
const FLOATING_TABS_ENTRY_TARGET_READY_DELAY_MS: number = 0;
const FLOATING_TABS_ENTRY_TARGET_READY_RETRY_MS: number = 16;
const FLOATING_TABS_ENTRY_TARGET_READY_MAX_ATTEMPTS: number = 24;
const FLOATING_TABS_CARDS_Z_INDEX: number = 10;
const FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX: number = 20;
const FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX: number = 25;
const FLOATING_TABS_BOTTOM_CHROME_Z_INDEX: number = 31;
const FLOATING_TABS_CLEAR_BUTTON_Z_INDEX: number = 32;
const FLOATING_TABS_DEVICE_BUTTON_Z_INDEX: number = 32;
const HORIZONTAL_DECK_DRAG_START_DISTANCE: number = 6;

class BrowserTabsStackFrameCallback extends FrameCallback {
  private readonly task: (timeInNano: number) => void;

  constructor(task: (timeInNano: number) => void) {
    super();
    this.task = task;
  }

  onFrame(timeInNano: number): void {
    this.task(timeInNano);
  }
}

interface BrowserTabsFloatingItem {
  id: string;
  tab: BrowserTabState;
  presentation: BrowserTabOverviewItemPresentation;
  index: number;
}

interface BrowserTabsFloatingContentPadding {
  top: number;
  bottom: number;
}

@Component
export struct BrowserTabsFloatingOverlay {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY)
  @Watch('handleStoredTabsOverviewLayoutStyleChanged')
  private storedTabsOverviewLayoutStyle: string = 'horizontal_cards';
  @StorageProp(BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY)
  private storedTabsOverviewCloseButtonAlwaysVisible: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';

  @Watch('handleTabsChanged')
  @Prop tabs: BrowserTabState[] = [];
  @Watch('refreshDeckPresentation')
  @Prop previewStates: BrowserTabPreviewState[] = [];
  @Prop activeTabId: string = '';
  @Prop activeSection: BrowserTabsOverviewSection = 'tabs';
  @Prop morphCoveredTabId: string = '';
  @Prop selectionDisplacementTabId: string = '';
  @Watch('syncEntryDisplacementFromProps')
  @Prop entryDisplacementTabId: string = '';
  @Watch('syncEntryDisplacementFromProps')
  @Prop entryDisplacementSettlingEnabled: boolean = false;
  @Watch('handleDeckInteractionChanged')
  @Prop interactionEnabled: boolean = true;
  @Prop sideEntryAnimationEnabled: boolean = true;
  @Prop viewportLeft: number = 0;
  @Prop viewportTop: number = 0;
  @Prop viewportWidth: number = 390;
  @Prop viewportHeight: number = 844;
  @Prop topSafeInsetVp: number = 0;
  @Prop backdropBlurRadius: number = 0;
  @Prop backgroundTintEnabled: boolean = true;
  @Prop backgroundSurfaceOpacity: number = -1;
  @Prop layerOpacity: number = 1;
  @Prop homeExitProgress: number = 0;
  @Watch('handleDeckInteractionChanged')
  @Prop exiting: boolean = false;
  @Watch('refreshDeckPresentation')
  @Prop blurPrivateTabPreviews: boolean = true;
  @Prop panelPageBackgroundColor: ResourceColor | undefined = undefined;
  @Prop panelSecondaryTextColor: ResourceColor | undefined = undefined;
  @Prop regularChromeIconTone: AppChromeIconTone = 'light';
  @Watch('startCloseAllTabsAnimationFromRequest')
  @Prop closeAllTabsAnimationRequestVersion: number = 0;
  @Prop entrySharedSnapshotMounted: boolean = false;
  @Watch('handleEntrySharedSnapshotChanged')
  @Prop entrySharedSnapshotState: BrowserTabsSharedSnapshotTransitionState =
    new BrowserTabsSharedSnapshotTransitionCoordinator().buildIdleState();
  /**
   * An upward drag on the middle of the bottom bar is pulling the overview open.
   *
   * The overview is entered while the finger is still down, so the page-to-card morph is driven by the
   * drag instead of by its own clock: the finger's travel decides how far the card has come and how
   * much smaller than the deck's card it still is. Releasing hands the entry back to its normal
   * settling path.
   */
  @Watch('handleEntryGestureActiveChanged')
  @Prop entryGestureActive: boolean = false;
  @Watch('handleEntryGestureOffsetsChanged')
  @Prop entryGestureOffsetX: number = 0;
  @Watch('handleEntryGestureOffsetsChanged')
  @Prop entryGestureOffsetY: number = 0;
  @Prop entrySharedSnapshotBackgroundColor: ResourceColor | undefined = undefined;
  // Incremented by the page every time the sheet is opened. While the overlay is
  // resident (mounted but closed) it never re-runs aboutToAppear, so the per-open
  // setup has to be replayed from this signal.
  @Watch('handleOpenRequested')
  @Prop openRequestVersion: number = 0;

  @State private selectedSection: BrowserTabsOverviewSection = 'tabs';
  @State private layoutState: BrowserTabsOverviewLayoutState =
    new BrowserTabsOverviewLayoutViewModel().buildState({
      gridWidth: 0,
      sheetWidth: 360,
      sheetHeight: 844,
      layoutStyle: 'horizontal_cards'
    });
  @State private entryProgress: number = 0;
  @State private removalState: BrowserTabsOverviewLocalRemovalState =
    new BrowserTabsOverviewShadowViewModel().buildInitialLocalRemovalState();
  @State private lateMountEntryAnimationEnabled: boolean = false;
  @State private entryDisplacementProgress: number = 1;
  @State private closeAllExitActive: boolean = false;
  @Watch('refreshDeckPresentation')
  @State private siteIconStates: SiteIconListRenderState[] = [];
  @State private chromeMounted: boolean = false;
  /**
   * Continuous deck position, in card units: 2 means the third card is focused, 2.4 means 40% of
   * the way to the fourth.
   *
   * Every card's place in the deck is derived from it, so it has to stay continuous. Snapping it
   * to whole cards would make the whole deck jump each time the finger crossed a midpoint.
   */
  @State private horizontalDeckPosition: number = 0;
  @State private deckItems: BrowserTabsFloatingItem[] = [];
  private entryGesturePolicy: BrowserTabsOverviewEntryGesturePolicy =
    new BrowserTabsOverviewEntryGesturePolicy();
  /**
   * The entry snapshot the finger drives.
   *
   * The scene owns the real one and publishes it as idle the moment the entry settles, which can
   * happen while the finger is still down. This copy is what keeps the card under the finger after
   * that, so a pull that is held does not lose its picture half way through.
   */
  @State private entryGestureSnapshotState: BrowserTabsSharedSnapshotTransitionState | undefined =
    undefined;
  /**
   * The rectangle the pull paints the held card in.
   *
   * One interpolation from the page to the smallest card, driven by the finger and nothing else, so
   * the shrink only ever slows down as the finger climbs. It is also what the release animates to the
   * deck's own card, which is why letting go lands the card instead of jumping to it.
   */
  @State private entryGestureCardRect: BrowserTabsOverlayRect = { left: 0, top: 0, width: 1, height: 1 };
  /** Used only until the held tab is known, so the header builder needs no undefined branch. */
  private entryGesturePlaceholderIdentity: BrowserTabOverviewIdentityPresentation = {
    label: '',
    iconUri: '',
    iconPixelMap: undefined,
    fallbackLabel: '?',
    fallbackAiraIconId: 'browser.shortcut.home',
    sourceRevision: 0
  };
  @State private entryGesturePanX: number = 0;
  @State private entryGesturePanY: number = 0;
  /** 0 while the finger holds the row flat, 1 once the cards have settled into the deck. */
  @State private entryGestureSettle: number = 0;
  /** True while the finger's release is still landing the row into the deck. */
  @State private entryGestureSettling: boolean = false;
  @State private deckSwipeTabId: string = '';
  @State private deckDismissGhostTabId: string = '';
  /**
   * Each card's slot in the deck, keyed by tab id.
   *
   * A card must never read its slot from the `ForEach` item. `ForEach` reuses a node whose key is
   * unchanged without running the item builder again, so the item captured by that card's builder
   * keeps the index it had when the node was created. Reading the slot from a list the card does
   * observe is what lets a removal move the surviving cards at all.
   */
  @State private deckSlotIndexById: Record<string, number> = {};

  private scroller: Scroller = new Scroller();
  private bottomScrollTimer: number = 0;
  private entryAnimationTimer: number = 0;
  private lateMountEntryAnimationTimer: number = 0;
  private closeAllCommitTimer: number = 0;
  private entryTargetReadyTimer: number = 0;
  private chromeMountTimer: number = 0;
  private entryDisplacementTargetId: string = '';
  private entryReturnTabId: string = '';
  /**
   * True only for the cold open, whose cards are mounted as the grid is first built and can
   * fly in as they appear. A resident re-open reuses an already-built grid, so it enters
   * plainly: neither the coordinated fly-in nor a per-card mount fly-in runs there. Letting
   * either run on an already-laid-out grid made cards jump back from off-screen and settle,
   * which read as a jitter.
   */
  private isFirstOpenInFlight: boolean = true;
  private handledCloseAllRequestVersion: number = 0;
  private entryTargetPreparationState: BrowserTabsFloatingEntryTargetPreparationState =
    new BrowserTabsFloatingEntryTargetCoordinator().buildIdleState();
  private layoutViewModel: BrowserTabsOverviewLayoutViewModel = new BrowserTabsOverviewLayoutViewModel();
  private shadowViewModel: BrowserTabsOverviewShadowViewModel = new BrowserTabsOverviewShadowViewModel();
  private overlayViewModel: BrowserTabsOverlayViewModel = new BrowserTabsOverlayViewModel();
  private animationViewModel: BrowserTabsOverlayAnimationViewModel = new BrowserTabsOverlayAnimationViewModel();
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();
  private swipeDismissPolicy: BrowserTabsOverviewSwipeDismissPolicy =
    new BrowserTabsOverviewSwipeDismissPolicy();
  private stackLayoutPolicy: BrowserTabsOverviewStackLayoutPolicy =
    new BrowserTabsOverviewStackLayoutPolicy();
  private deckMotion: BrowserTabsOverviewStackMotion = new BrowserTabsOverviewStackMotion();
  private deckDragActive: boolean = false;
  /**
   * The tab whose dismissal is mid fill-in, if any.
   *
   * This has to be observed state, not a plain field: the deck's touch handling reads it (see
   * `canInteractWithDeck`), and a plain field would leave the cards layer holding whatever
   * `HitTestMode` it rendered last. A dismissal that clears a field the framework cannot see would
   * therefore leave the deck unwatchable — the fill-in lands, and then nothing can be dragged again
   * until the whole overview is closed and reopened.
   */
  @State private pendingDeckDismissTabId: string = '';
  private pendingDeckDismissPosition: number = -1;
  private deckDismissCommitTimer: number = 0;
  /**
   * Whether the deck has been placed on a card for the current entry.
   *
   * `layoutStyle` only resolves to `horizontal_cards` after the first `onAreaChange`, which can run
   * after `initializeForOpen`. Without this latch the deck would be left at card zero whenever the
   * window measured late.
   */
  private deckPositionSeeded: boolean = false;
  private deckMetricsCacheKey: string = '';
  private deckMetricsCache: BrowserTabsOverviewStackCardMetrics[] = [];
  /**
   * Identity of the current item list, refreshed only when the list is rebuilt.
   *
   * The memo below caches metrics by card slot, so the key has to change when a card leaves or
   * shifts: two decks of the same length can hold different tabs at the same slot.
   */
  private deckItemsSignature: string = '';
  /** Order of the recorded slots, so an unchanged list does not replace the map every frame. */
  private deckSlotSignature: string = '';
  private selectionDisplacementCoordinator: BrowserTabsOverviewSelectionDisplacementCoordinator =
    new BrowserTabsOverviewSelectionDisplacementCoordinator();
  private entryTargetCoordinator: BrowserTabsFloatingEntryTargetCoordinator =
    new BrowserTabsFloatingEntryTargetCoordinator();
  private bottomChromeViewModel: BrowserTabsOverviewBottomChromeViewModel =
    new BrowserTabsOverviewBottomChromeViewModel();
  onDismiss: () => void = () => {};
  onCreateTab: () => void = () => {};
  onRequestCloseAll: () => void = () => {};
  onCloseAllAnimationFinished: () => void = () => {};
  onSwitchSectionHome: (section: BrowserTabsOverviewSection) => void = (_section: BrowserTabsOverviewSection) => {};
  onActiveSectionChange: (section: BrowserTabsOverviewSection) => void = (_section: BrowserTabsOverviewSection) => {};
  onSelectTab: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => void =
    (_tabId: string, _rect?: BrowserTabOverviewCardSelectRect) => {};
  onCloseTab: (tabId: string) => void = (_tabId: string) => {};
  onPreviewRectChange: (
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ) => void = (_tabId: string, _left: number, _top: number, _width: number, _height: number) => {};
  onEntryTargetPreviewRectReady: (
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ) => void = (_tabId: string, _left: number, _top: number, _width: number, _height: number) => {};
  onEntrySharedSnapshotRectChange: (rect: BrowserTabsOverlayRect) => void = (_rect: BrowserTabsOverlayRect) => {};
  onEntrySharedSnapshotTap: (tabId: string) => void = (_tabId: string) => {};
  onOpenDeviceTabs: () => void = () => {};

  aboutToAppear(): void {
    // Subscribe once for the lifetime of the component; the identity-icon binding is
    // not per-open, and re-binding it on every open would stack subscriptions.
    this.overlayViewModel.bindIdentityIconUpdates(
      (): BrowserTabsOverviewIdentityIconSnapshot => this.buildIdentityIconSnapshot(),
      (states: SiteIconListRenderState[]): void => {
        this.siteIconStates = states;
      }
    );
    this.initializeForOpen();
    // HDS segmented tabs, the blurred material bar and the corner buttons add a large
    // native subtree on top of the grid. Mount them on the next frame so the first
    // frame stays cheap: it blocks the main thread, so this timer only runs once the
    // grid has been laid out. Only the first open defers them; later opens reuse them.
    this.chromeMountTimer = setTimeout(() => {
      this.chromeMountTimer = 0;
      this.chromeMounted = true;
    }, 0);
  }

  private handleOpenRequested(): void {
    // A resident re-open reuses the built grid, so it enters plainly: no coordinated
    // fly-in and no per-card mount fly-in.
    this.isFirstOpenInFlight = false;
    this.initializeForOpen();
  }

  /**
   * Per-open setup. Runs from aboutToAppear on the first open and from
   * openRequestVersion on every later open, because a resident overlay does not
   * remount and therefore never re-enters aboutToAppear.
   */
  private initializeForOpen(): void {
    this.commitPendingDeckDismiss();
    this.stopDeckMotion();
    this.deckPositionSeeded = false;
    this.selectedSection = this.activeSection;
    this.entryReturnTabId = this.activeTabId.trim();
    // A close-all leaves this latched true. It used to be cleared by the remount;
    // a resident overlay must clear it here or every later open stays non-interactive.
    this.closeAllExitActive = false;
    this.syncLayoutState();
    // A cold open starts at 0 so its freshly mounted cards fly in; a resident re-open starts
    // settled so an already-built grid enters plainly instead of jumping back and settling.
    this.entryProgress = this.isFirstOpenInFlight ? this.resolveEntryInitialProgress() : 1;
    this.entryDisplacementTargetId = this.entryDisplacementTabId.trim();
    this.entryDisplacementProgress = this.resolveEntryDisplacementInitialProgress();
    this.entryTargetPreparationState =
      this.entryTargetCoordinator.clearPreviewRectCache(this.entryTargetPreparationState);
    this.resetEntryTargetPreparation();
    this.beginEntryTargetPreparationIfNeeded();
    this.removalState = this.shadowViewModel.buildInitialLocalRemovalState();
    this.ensureDeckPositionForCurrentSection();
    this.syncEntryDisplacementFromProps();
    this.prepareBottomEntryAnimation();
    // Resolve identity icons before the grid is first built. The grid is keyed by tab
    // id, so a later @State update would not repaint already-built cards and every
    // favicon would stay on its letter fallback.
    this.syncSiteIcons();
  }

  aboutToDisappear(): void {
    this.commitPendingDeckDismiss();
    this.clearDeckDismissCommitTimer();
    this.stopDeckMotion();
    this.clearBottomScrollTimer();
    this.clearEntryAnimationTimer();
    this.clearLateMountEntryAnimationTimer();
    this.clearCloseAllCommitTimer();
    this.clearEntryTargetReadyTimer();
    if (this.chromeMountTimer > 0) {
      clearTimeout(this.chromeMountTimer);
      this.chromeMountTimer = 0;
    }
    this.overlayViewModel.disposeIdentityIcons();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildBackgroundDismissLayer()

      this.buildCardsLayer()

      if (this.isSelectedSectionEmpty()) {
        this.buildEmptyStateLayer()
        this.buildEmptyDismissLayer()
      }

      // The entering morph is stacked inside the deck instead of above the cards layer, so the
      // cards that trail the covered one keep the slot they own at rest. Every other case — the
      // grid, the exit back to the page — still paints it from here.
      // The held pull paints its own copy of the snapshot — the scene drops the real one the moment the
      // entry settles, which can happen while the finger is still down.
      if (this.shouldRenderEntryGestureOverlay()) {
        this.buildEntryGestureHeldIdentity()
        this.buildEntryGestureSnapshot()
      } else if (this.entrySharedSnapshotMounted && !this.shouldMountSharedSnapshotInDeck()) {
        this.buildSharedSnapshotOverlay()
      }

      if (this.chromeMounted) {
        BrowserTabsOverviewClearButton({
          selectedSection: this.selectedSection,
          viewportWidth: this.resolveRootWidth(),
          topSafeInsetVp: this.topSafeInsetVp,
          surfaceOpacity: this.resolveClearButtonOpacity(),
          interactionEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive,
          regularChromeIconTone: this.regularChromeIconTone,
          adaptiveForeground: true,
          onClearAll: () => {
            this.onRequestCloseAll();
          }
        })
        .zIndex(FLOATING_TABS_CLEAR_BUTTON_Z_INDEX)

        if (this.selectedSection === 'tabs') {
          BrowserTabsOverviewDeviceButton({
            topSafeInsetVp: this.topSafeInsetVp,
            surfaceOpacity: this.resolveClearButtonOpacity(),
            interactionEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive,
            regularChromeIconTone: this.regularChromeIconTone,
            adaptiveForeground: true,
            onOpenDeviceTabs: () => {
              this.onOpenDeviceTabs();
            }
          })
          .zIndex(FLOATING_TABS_DEVICE_BUTTON_Z_INDEX)
        }

        if (this.shouldShowBottomChrome()) {
          BrowserTabsOverviewBottomChrome({
            selectedSection: this.selectedSection,
            regularTabsLabel: this.buildBottomChromeState().regularTabsLabel,
            viewportWidth: this.resolveRootWidth(),
            viewportHeight: this.resolveRootHeight(),
            surfaceOpacity: this.resolveBottomChromeOpacity(),
            chromeInteractionEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive,
            regularChromeIconTone: this.regularChromeIconTone,
            adaptiveForeground: true,
            onReturn: () => {
              this.returnToEntryTab();
            },
            onCreateHome: () => {
              this.onCreateTab();
            },
            onSwitchToTabs: () => {
              this.switchSection('tabs');
            },
            onSwitchToPrivacy: () => {
              this.switchSection('privacy');
            }
          })
          .zIndex(FLOATING_TABS_BOTTOM_CHROME_Z_INDEX)
        }
      }
    }
    .width(this.resolveRootWidth())
    .height(this.resolveRootHeight())
    .opacity(this.resolveLayerOpacity())
    .onVisibleAreaChange([0], (visible: boolean) => {
      if (visible) {
        // Becoming visible again must not expose a deck frozen between two cards.
        this.settleDeckToNearestCard();
      } else {
        this.stopDeckMotion();
      }
    })
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .onAreaChange((_oldArea: Area, _newArea: Area) => {
      this.syncLayoutState();
      this.syncLocalRemovalStateFromTabs();
    })
  }

  @Builder
  private buildBackgroundDismissLayer() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePanelPageBackgroundColor())
      .opacity(this.resolveBackgroundTintOpacity())
      .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
        HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.interactionEnabled && !this.closeAllExitActive) {
          this.onDismiss();
        }
      })
      .zIndex(0)
  }

  @Builder
  private buildEmptyStateLayer() {
    Column() {
      BrowserTabsOverviewEmptyState({
        selectedSection: this.selectedSection,
        textColor: this.resolvePanelSecondaryTextColor()
      })
        .opacity(0.82 * this.resolveSurfaceProgress())
    }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: FLOATING_TABS_HORIZONTAL_PADDING,
        right: FLOATING_TABS_HORIZONTAL_PADDING,
        top: this.resolveContentTopPadding(),
        bottom: this.resolveContentBottomPadding()
      })
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
        HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.interactionEnabled && !this.closeAllExitActive) {
          this.onDismiss();
        }
      })
      .zIndex(20)
  }

  @Builder
  private buildEmptyDismissLayer() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .hitTestBehavior(this.shouldAllowEmptyDismiss() ? HitTestMode.Block : HitTestMode.None)
      .onClick(() => {
        if (this.shouldAllowEmptyDismiss()) {
          this.onDismiss();
        }
      })
      .zIndex(25)
  }

  @Builder
  private buildSharedSnapshotOverlay(inDeck: boolean = false) {
    BrowserTabsSharedSnapshotOverlay({
      state: this.entrySharedSnapshotState,
      snapshotBackgroundColor: this.entrySharedSnapshotBackgroundColor,
      // Inside the deck the slot wrapper already owns stacking. Passing the overlay-root
      // 20/25 here would let the morph compete with every card if ArkUI flattens z-index.
      snapshotLayerZIndex: inDeck ? 0 : FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX,
      snapshotDecorationLayerZIndex: inDeck ? 0 : FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX,
      viewportLeft: this.resolveRootLeft(),
      viewportTop: this.resolveRootTop(),
      onSnapshotRectChange: (rect: BrowserTabsOverlayRect) => {
        this.onEntrySharedSnapshotRectChange(rect);
      },
      onSnapshotTap: (tabId: string) => {
        this.onEntrySharedSnapshotTap(tabId);
      }
    })
  }

  @Builder
  private buildCardsLayer() {
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      this.buildHorizontalCardsLayer()
    } else {
      this.buildGridCardsLayer()
    }
  }

  /**
   * Whether the finger, not the scene, owns the page's snapshot.
   *
   * While a pull is in flight the deck is already there — it is what supplies the neighbours the pull
   * shows — but the card the page morphs into is held by the finger, so the snapshot paints it from
   * the root exactly like the normal entry does.
   */
  private shouldRenderEntryGestureOverlay(): boolean {
    return this.shouldApplyEntryGestureLayout() && this.entryGestureSnapshotState !== undefined;
  }

  /**
   * Whether the finger owns the deck's layout.
   *
   * True for the whole drag and for its landing, whether or not the page's snapshot has arrived: the
   * row is flat from the first claimed frame, and only the card the finger holds needs the capture.
   */
  private shouldApplyEntryGestureLayout(): boolean {
    return this.entryGestureActive || this.entryGestureSettling;
  }

  /**
   * The held card's icon and title, on top of its snapshot.
   *
   * The snapshot is the page's picture and nothing else — that is what a page-to-card morph needs,
   * because the card's own header fades in behind it. A pull shows a *card* the whole time, so its
   * header has to be painted here, at the same size and place as the ones on the cards beside it.
   */
  @Builder
  private buildEntryGestureHeldIdentity() {
    if (this.shouldRenderEntryGestureHeldIdentity()) {
      // A whole card box, scaled about its own centre exactly like a deck card, with the header at its
      // top. Scaling the header on its own moved it: a scale happens about the node's centre, so the row
      // drifted away from the card as the card shrank.
      Column() {
        this.buildEntryGestureHeldIdentityHeader()
      }
      .width(this.layoutState.cardWidth)
      .height(this.resolveItemHeight())
      .alignItems(HorizontalAlign.Start)
      .position({
        x: this.resolveEntryGestureHeldBoxLeft(),
        y: this.resolveEntryGestureHeldBoxTop()
      })
      .scale({
        x: this.resolveEntryGestureRowScale(),
        y: this.resolveEntryGestureRowScale()
      })
      .hitTestBehavior(HitTestMode.None)
      .zIndex(FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX)
    }
  }

  @Builder
  private buildEntryGestureHeldIdentityHeader() {
    Row({ space: BROWSER_TABS_OVERVIEW_IDENTITY_ICON_TEXT_GAP }) {
      SiteIconView({
        iconUri: this.resolveEntryGestureHeldIdentity().iconUri,
        iconPixelMap: this.resolveEntryGestureHeldIdentity().iconPixelMap,
        fallbackLabel: this.resolveEntryGestureHeldIdentity().fallbackLabel,
        fallbackAiraIconId: this.resolveEntryGestureHeldIdentity().fallbackAiraIconId,
        fallbackIconSize: 16,
        iconSize: BROWSER_TABS_OVERVIEW_IDENTITY_ICON_SIZE,
        cornerRadiusRatio: 0.22,
        frameBorderWidth: 0,
        contentPadding: 0,
        fallbackFontSize: 12,
        fallbackFontWeight: FontWeight.Medium,
        containerBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
        textColor: this.storedSecondaryTextColor,
        fit: ImageFit.Contain,
        preferPixelMap: this.resolveEntryGestureHeldIdentity().iconPixelMap !== undefined,
        sourceRevision: this.resolveEntryGestureHeldIdentity().sourceRevision,
        hitTestMode: HitTestMode.None
      })

      Text(this.resolveEntryGestureHeldIdentity().label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(this.layoutState.identityHeaderHeight)
    .width(this.layoutState.cardWidth)
    .margin({ left: BROWSER_TABS_OVERVIEW_IDENTITY_HORIZONTAL_INSET })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  /** The header box of a card of the pull: the preview's own rectangle drives where it sits. */
  private resolveEntryGestureHeldBoxLeft(): number {
    const scale = this.resolveEntryGestureRowScale();
    return this.entryGestureCardRect.left -
      this.layoutState.cardWidth * (1 - scale) / 2;
  }

  private resolveEntryGestureHeldBoxTop(): number {
    const scale = this.resolveEntryGestureRowScale();
    const header = this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap;
    const visibleItemTop = this.entryGestureCardRect.top - header * scale;
    return visibleItemTop - this.resolveItemHeight() * (1 - scale) / 2;
  }

  private resolveEntryGestureRowScale(): number {
    return Math.max(0.05,
      this.entryGestureCardRect.width / Math.max(1, this.layoutState.cardWidth));
  }

  private shouldRenderEntryGestureHeldIdentity(): boolean {
    return this.shouldRenderEntryGestureOverlay() &&
      this.entryGestureCardRect.width > 1 &&
      this.entryGestureCardRect.width < this.resolveRootWidth() * 0.98;
  }

  private resolveEntryGestureHeldIdentity(): BrowserTabOverviewIdentityPresentation {
    const heldTabId = this.resolveEntryGestureHeldTabId();
    const item = this.deckItems.find(
      (candidate: BrowserTabsFloatingItem): boolean => candidate.id === heldTabId);
    if (item === undefined) {
      return this.entryGesturePlaceholderIdentity;
    }
    return item.presentation.identity;
  }

  @Builder
  private buildEntryGestureSnapshot() {
    BrowserTabsSharedSnapshotOverlay({
      state: this.buildEntryGestureSnapshotPresentationState(),
      snapshotBackgroundColor: this.entrySharedSnapshotBackgroundColor,
      snapshotLayerZIndex: FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX,
      snapshotDecorationLayerZIndex: FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX,
      viewportLeft: this.resolveRootLeft(),
      viewportTop: this.resolveRootTop(),
      onSnapshotRectChange: (rect: BrowserTabsOverlayRect) => {
        this.onEntrySharedSnapshotRectChange(rect);
      },
      onSnapshotTap: (tabId: string) => {
        this.onEntrySharedSnapshotTap(tabId);
      }
    })
  }

  /**
   * The entry snapshot with the finger folded in: the whole card pans with the damped travel, and its
   * card end is scaled so pulling past it keeps shrinking the card. Scaling the *end* rectangles rather
   * than the painted frame is what lets the morph's own interpolation do the work — a pan applied to
   * both ends is a pan applied to every frame in between.
   */
  private buildEntryGestureSnapshotPresentationState(): BrowserTabsSharedSnapshotTransitionState {
    const base = this.entryGestureSnapshotState as BrowserTabsSharedSnapshotTransitionState;
    const target = this.entryGestureCardRect;
    return {
      phase: base.phase,
      direction: base.direction,
      tabId: base.tabId,
      // 1 puts the overlay's own frame exactly on `targetRect`: the pull's geometry is already the
      // interpolation, and running a second one over it is what made the shrink accelerate.
      progress: 1,
      sourceRect: target,
      targetRect: target,
      imageUri: base.imageUri,
      imagePixelMap: base.imagePixelMap,
      imageRevision: base.imageRevision,
      imageWidth: base.imageWidth,
      imageHeight: base.imageHeight,
      useFullWebSnapshot: base.useFullWebSnapshot,
      sourceImageTopInset: base.sourceImageTopInset,
      previewCornerRadius: base.previewCornerRadius,
      imageBlurRadius: base.imageBlurRadius,
      // Pulled open by a finger, this is a card from the first frame: it must not start square and
      // round off on the way, which is what the page-to-card morph does on its own.
      cornerRadiusFollowsProgress: false
    };
  }

  /** The tab the finger is holding: the one the entry morphs, or the active tab until that is known. */
  private resolveEntryGestureHeldTabId(): string {
    const base = this.entryGestureSnapshotState;
    if (base !== undefined) {
      return base.tabId;
    }
    const sceneState = this.entrySharedSnapshotState;
    return sceneState.tabId.trim().length > 0 ? sceneState.tabId : this.activeTabId.trim();
  }

  /**
   * The pull's page end, with the finger's travel already in it.
   *
   * The capture's own rectangle while it is there, and the visible web viewport before it lands: the row
   * has to be flat from the frame the drag is claimed, not from the frame the capture arrives, or the
   * deck is seen stacking up and then flattening again.
   */
  private resolveEntryGestureSourceRect(): BrowserTabsOverlayRect {
    const base = this.entryGestureSnapshotState;
    if (base !== undefined) {
      return this.panEntryGestureRect(base.sourceRect);
    }
    return this.panEntryGestureRect({
      left: this.resolveRootLeft() + this.viewportLeft,
      top: this.resolveRootTop() + this.viewportTop,
      width: Math.max(1, this.viewportWidth),
      height: Math.max(1, this.viewportHeight)
    });
  }

  /**
   * The card the finger is holding, as it is painted this frame.
   *
   * Both ends already carry the finger's travel, so interpolating between them is the whole gesture —
   * the row has nothing else moving it.
   */
  private resolveEntryGestureCardFrame(): BrowserTabsOverlayRect {
    return this.entryGestureCardRect;
  }

  private resolveEntryGestureDeckCardRect(scale: number): BrowserTabsOverlayRect {
    const heldTabId = this.resolveEntryGestureHeldTabId();
    const heldItem = this.deckItems.find(
      (candidate: BrowserTabsFloatingItem): boolean => candidate.id === heldTabId);
    if (heldItem === undefined) {
      return this.entryGestureCardRect;
    }
    const deck = this.stackLayoutPolicy.resolveCard(this.resolveDeckIndex(heldItem),
      this.horizontalDeckPosition, this.deckItems.length, this.layoutState.cardWidth);
    return this.scaleEntryGestureRectAboutCentre(this.buildDeckPreviewRect(deck), scale);
  }

  /** One interpolation from the page to the smallest card, eased, plus the finger's damped travel. */
  private resolveEntryGesturePulledRect(progress: number): BrowserTabsOverlayRect {
    const source = this.resolveEntryGestureSourceRect();
    const smallest = this.resolveEntryGestureDeckCardRect(
      BROWSER_TABS_OVERVIEW_ENTRY_GESTURE_MIN_CARD_RATIO);
    const eased = Math.max(0, Math.min(1, progress));
    return {
      left: source.left + (smallest.left - source.left) * eased,
      top: source.top + (smallest.top - source.top) * eased,
      width: source.width + (smallest.width - source.width) * eased,
      height: source.height + (smallest.height - source.height) * eased
    };
  }

  /**
   * Where a card sits while the finger is pulling the overview open.
   *
   * The tab order never changes — only the layout does. Every card is laid out flat, the same distance
   * apart and all at the held card's size, so what the pull shows is the whole row of tabs side by side
   * instead of the deck's stack, and it travels with the finger as one piece. Because each card's place
   * is measured from the held card's own frame, the row slides in from the screen edges as that card
   * shrinks, and the cards stay clear of each other instead of overlapping like the deck.
   *
   * The far end of the movement is the deck's own metrics, which is what a release blends into: every
   * card, in order, slides from its flat place into its slot in the stack.
   */
  private resolveEntryGestureCardMetrics(item: BrowserTabsFloatingItem): BrowserTabsOverviewStackCardMetrics {
    const index = this.resolveDeckIndex(item);
    const deck = this.stackLayoutPolicy.resolveCard(index, this.horizontalDeckPosition,
      this.deckItems.length, this.layoutState.cardWidth);
    const heldIndex = this.deckItems.findIndex(
      (candidate: BrowserTabsFloatingItem): boolean =>
        candidate.id === this.resolveEntryGestureHeldTabId());
    if (heldIndex < 0) {
      return deck;
    }
    if (index === heldIndex && this.entryGestureSnapshotState !== undefined) {
      // The card the finger holds is painted by the snapshot, so the deck hides its own copy.
      return {
        offsetX: deck.offsetX,
        offsetY: 0,
        scale: deck.scale,
        opacity: 0,
        titleOpacity: 0,
        shadeOpacity: 0,
        zIndex: deck.zIndex
      };
    }
    const frame = this.resolveEntryGestureCardFrame();
    const flatScale = Math.max(0.05, frame.width / Math.max(1, this.layoutState.cardWidth));
    const spacing = frame.width + FLOATING_TABS_ENTRY_GESTURE_ROW_GAP;
    const rowOffset = index - heldIndex;
    const flatPreviewCentreX = frame.left + frame.width / 2 + rowOffset * spacing;
    const flatOffsetX = flatPreviewCentreX - (this.resolveRootLeft() + this.resolveRootWidth() / 2);
    // Lined up with the held card, not with the deck's baseline: the card the finger pulls is on its
    // way down the screen, and the whole row has to travel with it.
    const padding = this.resolveHorizontalContentPadding();
    const deckCentreY = this.resolveRootTop() + padding.top +
      (this.resolveRootHeight() - padding.top - padding.bottom) / 2;
    const flatOffsetY = (frame.top + frame.height / 2) - deckCentreY -
      this.layoutState.identityHeaderHeight * flatScale / 2;
    const settle = Math.max(0, Math.min(1, this.entryGestureSettle));
    return {
      offsetX: flatOffsetX + (deck.offsetX - flatOffsetX) * settle,
      offsetY: flatOffsetY * (1 - settle),
      scale: flatScale + (deck.scale - flatScale) * settle,
      // Flat cards all stand on their own, so every one of them shows a title; the deck only shows the
      // ones near the focus. Blending instead of switching is what stops the whole row lighting its
      // titles up and then dropping them the frame the deck takes over.
      opacity: 1 + (deck.opacity - 1) * settle,
      titleOpacity: 1 + (deck.titleOpacity - 1) * settle,
      // Flat cards are not stacked, so nothing casts the deck's depth shading either.
      shadeOpacity: deck.shadeOpacity * settle,
      zIndex: deck.zIndex
    };
  }

  private panEntryGestureRect(rect: BrowserTabsOverlayRect): BrowserTabsOverlayRect {
    return {
      left: rect.left + this.entryGesturePanX,
      top: rect.top + this.entryGesturePanY,
      width: rect.width,
      height: rect.height
    };
  }

  private scaleEntryGestureRectAboutCentre(rect: BrowserTabsOverlayRect, scale: number): BrowserTabsOverlayRect {
    const safeScale = Number.isFinite(scale) ? Math.max(0.1, Math.min(1, scale)) : 1;
    const width = Math.max(1, rect.width * safeScale);
    const height = Math.max(1, rect.height * safeScale);
    return {
      left: rect.left + (rect.width - width) / 2,
      top: rect.top + (rect.height - height) / 2,
      width: width,
      height: height
    };
  }

  /** Keep the last usable entry snapshot, because the scene drops it as soon as the entry settles. */
  private handleEntrySharedSnapshotChanged(): void {
    const state = this.entrySharedSnapshotState;
    if (state.direction !== 'enter') {
      return;
    }
    if (state.imageUri.trim().length <= 0 && state.imagePixelMap === undefined) {
      return;
    }
    this.entryGestureSnapshotState = state;
  }

  private handleEntryGestureOffsetsChanged(): void {
    if (!this.entryGestureActive) {
      return;
    }
    this.applyEntryGestureLayout();
  }

  private applyEntryGestureLayout(): void {
    const layout = this.entryGesturePolicy.resolveLayout({
      offsetX: this.entryGestureOffsetX,
      offsetY: this.entryGestureOffsetY,
      viewportWidth: this.resolveRootWidth(),
      viewportHeight: this.resolveRootHeight()
    });
    this.entryGesturePanX = layout.panX;
    this.entryGesturePanY = layout.panY;
    this.entryGestureCardRect = this.panEntryGestureRect(
      this.resolveEntryGesturePulledRect(layout.progress));
  }

  private handleEntryGestureActiveChanged(): void {
    if (this.entryGestureActive) {
      this.entryGestureSettling = false;
      this.entryGestureSettle = 0;
      this.applyEntryGestureLayout();
      return;
    }
    if (this.entryGestureSnapshotState === undefined) {
      return;
    }
    if (this.resolveEntryGestureLayoutSettled()) {
      this.entryGestureSettling = false;
      return;
    }
    // The finger let go: the held card finishes shrinking into the deck's card and the two cards
    // beside it slide into the slots the deck already has for them, so the release reads as the row
    // being dealt into the stack rather than the screen switching.
    this.entryGestureSettling = true;
    animateTo({
      // The same spring the deck uses when it settles: a flat ease-out over a fifth of a second read as
      // the row being snapped into place rather than landing.
      duration: ENTRY_GESTURE_SETTLE_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardEntryCurve(),
      onFinish: () => {
        this.entryGestureSettling = false;
        // The deck owns every card from here; a stale copy would flash the old page at the next pull.
        this.entryGestureSnapshotState = undefined;
      }
    }, () => {
      // Straight onto the deck's own card rectangle: one move, so the card lands where the stack
      // expects it instead of growing and then being replaced by something else.
      this.entryGestureCardRect = this.resolveEntryGestureDeckCardRect(1);
      this.entryGesturePanX = 0;
      this.entryGesturePanY = 0;
      this.entryGestureSettle = 1;
    });
  }

  private resolveEntryGestureLayoutSettled(): boolean {
    const deck = this.resolveEntryGestureDeckCardRect(1);
    return Math.abs(this.entryGestureCardRect.width - deck.width) < 0.5 &&
      Math.abs(this.entryGestureCardRect.left - deck.left) < 0.5 &&
      Math.abs(this.entryGestureCardRect.top - deck.top) < 0.5 &&
      Math.abs(this.entryGesturePanX) < 0.5 && Math.abs(this.entryGesturePanY) < 0.5;
  }

  @Builder
  private buildGridCardsLayer() {
    Grid(this.scroller) {
      ForEach(this.resolveVisibleItems(), (item: BrowserTabsFloatingItem) => {
        GridItem() {
          this.buildCard(item)
        }
        .height(this.layoutState.itemHeight)
      }, (item: BrowserTabsFloatingItem) => this.resolveCardIdentityKey(item))

      ForEach(this.buildBlankSlotKeys(), (_key: string) => {
        this.buildBlankGridItem()
      }, (key: string) => key)
    }
    .width('100%')
    .height('100%')
    .columnsTemplate(this.layoutState.columnsTemplate)
    .columnsGap(FLOATING_TABS_GRID_GAP)
    .rowsGap(FLOATING_TABS_GRID_GAP)
    .cachedCount(8)
    .padding({
      left: FLOATING_TABS_HORIZONTAL_PADDING,
      right: FLOATING_TABS_HORIZONTAL_PADDING,
      top: this.resolveContentTopPadding(),
      bottom: this.resolveContentBottomPadding()
    })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
      HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
  }

  // Each tab has one render node. Fixed index order matches StackSwipe, so a trailing card
  // covers a leading one throughout the drag; no layer swaps at rounded-index boundaries.
  //
  // Card slots are doubled so the entering morph can hold a slot of its own strictly between the
  // covered card and its successor, instead of being one more layer painted above the whole deck.
  @Builder
  private buildHorizontalCardsLayer() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(this.resolveDeckItems(), (item: BrowserTabsFloatingItem) => {
        this.buildDeckCard(item)
      }, (item: BrowserTabsFloatingItem) => this.resolveCardIdentityKey(item))

      this.buildDeckEntryMorphSlot()
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.resolveHorizontalContentPadding().top,
      bottom: this.resolveHorizontalContentPadding().bottom
    })
    // Clip stays on for ordinary deck motion so peeking cards don't paint past the sheet. It drops
    // only while a card is in a vertical dismiss flight, otherwise the fly-out is cut at the stack
    // edge and reads as an instant vanish.
    .clip(this.deckSwipeTabId.length <= 0)
    .hitTestBehavior(this.canInteractWithDeck() ? HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal,
        distance: HORIZONTAL_DECK_DRAG_START_DISTANCE })
        .onActionStart(() => {
          this.beginDeckDrag();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateDeckDrag(event.offsetX);
        })
        .onActionEnd((event: GestureEvent) => {
          this.endDeckDrag(event.velocityX);
        })
        .onActionCancel(() => {
          this.cancelDeckDrag();
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildDeckCard(item: BrowserTabsFloatingItem) {
    Stack({ alignContent: Alignment.Center }) {
      this.buildCard(item)
    }
    .width(this.layoutState.cardWidth)
    .height(this.resolveItemHeight())
    .translate({
      x: this.resolveDeckMetrics(item).offsetX,
      y: this.resolveDeckMetrics(item).offsetY
    })
    .scale({ x: this.resolveDeckMetrics(item).scale, y: this.resolveDeckMetrics(item).scale })
    .opacity(item.id === this.deckDismissGhostTabId ? 0 : this.resolveDeckMetrics(item).opacity)
    .zIndex(this.resolveDeckCardLayerZIndex(item))
    .hitTestBehavior(this.resolveDeckMetrics(item).opacity > 0 && item.id !== this.deckDismissGhostTabId ?
      HitTestMode.Default : HitTestMode.None)
  }

  /**
   * Draw order by slot, doubled so the entering morph owns the odd slot between two cards.
   *
   * The card that is leaving takes the top slot: it is on its way out over the cards that are
   * closing the gap behind it, and it must not trade places with them mid-flight.
   */
  private resolveDeckCardLayerZIndex(item: BrowserTabsFloatingItem): number {
    if (item.id === this.deckDismissGhostTabId) {
      return (this.deckItems.length + 1) * 2;
    }
    return this.resolveDeckIndex(item) * 2;
  }

  /**
   * The slot the entering morph plays in while it settles into the covered card.
   *
   * It is held to the covered card's own stacking slot, one level under the cards that trail it, so
   * those cards stay in front of the snapshot for the whole entry and the handover has nothing left
   * to reorder. The holder stays mounted even while it is empty: changing the deck's child list
   * mid-entry would re-run the deck layout and re-measure every card beside the morph.
   */
  @Builder
  private buildDeckEntryMorphSlot() {
    Stack() {
      if (this.shouldMountSharedSnapshotInDeck()) {
        this.buildSharedSnapshotOverlay(true)
      }
    }
    .width('100%')
    .height(this.resolveRootHeight())
    // `position()` resolves against the parent's content box, so the holder is pulled back out of
    // the deck's vertical padding and the morph keeps addressing root coordinates.
    .position({ x: 0, y: -this.resolveHorizontalContentPadding().top })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(this.resolveDeckEntryMorphLayerZIndex())
  }

  @Builder
  private buildBlankGridItem() {
    GridItem() {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .onClick(() => {
          if (this.interactionEnabled && !this.closeAllExitActive) {
            this.onDismiss();
          }
        })
    }
    .height(this.layoutState.itemHeight)
  }

  @Builder
  private buildCard(item: BrowserTabsFloatingItem) {
    BrowserTabOverviewItem({
      tab: item.tab,
      presentation: item.presentation,
      snapshotImageUri: item.presentation.preview.sharedSnapshotImageUri,
      snapshotPixelMap: item.presentation.preview.sharedSnapshotPixelMap,
      snapshotAspectFitEnabled: this.isHorizontalCardsLayout(),
      snapshotCoverEnabled: this.isHorizontalCardsLayout(),
      deckShadeOpacity: this.isHorizontalCardsLayout() ? this.resolveDeckMetrics(item).shadeOpacity : 0,
      previewHeight: this.layoutState.previewHeight,
      cardWidth: this.layoutState.cardWidth,
      identityHeaderHeight: this.layoutState.identityHeaderHeight,
      identityPreviewGap: this.layoutState.identityPreviewGap,
      tabTranslateX: this.resolveCardTranslateX(item),
      tabTranslateY: this.resolveCardTranslateY(item),
      tabScale: this.resolveCardScale(item),
      tabOpacity: this.resolveCardOpacity(item),
      identityOpacity: this.resolveIdentityMotion(item).opacity *
        (this.isHorizontalCardsLayout() ? this.resolveDeckMetrics(item).titleOpacity : 1),
      identityTranslateY: this.resolveIdentityMotion(item).translateY,
      previewCardOpacity: 1,
      snapshotImageOpacity: 1,
      decorationOpacity: 1,
      coveredByMorph: this.shouldHideCardSurfaceUnderMorph(item.tab.id),
      tabEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive &&
        !this.isSelectionDisplacementActive() && !this.isEntryDisplacementActive() &&
        !this.isMorphCoveredTab(item.tab.id),
      trackPreviewRectChanges: true,
      motionDurationMs: this.resolveCardMotionDurationMs(),
      motionCurve: this.resolveCardMotionCurve(),
      motionDelayMs: this.resolveCardMotionDelayMs(this.resolveDeckIndex(item)),
      entryMountAnimationEnabled: this.shouldRunLateMountEntryAnimation(item),
      entryMountOffsetX: this.resolveLateMountEntryOffsetX(item),
      entryMountDurationMs: this.animationViewModel.getFloatingCardEntryDurationMs(),
      entryMountCurve: this.animationViewModel.getFloatingCardEntryCurve(),
      entryMountDelayMs: this.resolveCardMotionDelayMs(this.resolveDeckIndex(item)),
      swipeDismissThreshold: this.resolveSwipeDismissThreshold(),
      swipeFlyoutOffset: this.isHorizontalCardsLayout() ? this.resolveRootHeight() : this.resolveRootWidth(),
      swipeDismissMode: this.layoutState.layoutStyle === 'horizontal_cards' ? 'upward' : 'horizontal',
      closeButtonEnabled: true,
      closeButtonAlwaysVisible: this.storedTabsOverviewCloseButtonAlwaysVisible,
      onCloseTab: (tabId: string) => {
        this.closeTabFromOverlay(tabId);
      },
      onSwipeStart: (tabId: string) => {
        if (this.isHorizontalCardsLayout()) {
          // The card's vertical gesture claimed the touch, so the deck's horizontal one is over.
          this.abortDeckMotion();
          this.deckSwipeTabId = tabId;
        }
      },
      onSwipeCancel: (_tabId: string) => {
        this.deckSwipeTabId = '';
      },
      onSwipeEnd: (tabId: string, _offsetX: number, _direction: number) => {
        this.deckSwipeTabId = '';
        this.closeTabFromOverlay(tabId);
      },
      onSwipeThresholdReached: (_tabId: string) => {
        this.performSwipeThresholdFeedback();
      },
      onSelect: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => {
        this.selectOverviewTab(tabId, rect);
      },
      onPreviewRectChange: (tabId: string, left: number, top: number, width: number, height: number) => {
        this.handlePreviewRectChange(tabId, left, top, width, height);
      }
    })
    .width(this.resolveCardWidth())
    .height(this.resolveItemHeight())
  }

  private startEntryAnimation(): void {
    this.clearEntryAnimationTimer();
    if (!this.sideEntryAnimationEnabled) {
      this.entryProgress = 1;
      return;
    }
    this.entryAnimationTimer = setTimeout(() => {
      this.entryAnimationTimer = 0;
      if (this.exiting) {
        return;
      }
      this.startLateMountEntryAnimationWindow();
      animateTo({
        duration: this.animationViewModel.getFloatingCardEntryDurationMs(),
        curve: this.animationViewModel.getFloatingCardEntryCurve()
      }, () => {
        this.entryProgress = 1;
      });
    }, FLOATING_TABS_ENTRY_START_DELAY_MS);
  }

  private prepareBottomEntryAnimation(): void {
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (this.exiting) {
        return;
      }
      this.positionCardsForCurrentSection();
      this.startEntryAnimation();
    }, FLOATING_TABS_BOTTOM_POSITION_DELAY_MS);
  }

  private prepareSectionSwitchPosition(): void {
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (this.exiting || this.closeAllExitActive) {
        return;
      }
      this.positionCardsForCurrentSection();
    }, FLOATING_TABS_BOTTOM_POSITION_DELAY_MS);
  }

  private positionCardsForCurrentSection(): void {
    if (this.shouldPrepareEntryTarget()) {
      this.scrollToEntryTargetForEntry();
      return;
    }
    this.scrollToBottomForEntry();
  }

  private scrollToEntryTargetForEntry(): void {
    this.beginEntryTargetPreparationIfNeeded();
    const targetTabId = this.resolveEntryTargetTabId();
    if (targetTabId.length <= 0) {
      this.resetEntryTargetPreparation();
      this.scrollToBottomForEntry();
      return;
    }
    const targetIndex = this.resolveDisplacementTargetIndex(targetTabId);
    if (targetIndex < 0) {
      this.resetEntryTargetPreparation();
      this.scrollToBottomForEntry();
      return;
    }
    this.entryTargetPreparationState = this.entryTargetCoordinator.discardPreviewRect(
      this.entryTargetPreparationState,
      targetTabId
    );
    this.entryTargetPreparationState = this.entryTargetCoordinator.markScrollIssued(
      this.entryTargetPreparationState,
      targetTabId,
      this.entryTargetCoordinator.resolveCurrentRectGeneration(this.entryTargetPreparationState)
    );
    if (this.isHorizontalCardsLayout()) {
      this.seedDeckPosition(targetIndex);
    } else {
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.CENTER);
    }
    this.scheduleEntryTargetReady(targetTabId, 0, this.entryTargetPreparationState.version);
  }

  private scrollToBottomForEntry(): void {
    const lastItemIndex = this.resolveVisibleItems().length - 1;
    if (lastItemIndex < 0) {
      return;
    }
    if (this.isHorizontalCardsLayout()) {
      // The deck has no scroll position to restore, so opening on a tab means placing the deck on
      // that tab. When the active tab is not in the selected section there is nothing to centre
      // on, and the last card is the honest default.
      const activeTabIndex = this.resolveDisplacementTargetIndex(this.activeTabId);
      this.seedDeckPosition(activeTabIndex >= 0 ? activeTabIndex : lastItemIndex);
      return;
    }
    this.scroller.scrollToIndex(lastItemIndex, false, ScrollAlign.END);
  }

  private clearBottomScrollTimer(): void {
    if (this.bottomScrollTimer !== 0) {
      clearTimeout(this.bottomScrollTimer);
      this.bottomScrollTimer = 0;
    }
  }

  private clearEntryAnimationTimer(): void {
    if (this.entryAnimationTimer !== 0) {
      clearTimeout(this.entryAnimationTimer);
      this.entryAnimationTimer = 0;
    }
  }

  private clearEntryTargetReadyTimer(): void {
    if (this.entryTargetReadyTimer !== 0) {
      clearTimeout(this.entryTargetReadyTimer);
      this.entryTargetReadyTimer = 0;
    }
  }

  private startLateMountEntryAnimationWindow(): void {
    this.clearLateMountEntryAnimationTimer();
    this.lateMountEntryAnimationEnabled = true;
    this.lateMountEntryAnimationTimer = setTimeout(() => {
      this.lateMountEntryAnimationTimer = 0;
      this.lateMountEntryAnimationEnabled = false;
    }, this.resolveLateMountEntryAnimationWindowMs());
  }

  private clearLateMountEntryAnimationTimer(): void {
    if (this.lateMountEntryAnimationTimer !== 0) {
      clearTimeout(this.lateMountEntryAnimationTimer);
      this.lateMountEntryAnimationTimer = 0;
    }
    this.lateMountEntryAnimationEnabled = false;
  }

  private syncEntryDisplacementFromProps(): void {
    if (this.shouldApplyEntryGestureLayout()) {
      // The pull lays every card out itself, flat and in order. The entry's own per-card fly-in is a
      // second, independent offset on the same cards: it would shift the flat row while the finger
      // holds it and then snap back when the entry finished, which is the jump seen on release.
      this.entryDisplacementProgress = 1;
      return;
    }
    if (!this.isEntryDisplacementActive()) {
      this.entryDisplacementTargetId = '';
      this.entryDisplacementProgress = 1;
      this.resetEntryTargetPreparation();
      return;
    }
    const targetTabId = this.entryDisplacementTabId.trim();
    if (this.entryDisplacementTargetId !== targetTabId) {
      this.entryDisplacementTargetId = targetTabId;
      this.entryDisplacementProgress = 0;
      this.resetEntryTargetPreparation();
      this.beginEntryTargetPreparationIfNeeded();
      this.prepareBottomEntryAnimation();
    }
    if (!this.entryDisplacementSettlingEnabled) {
      // An in-flight value is the settle-watch race: settlingEnabled can drop one @Watch
      // before the tab id clears. Leave it alone. Anything else (including a leftover 1)
      // snaps to the origin; motion duration is 0 here, so this is not a visible fly-out.
      if (this.entryDisplacementProgress > 0 && this.entryDisplacementProgress < 1) {
        return;
      }
      this.entryDisplacementProgress = 0;
      return;
    }
    if (this.entryDisplacementProgress >= 1) {
      return;
    }
    animateTo({
      duration: this.animationViewModel.getSharedSnapshotEnterDurationMs(),
      curve: this.animationViewModel.getSharedSnapshotEnterCurve()
    }, () => {
      this.entryDisplacementProgress = 1;
    });
  }

  private switchSection(section: BrowserTabsOverviewSection): void {
    if (this.closeAllExitActive) {
      return;
    }
    if (this.selectedSection === section) {
      this.onSwitchSectionHome(section);
      return;
    }
    this.stopDeckMotion();
    this.deckPositionSeeded = false;
    this.selectedSection = section;
    this.onActiveSectionChange(section);
    this.syncSiteIcons();
    this.clearEntryAnimationTimer();
    this.clearLateMountEntryAnimationTimer();
    this.entryProgress = 1;
    this.removalState = this.shadowViewModel.buildInitialLocalRemovalState();
    this.refreshDeckPresentation();
    this.positionCardsForCurrentSection();
    this.prepareSectionSwitchPosition();
  }

  private returnToEntryTab(): void {
    const state = this.buildBottomChromeState();
    if (state.returnKind === 'tab' && state.returnTabId.length > 0) {
      this.selectOverviewTab(state.returnTabId);
      return;
    }
    this.onDismiss();
  }

  private buildBottomChromeState(): BrowserTabsOverviewBottomChromeState {
    return this.bottomChromeViewModel.buildState({
      tabs: this.tabs,
      locallyRemovedTabIds: this.removalState.locallyRemovedTabIds,
      entryTabId: this.entryReturnTabId,
      activeTabId: this.activeTabId
    });
  }

  private closeTabFromOverlay(tabId: string): void {
    if (!this.interactionEnabled || this.exiting || this.closeAllExitActive ||
      tabId.trim().length <= 0 || this.isLocallyRemovedTab(tabId)) {
      return;
    }
    if (this.isHorizontalCardsLayout()) {
      this.beginDeckDismiss(tabId);
      return;
    }
    animateTo({
      duration: FLOATING_TABS_REORDER_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardEntryCurve()
    }, () => {
      this.removalState = this.shadowViewModel.markLocalRemoval(this.removalState, tabId);
    });
    this.onCloseTab(tabId);
  }

  private performSwipeThresholdFeedback(): void {
    BrowserTabsOverviewSwipeFeedbackService.performThresholdFeedback();
  }

  private startCloseAllTabsAnimationFromRequest(): void {
    const requestVersion = Math.max(0, Math.floor(this.closeAllTabsAnimationRequestVersion));
    if (requestVersion <= 0 || requestVersion === this.handledCloseAllRequestVersion) {
      return;
    }
    this.stopDeckMotion();
    this.handledCloseAllRequestVersion = requestVersion;
    const tabIds = this.resolveSelectedSectionVisibleTabIds();
    if (tabIds.length <= 0) {
      this.onCloseAllAnimationFinished();
      return;
    }
    animateTo({
      duration: FLOATING_TABS_EXIT_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardExitCurve(),
      onFinish: () => {
        if (this.handledCloseAllRequestVersion !== requestVersion) {
          return;
        }
        this.scheduleCloseAllCommit(requestVersion);
      }
    }, () => {
      this.closeAllExitActive = true;
    });
  }

  private resolveSelectedSectionVisibleTabIds(): string[] {
    const visibleTabs = this.sectionPolicy.resolveTabsForSection(this.tabs, this.selectedSection);
    const tabIds: string[] = [];
    for (let index = 0; index < visibleTabs.length; index += 1) {
      const tabId = visibleTabs[index].id;
      if (!this.isLocallyRemovedTab(tabId)) {
        tabIds.push(tabId);
      }
    }
    return tabIds;
  }

  private isSelectedSectionEmpty(): boolean {
    // The deck already holds its item list; rebuilding every presentation here would run on every
    // animation frame, because `horizontalDeckPosition` is a `@State` the deck writes each frame.
    if (this.isHorizontalCardsLayout()) {
      return this.deckItems.length <= 0;
    }
    return this.resolveVisibleItems().length <= 0;
  }

  private shouldAllowEmptyDismiss(): boolean {
    return !this.exiting && !this.closeAllExitActive;
  }

  private scheduleCloseAllCommit(requestVersion: number): void {
    this.clearCloseAllCommitTimer();
    this.closeAllCommitTimer = setTimeout(() => {
      this.closeAllCommitTimer = 0;
      if (this.handledCloseAllRequestVersion !== requestVersion) {
        return;
      }
      this.onCloseAllAnimationFinished();
    }, FLOATING_TABS_CLOSE_ALL_COMMIT_DELAY_MS);
  }

  private clearCloseAllCommitTimer(): void {
    if (this.closeAllCommitTimer === 0) {
      return;
    }
    clearTimeout(this.closeAllCommitTimer);
    this.closeAllCommitTimer = 0;
  }

  private resolveVisibleItems(): BrowserTabsFloatingItem[] {
    const previews = this.buildPreviewMap();
    const visibleTabs = this.sectionPolicy.resolveTabsForSection(this.tabs, this.selectedSection);
    const items: BrowserTabsFloatingItem[] = [];
    for (let index = 0; index < visibleTabs.length; index += 1) {
      const tab = visibleTabs[index];
      if (this.isLocallyRemovedTab(tab.id)) {
        continue;
      }
      items.push({
        id: tab.id,
        tab: tab,
        presentation: this.overlayViewModel.buildItemPresentation(
          tab,
          previews[tab.id],
          this.resolveSiteIconState(tab.id),
          this.blurPrivateTabPreviews
        ),
        index: items.length
      });
    }
    return items;
  }

  // A card is keyed by more than the tab id: while the tab stays the same, the
  // preview moves from "no image yet" to "snapshot ready" a moment later when the
  // entry capture lands. ArkUI does not rebuild an item whose key is unchanged, so
  // keying on the id alone left the already-built card on its pending placeholder
  // forever. Including the image identity re-creates the card when the snapshot
  // arrives.
  private resolveCardIdentityKey(item: BrowserTabsFloatingItem): string {
    const preview = item.presentation.preview;
    const uri = preview.sharedSnapshotImageUri.trim();
    const hasPixelMap = preview.sharedSnapshotPixelMap !== undefined;
    return `${item.id}|${preview.previewKind}|${uri.length > 0 ? uri : (hasPixelMap ? 'pm' : 'none')}`;
  }

  private isLocallyRemovedTab(tabId: string): boolean {
    return this.shadowViewModel.isLocallyRemoved(this.removalState, tabId);
  }

  private syncLocalRemovalStateFromTabs(): void {
    this.removalState = this.shadowViewModel.reconcileLocalRemovalState(this.removalState, this.tabs);
  }

  private handleTabsChanged(): void {
    this.syncLocalRemovalStateFromTabs();
    this.refreshDeckPresentation();
    this.syncSiteIcons();
  }

  private syncSiteIcons(): void {
    this.overlayViewModel.syncIdentityIcons(
      (): BrowserTabsOverviewIdentityIconSnapshot => this.buildIdentityIconSnapshot(),
      (states: SiteIconListRenderState[]): void => {
        this.siteIconStates = states;
      }
    );
  }

  private buildIdentityIconSnapshot(): BrowserTabsOverviewIdentityIconSnapshot {
    return {
      tabs: this.tabs,
      section: this.selectedSection,
      iconStates: this.siteIconStates
    };
  }

  private resolveSiteIconState(tabId: string): SiteIconListRenderState | undefined {
    return this.overlayViewModel.resolveIdentityIconState(this.siteIconStates, tabId);
  }

  private buildPreviewMap(): Record<string, BrowserTabPreviewState | undefined> {
    const previewByTabId: Record<string, BrowserTabPreviewState | undefined> = {};
    for (const state of this.previewStates) {
      if (state.tabId.trim().length <= 0) {
        continue;
      }
      previewByTabId[state.tabId] = state;
    }
    return previewByTabId;
  }

  private handlePreviewRectChange(tabId: string, left: number, top: number, width: number, height: number): void {
    // `onAreaChange` reports layout bounds, which ignore the deck's per-card translate and scale;
    // every deck card would report the same centred rectangle. The same geometry that paints the
    // card supplies the rect instead, so the entry morph and the remembered rect stay honest.
    let rect: BrowserTabsOverlayRect;
    const deckRect = this.isHorizontalCardsLayout() ? this.resolveDeckPreviewRect(tabId) : undefined;
    if (deckRect !== undefined) {
      rect = deckRect;
    } else {
      rect = { left: left, top: top, width: width, height: height };
    }
    const recordResult: BrowserTabsFloatingEntryTargetRecordedRectResult =
      this.entryTargetCoordinator.recordPreviewRect(this.entryTargetPreparationState, tabId, rect);
    this.entryTargetPreparationState = recordResult.state;
    if (recordResult.measuredResult.ready) {
      this.publishEntryTargetReady(tabId, recordResult.rect, recordResult.measuredResult);
      return;
    }
    if (recordResult.shouldDefer) {
      if (recordResult.shouldScheduleReady) {
        this.scheduleEntryTargetReady(tabId, 0, recordResult.state.version);
      }
      return;
    }
    this.onPreviewRectChange(tabId, left, top, width, height);
  }

  private scheduleEntryTargetReady(tabId: string, attempt: number, version: number): void {
    this.clearEntryTargetReadyTimer();
    const delayMs = attempt <= 0 ? FLOATING_TABS_ENTRY_TARGET_READY_DELAY_MS : FLOATING_TABS_ENTRY_TARGET_READY_RETRY_MS;
    this.entryTargetReadyTimer = setTimeout(() => {
      this.entryTargetReadyTimer = 0;
      this.publishEntryTargetReadyOrRetry(tabId, attempt, version);
    }, delayMs);
  }

  private publishEntryTargetReadyOrRetry(tabId: string, attempt: number, version: number): void {
    if (!this.shouldPrepareEntryTarget()) {
      return;
    }
    const attemptResult: BrowserTabsFloatingEntryTargetReadyAttemptResult =
      this.entryTargetCoordinator.resolveReadyAttempt({
        state: this.entryTargetPreparationState,
        tabId: tabId,
        version: version,
        targetTabId: this.resolveEntryTargetTabId(),
        predictedRect: this.buildPredictedEntryTargetPreviewRect(tabId),
        attempt: attempt,
        maxAttempts: FLOATING_TABS_ENTRY_TARGET_READY_MAX_ATTEMPTS
      });
    this.entryTargetPreparationState = attemptResult.state;
    if (attemptResult.action === 'publish' && attemptResult.rect !== undefined) {
      const resolvedResult: BrowserTabsFloatingEntryTargetResolvedRectResult = {
        state: attemptResult.state,
        ready: true
      };
      this.publishEntryTargetReady(tabId, attemptResult.rect, resolvedResult);
      return;
    }
    if (attemptResult.action === 'retry') {
      this.scheduleEntryTargetReady(tabId, attemptResult.nextAttempt, version);
    }
  }

  private publishEntryTargetReady(
    tabId: string,
    rect: BrowserTabsOverlayRect,
    result: BrowserTabsFloatingEntryTargetResolvedRectResult
  ): void {
    this.entryTargetPreparationState = result.state;
    this.clearEntryTargetReadyTimer();
    this.onPreviewRectChange(tabId, rect.left, rect.top, rect.width, rect.height);
    this.onEntryTargetPreviewRectReady(tabId, rect.left, rect.top, rect.width, rect.height);
  }

  private resetEntryTargetPreparation(): void {
    this.entryTargetPreparationState = this.entryTargetCoordinator.cancel(this.entryTargetPreparationState);
    this.clearEntryTargetReadyTimer();
  }

  private beginEntryTargetPreparationIfNeeded(): void {
    if (!this.shouldPrepareEntryTarget()) {
      return;
    }
    this.entryTargetPreparationState = this.entryTargetCoordinator.beginPreparation(
      this.entryTargetPreparationState,
      this.resolveEntryTargetTabId()
    );
  }

  private buildPredictedEntryTargetPreviewRect(tabId: string): BrowserTabsOverlayRect | undefined {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return undefined;
    }
    const visibleTabIds = this.resolveVisibleTabIds();
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      if (visibleTabIds.indexOf(targetTabId) < 0) {
        return undefined;
      }
      // Same geometry that paints the focused card, including its 0.98 rest scale. The unscaled
      // layout slot was ~2% larger, so the morph landed full-size and the real card then shrank.
      const deckRect = this.resolveDeckPreviewRect(targetTabId);
      if (deckRect !== undefined) {
        return deckRect;
      }
      return this.buildDeckPreviewRect(this.stackLayoutPolicy.resolveCard(
        0, 0, 1, this.layoutState.cardWidth));
    }
    const columnCount = Math.max(1, Math.floor(this.layoutState.columnCount));
    const slotCount = visibleTabIds.length + this.resolveBlankSlotCount(columnCount, visibleTabIds.length);
    const rectInput: BrowserTabsFloatingEntryTargetRectInput = {
      tabIds: visibleTabIds,
      tabId: targetTabId,
      slotCount: slotCount,
      viewportLeft: this.resolveRootLeft(),
      viewportTop: this.resolveRootTop(),
      viewportHeight: this.resolveRootHeight(),
      horizontalPadding: FLOATING_TABS_HORIZONTAL_PADDING,
      topPadding: this.resolveContentTopPadding(),
      bottomPadding: this.resolveContentBottomPadding(),
      columnCount: columnCount,
      cardWidth: this.layoutState.cardWidth,
      previewHeight: this.layoutState.previewHeight,
      previewTopInset: this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap,
      itemHeight: this.layoutState.itemHeight,
      gridGap: FLOATING_TABS_GRID_GAP
    };
    const rect = this.entryTargetCoordinator.resolvePredictedCenteredPreviewRect(rectInput);
    if (rect === undefined) {
      return undefined;
    }
    return {
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height
    };
  }

  private syncLayoutState(): void {
    const width = this.resolveRootWidth();
    const height = this.resolveRootHeight();
    const nextState = this.layoutViewModel.buildState({
      gridWidth: Math.max(1, width - FLOATING_TABS_HORIZONTAL_PADDING * 2),
      sheetWidth: width,
      sheetHeight: height,
      layoutStyle: this.storedTabsOverviewLayoutStyle
    });
    // onAreaChange calls this on every layout pass. Re-assigning an equal @State
    // object forces another grid re-render, so keep the current object when the
    // resolved geometry is unchanged.
    if (isSameTabsOverviewLayoutState(this.layoutState, nextState)) {
      return;
    }
    this.layoutState = nextState;
    if (nextState.layoutStyle === 'horizontal_cards') {
      // The deck needs its own item list and a starting card as soon as the style is known.
      this.ensureDeckPositionForCurrentSection();
    } else {
      this.deckPositionSeeded = false;
    }
  }

  /**
   * Build the deck's item list and, once per entry, place it on the tab the overlay opened for.
   * Called from both `initializeForOpen` and `syncLayoutState`, because either can be the first to
   * observe the horizontal style.
   */
  private ensureDeckPositionForCurrentSection(): void {
    if (!this.isHorizontalCardsLayout()) {
      return;
    }
    this.refreshDeckPresentation();
    if (this.deckPositionSeeded || this.deckItems.length <= 0) {
      return;
    }
    const targetId = this.shouldPrepareEntryTarget() ? this.resolveEntryTargetTabId() : this.activeTabId;
    const target = this.deckItems.findIndex((item: BrowserTabsFloatingItem): boolean => item.id === targetId);
    this.seedDeckPosition(target >= 0 ? target : Math.max(0, this.deckItems.length - 1));
  }

  private handleStoredTabsOverviewLayoutStyleChanged(): void {
    const previousStyle = this.layoutState.layoutStyle;
    this.deckPositionSeeded = false;
    this.syncLayoutState();
    if (previousStyle === this.layoutState.layoutStyle) {
      return;
    }
    this.stopDeckMotion();
    this.refreshDeckPresentation();
    this.positionCardsForCurrentSection();
    this.entryTargetPreparationState =
      this.entryTargetCoordinator.clearPreviewRectCache(this.entryTargetPreparationState);
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (!this.exiting) {
        // Re-enters the same entry-target-aware path instead of forcing the deck onto the active
        // tab, which would drop an in-flight entry target.
        this.positionCardsForCurrentSection();
      }
    }, FLOATING_TABS_BOTTOM_POSITION_DELAY_MS);
  }

  private resolveCardTranslateX(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 0;
    }
    if (this.isSelectionDisplacementActive()) {
      return this.resolveSelectionDisplacement(item).x;
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      return this.resolveEntryDisplacement(item).x * (1 - this.resolveEntryDisplacementProgress());
    }
    if (this.exiting || this.closeAllExitActive) {
      return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item));
    }
    const homeExitProgress = this.resolveHomeExitProgress();
    if (homeExitProgress > 0) {
      return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item)) * homeExitProgress;
    }
    if (!this.sideEntryAnimationEnabled) {
      return 0;
    }
    const progress = this.resolveSurfaceProgress();
    return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item)) * (1 - progress);
  }

  private resolveCardTranslateY(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 0;
    }
    if (this.isSelectionDisplacementActive()) {
      return this.resolveSelectionDisplacement(item).y;
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      return this.resolveEntryDisplacement(item).y * (1 - this.resolveEntryDisplacementProgress());
    }
    if (this.exiting || this.closeAllExitActive) {
      return 0;
    }
    return 0;
  }

  private resolveCardScale(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 1;
    }
    if (this.isSelectionDisplacementActive()) {
      return 0.98;
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 1;
    }
    if (this.exiting || this.closeAllExitActive) {
      return 0.96;
    }
    const homeExitProgress = this.resolveHomeExitProgress();
    if (homeExitProgress > 0) {
      return 1 - (1 - 0.96) * homeExitProgress;
    }
    return 0.98 + this.resolveSurfaceProgress() * 0.02;
  }

  private resolveCardOpacity(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 1;
    }
    return 1 - this.resolveHomeExitProgress();
  }

  private resolveIdentityMotion(item: BrowserTabsFloatingItem): BrowserTabsOverviewIdentityMotionState {
    return this.animationViewModel.buildIdentityMotionState({
      coveredByMorph: this.isMorphCoveredTab(item.tab.id),
      transitionMounted: this.entrySharedSnapshotMounted &&
        this.entrySharedSnapshotState.tabId === item.tab.id,
      direction: this.entrySharedSnapshotState.direction,
      progress: this.entrySharedSnapshotState.progress
    });
  }

  private resolveCardMotionDurationMs(): number {
    if (this.isSelectionDisplacementActive()) {
      return this.animationViewModel.getSharedSnapshotExitDurationMs();
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      // Waiting: duration 0 so the origin is a snap while the layer is still hidden.
      // Settling: the same 350ms implicit animation that carries the fly-in. Animating
      // progress while this duration was 0 made ArkUI snap the derived translate to rest.
      if (!this.entryDisplacementSettlingEnabled) {
        return 0;
      }
      return this.animationViewModel.getSharedSnapshotEnterDurationMs();
    }
    if (this.resolveHomeExitProgress() > 0 && !this.exiting && !this.closeAllExitActive) {
      return this.animationViewModel.getHomeRevealExitDurationMs();
    }
    if (!this.sideEntryAnimationEnabled && !this.exiting) {
      return 0;
    }
    return (this.exiting || this.closeAllExitActive) ? FLOATING_TABS_EXIT_DURATION_MS :
      this.animationViewModel.getFloatingCardEntryDurationMs();
  }

  private resolveCardMotionCurve(): Curve | string | ICurve {
    if (this.isSelectionDisplacementActive()) {
      return this.animationViewModel.getSharedSnapshotExitCurve();
    }
    if (this.isEntryDisplacementActive()) {
      return this.animationViewModel.getSharedSnapshotEnterCurve();
    }
    if (this.resolveHomeExitProgress() > 0 && !this.exiting && !this.closeAllExitActive) {
      return this.animationViewModel.getHomeRevealExitCurve();
    }
    return (this.exiting || this.closeAllExitActive) ? this.animationViewModel.getFloatingCardExitCurve() :
      this.animationViewModel.getFloatingCardEntryCurve();
  }

  private resolveCardMotionDelayMs(index: number): number {
    if (this.isSelectionDisplacementActive()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      return 0;
    }
    if (this.exiting || this.closeAllExitActive) {
      return 0;
    }
    if (this.resolveHomeExitProgress() > 0) {
      return 0;
    }
    if (!this.sideEntryAnimationEnabled) {
      return 0;
    }
    return this.animationViewModel.resolveFloatingCardDelayMs(index, this.layoutState.columnCount);
  }

  private shouldRunLateMountEntryAnimation(item: BrowserTabsFloatingItem): boolean {
    return this.isFirstOpenInFlight &&
      this.lateMountEntryAnimationEnabled &&
      this.sideEntryAnimationEnabled &&
      !this.exiting &&
      !this.closeAllExitActive &&
      !this.isMorphCoveredTab(item.tab.id) &&
      !this.isSelectionDisplacementActive();
  }

  private resolveLateMountEntryOffsetX(item: BrowserTabsFloatingItem): number {
    if (!this.shouldRunLateMountEntryAnimation(item)) {
      return 0;
    }
    return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item)) * this.resolveSurfaceProgress();
  }

  private resolveLateMountEntryAnimationWindowMs(): number {
    return this.animationViewModel.getFloatingCardEntryDurationMs() +
      this.animationViewModel.getFloatingCardMaxDelayMs() +
      160;
  }

  private resolveSurfaceProgress(): number {
    if (this.exiting && this.isSelectionDisplacementActive()) {
      return Math.max(0, Math.min(1, this.entryProgress));
    }
    if (this.exiting) {
      return 0;
    }
    const exitProgress = this.closeAllExitActive ? 0 : this.resolveHomeExitProgress();
    return Math.max(0, Math.min(1, this.entryProgress)) * (1 - exitProgress);
  }

  private resolveBottomChromeOpacity(): number {
    if (this.exiting || this.closeAllExitActive) {
      return 0;
    }
    return this.resolveSurfaceProgress();
  }

  private resolveClearButtonOpacity(): number {
    return this.resolveBottomChromeOpacity();
  }

  private resolveLayerOpacity(): number {
    if (!Number.isFinite(this.layerOpacity)) {
      return 1;
    }
    return Math.max(0, Math.min(1, this.layerOpacity));
  }

  private resolveHomeExitProgress(): number {
    if (!Number.isFinite(this.homeExitProgress)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.homeExitProgress));
  }

  private resolveEntryInitialProgress(): number {
    return this.sideEntryAnimationEnabled ? 0 : 1;
  }

  private resolveEntryDisplacementInitialProgress(): number {
    if (!this.isEntryDisplacementActive()) {
      return 1;
    }
    return 0;
  }

  private resolveContentTopPadding(): number {
    return Math.max(FLOATING_TABS_TOP_PADDING, this.topSafeInsetVp + FLOATING_TABS_TOP_PADDING);
  }

  private resolveContentBottomPadding(): number {
    if (!this.shouldShowBottomChrome()) {
      return FLOATING_TABS_TOP_PADDING;
    }
    return BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE +
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT +
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP;
  }

  private resolveHorizontalContentPadding(): BrowserTabsFloatingContentPadding {
    let top = this.resolveContentTopPadding();
    let bottom = this.resolveContentBottomPadding();
    let overflow = Math.max(0, this.layoutState.itemHeight + top + bottom - this.resolveRootHeight());
    if (overflow <= 0) {
      return { top: top, bottom: bottom };
    }

    const minimumTop = Math.max(0, this.topSafeInsetVp);
    const topReduction = Math.min(overflow, Math.max(0, top - minimumTop));
    top -= topReduction;
    overflow -= topReduction;

    const minimumBottom = this.shouldShowBottomChrome()
      ? BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE + BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT
      : 0;
    const bottomReduction = Math.min(overflow, Math.max(0, bottom - minimumBottom));
    bottom -= bottomReduction;
    return { top: top, bottom: bottom };
  }

  private shouldShowBottomChrome(): boolean {
    return BrowserWindowRuntime.resolveActiveShellPresentationSurface() !== 'large_screen';
  }

  private resolvePanelPageBackgroundColor(): ResourceColor {
    return this.panelPageBackgroundColor ?? this.storedPageBackgroundColor;
  }

  private resolveBackgroundTintOpacity(): number {
    // The API 26 immersive material is intentionally not used for the full-screen
    // overview backdrop. Keep the existing transition opacity on the plain page
    // background so the home surface does not show through unexpectedly.
    return this.resolveBackgroundSurfaceOpacity();
  }

  private resolveBackgroundSurfaceOpacity(): number {
    if (!Number.isFinite(this.backgroundSurfaceOpacity) || this.backgroundSurfaceOpacity < 0) {
      return this.resolveSurfaceProgress();
    }
    return Math.max(0, Math.min(1, this.backgroundSurfaceOpacity));
  }

  private resolvePanelSecondaryTextColor(): ResourceColor {
    return this.panelSecondaryTextColor ?? this.storedSecondaryTextColor;
  }

  private resolveRootWidth(): number {
    return Math.max(1, Math.round(this.viewportWidth));
  }

  private resolveRootHeight(): number {
    return Math.max(1, Math.round(this.viewportHeight));
  }

  private resolveRootLeft(): number {
    return Number.isFinite(this.viewportLeft) ? this.viewportLeft : 0;
  }

  private resolveRootTop(): number {
    return Number.isFinite(this.viewportTop) ? this.viewportTop : 0;
  }

  private resolveLeftFlyOffsetX(index: number): number {
    const column = Math.max(0, Math.floor(index)) % Math.max(1, Math.floor(this.layoutState.columnCount));
    const columnStride = Math.max(1, this.layoutState.cardWidth + FLOATING_TABS_GRID_GAP);
    return -Math.max(this.resolveRootWidth(), this.layoutState.cardWidth) - (column + 1) * columnStride;
  }

  private resolveMorphCoveredTabId(): string {
    return this.morphCoveredTabId.trim();
  }

  /**
   * Whether the entering morph has to be painted from inside the deck.
   *
   * Only an entering morph settles into a deck card and therefore has to interleave with the deck's
   * own draw order. The exit morph grows back out to the page and stays above every card.
   */
  private shouldMountSharedSnapshotInDeck(): boolean {
    // The pull already paints the held card from its own copy of this snapshot. Letting the deck's slot
    // mount the scene's copy as well put two screenshots of the same page on screen — the lower one at
    // the deck's card, which then vanished the moment the entry handed over.
    if (this.shouldApplyEntryGestureLayout()) {
      return false;
    }
    return this.entrySharedSnapshotMounted &&
      this.entrySharedSnapshotState.direction === 'enter' &&
      this.resolveDeckEntryMorphSlot() >= 0;
  }

  /**
   * The covered card's slot, or -1 when the morph is not settling into a card of this deck.
   *
   * This is the card's position in the deck's own list, which is also the slot the deck records for
   * it, so the morph holds a stacking slot that belongs to no other card.
   */
  private resolveDeckEntryMorphSlot(): number {
    if (!this.isHorizontalCardsLayout()) {
      return -1;
    }
    const coveredTabId = this.resolveMorphCoveredTabId();
    if (coveredTabId.length <= 0) {
      return -1;
    }
    for (let position = 0; position < this.deckItems.length; position += 1) {
      const item: BrowserTabsFloatingItem = this.deckItems[position];
      if (item.id === coveredTabId) {
        // The live position, not `item.index`: a reused card keeps the index it was built with.
        return position;
      }
    }
    return -1;
  }

  /** The deck slot's own layer: strictly above the covered card, strictly below its successor. */
  private resolveDeckEntryMorphLayerZIndex(): number {
    const slot = this.shouldMountSharedSnapshotInDeck() ? this.resolveDeckEntryMorphSlot() : -1;
    return slot < 0 ? 0 : slot * 2 + 1;
  }

  private isMorphCoveredTab(tabId: string): boolean {
    const coveredTabId = this.resolveMorphCoveredTabId();
    return coveredTabId.length > 0 && coveredTabId === tabId;
  }

  /**
   * Hide the card surface only when the morph is not already painting in front of it.
   *
   * An in-deck morph sits one slot above the covered card and covers its preview for the whole
   * entry. Zeroing that preview left a hole the frame the morph unmounted — the current card
   * vanished and then popped back. Keeping it painted means unmount only removes the overlay.
   */
  private shouldHideCardSurfaceUnderMorph(tabId: string): boolean {
    if (this.shouldMountSharedSnapshotInDeck()) {
      return false;
    }
    return this.isMorphCoveredTab(tabId);
  }

  private isSelectionDisplacementActive(): boolean {
    return this.selectionDisplacementTabId.trim().length > 0;
  }

  private isSelectionMorphWaitingForDisplacement(): boolean {
    return this.exiting && this.resolveMorphCoveredTabId().length > 0 &&
      !this.isSelectionDisplacementActive();
  }

  private isEntryDisplacementActive(): boolean {
    return !this.sideEntryAnimationEnabled && !this.exiting && this.entryDisplacementTabId.trim().length > 0;
  }

  private shouldPrepareEntryTarget(): boolean {
    return this.isEntryDisplacementActive();
  }

  private resolveEntryTargetTabId(): string {
    return this.entryDisplacementTabId.trim();
  }

  private resolveSelectionDisplacement(item: BrowserTabsFloatingItem): BrowserTabsOverviewSelectionDisplacement {
    return this.selectionDisplacementCoordinator.resolveDisplacement({
      tabId: item.tab.id,
      itemIndex: item.index,
      selectedTabId: this.selectionDisplacementTabId,
      selectedIndex: this.resolveSelectionDisplacementIndex(),
      columnCount: this.resolveDisplacementColumnCount(),
      cardWidth: this.layoutState.cardWidth,
      itemHeight: this.resolveItemHeight(),
      gridGap: this.layoutState.gridGap
    });
  }

  private resolveSelectionDisplacementIndex(): number {
    return this.resolveDisplacementTargetIndex(this.selectionDisplacementTabId);
  }

  private resolveEntryDisplacement(item: BrowserTabsFloatingItem): BrowserTabsOverviewSelectionDisplacement {
    return this.selectionDisplacementCoordinator.resolveDisplacement({
      tabId: item.tab.id,
      itemIndex: item.index,
      selectedTabId: this.entryDisplacementTabId,
      selectedIndex: this.resolveEntryDisplacementIndex(),
      columnCount: this.resolveDisplacementColumnCount(),
      cardWidth: this.layoutState.cardWidth,
      itemHeight: this.resolveItemHeight(),
      gridGap: this.layoutState.gridGap
    });
  }

  private resolveDisplacementColumnCount(): number {
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      return Math.max(1, this.deckItems.length);
    }
    return Math.max(1, this.layoutState.columnCount);
  }

  private resolveEntryDisplacementIndex(): number {
    return this.resolveDisplacementTargetIndex(this.entryDisplacementTabId);
  }

  private resolveEntryDisplacementProgress(): number {
    return Math.max(0, Math.min(1, this.entryDisplacementProgress));
  }

  private resolveDisplacementTargetIndex(tabId: string): number {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return -1;
    }
    const items = this.resolveVisibleItems();
    for (const item of items) {
      if (item.tab.id === targetTabId) {
        return item.index;
      }
    }
    return -1;
  }

  private resolveVisibleTabIds(): string[] {
    const items = this.resolveVisibleItems();
    const ids: string[] = [];
    for (const item of items) {
      ids.push(item.tab.id);
    }
    return ids;
  }

  /**
   * Deck cards share one width and one height.
   *
   * The flat strip sized every card to its own screenshot so a whole page stayed visible at the
   * largest size that fit it. A deck cannot do that: a card of a different width sits a different
   * distance from the focused card and overlaps its neighbours by a different amount, so the whole
   * deck geometry stops matching. Every deck screenshot therefore fills the one shared card with
   * `ImageFit.Cover`; the grid and the flat strip keep their own sizing.
   */
  private resolveCardWidth(): number {
    return this.layoutState.cardWidth;
  }

  private resolveItemHeight(): number {
    return this.layoutState.previewHeight + this.layoutState.identityHeaderHeight +
      this.layoutState.identityPreviewGap;
  }

  /**
   * The dismiss gesture runs along the card's own axis: a grid card is swiped sideways, while the
   * horizontal-cards style is swiped up, so the travel that matters is the card's height. Measuring
   * the card keeps the effort the same on every window size instead of a fixed distance that is a
   * fifth of a desktop card and two thirds of a phone one.
   */
  private resolveSwipeDismissThreshold(): number {
    const extent = this.isHorizontalCardsLayout() ?
      this.resolveItemHeight() : this.resolveCardWidth();
    return this.swipeDismissPolicy.resolveThresholdVp(extent);
  }

  private isHorizontalCardsLayout(): boolean {
    return this.layoutState.layoutStyle === 'horizontal_cards';
  }

  private resolveDeckItems(): BrowserTabsFloatingItem[] {
    const range = this.stackLayoutPolicy.resolveVisibleRange(this.horizontalDeckPosition,
      this.deckItems.length, this.resolveRootWidth(), this.layoutState.cardWidth);
    return this.deckItems.slice(range.first, range.last + 1);
  }

  /**
   * The card's slot in the deck.
   *
   * Read from the recorded map, never from the `ForEach` item: a reused node keeps the item it was
   * built with, so a removal would leave every surviving card on its old slot. The `item.index`
   * fallback only covers a card whose map entry has not been written yet.
   */
  private resolveDeckIndex(item: BrowserTabsFloatingItem): number {
    const slot = this.deckSlotIndexById[item.id];
    return slot === undefined ? item.index : slot;
  }

  private buildDeckSlotMap(ids: string[]): Record<string, number> {
    const slots: Record<string, number> = {};
    for (let index = 0; index < ids.length; index += 1) {
      slots[ids[index]] = index;
    }
    return slots;
  }

  /** Publish the slots of `items`, unless the deck already holds exactly this order. */
  private recordDeckSlots(items: BrowserTabsFloatingItem[]): void {
    const ids: string[] = [];
    for (const item of items) {
      ids.push(item.id);
    }
    const signature = ids.join('|');
    if (signature === this.deckSlotSignature) {
      return;
    }
    this.deckSlotSignature = signature;
    this.deckSlotIndexById = this.buildDeckSlotMap(ids);
  }

  private resolveDeckMetrics(item: BrowserTabsFloatingItem): BrowserTabsOverviewStackCardMetrics {
    // `build()` reads the metrics several times per card per display frame. They are pure in the
    // deck scalar, the recorded slots and the card width, so one memo table serves the whole frame.
    const slot = this.resolveDeckIndex(item);
    // Flat for the whole drag, snapshot or not: the row never stacks first.
    if (this.shouldApplyEntryGestureLayout()) {
      return this.resolveEntryGestureCardMetrics(item);
    }
    const key = `${this.horizontalDeckPosition}|${this.layoutState.cardWidth}|` +
      `${this.deckItemsSignature}|${this.deckSlotSignature}`;
    if (key !== this.deckMetricsCacheKey) {
      this.deckMetricsCacheKey = key;
      this.deckMetricsCache = [];
    }
    const cached = this.deckMetricsCache[slot];
    if (cached !== undefined) {
      return cached;
    }
    const metrics = this.stackLayoutPolicy.resolveCard(slot, this.horizontalDeckPosition,
      this.deckItems.length, this.layoutState.cardWidth);
    this.deckMetricsCache[slot] = metrics;
    return metrics;
  }

  // Presentation construction is driven by data changes, never by an animation frame. The item
  // list is rebuilt only when the tab list itself changes; the per-frame cost is the metrics, and
  // `build()` reads `deckItems` instead of rebuilding presentations.
  private refreshDeckPresentation(): void {
    if (!this.isHorizontalCardsLayout()) { return; }
    const next = this.resolveVisibleItems();
    const previousIds = this.deckItems.map((item: BrowserTabsFloatingItem): string => item.id);
    const nextIds = next.map((item: BrowserTabsFloatingItem): string => item.id);
    const listChanged = previousIds.join('|') !== nextIds.join('|');
    if (listChanged) {
      const position = this.stackLayoutPolicy.reconcilePosition(
        this.horizontalDeckPosition, previousIds, nextIds);
      // A snapshot or icon update can land mid-drag; adopting the position keeps the finger
      // attached instead of cancelling the gesture. Overscroll is preserved on purpose.
      this.horizontalDeckPosition = this.deckMotion.setPosition(position);
      if (!this.deckMotion.isDragging()) {
        this.deckDragActive = false;
      }
      // A card that vanished mid-swipe never reports its own cancel, so the latch is cleared here.
      if (this.deckSwipeTabId.length > 0 && nextIds.indexOf(this.deckSwipeTabId) < 0) {
        this.deckSwipeTabId = '';
      }
    }
    this.deckItems = next;
    this.deckItemsSignature = nextIds.join('|');
    // A fill-in owns the recorded slots until it commits. A preview or an icon can land during those
    // few hundred milliseconds, and re-recording the list that still holds the closed card would put
    // every card back on its old slot halfway through the animation.
    if (this.pendingDeckDismissTabId.length <= 0) {
      this.recordDeckSlots(next);
    }
    // A non-gesture state change must not leave the deck between two cards with no frame left.
    if (listChanged && !this.deckMotion.isDragging()) {
      this.settleDeckToNearestCard();
    }
  }

  private canInteractWithDeck(): boolean {
    return this.interactionEnabled && !this.exiting && !this.closeAllExitActive &&
      !this.isSelectionDisplacementActive() && !this.isEntryDisplacementActive() &&
      this.pendingDeckDismissTabId.length <= 0;
  }

  /** Cancel the gesture and any settle, and leave the position where it is. */
  private stopDeckMotion(): void {
    this.deckMotion.stop();
    this.deckDragActive = false;
    this.deckSwipeTabId = '';
  }

  /**
   * Close a card without re-indexing first: one animation moves the whole deck into its new shape.
   *
   * Taking the card out of the list changes every later card's slot in one assignment, and a card
   * cannot be moved by animating a `ForEach` index change — the node is reused with the item it was
   * built with, and the nonlinear deck layout is not something ArkUI interpolates. So the closed card
   * stays in the list as a ghost while two pieces of state the cards do observe move together: the
   * deck scalar moves to the focus the shorter list will have, and every surviving card moves to its
   * new slot. Cards the removal does not affect keep both values and therefore do not move at all.
   *
   * The new focus is the closed card's successor when it held the focus, and its predecessor when it
   * was the last card — which is exactly what `reconcilePosition` resolves against the shorter list.
   */
  private beginDeckDismiss(tabId: string): void {
    if (this.pendingDeckDismissTabId.length > 0) {
      return;
    }
    this.stopDeckMotion();
    const previousIds = this.deckItems.map((item: BrowserTabsFloatingItem): string => item.id);
    const nextIds = previousIds.filter((id: string): boolean => id !== tabId);
    const position = this.stackLayoutPolicy.reconcilePosition(
      this.horizontalDeckPosition, previousIds, nextIds);
    this.pendingDeckDismissTabId = tabId;
    this.pendingDeckDismissPosition = position;
    this.deckDismissGhostTabId = tabId;
    // The outermost card leaves no slot behind, so nothing moves and the ghost can go at once.
    if (nextIds.length <= 0 || !this.hasDeckSlotChange(previousIds, nextIds, position)) {
      this.commitPendingDeckDismiss();
      return;
    }
    const slots = this.buildDeckSlotMap(nextIds);
    const slotSignature = nextIds.join('|');
    // Armed before the animation: a dismissal that never commits would leave the deck holding a
    // ghost and refusing every pan, which is worse than losing the fill-in's animation.
    this.scheduleDeckDismissCommit();
    animateTo({
      duration: FLOATING_TABS_REORDER_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardEntryCurve()
    }, () => {
      this.horizontalDeckPosition = position;
      this.deckSlotIndexById = slots;
      this.deckSlotSignature = slotSignature;
    });
    this.deckMotion.setPosition(position);
  }

  /**
   * Whether the fill-in has anything to move.
   *
   * A card's place is its slot against the deck scalar, so a removal only moves the cards beyond the
   * removed one, and only towards the focus. Closing the outermost card moves none of them: the fan
   * simply loses that slot, which is why the two end cases need no fill-in at all.
   */
  private hasDeckSlotChange(previousIds: string[], nextIds: string[], position: number): boolean {
    const previousPosition = this.horizontalDeckPosition;
    for (let index = 0; index < nextIds.length; index += 1) {
      const previousIndex = previousIds.indexOf(nextIds[index]);
      if (previousIndex < 0) {
        continue;
      }
      if (Math.abs((previousIndex - previousPosition) - (index - position)) > 0.000001) {
        return true;
      }
    }
    return false;
  }

  /**
   * Finish a dismissal once the fill-in has painted.
   *
   * The timer owns the commit instead of the animation's completion callback, and it doubles as a
   * backstop: a dismissal that never commits would leave the deck holding a ghost and refusing every
   * touch. Committing early is harmless — the committed values are the animation's own end state.
   */
  private scheduleDeckDismissCommit(): void {
    this.clearDeckDismissCommitTimer();
    this.deckDismissCommitTimer = setTimeout(() => {
      this.deckDismissCommitTimer = 0;
      this.commitPendingDeckDismiss();
    }, FLOATING_TABS_REORDER_DURATION_MS);
  }

  private clearDeckDismissCommitTimer(): void {
    if (this.deckDismissCommitTimer <= 0) {
      return;
    }
    clearTimeout(this.deckDismissCommitTimer);
    this.deckDismissCommitTimer = 0;
  }

  private commitPendingDeckDismiss(): void {
    const tabId = this.pendingDeckDismissTabId;
    const position = this.pendingDeckDismissPosition;
    this.clearDeckDismissCommitTimer();
    this.pendingDeckDismissTabId = '';
    this.pendingDeckDismissPosition = -1;
    this.deckDismissGhostTabId = '';
    this.deckSwipeTabId = '';
    if (tabId.length <= 0) {
      return;
    }
    this.stopDeckMotion();
    this.removalState = this.shadowViewModel.markLocalRemoval(this.removalState, tabId);
    this.refreshDeckPresentation();
    // `refreshDeckPresentation` anchors on the list that still held the closed card, so its position
    // is not the one the animation already reached. Re-publishing the settled values is a no-op for
    // the cards, because they are where the animation left them.
    if (this.deckItems.length > 0) {
      this.horizontalDeckPosition = this.deckMotion.seed(
        this.stackLayoutPolicy.clamp(position, this.deckItems.length), this.deckItems.length);
    }
    this.recordDeckSlots(this.deckItems);
    this.onCloseTab(tabId);
  }

  /**
   * End the interaction and put the deck back on a card.
   *
   * Anything that interrupts a gesture or a settle without the finger handing over (the layer
   * hides, a card claims the touch, a tab closes) has to come through here. Stopping alone would
   * leave the deck parked between two cards, and the gesture's own `onActionEnd` no longer owns the
   * motion to finish it.
   */
  private abortDeckMotion(): void {
    if (this.pendingDeckDismissTabId.length > 0) {
      this.commitPendingDeckDismiss();
      return;
    }
    this.stopDeckMotion();
    this.settleDeckToNearestCard();
  }

  private settleDeckToNearestCard(): void {
    if (!this.isHorizontalCardsLayout() || this.deckItems.length <= 0) {
      return;
    }
    if (this.exiting || this.closeAllExitActive) {
      // The deck is on its way out; a floor-level position no longer shows, and a reopen reseeds.
      return;
    }
    this.deckMotion.settleToNearest(this.deckItems.length,
      (callback: (time: number) => void): void => { this.scheduleDeckFrame(callback); },
      (position: number): void => { this.horizontalDeckPosition = position; });
  }

  private handleDeckInteractionChanged(): void {
    if (!this.canInteractWithDeck()) {
      this.abortDeckMotion();
    }
  }

  private beginDeckDrag(): void {
    if (this.pendingDeckDismissTabId.length > 0) {
      // The gesture reaching the deck means the fill-in has had its time. Finishing it here rather
      // than waiting for the timer cannot leave the deck locked behind a dismissal that never
      // committed, and the committed values are the animation's own end state either way.
      this.commitPendingDeckDismiss();
    }
    if (!this.canInteractWithDeck() || this.deckSwipeTabId.length > 0) { return; }
    this.deckMotion.begin();
    this.deckDragActive = true;
  }

  private updateDeckDrag(offsetX: number): void {
    if (!this.deckDragActive || !this.canInteractWithDeck()) { return; }
    this.horizontalDeckPosition = this.deckMotion.drag(offsetX, this.layoutState.cardWidth, this.deckItems.length);
  }

  private scheduleDeckFrame(callback: (time: number) => void): void {
    this.getUIContext().postFrameCallback(new BrowserTabsStackFrameCallback(callback));
  }

  private endDeckDrag(velocityX: number): void {
    if (!this.deckDragActive) { return; }
    this.deckDragActive = false;
    this.deckMotion.release(velocityX, this.layoutState.cardWidth, this.deckItems.length,
      (callback: (time: number) => void): void => { this.scheduleDeckFrame(callback); },
      (position: number): void => { this.horizontalDeckPosition = position; });
  }

  private cancelDeckDrag(): void {
    if (!this.deckDragActive) { return; }
    this.deckDragActive = false;
    this.deckMotion.cancel(this.deckItems.length,
      (callback: (time: number) => void): void => { this.scheduleDeckFrame(callback); },
      (position: number): void => { this.horizontalDeckPosition = position; });
  }

  private seedDeckPosition(index: number): void {
    if (!this.isHorizontalCardsLayout()) { return; }
    this.stopDeckMotion();
    this.horizontalDeckPosition = this.deckMotion.seed(index, this.deckItems.length);
    this.deckPositionSeeded = true;
  }

  private selectOverviewTab(tabId: string, rect?: BrowserTabOverviewCardSelectRect): void {
    if (this.isHorizontalCardsLayout()) {
      if (this.deckDragActive) { return; }
      this.stopDeckMotion();
      const deckRect = this.resolveDeckPreviewRect(tabId);
      this.onSelectTab(tabId, deckRect === undefined ? rect : this.toSelectRect(deckRect));
      return;
    }
    this.onSelectTab(tabId, rect);
  }

  /**
   * `BrowserTabsOverlayRect` and `BrowserTabOverviewCardSelectRect` describe the same rectangle but
   * are independent types, and ArkTS rejects structural compatibility between them.
   */
  private toSelectRect(rect: BrowserTabsOverlayRect): BrowserTabOverviewCardSelectRect {
    return {
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height
    };
  }

  // onAreaChange reports layout bounds, not the wrapper's live scale/translation. The same
  // geometry that paints the preview supplies the morph rectangle, including the scaled header.
  private resolveDeckPreviewRect(tabId: string): BrowserTabsOverlayRect | undefined {
    const item = this.deckItems.find((candidate: BrowserTabsFloatingItem): boolean => candidate.id === tabId);
    if (item === undefined) { return undefined; }
    return this.buildDeckPreviewRect(this.resolveDeckMetrics(item));
  }

  private buildDeckPreviewRect(metrics: BrowserTabsOverviewStackCardMetrics): BrowserTabsOverlayRect {
    const padding = this.resolveHorizontalContentPadding();
    const centerY = this.resolveRootTop() + padding.top +
      (this.resolveRootHeight() - padding.top - padding.bottom) / 2;
    const header = this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap;
    return {
      left: this.resolveRootLeft() + this.resolveRootWidth() / 2 + metrics.offsetX -
        this.layoutState.cardWidth * metrics.scale / 2,
      top: centerY + (header - this.resolveItemHeight() / 2) * metrics.scale,
      width: this.layoutState.cardWidth * metrics.scale,
      height: this.layoutState.previewHeight * metrics.scale
    };
  }

  private buildBlankSlotKeys(): string[] {
    const safeColumnCount = Math.max(1, Math.floor(this.layoutState.columnCount));
    const itemCount = this.resolveVisibleItems().length;
    const blankSlotCount = this.resolveBlankSlotCount(safeColumnCount, itemCount);
    const keys: string[] = [];
    for (let index = 0; index < blankSlotCount; index += 1) {
      keys.push(`floating-blank-${this.selectedSection}-${itemCount}-${index}`);
    }
    return keys;
  }

  private resolveBlankSlotCount(safeColumnCount: number, itemCount: number): number {
    const remainder = itemCount % safeColumnCount;
    const trailingRowSlotCount = remainder === 0 ? 0 : safeColumnCount - remainder;
    const visibleRowCount = this.resolveVisibleRowCount();
    const visibleSlotCount = visibleRowCount * safeColumnCount;
    return Math.max(trailingRowSlotCount, visibleSlotCount - itemCount);
  }

  private resolveVisibleRowCount(): number {
    const safeItemHeight = Math.max(1, this.layoutState.itemHeight);
    const safeGridGap = Math.max(0, FLOATING_TABS_GRID_GAP);
    const visibleHeight = Math.max(1, this.resolveRootHeight() -
      this.resolveContentTopPadding() - this.resolveContentBottomPadding());
    return Math.max(1, Math.ceil((visibleHeight + safeGridGap) / (safeItemHeight + safeGridGap)));
  }
}
