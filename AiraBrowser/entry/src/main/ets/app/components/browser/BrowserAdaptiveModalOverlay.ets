import {
  DESKTOP_DIALOG_ENTER_DURATION_MS,
  DesktopDialogTier
} from '../../../core/browser/BrowserDialogPresentationTokens';
import { DesktopDialogWidthViewModel } from '../../../core/browser/DesktopDialogWidthViewModel';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
import { BrowserModalBottomOverlay } from './BrowserModalBottomSheet';

export type BrowserAdaptiveModalLayoutMode = 'phone' | 'large_screen';

@Component
export struct BrowserAdaptiveModalOverlay {
  @Prop @Watch('syncVisible') visible: boolean = false;
  @Prop @Watch('handleLayoutModeChanged') layoutMode: BrowserAdaptiveModalLayoutMode = 'phone';
  @Prop title: string = '';
  @Prop showDesktopHeader: boolean = true;
  @Prop showDesktopRefreshButton: boolean = false;
  /**
   * Whether a tap on the dimmed area (or an Escape press on a large screen) closes this
   * surface. Announcements that must actually be read keep it false: a stray tap then does
   * nothing, and only the surface's own action button can finish it.
   */
  @Prop dismissOnOutsideTap: boolean = true;
  @Prop phoneSheetHeight: Length = '';
  @Prop phoneSheetAlignment: Alignment = Alignment.Bottom;
  @Prop phoneEnterOffsetY: number = 48;
  @Prop animationDurationMs: number = 220;
  @Prop zIndexValue: number = 220;
  @Prop tier: DesktopDialogTier = 'm';
  onDismiss: () => void = () => {};
  onDidDismiss: () => void = () => {};
  refreshAction: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;
  @State private viewportWidthVp: number = 0;
  @State private viewportHeightVp: number = 0;
  @State private largeScreenCoverVisible: boolean = false;
  @State private largeScreenPresentationVisible: boolean = false;
  private largeScreenRevealTimer: number = -1;
  private largeScreenDismissTimer: number = -1;
  private largeScreenDismissRequested: boolean = false;
  private largeScreenDismissCompletionPending: boolean = false;
  private readonly desktopDialogWidthViewModel: DesktopDialogWidthViewModel =
    new DesktopDialogWidthViewModel();

  aboutToAppear(): void {
    this.syncVisible();
  }

  aboutToDisappear(): void {
    this.clearLargeScreenTimers();
  }

  build() {
    if (this.layoutMode === 'large_screen') {
      Row()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)
        .bindContentCover($$this.largeScreenCoverVisible, this.buildLargeScreenDialog(), {
          modalTransition: ModalTransition.NONE,
          backgroundColor: Color.Transparent,
          onWillDismiss: (_action: DismissContentCoverAction): void => {
            if (this.dismissOnOutsideTap) {
              this.requestDismiss();
            }
          },
          onDisappear: (): void => {
            this.handleLargeScreenCoverDisappear();
          }
        })
    } else {
      BrowserModalBottomOverlay({
        visible: this.visible,
        sheetHeight: this.phoneSheetHeight,
        sheetAlignment: this.phoneSheetAlignment,
        enterOffsetY: this.phoneEnterOffsetY,
        animationDurationMs: this.animationDurationMs,
        zIndexValue: this.zIndexValue,
        dismissOnOutsideTap: this.dismissOnOutsideTap,
        onDismiss: this.onDismiss
      }) {
        this.content()
      }
    }
  }

  @Builder
  private buildLargeScreenDialog() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isViewportMeasured()) {
        Stack()
          .backgroundColor($r('app.color.browser_overlay_scrim'))
          .opacity(this.largeScreenPresentationVisible ? 1 : 0)
          .animation({ duration: this.animationDurationMs, curve: Curve.EaseOut })
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.opacity(0).animation({
            duration: this.animationDurationMs,
            curve: Curve.EaseOut
          }))
          .hitTestBehavior(this.largeScreenPresentationVisible ? HitTestMode.Default : HitTestMode.None)
          .onClick((): void => {
            if (this.dismissOnOutsideTap) {
              this.requestDismiss();
            }
          })

        Column({ space: 0 }) {
          if (this.showDesktopHeader) {
            BrowserLargeScreenModalHeader({
              title: this.title,
              showRefreshButton: this.showDesktopRefreshButton,
              onRefresh: this.refreshAction,
              onClose: (): void => {
                this.requestDismiss();
              }
            })
          }

          Column() {
            this.content()
          }
          .width('100%')
          .layoutWeight(1)
        }
        .backgroundColor($r('app.color.surface_floating_background'))
        .borderRadius(this.resolveDesktopCornerRadius())
        .clip(true)
        .shadow({ radius: 28, color: '#21101420', offsetX: 0, offsetY: 8 })
        .opacity(this.largeScreenPresentationVisible ? 1 : 0)
        .animation({ duration: DESKTOP_DIALOG_ENTER_DURATION_MS, curve: Curve.EaseOut })
        .width(this.resolveDesktopWidth())
        .height(this.resolveDesktopHeight())
        .constraintSize({ maxHeight: this.resolveDesktopHeight() })
        .hitTestBehavior(this.largeScreenPresentationVisible ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
        .keyboardShortcut(FunctionKey.ESC, [], (): void => {
          if (this.dismissOnOutsideTap) {
            this.requestDismiss();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(this.zIndexValue)
    .hitTestBehavior(this.largeScreenPresentationVisible && this.isViewportMeasured()
      ? HitTestMode.Transparent
      : HitTestMode.None)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportSize(newArea);
    })
  }

  private resolveDesktopWidth(): number {
    return this.desktopDialogWidthViewModel.resolve(
      this.tier, this.viewportWidthVp, this.viewportHeightVp).widthVp;
  }

  private resolveDesktopHeight(): number {
    return this.desktopDialogWidthViewModel.resolve(
      this.tier, this.viewportWidthVp, this.viewportHeightVp).maxHeightVp;
  }

  private resolveDesktopCornerRadius(): number {
    return this.desktopDialogWidthViewModel.resolve(
      this.tier, this.viewportWidthVp, this.viewportHeightVp).cornerRadiusVp;
  }

  private isViewportMeasured(): boolean {
    return Number.isFinite(this.viewportWidthVp) && this.viewportWidthVp > 0 &&
      Number.isFinite(this.viewportHeightVp) && this.viewportHeightVp > 0;
  }

  private handleLayoutModeChanged(): void {
    this.clearLargeScreenTimers();
    this.viewportWidthVp = 0;
    this.viewportHeightVp = 0;
    this.largeScreenCoverVisible = false;
    this.largeScreenPresentationVisible = false;
    this.syncVisible();
  }

  private syncVisible(): void {
    this.clearLargeScreenTimers();
    if (this.layoutMode !== 'large_screen') {
      this.largeScreenCoverVisible = false;
      this.largeScreenPresentationVisible = false;
      this.largeScreenDismissRequested = false;
      return;
    }
    if (!this.visible) {
      this.largeScreenDismissRequested = false;
      this.largeScreenDismissCompletionPending = this.largeScreenCoverVisible;
      this.hideLargeScreenCoverAfterTransition();
      return;
    }
    this.largeScreenDismissRequested = false;
    this.largeScreenDismissCompletionPending = false;
    this.largeScreenCoverVisible = true;
    this.largeScreenPresentationVisible = false;
    this.largeScreenRevealTimer = setTimeout((): void => {
      this.largeScreenRevealTimer = -1;
      if (this.visible && this.layoutMode === 'large_screen') {
        this.largeScreenPresentationVisible = true;
      }
    }, 0);
  }

  private hideLargeScreenCoverAfterTransition(): void {
    this.largeScreenPresentationVisible = false;
    if (!this.largeScreenCoverVisible) {
      return;
    }
    this.largeScreenDismissTimer = setTimeout((): void => {
      this.largeScreenDismissTimer = -1;
      if (!this.visible || this.layoutMode !== 'large_screen') {
        this.largeScreenCoverVisible = false;
      }
    }, this.animationDurationMs);
  }

  private requestDismiss(): void {
    if (!this.visible || !this.largeScreenPresentationVisible || this.largeScreenDismissRequested) {
      return;
    }
    this.largeScreenDismissRequested = true;
    this.onDismiss();
  }

  private handleLargeScreenCoverDisappear(): void {
    const shouldNotifyDismissed: boolean = this.largeScreenDismissCompletionPending;
    this.largeScreenDismissCompletionPending = false;
    this.largeScreenPresentationVisible = false;
    this.viewportWidthVp = 0;
    this.viewportHeightVp = 0;
    if (shouldNotifyDismissed) {
      this.onDidDismiss();
    }
  }

  private clearLargeScreenTimers(): void {
    if (this.largeScreenRevealTimer >= 0) {
      clearTimeout(this.largeScreenRevealTimer);
      this.largeScreenRevealTimer = -1;
    }
    if (this.largeScreenDismissTimer >= 0) {
      clearTimeout(this.largeScreenDismissTimer);
      this.largeScreenDismissTimer = -1;
    }
  }

  private updateViewportSize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.viewportWidthVp) {
      this.viewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.viewportHeightVp) {
      this.viewportHeightVp = height;
    }
  }

  @Builder
  private emptyContent() {
  }
}
