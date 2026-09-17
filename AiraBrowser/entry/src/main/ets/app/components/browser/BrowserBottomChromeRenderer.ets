import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserBottomAddressContextAction,
  BrowserBottomChromeFrame,
  BrowserBottomChromeMotionDirective,
  BrowserBottomChromePresentation,
  BrowserBottomChromeTapIntent,
  BrowserBottomChromeTapTarget,
  DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION
} from '../../../core/browser/BrowserBottomChromePresentationViewModel';
import {
  SearchEngineId,
  SearchEngineRecord
} from '../../../common/models/BrowserModels';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import {
  BROWSER_BOTTOM_CHROME_CENTER_PRESSED_HORIZONTAL_INSET,
  BROWSER_BOTTOM_CHROME_CENTER_PRESSED_MIN_HORIZONTAL_SCALE,
  BROWSER_BOTTOM_CHROME_CENTER_PRESSED_MIN_VERTICAL_SCALE,
  BROWSER_BOTTOM_CHROME_CENTER_PRESSED_VERTICAL_INSET,
  BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT,
  BROWSER_BOTTOM_CHROME_TEXT_SIZE,
  BROWSER_FLOATING_CHROME_PRESSED_SCALE,
  BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
  BROWSER_FLOATING_CHROME_RELEASE_CURVE,
  BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import { AiraIcon } from '../common/AiraIcon';
import { logToolbarPopupReopen } from '../../../common/debug/AiraToolbarPopupReopenProbe';
import { SearchEngineIconResources } from '../search/SearchEngineIconResources';
import { BrowserSearchEnginePopupLayoutViewModel } from
  '../../../core/browser/BrowserSearchEnginePopupLayoutViewModel';
import {
  DownloadToolbarIndicatorState,
  createHiddenDownloadToolbarIndicatorState
} from '../../../core/download/DownloadToolbarIndicatorViewModel';
import { BrowserBottomChromeImmersiveMaterialSurface } from './BrowserBottomChromeImmersiveMaterialSurface';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import {
  BROWSER_BOTTOM_CHROME_LIGHT_EDGE_HIGHLIGHT_COLOR
} from './BrowserFloatingGlassMaterialTokens';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';

const BROWSER_BOTTOM_CHROME_RENDER_HEIGHT: number = 48;
const BROWSER_BOTTOM_CHROME_ICON_SIZE: number = 22;
const BROWSER_BOTTOM_CHROME_EDGE_HIGHLIGHT_WIDTH: number = 0.5;
const BROWSER_BOTTOM_CHROME_SHADOW_RADIUS: number = 40;
const BROWSER_BOTTOM_CHROME_ENABLED_OPACITY: number = 1;
const BROWSER_BOTTOM_CHROME_DISABLED_OPACITY: number = 0.42;
const BROWSER_BOTTOM_CHROME_PROGRESS_EPSILON: number = 0.001;
// Above this collapse progress the expanded rail is visually gone, so its nodes must stop taking
// touches and leave the compact capsule as the only live surface.
const BROWSER_BOTTOM_CHROME_COMPACT_HIT_TEST_PROGRESS: number = 0.5;
const EMPTY_BROWSER_BOTTOM_CHROME_TAP_TARGET: BrowserBottomChromeTapTarget =
  new BrowserBottomChromeTapTarget(new BrowserBottomChromeTapIntent('none'), false, '');
const BROWSER_BOTTOM_CHROME_DOWNLOAD_RING_SIZE: number = BROWSER_BOTTOM_CHROME_ICON_SIZE + 6;
const BROWSER_BOTTOM_CHROME_DOWNLOAD_RING_STROKE_WIDTH: number = 2;
const BROWSER_SEARCH_ENGINE_POPUP_WIDTH: number = 224;
const BROWSER_SEARCH_ENGINE_POPUP_ROW_HEIGHT: number = 48;
const BROWSER_SEARCH_ENGINE_POPUP_MAX_VISIBLE_ROWS: number = 6;
const BROWSER_SEARCH_ENGINE_POPUP_CONTENT_PADDING: number = 6;
const BROWSER_SEARCH_ENGINE_POPUP_TARGET_SPACE: number = 8;
const BROWSER_SEARCH_ENGINE_POPUP_RADIUS: number = 16;
const BROWSER_SEARCH_ENGINE_POPUP_ROW_RADIUS: number = 12;
const BROWSER_SEARCH_ENGINE_POPUP_ROW_HORIZONTAL_PADDING: number = 12;
const BROWSER_SEARCH_ENGINE_POPUP_ROW_GAP: number = 12;
const BROWSER_BOTTOM_ADDRESS_CONTEXT_MENU_LONG_PRESS_MS: number = 450;
const BROWSER_BOTTOM_ADDRESS_CONTEXT_MENU_WIDTH: number = 200;
const BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_HEIGHT: number = 44;
const BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_TEXT_SIZE: number = 16;
const BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_HORIZONTAL_PADDING: number = 12;
const BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_RADIUS: number = 6;
const BROWSER_WEB_PROTECTION_FEEDBACK_CROSSFADE_DURATION_MS: number = 180;
const PROTECTION_DEBUG_DOMAIN: number = 0x0000;
const PROTECTION_DEBUG_TAG: string = 'ProtectionCountDiag';
const PROTECTION_DEBUG_PREFIX: string = '[DEBUG-protection-count-20260808]';

@Component
export struct BrowserBottomChromeRenderer {
  @State private animatedFrame: BrowserBottomChromeFrame = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.frame;
  /**
   * Collapse of the floating chrome into the compact capsule is a pure opacity cross-fade between
   * two rails that are both laid out once at fixed geometry. Animating the expanded rail's width,
   * height, padding, radius and text metrics instead re-measured the whole bottom-chrome subtree,
   * re-sampled three glass materials and re-blurred three 40vp shadows on every frame of a
   * gesture-driven collapse.
   */
  @State private animatedScrollCompactProgress: number = 0;
  @State private outgoingDisplayText: string = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.centerContent.displayText;
  @State private incomingDisplayText: string = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.centerContent.displayText;
  @State private outgoingDisplayUsesSecondaryTone: boolean =
    DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.centerContent.displayUsesSecondaryTone;
  @State private incomingDisplayUsesSecondaryTone: boolean =
    DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.centerContent.displayUsesSecondaryTone;
  @State private outgoingDisplayViewportWidth: number = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.frame.centerViewportWidth;
  @State private incomingDisplayViewportWidth: number = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.frame.centerViewportWidth;
  @State private displaySwapProgress: number = 1;
  @State private promptText: string = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.centerContent.promptText;
  @State private webProtectionFeedbackVisible: boolean = false;
  @State private webProtectionFeedbackDisplayText: string = '';
  @State private webProtectionFeedbackAccessibilityLabel: string = '';
  @State private webProtectionFeedbackCrossfadeProgress: number = 0;
  @State private editingLayerHitTestEnabled: boolean = false;
  @State private pressedTargetKey: string = '';
  @State private pressedTargetScaleKey: string = '';
  @State private pressedTargetScale: number = 1;
  @State private centerBodyPressedProgress: number = 0;
  @State private addressContextMenuVisible: boolean = false;
  @State private searchEnginePopupVisible: boolean = false;
  /**
   * Visibility captured on touch-down. The toggle must be computed against the state the user
   * actually pressed, because the popup can dismiss itself (auto-cancel on a stray tap) between
   * down and click, and inverting the live value then reads as "open" again.
   */
  private searchEnginePopupVisibleAtPress: boolean = false;
  /**
   * Global top of the search-engine popup's anchor. The popup is capped to the space above it so
   * the framework never flips the menu onto the keyboard. Deliberately not reactive: it is
   * refreshed on layout and on touch-down, both of which run before the popup reads it, so it
   * needs no render of its own.
   */
  private searchEnginePopupAnchorTopVp: number = 0;
  private searchEnginePopupLayout: BrowserSearchEnginePopupLayoutViewModel =
    new BrowserSearchEnginePopupLayoutViewModel();
  private pressedTargetIntent: BrowserBottomChromeTapIntent | undefined;
  private pressedTargetIntentKey: string = '';
  private pressedTargetMotionVersion: number = 0;
  @State private leadingOuterVisualEnabled: boolean = false;
  @State private centerLeadingVisualEnabled: boolean = false;
  @State private centerPrimaryVisualEnabled: boolean = false;
  @State private trailingOuterVisualEnabled: boolean = false;
  private currentPresentation: BrowserBottomChromePresentation = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION;
  private targetFrame: BrowserBottomChromeFrame = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.frame;
  /**
   * Fixed geometry of the collapsed capsule. It is read by build() rather than animated, which is
   * what lets the compact rail stay laid out for the whole lifetime of this component.
   */
  private compactFrame: BrowserBottomChromeFrame = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.compactFrame;
  private targetScrollCompactProgress: number = 0;
  private motionVersion: number = 0;
  private focusReadyDispatched: boolean = false;
  private focusReadyTimer: number = -1;
  private lastDebugProtectionFeedbackVisible: boolean = false;
  private lastDebugProtectionFeedbackMode: string = '';
  @Prop
  @Watch('syncPresentation')
  presentation: BrowserBottomChromePresentation = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION;
  @Prop materialTint: ResourceColor = '';
  /**
   * Opt-in for the immersive light-sense material behind the three chrome clusters.
   * Only the floating bottom panel turns this on; callers that render the chrome
   * elsewhere leave it off and keep the capsules' own blurred fallback.
   */
  @Prop hdsMaterialPlateEnabled: boolean = false;
  @Prop materialShadowColor: ResourceColor = '';
  @Prop edgeHighlightColor: ResourceColor = BROWSER_BOTTOM_CHROME_LIGHT_EDGE_HIGHLIGHT_COLOR;
  @Prop primaryIconColor: ResourceColor = '';
  @Prop disabledIconColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  /**
   * API 26's color inversion only resolves when the material subtree receives
   * special system color resources. Keep the explicit colors as a fallback for
   * callers that render this component without adaptive material support.
   */
  @Prop adaptiveForeground: boolean = true;
  @Prop pressedBackgroundColor: ResourceColor = '';
  @Prop downloadProgressColor: ResourceColor = '';
  @Prop downloadIndicatorState: DownloadToolbarIndicatorState = createHiddenDownloadToolbarIndicatorState();
  @Prop chromeIconTone: AppChromeIconTone = 'light';
  @Prop reliableActionsEnabled: boolean = true;
  @Prop addressContextMenuEnabled: boolean = false;
  /** Window top safe inset, used to bound the search-engine popup to the space above its anchor. */
  @Prop topSafeInsetVp: number = 0;
  @BuilderParam editingLayer: () => void = this.emptyBuilder;
  onIntent: (intent: BrowserBottomChromeTapIntent) => void = (_intent: BrowserBottomChromeTapIntent) => {};
  onLongPressIntent: (intent: BrowserBottomChromeTapIntent) => void =
    (_intent: BrowserBottomChromeTapIntent) => {};
  onAddressContextAction: (action: BrowserBottomAddressContextAction) => void =
    (_action: BrowserBottomAddressContextAction) => {};
  onSelectSearchEngine: (engineId: SearchEngineId) => void = (_engineId: SearchEngineId) => {};
  onEditingFocusReady: () => void = () => {};

  aboutToAppear(): void {
    this.currentPresentation = this.presentation;
    this.targetFrame = this.presentation.frame;
    this.animatedFrame = this.presentation.frame;
    this.compactFrame = this.presentation.compactFrame;
    this.targetScrollCompactProgress = this.presentation.scrollCompactProgress;
    this.animatedScrollCompactProgress = this.presentation.scrollCompactProgress;
    this.initializeDisplayContent(this.presentation);
    this.applyPresentationMetadata(this.presentation);
    this.webProtectionFeedbackCrossfadeProgress =
      this.shouldPresentWebProtectionFeedback(this.presentation) ? 1 : 0;
    if (this.presentation.mode === 'center-active-editing') {
      this.scheduleImmediateFocusReady();
    }
    logToolbarPopupReopen('renderer_appear', `mode=${this.presentation.mode} scene=${this.presentation.scene} ` +
      `popupFlag=${this.searchEnginePopupVisible} slotVisible=${this.isSearchEngineMenuVisible()}`);
  }

  aboutToDisappear(): void {
    this.invalidateActiveMotion();
    this.resetPressedTarget();
    this.clearFocusReadyTimer();
    this.applySearchEnginePopupVisible(false, 'about_to_disappear');
    this.addressContextMenuVisible = false;
    this.clearPressedTargetIntent();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildExpandedRail()
      this.buildCompactRail()
    }
    .width('100%')
    .height(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildExpandedRail() {
    Row({ space: 0 }) {
      this.buildLeadingOuterMaterial()
      Blank()
        .width(this.animatedFrame.leadingGap)
        .height(1)
        .hitTestBehavior(HitTestMode.None)
      this.buildCenterMaterialRail()
      Blank()
        .width(this.animatedFrame.trailingGap)
        .height(1)
        .hitTestBehavior(HitTestMode.None)
      this.buildTrailingOuterMaterial()
    }
    .width('100%')
    .height(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .opacity(1 - this.resolveScrollCompactProgress())
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * The collapsed capsule. Both this rail and the expanded rail are always mounted and already laid
   * out, so collapsing and revealing them only changes opacity: no re-layout, no material re-sample,
   * no shadow re-blur on the frames where the finger is still on the page.
   */
  @Builder
  private buildCompactRail() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.shouldUseHdsMaterialPlate()) {
          HdsImmersiveMaterialSurface({
            plateWidth: this.compactFrame.centerWidth,
            plateHeight: this.compactFrame.centerHeight,
            plateRadius: this.compactFrame.centerRadius
          })
        }
        BrowserBottomChromeImmersiveMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: this.compactFrame.centerHeight,
          surfaceRadius: this.compactFrame.centerRadius,
          materialTint: this.materialTint,
          hostMaterialActive: this.shouldUseHdsMaterialPlate(),
          materialShadowEnabled: false,
          edgeHighlightWidth: BROWSER_BOTTOM_CHROME_EDGE_HIGHLIGHT_WIDTH,
          edgeHighlightColor: this.edgeHighlightColor
        }) {
          Stack({ alignContent: Alignment.Center }) {
            Text(this.presentation.centerContent.displayText)
              .width(this.compactFrame.centerViewportWidth)
              .height(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
              .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
              .lineHeight(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
              .halfLeading(true)
              .textVerticalAlign(TextVerticalAlign.CENTER)
              .fontColor(this.presentation.centerContent.displayUsesSecondaryTone ?
                this.resolveSecondaryTextForeground() : this.resolvePrimaryTextForeground())
              .fontWeight(FontWeight.Regular)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .scale({
                x: this.compactFrame.centerDisplayScale,
                y: this.compactFrame.centerDisplayScale
              })
              .hitTestBehavior(HitTestMode.None)
            this.buildCompactTapSurface()
          }
          .width('100%')
          .height('100%')
          .padding({
            left: this.compactFrame.centerHorizontalPadding,
            right: this.compactFrame.centerHorizontalPadding,
            top: this.compactFrame.centerVerticalPadding,
            bottom: this.compactFrame.centerVerticalPadding
          })
        }
      }
      .width(this.compactFrame.centerWidth)
      .height(this.compactFrame.centerHeight)
      .backgroundColor(this.resolvePressedBackground('compact-body'))
      .borderRadius(this.compactFrame.centerRadius)
      .shadow(this.resolveMaterialShadow())
      .scale({
        x: this.resolveCompactBodyScaleX(),
        y: this.resolveCompactBodyScaleY()
      })
    }
    .width(this.compactFrame.centerWidth)
    .height(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT)
    .translate({ y: this.compactFrame.centerTranslateY })
    .opacity(this.resolveScrollCompactProgress())
    .hitTestBehavior(this.isCompactChromePresented() ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private buildCompactTapSurface() {
    Button()
      .width('100%')
      .height('100%')
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .focusable(false)
      .focusOnTouch(false)
      .enabled(this.isPhysicalTargetInteractive('compact-body'))
      .accessibilityText(this.resolveLiveTapTarget('compact-body').accessibilityText)
      .hitTestBehavior(this.isPhysicalTargetInteractive('compact-body') ?
        HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.capturePressedTargetIntent('compact-body');
        } else if (event.type === TouchType.Cancel) {
          this.clearPressedTargetIntent();
        }
        this.updatePressedTarget('compact-body', this.resolveLiveTapTarget('compact-body'), event.type);
      })
      .onClick(() => {
        this.handleTap('compact-body');
      })
  }

  @Builder
  private buildLeadingOuterMaterial() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterialPlate()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.animatedFrame.leadingOuterWidth,
          plateHeight: this.resolveOuterVisualSize(this.animatedFrame.leadingOuterWidth),
          plateRadius: this.resolveOuterVisualSize(this.animatedFrame.leadingOuterWidth) / 2
        })
      }
      BrowserBottomChromeImmersiveMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: this.resolveOuterVisualSize(this.animatedFrame.leadingOuterWidth),
        surfaceRadius: this.resolveOuterVisualSize(this.animatedFrame.leadingOuterWidth) / 2,
        materialTint: this.materialTint,
        hostMaterialActive: this.shouldUseHdsMaterialPlate(),
        materialShadowEnabled: false,
        edgeHighlightWidth: BROWSER_BOTTOM_CHROME_EDGE_HIGHLIGHT_WIDTH,
        edgeHighlightColor: this.edgeHighlightColor
      }) {
        Stack({ alignContent: Alignment.Center }) {
          AiraIcon({
            airaIconId: this.presentation.leadingOuterIconId,
            iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
            iconColor: this.resolveIconForeground(this.leadingOuterVisualEnabled)
          })
            .opacity(this.resolveVisualIconOpacity(this.leadingOuterVisualEnabled))
            .hitTestBehavior(HitTestMode.None)
          this.buildTapSurface('leading-outer')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width(this.animatedFrame.leadingOuterWidth)
    .height(this.resolveOuterVisualSize(this.animatedFrame.leadingOuterWidth))
    .borderRadius(this.resolveOuterVisualSize(this.animatedFrame.leadingOuterWidth) / 2)
    .shadow(this.resolveMaterialShadow())
    .opacity(this.animatedFrame.outerOpacity)
    .translate({ y: this.resolveOuterVisualOffsetY(this.animatedFrame.leadingOuterWidth) })
    .scale({
      x: this.resolveTargetScale('leading-outer'),
      y: this.resolveTargetScale('leading-outer')
    })
    .hitTestBehavior(this.isPhysicalTargetInteractive('leading-outer') ?
      HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private buildTrailingOuterMaterial() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterialPlate()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.animatedFrame.trailingOuterWidth,
          plateHeight: this.resolveOuterVisualSize(this.animatedFrame.trailingOuterWidth),
          plateRadius: this.resolveOuterVisualSize(this.animatedFrame.trailingOuterWidth) / 2
        })
      }
      BrowserBottomChromeImmersiveMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: this.resolveOuterVisualSize(this.animatedFrame.trailingOuterWidth),
        surfaceRadius: this.resolveOuterVisualSize(this.animatedFrame.trailingOuterWidth) / 2,
        materialTint: this.materialTint,
        hostMaterialActive: this.shouldUseHdsMaterialPlate(),
        materialShadowEnabled: false,
        edgeHighlightWidth: BROWSER_BOTTOM_CHROME_EDGE_HIGHLIGHT_WIDTH,
        edgeHighlightColor: this.edgeHighlightColor
      }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.presentation.trailingOuterIconId === 'browser.toolbar.tabs') {
            AiraIcon({
              airaIconId: 'browser.toolbar.tabs',
              iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
              iconColor: this.resolveIconForeground(this.trailingOuterVisualEnabled)
            })
              .opacity(this.resolveVisualIconOpacity(this.trailingOuterVisualEnabled))
              .hitTestBehavior(HitTestMode.None)
          } else {
            AiraIcon({
              airaIconId: this.presentation.trailingOuterIconId,
              iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
              iconColor: this.resolveIconForeground(this.trailingOuterVisualEnabled)
            })
              .opacity(this.resolveVisualIconOpacity(this.trailingOuterVisualEnabled))
              .hitTestBehavior(HitTestMode.None)
          }
          this.buildTapSurface('trailing-outer')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width(this.animatedFrame.trailingOuterWidth)
    .height(this.resolveOuterVisualSize(this.animatedFrame.trailingOuterWidth))
    .borderRadius(this.resolveOuterVisualSize(this.animatedFrame.trailingOuterWidth) / 2)
    .shadow(this.resolveMaterialShadow())
    .opacity(this.animatedFrame.outerOpacity)
    .translate({ y: this.resolveOuterVisualOffsetY(this.animatedFrame.trailingOuterWidth) })
    .scale({
      x: this.resolveTargetScale('trailing-outer'),
      y: this.resolveTargetScale('trailing-outer')
    })
    .hitTestBehavior(this.isPhysicalTargetInteractive('trailing-outer') ?
      HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private buildCenterMaterialRail() {
    Stack({ alignContent: Alignment.Top }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.shouldUseHdsMaterialPlate()) {
          HdsImmersiveMaterialSurface({
            plateWidth: this.animatedFrame.centerWidth,
            plateHeight: this.animatedFrame.centerHeight,
            plateRadius: this.animatedFrame.centerRadius
          })
        }
        BrowserBottomChromeImmersiveMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: this.animatedFrame.centerHeight,
          surfaceRadius: this.animatedFrame.centerRadius,
          materialTint: this.materialTint,
          hostMaterialActive: this.shouldUseHdsMaterialPlate(),
          materialShadowEnabled: false,
          edgeHighlightWidth: BROWSER_BOTTOM_CHROME_EDGE_HIGHLIGHT_WIDTH,
          edgeHighlightColor: this.edgeHighlightColor
        }) {
          Row({ space: 0 }) {
            this.buildCenterLeadingSlot()
            this.buildCenterViewport()
            this.buildCenterPrimarySlot()
            Blank()
              .width(this.animatedFrame.centerAccessoryGap)
              .height(1)
              .hitTestBehavior(HitTestMode.None)
            this.buildCenterSecondarySlot()
          }
          .width('100%')
          .height('100%')
          .padding({
            left: this.animatedFrame.centerHorizontalPadding,
            right: this.animatedFrame.centerHorizontalPadding,
            top: this.animatedFrame.centerVerticalPadding,
            bottom: this.animatedFrame.centerVerticalPadding
          })
        }
      }
      .width(this.animatedFrame.centerWidth)
      .height(this.animatedFrame.centerHeight)
      .borderRadius(this.animatedFrame.centerRadius)
      .shadow(this.resolveMaterialShadow())
      .translate({ y: this.animatedFrame.centerTranslateY })
      .scale({
        x: this.resolveCenterBodyScaleX(),
        y: this.resolveCenterBodyScaleY()
      })
    }
    .width(this.animatedFrame.centerWidth)
    .height(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildCenterLeadingSlot() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldShowDownloadIndicator()) {
        Progress({
          value: this.downloadIndicatorState.progressValue,
          total: 100,
          type: ProgressType.Ring
        })
          .width(BROWSER_BOTTOM_CHROME_DOWNLOAD_RING_SIZE)
          .height(BROWSER_BOTTOM_CHROME_DOWNLOAD_RING_SIZE)
          .style({
            strokeWidth: BROWSER_BOTTOM_CHROME_DOWNLOAD_RING_STROKE_WIDTH,
            enableSmoothEffect: true,
            status: this.resolveDownloadProgressStatus()
          })
          .color(this.downloadProgressColor)
          .backgroundColor(this.disabledIconColor)
          .opacity(this.animatedFrame.menuOpacity + this.animatedFrame.editingOpacity)
          .hitTestBehavior(HitTestMode.None)

        AiraIcon({
          airaIconId: 'browser.toolbar.activeDownload',
          iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
          iconColor: this.resolvePrimaryIconForeground()
        })
          .opacity(this.animatedFrame.menuOpacity + this.animatedFrame.editingOpacity)
          .hitTestBehavior(HitTestMode.None)
        this.buildTapSurface('center-leading')
      } else if (this.isSearchEngineMenuVisible()) {
        if (this.resolveSelectedSearchEngineIcon() !== undefined) {
          Image(this.resolveSelectedSearchEngineIcon() as Resource)
            .width(BROWSER_BOTTOM_CHROME_ICON_SIZE)
            .height(BROWSER_BOTTOM_CHROME_ICON_SIZE)
            .objectFit(ImageFit.Contain)
            .opacity(this.animatedFrame.editingOpacity)
            .hitTestBehavior(HitTestMode.None)
        } else {
          AiraIcon({
            airaIconId: 'browser.toolbar.search',
            iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
            iconColor: this.resolvePrimaryIconForeground()
          })
            .opacity(this.animatedFrame.editingOpacity)
            .hitTestBehavior(HitTestMode.None)
        }
        this.buildSearchEngineMenuTapSurface()
      } else {
          AiraIcon({
            airaIconId: this.presentation.centerLeadingIconId,
            iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
            iconColor: this.resolveIconForeground(this.centerLeadingVisualEnabled)
          })
            .opacity(this.animatedFrame.menuOpacity *
              this.resolveVisualIconOpacity(this.centerLeadingVisualEnabled))
          .hitTestBehavior(HitTestMode.None)
        this.buildTapSurface('center-leading')
      }
    }
    .width(this.animatedFrame.centerLeadingWidth)
    .height(this.animatedFrame.centerViewportHeight)
    .backgroundColor(this.resolvePressedBackground('center-leading'))
    .borderRadius(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT / 2)
    .clip(true)
    .scale({
      x: this.resolveTargetScale('center-leading'),
      y: this.resolveTargetScale('center-leading')
    })
    .hitTestBehavior(this.isPhysicalTargetInteractive('center-leading') ?
      HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private buildSearchEngineMenuTapSurface() {
    Button()
      .width('100%')
      .height('100%')
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .focusable(false)
      .focusOnTouch(false)
      .enabled(this.isTargetEnabled(this.resolveLiveTapTarget('center-leading')))
      .accessibilityText(this.resolveLiveTapTarget('center-leading').accessibilityText)
      .hitTestBehavior(this.isTargetEnabled(this.resolveLiveTapTarget('center-leading')) ?
        HitTestMode.Default : HitTestMode.None)
      // The popup's own height is derived from this, so it must reflect the anchor's real
      // on-screen top rather than its untransformed layout slot.
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.rememberSearchEnginePopupAnchorTop(this.parseAreaPosition(newArea.globalPosition.y));
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.searchEnginePopupVisibleAtPress = this.searchEnginePopupVisible;
          // The frame that opens the popup has to know the anchor's top already, and onAreaChange
          // has not necessarily reported it for this mount yet, so take it from the press itself.
          this.rememberSearchEnginePopupAnchorTop(this.parseAreaPosition(event.target.area.globalPosition.y));
          logToolbarPopupReopen('popup_anchor_down',
            `visible=${this.searchEnginePopupVisible} slotVisible=${this.isSearchEngineMenuVisible()}`);
        }
        this.updatePressedTarget(
          'center-leading',
          this.resolveLiveTapTarget('center-leading'),
          event.type
        );
      })
      .onClick(() => {
        if (!this.isTargetEnabled(this.resolveLiveTapTarget('center-leading'))) {
          return;
        }
        this.applySearchEnginePopupVisible(!this.searchEnginePopupVisibleAtPress, 'anchor_click_toggle');
      })
      .bindPopup(this.searchEnginePopupVisible && this.isSearchEngineMenuVisible(), {
        builder: this.buildSearchEnginePopup,
        placement: Placement.Top,
        popupColor: $r('sys.color.ohos_id_color_background_transparent'),
        enableArrow: false,
        autoCancel: true,
        /**
         * The authoritative clear. onStateChange reports the dismissal only after it has happened
         * and is skipped entirely when the bound slot is torn down by a mode change, so a flag left
         * set there can be handed back to the framework as "show" on the next re-render and revive
         * the popup without a tap. Clearing it as the dismissal starts closes that window.
         */
        onWillDismiss: (action: DismissPopupAction) => {
          logToolbarPopupReopen('popup_on_will_dismiss', `reason=${action.reason}`);
          this.applySearchEnginePopupVisible(false, 'on_will_dismiss');
          action.dismiss();
        },
        onStateChange: (event: PopupStateChangeParam) => {
          logToolbarPopupReopen('popup_on_state_change', `isVisible=${event.isVisible}`);
          this.applySearchEnginePopupVisible(event.isVisible, 'on_state_change');
        },
        showInSubWindow: false,
        mask: false,
        targetSpace: BROWSER_SEARCH_ENGINE_POPUP_TARGET_SPACE,
        width: BROWSER_SEARCH_ENGINE_POPUP_WIDTH,
        radius: BROWSER_SEARCH_ENGINE_POPUP_RADIUS,
        shadow: this.resolveMaterialShadow(),
        backgroundBlurStyle: BlurStyle.NONE,
        focusable: false,
        keyboardAvoidMode: KeyboardAvoidMode.DEFAULT
      })
  }

  @Builder
  private buildSearchEnginePopup() {
    BrowserBottomChromeImmersiveMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: this.resolveSearchEnginePopupHeight(),
      surfaceRadius: BROWSER_SEARCH_ENGINE_POPUP_RADIUS,
      materialTint: this.materialTint
    }) {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.presentation.searchEnginePresentation.searchEngines, (engine: SearchEngineRecord) => {
            this.buildSearchEnginePopupRow(engine)
          }, (engine: SearchEngineRecord) => engine.id)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(BROWSER_SEARCH_ENGINE_POPUP_CONTENT_PADDING)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
  }

  @Builder
  private buildSearchEnginePopupRow(engine: SearchEngineRecord) {
    Button() {
      Row({ space: BROWSER_SEARCH_ENGINE_POPUP_ROW_GAP }) {
        if (SearchEngineIconResources.builtInIcon(engine.id) !== undefined) {
          Image(SearchEngineIconResources.builtInIcon(engine.id) as Resource)
            .width(BROWSER_BOTTOM_CHROME_ICON_SIZE)
            .height(BROWSER_BOTTOM_CHROME_ICON_SIZE)
            .objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.None)
        } else {
          AiraIcon({
            airaIconId: 'browser.toolbar.search',
            iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
            iconColor: this.resolvePrimaryIconForeground()
          })
            .hitTestBehavior(HitTestMode.None)
        }
        Text(engine.name)
          .layoutWeight(1)
          .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
          .fontColor(this.resolvePrimaryTextForeground())
          .fontWeight(this.isSelectedSearchEngine(engine.id) ? FontWeight.Medium : FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: BROWSER_SEARCH_ENGINE_POPUP_ROW_HORIZONTAL_PADDING,
        right: BROWSER_SEARCH_ENGINE_POPUP_ROW_HORIZONTAL_PADDING
      })
    }
    .width('100%')
    .height(BROWSER_SEARCH_ENGINE_POPUP_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .backgroundColor(this.isSelectedSearchEngine(engine.id) ? this.pressedBackgroundColor :
      $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(BROWSER_SEARCH_ENGINE_POPUP_ROW_RADIUS)
    .stateEffect(true)
    .focusable(false)
    .focusOnTouch(false)
    .accessibilityText(`切换到${engine.name}`)
    .onClick(() => {
      this.applySearchEnginePopupVisible(false, 'row_select');
      this.onSelectSearchEngine(engine.id);
    })
  }

  @Builder
  private buildCenterPrimarySlot() {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: this.presentation.centerPrimaryIconId,
        iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
        iconColor: this.resolveIconForeground(this.centerPrimaryVisualEnabled)
      })
        .opacity(this.animatedFrame.refreshOpacity *
          this.resolveVisualIconOpacity(this.centerPrimaryVisualEnabled))
        .hitTestBehavior(HitTestMode.None)
      AiraIcon({
        airaIconId: 'browser.address.expandedCopy',
        iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
        iconColor: this.resolvePrimaryIconForeground()
      })
        .opacity(this.animatedFrame.copyOpacity)
        .hitTestBehavior(HitTestMode.None)
      AiraIcon({
        airaIconId: 'browser.toolbar.clearInput',
        iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
        iconColor: this.resolvePrimaryIconForeground()
      })
        .opacity(this.animatedFrame.clearOpacity)
        .hitTestBehavior(HitTestMode.None)
      this.buildTapSurface('center-primary')
    }
    .width(this.animatedFrame.centerPrimaryWidth)
    .height(this.animatedFrame.centerViewportHeight)
    .backgroundColor(this.resolvePressedBackground('center-primary'))
    .borderRadius(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT / 2)
    .clip(true)
    .scale({
      x: this.resolveTargetScale('center-primary'),
      y: this.resolveTargetScale('center-primary')
    })
    .hitTestBehavior(this.isPhysicalTargetInteractive('center-primary') ?
      HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private buildCenterSecondarySlot() {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: 'browser.address.expandedEdit',
        iconSize: BROWSER_BOTTOM_CHROME_ICON_SIZE,
        iconColor: this.resolvePrimaryIconForeground()
      })
        .opacity(this.animatedFrame.editOpacity)
        .hitTestBehavior(HitTestMode.None)
      this.buildTapSurface('center-secondary')
    }
    .width(this.animatedFrame.centerSecondaryWidth)
    .height(this.animatedFrame.centerViewportHeight)
    .backgroundColor(this.resolvePressedBackground('center-secondary'))
    .borderRadius(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT / 2)
    .clip(true)
    .scale({
      x: this.resolveTargetScale('center-secondary'),
      y: this.resolveTargetScale('center-secondary')
    })
    .hitTestBehavior(this.isTargetEnabled(this.resolveLiveTapTarget('center-secondary')) ?
      HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private buildCenterViewport() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.outgoingDisplayText)
        .width(this.outgoingDisplayViewportWidth)
        .height(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
        .lineHeight(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .halfLeading(true)
        .textVerticalAlign(TextVerticalAlign.CENTER)
        .fontColor(this.outgoingDisplayUsesSecondaryTone ? this.resolveSecondaryTextForeground() :
          this.resolvePrimaryTextForeground())
        .fontWeight(FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .opacity(this.resolveOutgoingDisplayOpacity() * this.resolveAddressCrossfadeOpacity())
        .position({ x: this.resolveOutgoingDisplayLeft(), y: this.resolveDisplayTextTop() })
        .scale({ x: this.animatedFrame.centerDisplayScale, y: this.animatedFrame.centerDisplayScale })
        .hitTestBehavior(HitTestMode.None)

      Text(this.incomingDisplayText)
        .width(this.incomingDisplayViewportWidth)
        .height(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
        .lineHeight(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .halfLeading(true)
        .textVerticalAlign(TextVerticalAlign.CENTER)
        .fontColor(this.incomingDisplayUsesSecondaryTone ? this.resolveSecondaryTextForeground() :
          this.resolvePrimaryTextForeground())
        .fontWeight(FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .opacity(this.resolveIncomingDisplayOpacity() * this.resolveAddressCrossfadeOpacity())
        .position({ x: this.resolveIncomingDisplayLeft(), y: this.resolveDisplayTextTop() })
        .scale({ x: this.animatedFrame.centerDisplayScale, y: this.animatedFrame.centerDisplayScale })
        .hitTestBehavior(HitTestMode.None)

      this.buildWebProtectionConfirmation()

      Text(this.promptText)
        .width('100%')
        .height(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
        .lineHeight(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .halfLeading(true)
        .textVerticalAlign(TextVerticalAlign.CENTER)
        .fontColor(this.resolvePrimaryTextForeground())
        .fontWeight(FontWeight.Regular)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .opacity(this.animatedFrame.returnHomeOpacity)
        .position({ x: 0, y: this.resolveDisplayTextTop() })
        .scale({ x: this.animatedFrame.centerDisplayScale, y: this.animatedFrame.centerDisplayScale })
        .hitTestBehavior(HitTestMode.None)

      this.buildCenterBodyTapSurface()

      Stack({ alignContent: Alignment.Center }) {
        this.editingLayer()
      }
      .width('100%')
      .height('100%')
      .opacity(this.animatedFrame.editingOpacity)
      .hitTestBehavior(this.editingLayerHitTestEnabled ? HitTestMode.Default : HitTestMode.None)
    }
    .width(this.animatedFrame.centerViewportWidth)
    .height(this.animatedFrame.centerViewportHeight)
    .clip(true)
  }

  @Builder
  private buildWebProtectionConfirmation() {
    Row({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        AiraIcon({
          airaIconId: 'settings.privacySecurity',
          iconSize: 23,
          iconColor: this.resolvePrimaryTextForeground()
        })
      }
      .width(24)
      .height(24)

      Text(this.webProtectionFeedbackDisplayText)
        .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
        .lineHeight(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryTextForeground())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .opacity(this.animatedFrame.displayOpacity * this.webProtectionFeedbackCrossfadeProgress)
    .scale({ x: this.animatedFrame.centerDisplayScale, y: this.animatedFrame.centerDisplayScale })
    .accessibilityText(this.webProtectionFeedbackVisible ? this.webProtectionFeedbackAccessibilityLabel : '')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTapSurface(targetKey: string) {
    if (this.shouldUseToolbarInteractionGesture(targetKey)) {
      this.buildProfileTapSurface(targetKey)
    } else {
      this.buildLegacyTapSurface(targetKey)
    }
  }

  @Builder
  private buildCenterBodyTapSurface() {
    Button()
      .width('100%')
      .height('100%')
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .focusable(false)
      .focusOnTouch(false)
      .enabled(this.isPhysicalTargetInteractive('center-body'))
      .accessibilityText(this.resolveLiveTapTarget('center-body').accessibilityText)
      .hitTestBehavior(this.isPhysicalTargetInteractive('center-body') ? HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.capturePressedTargetIntent('center-body');
        } else if (event.type === TouchType.Cancel) {
          this.clearPressedTargetIntent();
        }
        this.updatePressedTarget('center-body', this.resolveLiveTapTarget('center-body'), event.type);
      })
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          LongPressGesture({
            fingers: 1,
            repeat: false,
            duration: BROWSER_BOTTOM_ADDRESS_CONTEXT_MENU_LONG_PRESS_MS
          })
            .onAction(() => {
              this.openAddressContextMenu();
            }),
          TapGesture()
            .onAction(() => {
              this.handleTap('center-body');
            })
        )
      )
      .bindContextMenu(this.addressContextMenuVisible, this.buildAddressContextMenu(), {
        placement: Placement.Top,
        modalMode: ModalMode.TARGET_WINDOW,
        onDisappear: () => {
          this.addressContextMenuVisible = false;
          this.resetPressedTarget();
        }
      })
  }

  @Builder
  private buildAddressContextMenu() {
    Menu() {
      MenuItem({ content: '复制链接' })
        .enabled(this.isAddressContextCopyLinkEnabled())
        .onClick(() => {
          if (!this.isAddressContextCopyLinkEnabled()) {
            return;
          }
          this.dispatchAddressContextAction('copy_link');
        })

      MenuItem(this.buildPasteAndGoMenuItem)
    }
    .width(BROWSER_BOTTOM_ADDRESS_CONTEXT_MENU_WIDTH)
    .fontColor(this.resolvePrimaryTextForeground())
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(this.materialTint)))
  }

  @Builder
  private buildPasteAndGoMenuItem() {
    PasteButton({ text: PasteDescription.PASTE, buttonType: ButtonType.Normal })
      .width('100%')
      .height(BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_HEIGHT)
      .padding({
        left: BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_HORIZONTAL_PADDING,
        right: BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_HORIZONTAL_PADDING,
        top: 0,
        bottom: 0
      })
      .align(Alignment.Start)
      .fontSize(BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_TEXT_SIZE)
      .fontWeight(FontWeight.Regular)
      .fontColor(this.resolvePrimaryTextForeground())
      .backgroundColor(this.resolveAddressContextPasteBackground())
      .borderWidth(0)
      .borderRadius(BROWSER_BOTTOM_ADDRESS_PASTE_BUTTON_RADIUS)
      .minFontScale(1)
      .maxFontScale(1)
      .maxLines(1)
      .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
        if (result !== PasteButtonOnClickResult.SUCCESS) {
          this.dispatchAddressContextAction('paste_authorization_failed');
          return;
        }
        this.dispatchAddressContextAction('paste_and_go');
      })
  }

  @Builder
  private buildProfileTapSurface(targetKey: string) {
    Button()
      .width('100%')
      .height('100%')
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .focusable(false)
      .focusOnTouch(false)
      .enabled(this.isPhysicalTargetInteractive(targetKey))
      .accessibilityText(this.resolveLiveTapTarget(targetKey).accessibilityText)
      .hitTestBehavior(this.isPhysicalTargetInteractive(targetKey) ?
        HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.capturePressedTargetIntent(targetKey);
        } else if (event.type === TouchType.Cancel) {
          this.clearPressedTargetIntent();
        }
        this.updatePressedTarget(targetKey, this.resolveLiveTapTarget(targetKey), event.type);
      })
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
            .onAction(() => {
              this.handleLongPress(targetKey);
            }),
          TapGesture()
            .onAction(() => {
              this.handleTap(targetKey);
            })
        )
      )
  }

  @Builder
  private buildLegacyTapSurface(targetKey: string) {
    Button()
      .width('100%')
      .height('100%')
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .focusable(false)
      .focusOnTouch(false)
      .enabled(this.isPhysicalTargetInteractive(targetKey))
      .accessibilityText(this.resolveLiveTapTarget(targetKey).accessibilityText)
      .hitTestBehavior(this.isPhysicalTargetInteractive(targetKey) ?
        HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.capturePressedTargetIntent(targetKey);
        } else if (event.type === TouchType.Cancel) {
          this.clearPressedTargetIntent();
        }
        this.updatePressedTarget(targetKey, this.resolveLiveTapTarget(targetKey), event.type);
      })
      .onClick(() => {
        this.handleTap(targetKey);
      })
  }

  @Builder
  private emptyBuilder() {
  }

  private resolveOuterVisualSize(width: number): number {
    return Math.max(0, Math.min(BROWSER_BOTTOM_CHROME_RENDER_HEIGHT, width));
  }

  private resolveOuterVisualOffsetY(width: number): number {
    return Math.max(0, (BROWSER_BOTTOM_CHROME_RENDER_HEIGHT - this.resolveOuterVisualSize(width)) / 2);
  }

  private syncPresentation(): void {
    const previous = this.currentPresentation;
    const previousProtectionFeedbackVisible = this.shouldPresentWebProtectionFeedback(previous);
    const frameChanged = !this.targetFrame.isEquivalent(this.presentation.frame);
    const compactChanged = !this.isCompactProgressSettled();
    const displaySwapNeeded = this.shouldSwapDisplayContent(previous, this.presentation);
    logToolbarPopupReopen('renderer_sync_presentation',
      `mode=${previous.mode}->${this.presentation.mode} scene=${this.presentation.scene} ` +
      `popupFlag=${this.searchEnginePopupVisible} frameChanged=${frameChanged} compactChanged=${compactChanged}`);
    this.currentPresentation = this.presentation;
    this.compactFrame = this.presentation.compactFrame;
    this.applyPresentationMetadata(this.presentation);
    this.syncWebProtectionFeedbackCrossfade(
      previousProtectionFeedbackVisible,
      this.shouldPresentWebProtectionFeedback(this.presentation)
    );
    if (!this.isAddressContextMenuEligible()) {
      this.addressContextMenuVisible = false;
    }
    if (!this.isSearchEngineMenuVisible()) {
      this.applySearchEnginePopupVisible(false, 'sync_presentation_slot_gone');
    }
    if (this.presentation.mode !== 'center-active-editing') {
      this.focusReadyDispatched = false;
      this.clearFocusReadyTimer();
    }
    if (displaySwapNeeded) {
      this.prepareDisplaySwap(this.presentation);
    }
    if (!frameChanged && !compactChanged && !displaySwapNeeded) {
      return;
    }
    this.targetFrame = this.presentation.frame;
    this.targetScrollCompactProgress = this.presentation.scrollCompactProgress;
    const directive = this.presentation.resolveMotionFrom(previous);
    if (directive.kind !== 'animated' || directive.durationMs <= 0 || directive.curve === undefined) {
      this.invalidateActiveMotion();
      this.animatedFrame = this.presentation.frame;
      this.animatedScrollCompactProgress = this.targetScrollCompactProgress;
      if (displaySwapNeeded) {
        this.commitDisplayContent(this.presentation);
      } else {
        this.displaySwapProgress = 1;
      }
      this.maybeScheduleImmediateFocusReady(directive);
      return;
    }
    this.startMotion(directive);
  }

  private isCompactProgressSettled(): boolean {
    return Math.abs(this.targetScrollCompactProgress - this.presentation.scrollCompactProgress) <=
      BROWSER_BOTTOM_CHROME_PROGRESS_EPSILON;
  }

  private applyPresentationMetadata(presentation: BrowserBottomChromePresentation): void {
    const feedback = presentation.centerContent.webProtectionFeedback;
    this.promptText = presentation.centerContent.promptText;
    this.webProtectionFeedbackVisible = feedback.visible;
    this.webProtectionFeedbackDisplayText = feedback.displayText;
    this.webProtectionFeedbackAccessibilityLabel = feedback.accessibilityLabel;
    if (this.lastDebugProtectionFeedbackVisible !== feedback.visible ||
      this.lastDebugProtectionFeedbackMode !== presentation.mode) {
      this.lastDebugProtectionFeedbackVisible = feedback.visible;
      this.lastDebugProtectionFeedbackMode = presentation.mode;
      hilog.info(
        PROTECTION_DEBUG_DOMAIN,
        PROTECTION_DEBUG_TAG,
        '%{public}s renderer feedback visible=%{public}d mode=%{public}s generation=%{public}d',
        PROTECTION_DEBUG_PREFIX,
        feedback.visible ? 1 : 0,
        presentation.mode,
        feedback.navigationGeneration
      );
    }
    this.editingLayerHitTestEnabled = presentation.centerContent.activeLayer === 'editing';
    this.leadingOuterVisualEnabled = presentation.leadingOuterVisualEnabled;
    this.centerLeadingVisualEnabled = presentation.centerLeadingVisualEnabled;
    this.centerPrimaryVisualEnabled = presentation.centerPrimaryVisualEnabled;
    this.trailingOuterVisualEnabled = presentation.trailingOuterVisualEnabled;
  }

  private startMotion(directive: BrowserBottomChromeMotionDirective): void {
    this.invalidateActiveMotion();
    const version = this.motionVersion;
    const targetFrame = this.presentation.frame;
    const targetScrollCompactProgress = this.targetScrollCompactProgress;
    const curve = directive.curve as ICurve;
    this.scheduleFocusReady(directive, version);
    animateTo({
      duration: directive.durationMs,
      curve,
      onFinish: () => {
        if (this.motionVersion !== version) {
          return;
        }
        this.dispatchFocusReadyIfNeeded(directive, 1);
      }
    }, () => {
      if (this.motionVersion !== version) {
        return;
      }
      this.animatedFrame = targetFrame;
      this.animatedScrollCompactProgress = targetScrollCompactProgress;
      this.displaySwapProgress = 1;
    });
  }

  private initializeDisplayContent(presentation: BrowserBottomChromePresentation): void {
    const content = presentation.centerContent;
    this.outgoingDisplayText = content.displayText;
    this.incomingDisplayText = content.displayText;
    this.outgoingDisplayUsesSecondaryTone = content.displayUsesSecondaryTone;
    this.incomingDisplayUsesSecondaryTone = content.displayUsesSecondaryTone;
    this.outgoingDisplayViewportWidth = presentation.frame.centerViewportWidth;
    this.incomingDisplayViewportWidth = presentation.frame.centerViewportWidth;
    this.displaySwapProgress = 1;
  }

  private shouldSwapDisplayContent(
    previous: BrowserBottomChromePresentation,
    next: BrowserBottomChromePresentation
  ): boolean {
    return previous.centerContent.displayKey !== next.centerContent.displayKey ||
      Math.abs(previous.frame.centerViewportWidth - next.frame.centerViewportWidth) > BROWSER_BOTTOM_CHROME_PROGRESS_EPSILON;
  }

  private prepareDisplaySwap(presentation: BrowserBottomChromePresentation): void {
    const useIncomingAsOutgoing = this.resolveDisplaySwapProgress() >= 0.5;
    this.outgoingDisplayText = useIncomingAsOutgoing ? this.incomingDisplayText : this.outgoingDisplayText;
    this.outgoingDisplayUsesSecondaryTone = useIncomingAsOutgoing ? this.incomingDisplayUsesSecondaryTone :
      this.outgoingDisplayUsesSecondaryTone;
    this.outgoingDisplayViewportWidth = useIncomingAsOutgoing ? this.incomingDisplayViewportWidth :
      this.outgoingDisplayViewportWidth;
    this.incomingDisplayText = presentation.centerContent.displayText;
    this.incomingDisplayUsesSecondaryTone = presentation.centerContent.displayUsesSecondaryTone;
    this.incomingDisplayViewportWidth = presentation.frame.centerViewportWidth;
    this.displaySwapProgress = 0;
  }

  private commitDisplayContent(presentation: BrowserBottomChromePresentation): void {
    const content = presentation.centerContent;
    this.outgoingDisplayText = content.displayText;
    this.incomingDisplayText = content.displayText;
    this.outgoingDisplayUsesSecondaryTone = content.displayUsesSecondaryTone;
    this.incomingDisplayUsesSecondaryTone = content.displayUsesSecondaryTone;
    this.outgoingDisplayViewportWidth = presentation.frame.centerViewportWidth;
    this.incomingDisplayViewportWidth = presentation.frame.centerViewportWidth;
    this.displaySwapProgress = 1;
  }

  private resolveDisplaySwapProgress(): number {
    return Math.max(0, Math.min(1, this.displaySwapProgress));
  }

  private resolveOutgoingDisplayOpacity(): number {
    return this.animatedFrame.displayOpacity * (1 - this.resolveDisplaySwapProgress());
  }

  private resolveIncomingDisplayOpacity(): number {
    return this.animatedFrame.displayOpacity * this.resolveDisplaySwapProgress();
  }

  private resolveOutgoingDisplayLeft(): number {
    return (this.animatedFrame.centerViewportWidth - this.outgoingDisplayViewportWidth) / 2;
  }

  private resolveIncomingDisplayLeft(): number {
    return (this.animatedFrame.centerViewportWidth - this.incomingDisplayViewportWidth) / 2;
  }

  private resolveDisplayTextTop(): number {
    return Math.max(0,
      (this.animatedFrame.centerViewportHeight - BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT) / 2);
  }

  private syncWebProtectionFeedbackCrossfade(previousVisible: boolean, nextVisible: boolean): void {
    if (previousVisible === nextVisible) {
      return;
    }
    if (!nextVisible && this.presentation.mode !== 'resting-three-block') {
      this.webProtectionFeedbackCrossfadeProgress = 0;
      return;
    }
    animateTo({
      duration: BROWSER_WEB_PROTECTION_FEEDBACK_CROSSFADE_DURATION_MS,
      curve: Curve.EaseInOut
    }, () => {
      this.webProtectionFeedbackCrossfadeProgress = nextVisible ? 1 : 0;
    });
  }

  private shouldPresentWebProtectionFeedback(presentation: BrowserBottomChromePresentation): boolean {
    return presentation.effectiveWeb &&
      presentation.mode === 'resting-three-block' &&
      presentation.centerContent.activeLayer === 'display' &&
      presentation.centerContent.webProtectionFeedback.visible;
  }

  private resolveAddressCrossfadeOpacity(): number {
    return 1 - this.webProtectionFeedbackCrossfadeProgress;
  }

  private invalidateActiveMotion(): void {
    this.motionVersion += 1;
    this.clearFocusReadyTimer();
  }

  private scheduleFocusReady(directive: BrowserBottomChromeMotionDirective, version: number): void {
    if (directive.focusReadyProgress < 0 || this.currentPresentation.mode !== 'center-active-editing') {
      return;
    }
    const delayMs = Math.max(0, Math.round(directive.durationMs * directive.focusReadyProgress));
    this.focusReadyTimer = setTimeout(() => {
      this.focusReadyTimer = -1;
      if (this.motionVersion !== version) {
        return;
      }
      this.dispatchFocusReadyIfNeeded(directive, directive.focusReadyProgress);
    }, delayMs);
  }

  private dispatchFocusReadyIfNeeded(
    directive: BrowserBottomChromeMotionDirective,
    progress: number
  ): void {
    if (this.focusReadyDispatched ||
      directive.focusReadyProgress < 0 ||
      progress + BROWSER_BOTTOM_CHROME_PROGRESS_EPSILON < directive.focusReadyProgress ||
      this.currentPresentation.mode !== 'center-active-editing') {
      return;
    }
    this.focusReadyDispatched = true;
    this.onEditingFocusReady();
  }

  private maybeScheduleImmediateFocusReady(directive: BrowserBottomChromeMotionDirective): void {
    if (directive.focusReadyProgress < 0 || this.currentPresentation.mode !== 'center-active-editing') {
      return;
    }
    this.scheduleImmediateFocusReady();
  }

  private scheduleImmediateFocusReady(): void {
    if (this.focusReadyDispatched || this.focusReadyTimer >= 0) {
      return;
    }
    this.focusReadyTimer = setTimeout(() => {
      this.focusReadyTimer = -1;
      if (this.focusReadyDispatched || this.currentPresentation.mode !== 'center-active-editing') {
        return;
      }
      this.focusReadyDispatched = true;
      this.onEditingFocusReady();
    }, 0);
  }

  private clearFocusReadyTimer(): void {
    if (this.focusReadyTimer < 0) {
      return;
    }
    clearTimeout(this.focusReadyTimer);
    this.focusReadyTimer = -1;
  }

  private isTargetEnabled(target: BrowserBottomChromeTapTarget): boolean {
    return target.enabled && (!target.reliable || this.reliableActionsEnabled);
  }

  private updatePressedTarget(
    targetKey: string,
    target: BrowserBottomChromeTapTarget,
    touchType: TouchType
  ): void {
    if (!this.isTargetEnabled(target)) {
      this.resetPressedTarget();
      return;
    }
    if (touchType === TouchType.Down) {
      this.pressTarget(targetKey);
      return;
    }
    if (touchType === TouchType.Up || touchType === TouchType.Cancel) {
      this.releasePressedTarget(targetKey);
    }
  }

  private pressTarget(targetKey: string): void {
    const version = this.beginPressedTargetMotion();
    this.pressedTargetKey = targetKey;
    this.pressedTargetScaleKey = targetKey;
    animateTo({
      duration: BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
      curve: Curve.EaseOut
    }, () => {
      if (this.pressedTargetMotionVersion !== version) {
        return;
      }
      if (targetKey === 'center-body' || targetKey === 'compact-body') {
        this.pressedTargetScale = 1;
        this.centerBodyPressedProgress = 1;
        return;
      }
      this.centerBodyPressedProgress = 0;
      this.pressedTargetScale = BROWSER_FLOATING_CHROME_PRESSED_SCALE;
    });
  }

  private releasePressedTarget(targetKey: string): void {
    if (this.pressedTargetScaleKey !== targetKey) {
      return;
    }
    this.pressedTargetKey = '';
    const version = this.beginPressedTargetMotion();
    animateTo({
      duration: BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS,
      curve: BROWSER_FLOATING_CHROME_RELEASE_CURVE,
      onFinish: () => {
        if (this.pressedTargetMotionVersion !== version) {
          return;
        }
        this.pressedTargetScaleKey = '';
      }
    }, () => {
      if (this.pressedTargetMotionVersion !== version) {
        return;
      }
      if (targetKey === 'center-body' || targetKey === 'compact-body') {
        this.centerBodyPressedProgress = 0;
        return;
      }
      this.pressedTargetScale = 1;
    });
  }

  private beginPressedTargetMotion(): number {
    this.pressedTargetMotionVersion += 1;
    return this.pressedTargetMotionVersion;
  }

  private resetPressedTarget(): void {
    this.beginPressedTargetMotion();
    this.pressedTargetKey = '';
    this.pressedTargetScaleKey = '';
    this.pressedTargetScale = 1;
    this.centerBodyPressedProgress = 0;
  }

  private capturePressedTargetIntent(targetKey: string): void {
    const target = this.resolveLiveTapTarget(targetKey);
    if (!this.isTargetPresent(target)) {
      this.clearPressedTargetIntent();
      return;
    }
    this.pressedTargetIntentKey = targetKey;
    this.pressedTargetIntent = new BrowserBottomChromeTapIntent(
      target.intent.kind,
      target.intent.actionId,
      target.intent.slotId,
      target.intent.disabledMessage
    );
  }

  private handleTap(targetKey: string): void {
    const pressedIntent = this.pressedTargetIntentKey === targetKey ? this.pressedTargetIntent : undefined;
    this.clearPressedTargetIntent();
    if (pressedIntent !== undefined) {
      const target = this.resolveLiveTapTarget(targetKey);
      if (!target.reliable || this.reliableActionsEnabled) {
        this.onIntent(pressedIntent);
      }
      return;
    }
    const liveTarget = this.resolveLiveTapTarget(targetKey);
    if (this.isTargetPresent(liveTarget) && (!liveTarget.reliable || this.reliableActionsEnabled)) {
      this.onIntent(liveTarget.intent);
    }
  }

  private handleLongPress(targetKey: string): void {
    this.clearPressedTargetIntent();
    const target = this.resolveLiveLongPressTarget(targetKey);
    if (this.isTargetPresent(target)) {
      this.onLongPressIntent(target.intent);
    }
  }

  private openAddressContextMenu(): void {
    this.clearPressedTargetIntent();
    if (!this.isAddressContextMenuEligible()) {
      return;
    }
    this.addressContextMenuVisible = true;
  }

  private dispatchAddressContextAction(action: BrowserBottomAddressContextAction): void {
    this.addressContextMenuVisible = false;
    this.onAddressContextAction(action);
  }

  private isAddressContextMenuEligible(): boolean {
    return this.addressContextMenuEnabled &&
      (this.currentPresentation.scene === 'home' || this.currentPresentation.scene === 'web') &&
      (this.currentPresentation.mode === 'resting-three-block' ||
        this.currentPresentation.mode === 'center-active-tools') &&
      this.currentPresentation.centerContent.activeLayer === 'display' &&
      this.currentPresentation.centerContent.displayText.trim().length > 0;
  }

  private isAddressContextCopyLinkEnabled(): boolean {
    return this.currentPresentation.scene === 'web' &&
      this.currentPresentation.centerContent.displayText.trim().length > 0;
  }

  private isPhysicalTargetInteractive(targetKey: string): boolean {
    // The expanded rail stays mounted behind the collapsed capsule. Once the compact capsule is the
    // presented chrome it must not swallow touches aimed at the expanded clusters, and vice versa:
    // keying this off the restore target rather than opacity alone keeps taps alive mid-transition.
    if (targetKey !== 'compact-body' && this.isCompactChromePresented()) {
      return false;
    }
    if (!this.shouldUseToolbarInteractionGesture(targetKey)) {
      return this.isTargetEnabled(this.resolveLiveTapTarget(targetKey));
    }
    return this.isTargetPresent(this.resolveLiveTapTarget(targetKey)) ||
      this.isTargetPresent(this.resolveLiveLongPressTarget(targetKey));
  }

  /**
   * True while the collapsed capsule is the chrome the user is actually looking at. The restore
   * target only exists for Scroll-Compact, so this is false for the whole reveal direction and the
   * expanded clusters keep receiving taps until they are the presented state again.
   */
  private isCompactChromePresented(): boolean {
    return this.resolveScrollCompactProgress() >= BROWSER_BOTTOM_CHROME_COMPACT_HIT_TEST_PROGRESS &&
      this.isTargetPresent(this.presentation.compactBodyTarget);
  }

  private shouldUseToolbarInteractionGesture(targetKey: string): boolean {
    if (!this.presentation.toolbarInteractionProfileActive ||
      (this.presentation.mode !== 'resting-three-block' && this.presentation.mode !== 'center-active-tools')) {
      return false;
    }
    return targetKey === 'leading-outer' || targetKey === 'center-leading' ||
      targetKey === 'center-primary' || targetKey === 'trailing-outer';
  }

  private isTargetPresent(target: BrowserBottomChromeTapTarget): boolean {
    return target.intent.kind !== 'none';
  }

  private resolveLiveLongPressTarget(targetKey: string): BrowserBottomChromeTapTarget {
    if (targetKey === 'compact-body') {
      return EMPTY_BROWSER_BOTTOM_CHROME_TAP_TARGET;
    }
    if (targetKey === 'leading-outer') {
      return this.presentation.leadingOuterLongPressTarget;
    }
    if (targetKey === 'center-leading') {
      return this.presentation.centerLeadingLongPressTarget;
    }
    if (targetKey === 'center-primary') {
      return this.presentation.centerPrimaryLongPressTarget;
    }
    if (targetKey === 'trailing-outer') {
      return this.presentation.trailingOuterLongPressTarget;
    }
    return DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION.centerBodyTarget;
  }

  private resolveLiveTapTarget(targetKey: string): BrowserBottomChromeTapTarget {
    if (targetKey === 'leading-outer') {
      return this.presentation.leadingOuterTarget;
    }
    if (targetKey === 'compact-body') {
      return this.presentation.compactBodyTarget;
    }
    if (targetKey === 'center-body') {
      return this.presentation.centerBodyTarget;
    }
    if (targetKey === 'center-leading') {
      if (this.shouldShowDownloadIndicator()) {
        return new BrowserBottomChromeTapTarget(
          new BrowserBottomChromeTapIntent('dispatch-panel-action', 'downloads'),
          true,
          this.downloadIndicatorState.accessibilityText()
        );
      }
      return this.presentation.centerLeadingTarget;
    }
    if (targetKey === 'center-primary') {
      return this.presentation.centerPrimaryTarget;
    }
    if (targetKey === 'center-secondary') {
      return this.presentation.centerSecondaryTarget;
    }
    return this.presentation.trailingOuterTarget;
  }

  private shouldShowDownloadIndicator(): boolean {
    return this.downloadIndicatorState.visible;
  }

  private resolveDownloadProgressStatus(): ProgressStatus {
    return this.downloadIndicatorState.progressKnown ?
      ProgressStatus.PROGRESSING : ProgressStatus.LOADING;
  }

  private clearPressedTargetIntent(): void {
    this.pressedTargetIntentKey = '';
    this.pressedTargetIntent = undefined;
  }

  private resolvePressedBackground(targetKey: string): ResourceColor {
    return this.pressedTargetKey === targetKey ? this.pressedBackgroundColor :
      $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveTargetScale(targetKey: string): number {
    return this.pressedTargetScaleKey === targetKey ? this.pressedTargetScale : 1;
  }

  private resolveCenterBodyScaleX(): number {
    return this.resolveCenterBodyAnimatedScale(
      this.animatedFrame.centerWidth,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_HORIZONTAL_INSET,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_MIN_HORIZONTAL_SCALE
    );
  }

  private resolveCenterBodyScaleY(): number {
    return this.resolveCenterBodyAnimatedScale(
      this.animatedFrame.centerHeight,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_VERTICAL_INSET,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_MIN_VERTICAL_SCALE
    );
  }

  private resolveCompactBodyScaleX(): number {
    return this.resolveCenterBodyAnimatedScale(
      this.compactFrame.centerWidth,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_HORIZONTAL_INSET,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_MIN_HORIZONTAL_SCALE
    );
  }

  private resolveCompactBodyScaleY(): number {
    return this.resolveCenterBodyAnimatedScale(
      this.compactFrame.centerHeight,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_VERTICAL_INSET,
      BROWSER_BOTTOM_CHROME_CENTER_PRESSED_MIN_VERTICAL_SCALE
    );
  }

  /**
   * Collapse progress drives opacity only, so no geometry, material plate or shadow has to be
   * rebuilt while the finger is still on the page.
   */
  private resolveScrollCompactProgress(): number {
    return Math.max(0, Math.min(1, this.animatedScrollCompactProgress));
  }

  private resolveCenterBodyAnimatedScale(size: number, inset: number, minimumScale: number): number {
    const normalizedSize = Math.max(1, size);
    const targetScale = Math.max(
      minimumScale,
      Math.min(1, (normalizedSize - Math.max(0, inset) * 2) / normalizedSize)
    );
    const progress = Math.max(0, Math.min(1, this.centerBodyPressedProgress));
    return 1 - (1 - targetScale) * progress;
  }

  private resolveVisualIconOpacity(enabled: boolean): number {
    return enabled ? BROWSER_BOTTOM_CHROME_ENABLED_OPACITY : BROWSER_BOTTOM_CHROME_DISABLED_OPACITY;
  }

  private isSearchEngineMenuVisible(): boolean {
    return this.presentation.centerLeadingTarget.intent.kind === 'open-search-engine-menu';
  }

  /**
   * Temporary probe: every write to the popup flag goes through here so a capture shows not just
   * that the popup came back but which trigger asked for it.
   */
  private applySearchEnginePopupVisible(next: boolean, trigger: string): void {
    logToolbarPopupReopen('popup_write', `trigger=${trigger} from=${this.searchEnginePopupVisible} ` +
      `to=${next} slotVisible=${this.isSearchEngineMenuVisible()} mode=${this.presentation.mode} ` +
      `scene=${this.presentation.scene} atPress=${this.searchEnginePopupVisibleAtPress}`);
    this.searchEnginePopupVisible = next;
  }

  private isSelectedSearchEngine(engineId: SearchEngineId): boolean {
    return this.presentation.searchEnginePresentation.selectedSearchEngine === engineId;
  }

  /**
   * The menu is capped to the space above its own anchor so `Placement.Top` stays satisfiable.
   * Anything taller lets the framework flip the popup downwards onto the keyboard, which this
   * window never treats as occupied. Rows that no longer fit stay reachable through the popup's
   * Scroll.
   */
  private resolveSearchEnginePopupHeight(): number {
    const preferredRowCount = Math.max(1, Math.min(
      BROWSER_SEARCH_ENGINE_POPUP_MAX_VISIBLE_ROWS,
      this.presentation.searchEnginePresentation.searchEngines.length
    ));
    return this.searchEnginePopupLayout.resolve({
      anchorTopVp: this.searchEnginePopupAnchorTopVp,
      topSafeInsetVp: this.topSafeInsetVp,
      rowHeightVp: BROWSER_SEARCH_ENGINE_POPUP_ROW_HEIGHT,
      contentPaddingVp: BROWSER_SEARCH_ENGINE_POPUP_CONTENT_PADDING,
      preferredRowCount: preferredRowCount,
      anchorGapVp: BROWSER_SEARCH_ENGINE_POPUP_TARGET_SPACE
    }).heightVp;
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseAreaPosition(value?: Length): number {
    return value === undefined ? 0 : this.parseAreaDimension(value);
  }

  /**
   * A zero or negative reading means the host has not measured the anchor; the popup policy keeps
   * the full menu in that case rather than collapsing to a single row on a bad measurement.
   */
  private rememberSearchEnginePopupAnchorTop(anchorTop: number): void {
    if (!Number.isFinite(anchorTop) || anchorTop <= 0) {
      return;
    }
    if (Math.abs(anchorTop - this.searchEnginePopupAnchorTopVp) < 1) {
      return;
    }
    this.searchEnginePopupAnchorTopVp = anchorTop;
  }

  private resolveSelectedSearchEngineIcon(): Resource | undefined {
    return SearchEngineIconResources.searchEntryIcon(
      this.presentation.searchEnginePresentation.selectedSearchEngine,
      this.chromeIconTone
    );
  }

  private resolveIconForeground(enabled: boolean): ResourceColor {
    return enabled ? this.resolvePrimaryIconForeground() : this.resolveDisabledIconForeground();
  }

  private resolvePrimaryIconForeground(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.icon_primary') : this.primaryIconColor;
  }

  private resolveDisabledIconForeground(): ResourceColor {
    // Keep the disabled opacity animation in the renderer; the adaptive
    // resource supplies the complementary foreground for the material.
    return this.adaptiveForeground ? $r('sys.color.icon_primary') : this.disabledIconColor;
  }

  private resolvePrimaryTextForeground(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.font_primary') : this.primaryTextColor;
  }

  private resolveSecondaryTextForeground(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.font_secondary') : this.secondaryTextColor;
  }

  /**
   * The paste row is a security control, which forces any background alpha below 0x1a up to opaque.
   * A transparent background therefore paints an opaque tile, and the raw system transparent color
   * resolves to white in both themes, hiding the white dark-mode label. Reuse the menu surface token
   * so the row keeps the same themed background as the copy-link row.
   */
  private resolveAddressContextPasteBackground(): ResourceColor {
    return $r('app.color.surface_floating_background');
  }

  private resolveMaterialShadow(): ShadowOptions {
    return {
      radius: BROWSER_BOTTOM_CHROME_SHADOW_RADIUS,
      color: this.materialShadowColor,
      offsetX: 0,
      offsetY: 0
    };
  }

  private shouldUseHdsMaterialPlate(): boolean {
    return this.hdsMaterialPlateEnabled && isHdsMaterialAvailable();
  }
}
